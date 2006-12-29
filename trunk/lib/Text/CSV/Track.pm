=head1 NAME

Text::CSV::Track - module to work with .csv file that stores some value per identificator

=head1 VERSION

v1.0 - created to track answer from survey

=head1 SYNOPSIS

	use Text::CSV::Track;
	
	#create object
	my $access_time = Text::CSV::Track->new({ file_name => $file_name, ignore_missing_file => 1 });
	
	#store value
	$access_time->value_of($login, $access_time);
	
	#fetch value
	print $access_time->value_of($login);
	
	#save changes
	$access_time->store();
	
	#print out all the identificators we have
	foreach my $login (sort $access_time->ident_list()) {
		print "$login\n";
	}

=head1 DESCRIPTION

The module manipulates csv file:

"identificator","value"
...

It is designet to work when multiple processes access the same file at
the same time. It uses lazy initialization. That mean that the file is
read only when it is needed. There are three scenarios:

1. Only reading of values is needed. In this case first ->value_of() also
activates the reading of file. File is read while holding shared flock.
Then the lock is released.

2. Only setting of values is needed. In this case ->value_of($ident,$val)
calls just saves the values to the hash. Then when ->store() is called
it activates the reading of file. File is read while holding exclusive flock.
The identifications that were stored in the hash are replaced, the rest
is kept.

3. Both reading and setting values is needed. In this case 'full_time_lock'
flag is needed. The exclusive lock will be held from the first read until
the object is destroied. While the lock is there no other process that uses
flock can read or write to this file.

=head1 METHODS

=over 4

=item new()

	new({
		file_name           => 'filename.csv',
		ignore_missing_file => 1,
		full_time_lock      => 1,
		
	})
	
all flags are optional.

'file_name' is used to read old results and then store the updated ones

if 'ignore_missing_file' is set then the lib will just warn that it can not
read the file. store() will use this name to store the results.

if 'full_time_lock' is set the exclusive lock will be held until the object is
not destroyed. use it when you need both reading the values and changing the values.
If you need just read OR change then you don't need to set this flag. See description
about lazy initialization.

=item value_of()

is used to both store or retrieve the value. if called with one argument
then it is a read. if called with two arguments then it will update the
value. The update will be done ONLY if the supplied value is bigger.
	
=item store()

when this one is called it will write the changes back to file.

=item ident_list()

will return the array of identificators

=back

=head1 AUTHOR

Jozef Kutej <jozef.kutej@hp.com>

=cut 



package Text::CSV::Track;

our $VERSION = '1.0';
use 5.006;

use strict;
use warnings;

use base qw(Class::Accessor::Fast);
Text::CSV::Track->mk_accessors(qw(file_name file_fh rh_value_of lazy_init ignore_missing_file full_time_lock _no_lock));

use FindBin;

use Text::CSV;
use Carp::Clan;
use English qw(-no_match_vars);
use Fcntl ':flock'; # import LOCK_* constants
use Fcntl ':seek';  # import SEEK_* constants

#readonly defaults

my $CSV_FORMAT = Text::CSV->new({
		sep_char    => q{,},
		escape_char => q{\\},
		quote_char  => q{"},
	});

#new
sub new {
	my $class  = shift;
	my $ra_arg = shift;

	#build object from parent
	my $self = $class->SUPER::new($ra_arg);

	#create empty hash
	$self->{rh_value_of} = {};
	
	return $self;
}

#get or set value
sub value_of {
	my $self          = shift;
	my $identificator = shift;
	my $is_set = (@_ > 0 ? 1 : 0);	#get or set request depending on number of arguments
	my $value = shift;

	#check if we have identificator
	return if not $identificator;
	
	#value_of hash
	my $rh_value_of = $self->{rh_value_of};

	#lazy initialization is needed for get
	$self->_init() if not $is_set;

	#switch between set and get variant
	#set
	if ($is_set) {
		$rh_value_of->{$identificator} = $value;
	}
	#get
	else {
		return $rh_value_of->{$identificator}
	}
}

#save back changes 
sub store {
	my $self = shift;

	#lazy initialization
	$self->_init();

	#get local variables from self hash
	my $rh_value_of    = $self->{rh_value_of};
	my $file_name      = $self->{file_name};
	my $full_time_lock = $self->{full_time_lock};
	my $file_fh        = $self->{file_fh};

	if (not $full_time_lock) {
		open($file_fh, "+>>", $file_name) or croak "can't write to file '$file_name' - $OS_ERROR";
	
		#lock and truncate the access store file
		flock($file_fh, LOCK_EX) or croak "can't lock file '$file_name' - $OS_ERROR\n";
	}

	#do lazy init now becouse afterwards the file will be truncated
	$self->_init();
	
	#truncate the file so that we can store new results
	truncate($file_fh, 0) or croak "can't truncate file '$file_name' - $OS_ERROR\n";
	
	#loop through identificators and write to file
	foreach my $identificator (sort $self->ident_list()) {
		#combine values for csv file
		my $value = $self->value_of($identificator);

		#skip removed entries
		next if not defined $value;
		
		if (not $CSV_FORMAT->combine($identificator, $value)) {
			warn "invalid value to store to an csv file - ", $CSV_FORMAT->error_input(),"\n";
			next;
		}
		
		#print the line to csv file
		print {$file_fh} $CSV_FORMAT->string(), "\n";
	}
	
	close($file_fh);
}

#lazy initialization
sub _init {
	my $self = shift;
	
	return if $self->{lazy_init};

	#prevent from reexecuting
	$self->{lazy_init}   = 1;
	
	#get local variables from self hash
	my $rh_value_of         = $self->{rh_value_of};
	my $file_name           = $self->{file_name};
	my $ignore_missing_file = $self->{ignore_missing_file};
	my $full_time_lock      = $self->{full_time_lock};
	my $_no_lock            = $self->{_no_lock};
	
	#done with initialization if file_name empty
	return if not $file_name;

	#default open mode is reading
	my $open_mode = '<';
	
	#if full_time_lock is set do open for writting
	if ($full_time_lock) {
		if ($ignore_missing_file) {
			$open_mode = '+>>';
		}
		else {
			$open_mode = '+<';
		}
	}
	
	#open file with old stored values and handle error
	my $file_fh;
	if (not open($file_fh, $open_mode, $file_name)) {
		if (defined $ignore_missing_file) {
			return;
		}
		else {
			croak "can't read access file '$file_name' - $OS_ERROR";
		}
	}
	
	#do exclusive lock if full time lock
	if ($full_time_lock) {
		flock($file_fh, LOCK_EX) or croak "can't lock file '$file_name' - $OS_ERROR\n";
		seek($file_fh, 0, SEEK_SET);
	}
	#internal flag. used from within the same module if file is already locked
	elsif ($_no_lock) {
	}
	#otherwise shared lock is enought
	else {
		flock($file_fh, LOCK_SH) or croak "can't lock file '$file_name' - $OS_ERROR\n";
	}

	#parse lines and store values in the hash
	LINE:
	while (my $line = <$file_fh>) {
		#verify line. if incorrect skip with warning
		if (!$CSV_FORMAT->parse($line)) {
			warn "badly formated '$file_name' csv line ", $file_fh->input_line_number(), " - '$line'. skipping\n";
			next LINE;
		}
		
		#extract fields
		my ($identificator, $value) = $CSV_FORMAT->fields();

		#save the value that we have now in hash
		my $new_value = $self->value_of($identificator);
				
		#set the value from file
		$self->value_of($identificator, $value);

		#if we already changed this value update over it
		if (defined $new_value) {
			$self->value_of($identificator, $new_value);
		}
	}
	
	#if full time lock then store file handle
	if ($full_time_lock) {
		$self->{file_fh} = $file_fh;
	}
	#otherwise release shared lock and close file
	else {
		flock($file_fh, LOCK_UN) if not $_no_lock;
		close($file_fh);
	}
}

sub ident_list {
	my $self = shift;

	#lazy initialization
	$self->_init();

	#get local variables from self hash
	my $rh_value_of = $self->{rh_value_of};

	return keys %{$rh_value_of};
}

sub finish {
	my $self = shift;

	#get local variables from self hash
	my $file_fh = $self->{file_fh};

	if ($file_fh) {
		close($file_fh);
	}	

	$self->{file_fh} = undef;
}

sub DESTROY {
	my $self = shift;

	$self->finish();	
}


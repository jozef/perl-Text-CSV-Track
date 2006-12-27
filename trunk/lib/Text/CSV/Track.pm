=head1 NAME

Text::CSV::Track - module to work with .csv file that stores some value per identificator

=head1 VERSION

v1.0 - created to track last login time

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
	
	#print out all the indentificators we have
	foreach my $login (sort $access_time->ident_list()) {
		print "$login\n";
	}

=head1 DESCRIPTION

the module reads csv file:

"identificator","numeric value"
...

and can return the numeric value for the identificator or update it

=head1 METHODS

=over 4

=item new()

	new({
		file_name           => 'filename.csv',
		ignore_missing_file => 1,
		
	})
	
	both file_name and ignore_missing_file are optional.
	
	'file_name' is used to read old results and then store the updated ones

	if 'ignore_missing_file' is set then the lib will just warn that it can not
	read the file. store() will use this name to store the results.

=item value_of()

	is used to both store or retrieve the value. if called with one argument
	then it is a read. if called with two arguments then it will update the
	value. The update will be done ONLY if the supplied value is bigger.
	
=item store()

	when this one is called it will write the changes back to file

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
Text::CSV::TrackMAX->mk_accessors(qw(file_name rh_value_of lazy_init ignore_missing_file));

use FindBin;

use Text::CSV;
use Carp::Clan;
use English qw(-no_match_vars);
use Fcntl ':flock'; # import LOCK_* constants

#readonly defaults

my $ACCESS_CSV_FORMAT = Text::CSV->new({
		sep_char    => q{,},
		escape_char => q{\\},
		quote_char  => q{"},
	});

#get or set access_time of active card user
sub value_of {
	#arg
	my $self          = shift;
	my $indetificator = shift;

	#separate get and set request depending on number of arguments
	my $is_set = 0;
	$is_set    = 1 if (@_ > 0);

	#arg
	my $max_value = shift;

	#lazy initialization
	$self->_init();
			
	
	#check if we have ac_login
	return if not $indetificator;
	
	#access_time_of hash
	my $rh_value_of = $self->{rh_value_of};

	#switch between set and get variant
	#set
	if ($is_set) {
		#if access_time is 'undef' then remove it from the hash
		if (not defined $max_value) {
			delete $rh_value_of->{$indetificator};
		}
		#update value in hash
		else {
			$rh_value_of->{$indetificator} = $max_value;
		}
	}
	#get
	else {
		return $rh_value_of->{$indetificator}
	}
}

#save back changes 
sub store {
	my $self = shift;

	#lazy initialization
	$self->_init();

	#get local variables from self hash
	my $rh_value_of = $self->{rh_value_of};
	my $file_name   = $self->{file_name};

	open(my $file_fh, "+>>", $file_name) or croak "can't write to file '$file_name' - $OS_ERROR";
	
	#lock and truncate the access store file
	flock($file_fh, LOCK_EX) or croak "can't lock file '$file_name' - $OS_ERROR\n";
	truncate($file_fh, 0) or croak "can't truncate file '$file_name' - $OS_ERROR\n";
	
	foreach my $indetificator (sort $self->ident_list()) {
		#combine values for csv file
		if (not $ACCESS_CSV_FORMAT->combine($indetificator, $rh_value_of->{$indetificator})) {
			warn "invalid value to store to an csv file - ", $ACCESS_CSV_FORMAT->error_input(),"\n";
			next;
		}
		
		#print the line to csv file
		print {$file_fh} $ACCESS_CSV_FORMAT->string(), "\n";
	}
	
	close($file_fh);
}

#lazy initialization
sub _init {
	my $self = shift;
	
	return if $self->{lazy_init};

	#set default values
	$self->{lazy_init}   = 1;
	$self->{rh_value_of} = {};
	
	#get local variables from self hash
	my $rh_value_of         = $self->{rh_value_of};
	my $file_name           = $self->{file_name};
	my $ignore_missing_file = $self->{ignore_missing_file};
	
	#done with initialization if file_name empty
	return if not $file_name;
	
	#open file with old stored access times and handle error
	my $file_fh;
	if (not open($file_fh, "<", $file_name)) {
		if (defined $ignore_missing_file) {
			warn "skipping reading of access file '$file_name' - $OS_ERROR\n";
			return;
		}
		else {
			croak "can't read access file '$file_name' - $OS_ERROR";
		}
	}
	
	#do shared lock
	flock($file_fh, LOCK_SH) or croak "can't lock file '$file_name' - $OS_ERROR\n";

	#parse lines and store values in the hash
	LINE:
	while (my $line = <$file_fh>) {
		#verify line. if incorrect skip with warning
		if (!$ACCESS_CSV_FORMAT->parse($line)) {
			warn "badly formated '$file_name' csv line ", $file_fh->input_line_number(), " - '$line'. skipping\n";
			next LINE;
		}
		
		#extract fields
		my ($indetificator, $max_value) = $ACCESS_CSV_FORMAT->fields();

		#update access time
		$self->value_of($indetificator, $max_value);
	}
	
	close($file_fh);
}

sub ident_list {
	my $self = shift;

	#lazy initialization
	$self->_init();

	#get local variables from self hash
	my $rh_value_of = $self->{rh_value_of};

	return keys %{$rh_value_of};
}

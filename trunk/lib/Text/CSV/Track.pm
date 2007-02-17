=head1 NAME

Text::CSV::Track - module to work with .csv file that stores some value(s) per identificator

=head1 VERSION

This documentation refers to version 0.4. 

=head1 SYNOPSIS

	use Text::CSV::Track;
	
	#create object
	my $access_time = Text::CSV::Track->new({ file_name => $file_name, ignore_missing_file => 1 });
	
	#set single value
	$access_time->value_of($login, $access_time);

	#fetch single value
	print $access_time->value_of($login);

	#set multiple values
	$access_time->value_of($login, $access_time);
	
	#fetch multiple values
	my @fields = $access_time->value_of($login);
	
	#save changes
	$access_time->store();
	
	#print out all the identificators we have
	foreach my $login (sort $access_time->ident_list()) {
		print "$login\n";
	}

	#getting muticolumn by hash
	$track_object = Text::CSV::Track->new({
		file_name    => $file_name
		, hash_names => [ qw{ col coool } ]
	});
	my %hash = %{$track_object->hash_of('ident')};
	print "second column is: ", $hash{'coool'}, "\n";

	#setting multicolumn by hash
	$track_object->hash_of('ident2', { coool => 333 } );

=head1 DESCRIPTION

The module manipulates csv file:

"identificator","value1"
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

When setting and getting only single value value_of($ident) will return scalar.
If setting/getting multiple columns then an array.

=head1 METHODS

=over 4

=item new()

	new({
		file_name             => 'filename.csv',
		ignore_missing_file   => 1,
		full_time_lock        => 1,
		auto_store            => 1,
		ignore_badly_formated => 1,
		header_lines          => 3,
		hash_names            => [ qw{ column1 column2 }  ],
		single_column         => 1,
		trunc                 => 1,

		#L<Text::CSV> paramteres
		sep_char              => q{,},
		escape_char           => q{\\},
		quote_char            => q{"},
		always_quote          => 0,
		binary                => 0,
		type                  => undef,
	})
	
All flags are optional.

'file_name' is used to read old results and then store the updated ones

If 'ignore_missing_file' is set then the lib will just warn that it can not
read the file. store() will use this name to store the results.

If 'full_time_lock' is set the exclusive lock will be held until the object is
not destroyed. use it when you need both reading the values and changing the values.
If you need just read OR change then you don't need to set this flag. See description
about lazy initialization.

If 'auto_store' is on then the store() is called when object is destroied

If 'ignore_badly_formated_lines' in on badly formated lines from input are ignored.
Otherwise the modules calls croak.

'header_lines' specifies how many lines of csv are the header lines. They will
be skipped during the reading of the file and rewritten during the storing to the
file.

'hash_names' specifies hash names fro hash_of() function.

'single_column' files that store just the identificator for line. In this case during the read
1 is set as the second column. During store that one is dropped so single column will be stored
back.

'trunc' don't read previous file values. Header lines will persist.

See L<Text::CSV> for 'sep_char', 'escape_char', 'quote_char', 'always_quote', 'binary, type'

=item value_of()

Is used to both store or retrieve the value. if called with one argument
then it is a read. if called with two arguments then it will update the
value. The update will be done ONLY if the supplied value is bigger.

=item hash_of()

Returns hash of values. Names for the hash values are taken from hash_names parameter.

=item store()

when this one is called it will write the changes back to file.

=item ident_list()

will return the array of identificators

=item csv_line_of($ident)

Returns one line of csv for given identificator.

=back

=head1 TODO

	- mention Track::Max and Track::Min
	- ident_list() should return number of non undef rows in scalar context
	- strategy for Track ->new({ strategy => sub { $a > $b } })
	- then rewrite max/min to use it this way
	- different column as the first one as identiffier column
	- constraints for columns

=head1 SEE ALSO

L<Text::CSV::Trac::Max>, L<Text::CSV::Trac::Min>, SVN repository - L<http://svn.cle.sk/svn/pub/cpan/Text-CSV-Track/>

=head1 AUTHOR

Jozef Kutej <jozef.kutej@hp.com>

=cut 



package Text::CSV::Track;

our $VERSION = '0.4';
use 5.006;

use strict;
use warnings;

use base qw(Class::Accessor::Fast);
__PACKAGE__->mk_accessors(
	qw(
		file_name
		_file_fh
		_rh_value_of
		_lazy_init
		ignore_missing_file
		full_time_lock
		auto_store
		_no_lock
		ignore_badly_formated
		_csv_format
		header_lines
		_header_lines_ra
		hash_names
		single_column
		trunc

		sep_char
		escape_char
		quote_char
		always_quote
		binary
		type
	)
);

use FindBin;

use Text::CSV;
use Carp::Clan;
use English qw(-no_match_vars);
use Fcntl ':flock'; # import LOCK_* constants
use Fcntl ':seek';  # import SEEK_* constants
use List::MoreUtils qw { first_index };


#new
sub new {
	my $class  = shift;
	my $ra_arg = shift;

	#build object from parent
	my $self = $class->SUPER::new($ra_arg);

	#create empty hash
	$self->{_rh_value_of}     = {};
	$self->{_header_lines_ra} = [];
	
	return $self;
}

sub csv_line_of {
	my $self          = shift;
	my $identificator = shift;

	#combine values for csv file
	my @fields = $self->value_of($identificator);

	#removed entry
	return undef if (@fields == 1) and (not defined $fields[0]);

	#if in single column mode remove '1' from the start of the fields
	shift(@fields) if $self->single_column;
	
	croak "invalid value to store to an csv file - ", $self->_csv_format->error_input(),"\n"
		if (not $self->_csv_format->combine($identificator, @fields));
	
	return $self->_csv_format->string();
}

#get or set value
sub value_of {
	my $self          = shift;
	my $identificator = shift;
	my $is_set        = 0;	#by default get

	#if we have one more parameter then it is set
	my $value;
	if (@_ >= 1) {
		$is_set = 1;
		$value = \@_;
	}

	#check if we have identificator
	return if not $identificator;
	
	#value_of hash
	my $rh_value_of = $self->_rh_value_of;

	#lazy initialization is needed for get
	$self->_init() if not $is_set;

	#switch between set and get variant
	#set
	if ($is_set) {
		$rh_value_of->{$identificator} = $value;
	}
	#get
	else {
		return undef if not defined $rh_value_of->{$identificator};	
	
		#if we have more then one field return array
		if (@{$rh_value_of->{$identificator}} > 1) {
			return @{$rh_value_of->{$identificator}};
		}
		#otherwise return one and only value from array as scallar
		else {
			return ${$rh_value_of->{$identificator}}[0];
		}
	}
}

sub hash_of {
	my $self          = shift;
	my $identificator = shift;
	my $is_set        = 0;	#by default get

	croak "'hash_names' parameter not set" if not defined $self->hash_names;
	my @hash_names    = @{$self->hash_names};
	my @fields = $self->value_of($identificator);

	#if we have one more parameter then it is set
	my $rh;
	if (@_ >= 1) {
		$is_set = 1;
		$rh     = shift;
		
		croak "not a hash reference as set argument" if ref $rh ne 'HASH';
	}
	
	if ($is_set) {
		foreach my $key (keys %{$rh}) {
			my $index = first_index { $_ eq $key } @hash_names;
			
			croak "no such hash key name '$key'" if $index == -1;

			$fields[$index] = $rh->{$key};			
		}
		
		#save back the fields
		$self->value_of($identificator, @fields);
	}
	else {	
		my %hash;
		foreach my $name (@hash_names) {
			$hash{$name} = shift @fields;
		}
		
		return \%hash;
	}
}

#save back changes 
sub store {
	my $self = shift;

	#lazy initialization
	$self->_init();

	#get local variables from self hash
	my $rh_value_of    = $self->_rh_value_of;
	my $file_name      = $self->file_name;
	my $full_time_lock = $self->full_time_lock;
	my $file_fh        = $self->_file_fh;
	my $header_lines   = $self->header_lines;

	if (not $full_time_lock) {
		open($file_fh, "+>>", $file_name) or croak "can't write to file '$file_name' - $OS_ERROR";
	
		#lock and truncate the access store file
		flock($file_fh, LOCK_EX) or croak "can't lock file '$file_name' - $OS_ERROR\n";
	}

	#do lazy init now becouse afterwards the file will be truncated
	$self->_init();
	
	#truncate the file so that we can store new results
	truncate($file_fh, 0) or croak "can't truncate file '$file_name' - $OS_ERROR\n";

	#write header lines
	foreach my $header_line (@{$self->_header_lines_ra}) {
		print {$file_fh} $header_line;
		$header_lines--;
	}
	
	#if there are some missing lines then add empty ones
	while ($header_lines) {
		print {$file_fh} "\n";
		$header_lines--;
	}
	
	#loop through identificators and write to file
	foreach my $identificator (sort $self->ident_list()) {
		my $csv_line = $self->csv_line_of($identificator);

		#skip removed entries
		next if not $csv_line;
		
		#print the line to csv file
		print {$file_fh} $csv_line, "\n";
	}
	
	close($file_fh);
}

#lazy initialization
sub _init {
	my $self = shift;
	
	return if $self->_lazy_init;

	#prevent from reexecuting
	$self->_lazy_init(1);
	
	#get local variables from self hash
	my $rh_value_of         = $self->_rh_value_of;
	my $file_name           = $self->file_name;
	my $ignore_missing_file = $self->ignore_missing_file;
	my $full_time_lock      = $self->full_time_lock;
	my $_no_lock            = $self->_no_lock;
	my $header_lines_count  = $self->header_lines;

	#Text::CSV variables
	my $sep_char            = defined $self->sep_char    ? $self->sep_char    : q{,};
	my $escape_char         = defined $self->escape_char ? $self->escape_char : q{\\};
	my $quote_char          = defined $self->quote_char  ? $self->quote_char  : q{"};
	my $always_quote        = $self->always_quote;
	my $binary              = $self->binary;
	my $type                = $self->type;
	
	#done with initialization if file_name empty
	return if not $file_name;

	#define csv format
	$self->_csv_format(Text::CSV->new({
		sep_char     => $sep_char,
		escape_char  => $escape_char,
		quote_char   => $quote_char,
		always_quote => $always_quote,
		binary       => $binary,
		type         => $type,
	}));

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
		if ($ignore_missing_file) {
			$OS_ERROR = undef;
			return;
		}
		else {
			croak "can't read file '$file_name' - $OS_ERROR";
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

	#create hash of identificator => 1
	my %identificator_exist = map { $_ => 1 } $self->ident_list;

	#parse lines and store values in the hash
	LINE:
	while (my $line = <$file_fh>) {
		#skip header lines and save them for store()
		if ($header_lines_count) {
			#save push header line
			push(@{$self->_header_lines_ra}, $line);
			
			#decrease header lines code so then we will know when there is an end of headers
			$header_lines_count--;
			
			next;
		}
		
		#skip reading of values if in 'trunc' mode
		last if $self->trunc;
	
		#verify line. if incorrect skip with warning
		if (!$self->_csv_format->parse($line)) {
			chomp($line);			
			my $msg = "badly formated '$file_name' csv line " . $file_fh->input_line_number() . " - '$line'.\n";

			#by default croak on bad line			
			croak $msg if not $self->ignore_badly_formated;
			
			#if ignore_badly_formated_lines is on just print warning
			warn $msg;
			
			next;
		}
		
		#extract fields
		my @fields = $self->_csv_format->fields();
		my $identificator = shift @fields;
		
		#if in single column mode insert '1' to the fields
		unshift(@fields, 1) if $self->single_column;

		#save present fields
		my @old_fields = $self->value_of($identificator);
				
		#set the value from file
		$self->value_of($identificator, @fields);

		#set the value from before values from file was read !needed becouse of the strategy!
		$self->value_of($identificator, @old_fields) if $identificator_exist{$identificator};
	}
	
	#if full time lock then store file handle
	if ($full_time_lock) {
		$self->_file_fh($file_fh);
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
	my $rh_value_of = $self->_rh_value_of;

	return keys %{$rh_value_of};
}

sub finish {
	my $self = shift;

	#call store if in auto_store mode
	$self->store() if $self->auto_store;

	#get local variables from self hash
	my $file_fh = $self->_file_fh;

	if (defined $file_fh) {
		close($file_fh);
	}	

	$self->_file_fh(undef);
}

sub DESTROY {
	my $self = shift;

	$self->finish();	
}

1;

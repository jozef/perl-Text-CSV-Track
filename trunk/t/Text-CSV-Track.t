# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Text-CSV-Track.t'

#########################

use Test::More; # 'no_plan';
BEGIN { plan tests => 20 };

use Text::CSV::Track;

use File::Temp qw{tempfile};	#generate temp filename
use File::Spec qw{tmpdir};		#get temp directory
use File::Slurp qw{read_file write_file};		#reading whole file
use English qw(-no_match_vars);
use Fcntl ':flock'; # import LOCK_* constants

use strict;
use warnings;

#constants
my $DEVELOPMENT = 1;
my $MULTI_LINE_SUPPORT = 0;
my $EMPTY_STRING = q{};

ok(1,															'all required modules loaded'); # If we made it this far, we're ok.

#########################


### TEST WITHOUT FILE MANIPULATION

#creation of object
my $track_object = Text::CSV::Track->new();
ok(defined $track_object,								'object creation');
ok($track_object->isa('Text::CSV::Track'),		'right class');

#store one value
$track_object->value_of('test1', 123);
is($track_object->value_of('test1'), 123,			'one value storing');

#store ten more
foreach my $i (1..10) {
	$track_object->value_of("test value $i", 100 - $i);
}
is($track_object->ident_list, 11,					'has 11 elements');

#remove one
$track_object->value_of('test1', undef);
is($track_object->ident_list, 10,					'has 10 elements after removal');


### TESTS WITH NEW FILE
# and no full time locking

#generate temp file name
my $tmp_template = 'text-csv-track-XXXXXX';
my (undef, $short_file_name) = tempfile($tmp_template, OPEN => 0);
my $tmpdir = File::Spec->tmpdir();
my $file_name = $tmpdir.'/'.$tmp_template;	#default will be overwriteen if not in DEVELOPMENT mode

SKIP: {
	skip "random temp filename it's development time", 1 if $DEVELOPMENT;
	
	$file_name = $tmpdir.'/'.$short_file_name;
	ok(-w $tmpdir,											"temp filename is '$file_name'");
}

#remove temp file if exists
unlink($file_name);

#cleanup after tempfile()
$OS_ERROR = undef;

#try to read nonexisting file
$track_object = Text::CSV::Track->new({ file_name => $file_name });
eval { $track_object->value_of('test1') };
isnt($OS_ERROR, $EMPTY_STRING,						'OS ERROR if file missing');
$OS_ERROR = undef;

#try to read nonexisting file with ignoring on
$track_object = Text::CSV::Track->new({ file_name => $file_name, ignore_missing_file => 1 });
is($OS_ERROR, $EMPTY_STRING,							'no OS ERROR with ignore missing file on');
is($track_object->value_of('test1'), undef,		'undef in empty file');

#store 100 values
foreach my $i (1..100) {
	my $store_string = qq{store string's value number "$i" with "' - quotes and \\"\\' backslash quotes};
	$track_object->value_of("test value $i", $store_string);
}
is($track_object->ident_list, 100,					'has 100 elements with quotes and backslashes');

#save to file
eval { $track_object->store(); };
is($OS_ERROR, $EMPTY_STRING,							"no OS ERROR while saveing to '$file_name'");

#clean object
$track_object = undef;


### TEST WITH GENERATED FILE
$track_object = Text::CSV::Track->new({ file_name => $file_name });

is($track_object->ident_list, 100,					'has 100 elements after read');
my $ident = 'test value 23';
my $stored_string = qq{store string's value number "23" with "' - quotes and \\"\\' backslash quotes};
is($track_object->value_of($ident), $stored_string,
																'check one stored value');

#change a value
$track_object->value_of($ident,'"\\ ' x 10);
$ident = 'test value 2';
$track_object->value_of($ident, undef);

#save to file
eval { $track_object->store(); };
is($OS_ERROR, $EMPTY_STRING,							"save with removal and single change");

#clean object
$track_object = undef;


### MESS UP WITH FILE
my @lines = read_file($file_name);

#add one more line and reverse sort
$lines[10] = "xman1,muhaha\n";
@lines = reverse @lines;
write_file($file_name, @lines);

#check
$track_object = Text::CSV::Track->new({ file_name => $file_name });
is($track_object->value_of('xman1'), 'muhaha',
																'check manualy stored value');
$track_object = undef;

SKIP: {
	skip 'multiple line values not jet supported by Text::CSV', 1 if not $MULTI_LINE_SUPPORT;

	#add 2 line entry
	$track_object->value_of("xman2","muhaha\nhaha");
	$track_object->store();
	$track_object = undef;
	
	#check
	my $track_object = Text::CSV::Track->new({ file_name => $file_name });
	is($track_object->ident_list, 100,				'was double line entry added?');
	$track_object = undef;
}

#save a copy for comparation
my @bckup_lines = sort @lines;

#add badly formated line
push(@lines, qq{"aman2\n});
push(@lines, qq{"xman3,"muhaha\n});
write_file($file_name, @lines);

#check
$track_object = Text::CSV::Track->new({ file_name => $file_name });
is($track_object->ident_list, 99,					'was badly formated lines ignored?');
$track_object->store();
$track_object = undef;

sub compare_arrays {
	my ($first, $second) = @_;
	no warnings;  # silence spurious -w undef complaints
	return 0 unless @$first == @$second;
	for (my $i = 0; $i < @$first; $i++) {
	    return 0 if $first->[$i] ne $second->[$i];
	}
	return 1;
}

@lines = read_file($file_name);
@lines = sort @lines;
ok(compare_arrays(\@lines, \@bckup_lines),		'compare if now the values are the same as before adding two badly formated lines');


### TEST LOCKING

#open with full time locking
$track_object = Text::CSV::Track->new({ file_name => $file_name, full_time_lock => 1 });
open(my $fh, "<", $file_name) or die "can't open file '$file_name' - $OS_ERROR";
#active lazy initialization
$track_object->value_of('x', 0);
#try non blocking shared flock. it should fail
is(flock($fh, LOCK_SH | LOCK_NB), 0,				'try shared lock while in full time lock mode, should fail');
close($fh);
$track_object = undef;


### CLEANUP

#remove temporary file
unlink($file_name);


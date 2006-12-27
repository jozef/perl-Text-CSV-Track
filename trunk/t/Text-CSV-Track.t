# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Text-CSV-Track.t'

#########################

use Test::More 'no_plan';
#BEGIN { plan tests => 12 };

use Text::CSV::Track;

use File::Temp qw{tempfile};	#generate temp filename
use File::Spec qw{tmpdir};		#get temp directory
use English qw(-no_match_vars);

#constants
my $DEVELOPMENT = 1;
my $EMPTY_STRING = q{};

ok(1); # If we made it this far, we're ok.

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
$file_name = $tmpdir.'/'.$tmp_template;	#default will be overwriteen if not in DEVELOPMENT mode

SKIP: {
	skip "it's development time", 1 if $DEVELOPMENT;
	
	$file_name = $tmpdir.'/'.$short_file_name;
	ok(-w $tmpdir,											"temp filename is '$file_name'");
}

#remove temp file if exists
unlink($file_name);

#cleanup after tempfile()
$OS_ERROR = undef;

#try to read nonexisting file
my $track_object = Text::CSV::Track->new({ file_name => $file_name });
eval { $track_object->value_of('test1') };
isnt($OS_ERROR, $EMPTY_STRING,						'OS ERROR if file missing');
$OS_ERROR = undef;

#try to read nonexisting file with ignoring on
my $track_object = Text::CSV::Track->new({ file_name => $file_name, ignore_missing_file => 1 });
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
my $track_object = Text::CSV::Track->new({ file_name => $file_name });

is($track_object->ident_list, 100,					'has 100 elements after read');


### MESS UP WITH FILE

#add one more line and reverse sort

#add 2 line entry

#add badly formated line


### CLEANUP

#remove temporary file
#unlink($file_name);


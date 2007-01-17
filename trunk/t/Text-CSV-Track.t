# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Text-CSV-Track.t'

#########################

use Test::More 'no_plan';
#BEGIN { plan tests => 29 };

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
is(scalar grep (defined $track_object->value_of($_), $track_object->ident_list()), 10,
																'has 10 elements after removal');


### TESTS WITH NEW FILE
# and no full time locking

#generate temp file name
my $tmp_template = 'text-csv-track-XXXXXX';
my (undef, $short_file_name) = tempfile($tmp_template, OPEN => 0);
my $tmpdir = File::Spec->tmpdir();
my $file_name = $tmpdir.'/'.$tmp_template;	#default will be overwriteen if not in DEVELOPMENT mode

#in development it's better to have steady filename other wise it should be random
if ($DEVELOPMENT) {
	print "skip random temp filename it's development time\n";	
}
else {
	$file_name = $tmpdir.'/'.$short_file_name;
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
$stored_string = '"\\ ' x 10;
$track_object->value_of($ident, $stored_string);
my $ident2 = 'test value 2';
$track_object->value_of($ident2, undef);

#save to file
eval { $track_object->store(); };
is($OS_ERROR, $EMPTY_STRING,							"save with removal and single change");

#clean object
$track_object = undef;

#check
$track_object = Text::CSV::Track->new({ file_name => $file_name });
is($track_object->ident_list, 99,					'has 99 elements after read');
is($track_object->value_of($ident), $stored_string,			"is '$ident' '$stored_string'?");

#not storing this element
$ident = 'test value 2 2222';
$stored_string = '2222';
$track_object->value_of($ident, $stored_string);

#clean object
$track_object = undef;

#store was not called. should normaly not be called by DESTROY
$track_object = Text::CSV::Track->new({ file_name => $file_name });
is($track_object->value_of($ident), undef,		'was store() skipped by DESTROY?');

#now with auto_store
$track_object = Text::CSV::Track->new({ file_name => $file_name, auto_store => 1 });
$track_object->value_of($ident, $stored_string);
$track_object = undef;

#store was not called. should be now called by DESTROY
$track_object = Text::CSV::Track->new({ file_name => $file_name });
is($track_object->value_of($ident), $stored_string,'was store() called with auto_store by DESTROY?');

#clean object
$track_object = undef;

#delete before lazy init
$track_object = Text::CSV::Track->new({ file_name => $file_name });
$track_object->value_of($ident, undef);
$track_object->value_of($ident."don't know", "123"); #set some other so the count of records will be kept on 100
isnt($track_object->{_lazy_init}, 1,				'after set the lazy init should not be trigered');
$track_object->store();
$track_object = undef;

$track_object = Text::CSV::Track->new({ file_name => $file_name });
is($track_object->value_of($ident), undef,		'delete before lazy init');
$track_object = undef;


###
# MESS UP WITH FILE
my @lines = read_file($file_name);

#add one more line and reverse sort
$lines[10] = "xman1,muhaha\n";
@lines = reverse @lines;
write_file($file_name, @lines);

#check
$track_object = Text::CSV::Track->new({ file_name => $file_name });
is($track_object->value_of('xman1'), 'muhaha',
																'check manualy stored value');
#revert the change
$track_object->value_of('xman1', undef);
$track_object->store();
$track_object = undef;

SKIP: {
	skip 'multiple line values not jet supported by Text::CSV', 1 if not $MULTI_LINE_SUPPORT;

	#add 2 line entry
	$track_object->value_of("xman2","muhaha\nhaha");
	$track_object->store();
	$track_object = undef;
	
	#check
	my $track_object = Text::CSV::Track->new({ file_name => $file_name });
	is(100, 100,											'was double line entry added?');
	$track_object = undef;
}

#save a copy for comparation
my @bckup_lines = sort @lines;

#add badly formated line
push(@lines, qq{"aman2\n});
push(@lines, qq{"xman3,"muhaha\n});
write_file($file_name, sort @lines);

#check
$track_object = Text::CSV::Track->new({ file_name => $file_name });

$track_object->ident_list;

is($track_object->ident_list, 100,					'was badly formated lines ignored?');
$track_object->store();
$track_object = undef;

@lines = read_file($file_name);
@lines = sort @lines;
is_deeply(\@lines, \@bckup_lines,					'compare if now the values are the same as before adding two badly formated lines');


### TWO PROCESSES WRITTING AT ONCE

#do change in first process
$track_object  = Text::CSV::Track->new({ file_name => $file_name });
is($track_object->value_of('atonce2'), undef,	'atonce2 undef in first process');
$track_object->value_of('atonce','432');

#do change in second process
my $track_object2 = Text::CSV::Track->new({ file_name => $file_name });
is($track_object2->value_of('atonce'), undef,		'atonce undef in second process');
$track_object2->value_of('atonce2','234');

#now do store for both of them
$track_object->store();
$track_object2->store();

$track_object  = undef;
$track_object2 = undef;

#now read the result and check
$track_object  = Text::CSV::Track->new({ file_name => $file_name });
is($track_object->value_of('atonce2'), 234,		'do we have atonce2?');
is($track_object->value_of('atonce'), undef,		'do we miss atonce overwritten by second process?');

#same as above but now we have atonce and atonce2
#we test if in case we do only set-s we will inherite changes from other processes

#do change in first process
$track_object  = Text::CSV::Track->new({ file_name => $file_name });
$track_object->value_of('atonce', '2nd 432');

#do change in second process
$track_object2 = Text::CSV::Track->new({ file_name => $file_name });
$track_object2->value_of('atonce2', '2nd 234');

#now do store for both of them
$track_object2->store();
$track_object->store();

$track_object  = undef;
$track_object2 = undef;

#now read the result and check
$track_object  = Text::CSV::Track->new({ file_name => $file_name });
is($track_object->value_of('atonce'), '2nd 432',	'does atonce has the right value?');
is($track_object->value_of('atonce2'), '2nd 234',	'does atonce2 has the right value?');



### TEST LOCKING

#open with full time locking
$track_object = Text::CSV::Track->new({ file_name => $file_name, full_time_lock => 1 });
open(my $fh, "<", $file_name) or die "can't open file '$file_name' - $OS_ERROR";
$track_object->value_of('x', 1);
#check lazy init. it should succeed
isnt(flock($fh, LOCK_SH | LOCK_NB), 0,				'try shared lock while lazy init should not be activated, should succeed');
#release the lock
flock($fh, LOCK_UN) or die "flock ulock failed - $OS_ERROR";

#active lazy initialization
$track_object->value_of('x');
#try non blocking shared flock. it should fail
is(flock($fh, LOCK_SH | LOCK_NB), 0,				"try shared lock while in full time lock mode, should fail - $OS_ERROR");
$track_object = undef;

#try non blocking shared flock after object is destroied. now it should succeed
isnt(flock($fh, LOCK_SH | LOCK_NB), 0,				'try shared lock after track object is destroyed, should succeed');

close($fh);



### TEST multi column tracking
#store one value
$track_object = Text::CSV::Track->new({ file_name => $file_name, ignore_missing_file => 1 });
$track_object->value_of('multi test1', 123, 321);
is($track_object->value_of('multi test1'), 2,			'multi column storing in scalar context number of records');

my @got = $track_object->value_of('multi test1');
my @expected = (123, 321);
is_deeply(\@got, \@expected,							'multi column storing');

$track_object->store();
$track_object = undef;



### CLEANUP

#remove temporary file
unlink($file_name) if not $DEVELOPMENT;


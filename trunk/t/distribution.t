use Test::More;

eval 'use Test::Distribution';
plan( skip_all => 'Test::Distribution not installed') if $@;

Test::Distribution->import();

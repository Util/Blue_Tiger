#!perl -T
use strict;
use warnings;
use Test::More tests => 1;
use lib 'lib';

BEGIN {
    use_ok( 'PPIx::Transform::Perl5_to_Perl6' )
        or print "Bail out!\n";
}

note(
    'Testing PPIx::Transform::Perl5_to_Perl6'
        . " $PPIx::Transform::Perl5_to_Perl6::VERSION, Perl $], $^X"
);

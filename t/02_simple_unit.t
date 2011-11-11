#!perl -T
use strict;
use warnings;
use Carp;
use Test::More;
use lib 'lib';
use PPIx::Transform::Perl5_to_Perl6;

my $USAGE = <<'END_OF_USAGE';
Usage:
    perl t/02_simple_unit.t [n]
      or
    prove [-v] t/02_simple_unit.t
This test runs all the unit tests contained in 02_simple_unit.pl.
A single test number (1-based) can be given; e.g. to run the third test:
    perl t/02_simple_unit.t 3
END_OF_USAGE

die $USAGE if @ARGV > 1;
my $single_test = @ARGV ? shift : undef;

my $p5_and_p6_filename = 't/data/02_simple_unit/02_simple_unit.pl';

my $perl5_and_perl6_code = do {
    open my $fh, '<', $p5_and_p6_filename
        or die "Failed to open test data file '$p5_and_p6_filename': $!";
    local $/;
    <$fh>;
};

my $test_separator_re = qr{ ^ [#] [ ]? -{3,} \s* $ }msx;

my $test_re = qr{
  \A
                                   \n?
    \# \s* Name: [ ]*    ([^\n]+?) \n
    \# \s* In:   [ ]* \n     (.+?) \n
    \# \s* Out:  [ ]* \n     (.+?) \n
(?: \# \s* Warn: [ ]* \n     (.+?) \n )?
  \z
}msx;

my ( $first_block, @tests ) = split /$test_separator_re/, $perl5_and_perl6_code;

# Expect the first block to be comments only.
die if $first_block =~ /$test_re/;

if ($single_test) {
    @tests = $tests[$single_test-1];
}
plan tests => scalar(@tests);

# Replace each string with a named hash of its components.
for my $test_block (@tests) {
    my @fields = ( $test_block =~ /$test_re/ )
      or die "Ack! '$test_block'";

    # Force existance of any optional captures.
    $#fields = 3 if $#fields < 3;

    my %t;
    @t{ qw( NAME IN OUT WARN ) } = @fields;

    $t{WARN} = '' if not defined $t{WARN};
    $test_block = \%t;
}

for my $test_aref (@tests) {
    my %t = %{$test_aref};

    my $PPI_doc = PPI::Document->new( \$t{IN} ) or die;
#require PPI::Dumper; PPI::Dumper->new( $PPI_doc )->print;

    my @warnings;
    my $xlate = PPIx::Transform::Perl5_to_Perl6->new(
        WARNING_LOG => \@warnings,
    ) or die;

    $xlate->apply($PPI_doc)
        or die "Failed to apply xlate to PPI_doc: $t{IN}";

    my $actual_out  = $PPI_doc->serialize;
    my $actual_warn = join '', @warnings;
    chomp $actual_warn;

    my %actual   = ( OUT => $actual_out, WARN => $actual_warn );
    my %expected = ( OUT => $t{OUT},     WARN => $t{WARN}     );

    is_deeply( \%actual, \%expected, $t{NAME} ) or do {
        note explain( 'Original: ' => $t{IN} );
        note explain( 'Expected: ' => \%expected );
        note explain(   'Actual: ' => \%actual );
    }
}

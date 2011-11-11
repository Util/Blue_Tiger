package PPIx::Transform::Perl5_to_Perl6;
use strict;
use warnings;
use Carp         qw( croak );
use Scalar::Util qw( blessed );
use Params::Util qw( _INSTANCE _ARRAY _STRING );
use base 'PPI::Transform';

=head1 NAME

PPIx::Transform::Perl5_to_Perl6

A class to transform Perl 5 source code into equivalent Perl 6.

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use PPIx::Transform::Perl5_to_Perl6;

    my $transform = PPIx::Transform::Perl5_to_Perl6->new();

    # Read from one file and write to another
    $transform->file( 'some_perl_5_module.pm' => 'some_perl_5_module.pm6' );

    # Change a file in place
    $transform->file( 'some_perl_5_program.pl' );

    my $code_in = '$x = $y . $z';

    my $PPI_doc = PPI::Document->new( \$code_in ) or die;

    my $rc = $transform->apply($PPI_doc) or warn;

    my $code_out = $PPI_doc->serialize;
    # $code_out contains '$x = $y ~ $z'

=head1 DESCRIPTION

This class implements a document transform that will translate Perl 5 source
code into equivalent Perl 6.

=cut

=begin comments

2008-01-19  Bruce Gray
Wrote program.

This program will translate Perl 5 code into Perl 6. Mostly :)

Currently handles:
    Operator changes.

=end comments

=cut


# Scaffolding to allow us to work as a PPI::Transform.
sub new {
    my $self = shift->SUPER::new(@_);
    return $self;
}

sub document {
    croak 'Wrong number of arguments passed to method' if @_ != 2;
    my ( $self, $document ) = @_;
    croak 'Parameter 2 must be a PPI::Document!' if !_INSTANCE($document, 'PPI::Document');

    my $change_count = $self->_convert_Perl5_PPI_to_Perl6_PPI($document);

    # XXX Work-around for a bug in PPI.
    # PPI::Transform documentation on apply() says:
    #    Returns true if the transform was applied,
    #    false if there is an error in the transform process,
    #    or may die if there is a critical error in the apply handler.
    # but if the transform *is* applied without error, and no change happens as a result, then apply() incorrectly returns undef.
    return 1 if defined $change_count and $change_count == 0;

    return $change_count;
}


# Converts the passed document in-place!
# Returns number of changes, 0 if not changes, undef on error.
sub _convert_Perl5_PPI_to_Perl6_PPI {
    croak 'Wrong number of arguments passed to method' if @_ != 2;
    my ( $self, $PPI_doc ) = @_;
    croak 'Parameter 2 must be a PPI::Document!' if !_INSTANCE($PPI_doc, 'PPI::Document');

    my $change_count = 0;
    $change_count += $self->_translate_all_ops($PPI_doc);

    return $change_count;
}


# Each entry is either a straight translation,
# or a list of possible translations.
my %ops_translation = (
    '.'   =>   '~',
    '.='  =>   '~=',
    '->'  =>   '.',

    '=~'  =>   '~~',
    '!~'  =>   '!~~',
);

# Returns number of changes, 0 if not changes, undef on error.
sub _translate_all_ops {
    croak 'Wrong number of arguments passed to method' if @_ != 2;
    my ( $self, $PPI_doc ) = @_;

    my $ops_aref = $PPI_doc->find( 'PPI::Token::Operator' )
        or return 0;

    my $change_count;
    for my $op ( @{$ops_aref} ) {
        my $p5_op = $op->content;

        my $p6_op = $ops_translation{$p5_op}
            or next;

        if ( _STRING($p6_op) ) {
            $op->set_content( $p6_op );
            $change_count++;
        }
        else {
            croak "Don't know how to handle xlate of op '$p5_op' (is the entry in %ops_translation misconfigured?)";
        }
    }

    return $change_count;
}

1;

=head1 TODO

Move the rest of the original code slush into place.

=head1 SUPPORT

Please submit a ticket to:
    https://github.com/Util/Blue_Tiger/issues

Emails directly to the original author might be answered, but the discussion could not then be found and read by others.

=head1 AUTHOR

Bruce Gray E<lt>bgray@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2010-2011 Bruce Gray.

This program is free software; you can redistribute it and/or modify it under
the terms of version 2.0 of the Artistic License.

The full text of the license can be found in the LICENSE file included with
this module.

=cut
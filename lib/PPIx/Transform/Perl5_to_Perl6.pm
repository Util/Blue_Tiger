package PPIx::Transform::Perl5_to_Perl6;
use strict;
use warnings;
use Carp         qw( carp croak );
use Scalar::Util qw( blessed );
use Params::Util qw( _INSTANCE _ARRAY _ARRAY0 _STRING );
use base 'PPI::Transform';

BEGIN {
    # Before 1.204_03, PPI::Transform silently threw away all params to new().
    {
        no warnings 'numeric';
        use PPI::Transform 1.204 ();
    }
    my $ver = $PPI::Transform::VERSION;
    if ( $ver eq '1.204_01' or $ver eq '1.204_02' ) {
        die "PPI::Transform version 1.204_03 required--this is only version $ver";
    }
}

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
my %optional_initializer = map { $_ => 1 } qw( WARNING_LOG );
sub new {
    my $self = shift->SUPER::new(@_);

    my $bad = join "\n\t",
              grep { !$optional_initializer{$_} }
              sort keys %{$self};
    carp "Unexpected initializer keys are being ignored:\n$bad\n " if $bad;

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

    $self->_fix_PPI_shift_equals_op_bug($PPI_doc);

    my $change_count = 0;
    $change_count += $self->_translate_all_ops($PPI_doc);
    $change_count += $self->_change_sigils($PPI_doc);
    $change_count += $self->_change_casts($PPI_doc);
    $change_count += $self->_change_trailing_fp($PPI_doc);
    $change_count += $self->_insert_space_after_keyword($PPI_doc);
    $change_count += $self->_clothe_the_bareword_hash_keys($PPI_doc);

    return $change_count;
}


# PPI Bug: += is a single operator, but <<= is two operators, << and = .
# <<= should be one operator. Same for >>= .
sub _fix_PPI_shift_equals_op_bug {
    croak 'Wrong number of arguments passed to method' if @_ != 2;
    my ( $self, $PPI_doc ) = @_;

    my $ops_aref = $PPI_doc->find( 'PPI::Token::Operator' )
        or return;

    my @ops_to_delete;
    for my $op ( @{$ops_aref} ) {
        my $content = $op->content;

        next unless $content eq '<<'
                 or $content eq '>>';

        my $sib = $op->next_sibling
            or next;

        next unless $sib->class   eq 'PPI::Token::Operator'
                and $sib->content eq '=';

        $op->add_content('=');
        push @ops_to_delete, $sib;
    }

    $_->delete or warn for @ops_to_delete;

    return 1;
}


sub _get_all {
    croak 'Wrong number of arguments passed to sub' if @_ != 2;
    my ( $PPI_doc, $classname ) = @_;
    croak 'Parameter 1 must be a PPI::Document!' if !_INSTANCE($PPI_doc, 'PPI::Document');
    croak 'Parameter 2 must be a classname!'     if !_STRING($classname);

    $classname = "PPI::$classname" if $classname !~ m{^PPI::};

    my $aref = $PPI_doc->find($classname)
        or return;

    return @{$aref};
}

# Each entry is either a straight translation,
# or a list of possible translations.
my %ops_translation = (
    '.'   =>   '~',
    '.='  =>   '~=',
    '->'  =>   '.',

    '=~'  =>   '~~',
    '!~'  =>   '!~~',

    # Ternary op
    '?'   => '??',
    ':'   => '!!',

    # Bitwise ops
    # http://perlcabal.org/syn/S03.html#Changes_to_Perl_5_operators
    #   Bitwise operators get a data type prefix: +, ~, or ?.
    #   For example, Perl 5's | becomes either +| or ~| or ?|, depending
    #   on whether the operands are to be treated as numbers, strings,
    #   or boolean values.
    # In Perl 5, the choice of whether to treat the operation as numeric or
    # string depended on the data; In Perl 6, it depends on the operator.
    # Note that Perl 6 has a short-circuiting xor operator, (^^). Since Perl 5
    # had no equivalent operator, nothing should translate to ^^, but we might
    # spot code that could advise the user to inspect for a ^^ opportunity.
    # Note that Perl 5 has separate ops for prefix versus infix xor
    # (~ versus ^). Perl 6 uses typed ^ for both prefix and infix.
    '|'   => [ '+|', '~|', '?|' ], # bitwise or  ( infix)
    '&'   => [ '+&', '~&', '?&' ], # bitwise and ( infix)
    '^'   => [ '+^', '~^', '?^' ], # bitwise xor ( infix)
    '~'   => [ '+^', '~^', '?^' ], # bitwise not (prefix)

    '<<'  => [ '+<', '~<' ], # bitwise shift left
    '>>'  => [ '+>', '~>' ], # bitwise shift right
    '<<=' => [ '+<=', '~<=' ], # bitwise shift assign left
    '>>=' => [ '+>=', '~>=' ], # bitwise shift assign right
);

# Returns number of changes, 0 if not changes, undef on error.
sub _translate_all_ops {
    croak 'Wrong number of arguments passed to method' if @_ != 2;
    my ( $self, $PPI_doc ) = @_;

    my $change_count = 0;
    for my $op ( _get_all( $PPI_doc, 'Token::Operator' ) ) {
        my $p5_op = $op->content;

        my $p6_op = $ops_translation{$p5_op}
            or next;

        if ( _STRING($p6_op) ) {
            $op->set_content( $p6_op );
            $change_count++;
        }
        elsif ( _ARRAY($p6_op) ) {
            my @p6_ops = @{$p6_op};
            my $default_op = $p6_ops[0];

            my $possible_ops = join ', ', map { "'$_'" } @p6_ops;
            $self->log_warn(
                $op,
                "op '$p5_op' was"
               . " changed to '$default_op', but could have been"
               . " any of ( $possible_ops ). Verify the context!\n"
            );

            $op->set_content( $default_op );
            $change_count++;
        }
        else {
            carp "Don't know how to handle xlate of op '$p5_op'"
               . " (is the entry in %ops_translation misconfigured?)";
        }
    }

    return $change_count;
}

sub _change_sigils {
    croak 'Wrong number of arguments passed to method' if @_ != 2;
    my ( $self, $PPI_doc ) = @_;
    croak 'Parameter 2 must be a PPI::Document!' if !_INSTANCE($PPI_doc, 'PPI::Document');

    # Easy, since methods raw_type and symbol_type already contain the
    # logic to look at subscripts to figure out the real type of the variable.
    # Handles $foo[5]       -> @foo[5]       (array element),
    #         $foo{$key}    -> %foo{$key}    (hash  element),
    #     and @foo{'x','y'} -> %foo{'x','y'} (hash  slice  ).
    #
    # No change needed for     @foo[1,5]     (array slice  ).

    my $count = 0;
    for my $sym ( _get_all( $PPI_doc, 'Token::Symbol' ) ) {
        if ( $sym->raw_type ne $sym->symbol_type ) {
            $sym->set_content( $sym->symbol() );
            $count++;
        }
    }
}

sub _change_casts {
    croak 'Wrong number of arguments passed to method' if @_ != 2;
    my ( $self, $PPI_doc ) = @_;
    croak 'Parameter 2 must be a PPI::Document!' if !_INSTANCE($PPI_doc, 'PPI::Document');

    # PPI mis-parses `% $foo`, so we cannot easily convert to the
    # better-written '%($foo)'. See:
    #       bin/ppi_dump -e '%{$foo};' -e '%$foo;' -e '% $foo;' -e '% {$foo};'
    my $count = 0;
    for my $cast ( _get_all( $PPI_doc, 'Token::Cast' ) ) {
        my $s = $cast->next_sibling;
        if ( $s->isa('PPI::Token::Symbol') ) {
            # Don't do anything. %$foo is still a valid form in Perl 6.
        }
        elsif ( $s->isa('PPI::Structure::Block') ) {
            # %{...} becomes %(...). Same with @{...} and ${...}.
            if ( $s->start->content eq '{' and $s->finish->content eq '}' ) {
                 $s->start->set_content('(');
                $s->finish->set_content(')');
                $count++;
            }
        }
        else {
            $self->log_warn(
                $cast,
                'XXX May have mis-parsed a Cast - sibling class ', $s->class
            );
        }
    }

    return $count;
}

sub _change_trailing_fp {
    croak 'Wrong number of arguments passed to method' if @_ != 2;
    my ( $self, $PPI_doc ) = @_;
    croak 'Parameter 2 must be a PPI::Document!' if !_INSTANCE($PPI_doc, 'PPI::Document');

    # [S02] Implicit Topical Method Calls
    # ...you may no longer write a Num as C<42.> with just a trailing dot.
    my $count = 0;
    for my $fp ( _get_all( $PPI_doc, 'Token::Number::Float' ) ) {
        my $n = $fp->content;
        if ( $n =~ m{ \A ([_0-9]+) [.] \z }msx ) { # Could have underscore
            my $bare_num = $1;
            my $n0 = $n . '0';
            $fp->set_content( $n0 );
            $self->log_warn(
                $fp,
                "floating point number '$n' was changed to floating point number '$n0'. Consider changing it to integer '$bare_num'.",
            );
            $count++;
        }
    }

    return $count;
}

sub _insert_space_after_keyword {
    croak 'Wrong number of arguments passed to method' if @_ != 2;
    my ( $self, $PPI_doc ) = @_;
    croak 'Parameter 2 must be a PPI::Document!' if !_INSTANCE($PPI_doc, 'PPI::Document');

    # [S03] Minimal whitespace DWIMmery
    # Whitespace is in general required between any keyword and any opening
    # bracket that is I<not> introducing a subscript or function arguments.
    # Any keyword followed directly by parentheses will be taken as a
    # function call instead.
    #     if $a == 1 { say "yes" }            # preferred syntax
    #     if ($a == 1) { say "yes" }          # P5-ish if construct
    #     if($a,$b,$c)                        # if function call
    #
    # [S04] Statement parsing
    # Built-in statement-level keywords require whitespace between the
    # keyword and the first argument, as well as before any terminating loop.
    # In particular, a syntax error will be reported for C-isms such as these:
    #     if(...) {...}
    #     while(...) {...}
    #     for(...) {...}

    my %wanted = (
        if       => { 'PPI::Structure::Condition' => 1, },
        unless   => { 'PPI::Structure::Condition' => 1, },
        elsif    => { 'PPI::Structure::Condition' => 1, },
        while    => { 'PPI::Structure::Condition' => 1, },
        until    => { 'PPI::Structure::Condition' => 1, },
        given    => { 'PPI::Structure::Given'     => 1, },
        when     => { 'PPI::Structure::When'      => 1,
                      'PPI::Structure::List'      => 1, },
        for      => { 'PPI::Structure::List'      => 1,
                      'PPI::Structure::For'       => 1, },
        foreach  => { 'PPI::Structure::List'      => 1,
                      'PPI::Structure::For'       => 1, },
    );
    my $count = 0;
    for my $keyword ( _get_all( $PPI_doc, 'Token::Word' ) ) {
        my $expected_sib_types_href = $wanted{$keyword}
            or next;

        my $sib = $keyword->next_sibling
            or next;

        my $c = $sib->class
            or next;

        if ( $expected_sib_types_href->{$c} ) {
            my $space = PPI::Token::Whitespace->new(' ');
            $keyword->insert_after($space);
            $count++;
        }
    }

    return $count;
}

sub _only_schild {
    croak 'Wrong number of arguments passed to sub' if @_ != 2;
    my ( $element, $class ) = @_;

    my @ss_kids = $element->schildren;
    return unless @ss_kids == 1;
    my $child = $ss_kids[0];
    return unless $child->isa($class);
    return $child;
}

sub _clothe_the_bareword_hash_keys {
    croak 'Wrong number of arguments passed to method' if @_ != 2;
    my ( $self, $PPI_doc ) = @_;
    croak 'Parameter 2 must be a PPI::Document!' if !_INSTANCE($PPI_doc, 'PPI::Document');

    # Translate all the bareword hash keys into single-quote.
    my $count = 0;
    for my $subscript ( _get_all( $PPI_doc, 'Structure::Subscript' ) ) {

        # Must have this structure:
        #        PPI::Token::Symbol          '$z'
        #        PPI::Structure::Subscript   { ... }
        #          PPI::Statement::Expression
        #            PPI::Token::Word        'foo'

        next unless $subscript->sprevious_sibling->isa('PPI::Token::Symbol');

        next unless substr( $subscript,  0, 1 ) eq '{'
                and substr( $subscript, -1, 1 ) eq '}';

        my $expression = _only_schild($subscript, 'PPI::Statement::Expression')
            or next;

        my $word = _only_schild($expression, 'PPI::Token::Word')
            or next;

        my $quoted_word  = "'" . $word->content . "'";
        my $quoted_token = PPI::Token::Quote::Single->new($quoted_word);

        # Cannot use replace() because $quoted_token and $word differ in type.
        $word->insert_after($quoted_token) or warn;
        $word->delete or warn;

        $count++;
    }

    return $count;
}

sub log_warn {
    my ( $self, $loc, @message_parts ) = @_;
    my $message = join '', @message_parts;

    # $loc indicates the location where the warning or error occurred.
    # It could be an object that provides a location method,
    # or a hand-constructed location aref, or undef.
    my @location
        = !$loc                           ? ()
        : _ARRAY($loc)                    ? @{ $loc             }
        : _INSTANCE($loc, 'PPI::Element') ? @{ $loc->location() }
        : croak("Unknown type passed as location object: ".ref($loc))
        ;

    if (@location) {
        # Before PPI-1.204_05, ->location() only returned 3 elements.
        my ( $line, $rowchar, $col, $logical_line, $logical_file_name ) = @location;

        my $pos = $rowchar eq $col ? $col : "$rowchar/$col";

        $message = "At line $line, position $pos, " . $message;
    }

    my $log_aref = $self->{WARNING_LOG};
    if ( _ARRAY0($log_aref) ) {
        push @{$log_aref}, $message;
    }
    else {
        carp $message;
    }
}

1;

=head1 TODO

Move the rest of the original code slush into place.

=head1 SUPPORT

Please submit a ticket to:
    https://github.com/Util/Blue_Tiger/issues

Emails sent directly to the original author might be answered, but the discussion could not then be found and read by others.

=head1 AUTHOR

Bruce Gray E<lt>bgray@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2010-2011 Bruce Gray.

This program is free software; you can redistribute it and/or modify it under
the terms of version 2.0 of the Artistic License.

The full text of the license can be found in the LICENSE file included with
this module.

=cut

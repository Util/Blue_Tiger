#!/usr/bin/env perl
use strict;
use warnings;
use 5.012; # Probably works with lower versions, but not tested on them yet.
use PPIx::Regexp;
use PPIx::Regexp::Dumper;
use Data::Dumper; $Data::Dumper::Useqq = 1;
use Getopt::Long;

my $USAGE = <<"END_OF_USAGE";
$0 --elms [file ...]
    This program is a stand-alone Perl 5 to Perl 6 regexp translator.

    In this, its first incarnation, it has a special (and temporary) --elms option to
    automatically translate the data exported from http://elm.eu.org/elms/browse_elms.html

    If no options are given, then it translates each line as it is typed into the console.
END_OF_USAGE

GetOptions(
    'elms' => \( my $elms ),
) or die $USAGE;

my ( $DUMP_BEFORE, $DUMP_AFTER ) = ( 0, 0 );

=begin comments

This program is a stand-alone Perl 5 to Perl 6 regexp translator.
Quickly written due to this conversation:
  http://irclog.perlgeek.de/perl6/2013-08-07#i_7420578

Written in Perl 5 instead of Perl 6, because Perl 6 does not yet have PPI.

TODO:
    Change       . into \N        iff /s is in effect.
    Change ^ and $ into ^^ and $$ iff /m is in effect.
    Move modifiers from end to beginning.
    Translate non-alphas into escaped forms.
    Convert | to ||
        Is this needed?
    Translate tricks like [ ] and [|]  ???
    Warn about $1 becoming $0, etc ?
    Add tests.
    Integrate with the existing Blue Tiger code.
    Handle `use re` /flags mode? Probably not.
    Named capture: Translate qr{(?<FOO>bar)} into rx{ $<FOO>=[bar] } . See S05 "Named scalar aliasing to subpatterns"

=end comments

=cut

#say translate_regexp(
#    "qr{([DEQ].{0,1}[LIM].{2,3}[LIVMF][^P]{2,3}[LMVF].[LMIV].{0,3}[DE])|([DE].{0,1}[LIM].{2,3}[LIVMF][^P]{2,3}[LMVF].[LMIV].{0,3}[DEQ])}"
# "qr{foo}smx"
#   'qr{["]}'
#    "qr{[']}"
#    "qr{[ ]}"
#    "qr{abc{2,}}"
#    "qr(abc{2,})"
#    "qr{ab[-ce]{2,}}"
#    "qr{ab [c-ef-z]{19,}}" # /x changes ' ' from Token::Whitespace to Token::Literal!
#    "qr{(?:abc)}" # ?: changes from 'Structure::Capture	( ... )' to 'Structure::Modifier	(?: ... )'
#    'qr{(?mi)^(?:[a-z]|\d){1,2}(?=\s)}'  # Example from S05
#);

# From http://elm.eu.org/elms/browse_elms.html , export classes as tsv
if ($elms) {
    open my $fh, '<', 'elm_classes.tsv'
        or die;
    while (<$fh>) {
        chomp;
        next if /^\s*#/;
        next if /^"ELMIdentifier"/; # Header line
        my ( $id, $desc, $regex, $instances, $pdb_instances ) = split "\t";
        say 'P5: ', $regex;
        say 'P6: ', translate_regexp($regex);
        say '';
    }
    close $fh or warn;
}
else {
    while (<>) {
        chomp;
        next if /^\s*#/; # Skip commented-out lines.
        say translate_regexp($_);
    }
}
sub translate_regexp {
    die if @_ != 1;
    my ($regexp_in_a_string) = @_;

    my $re = PPIx::Regexp->new($regexp_in_a_string)
        or die;

    # Dump RE before changes are made.
    if ($DUMP_BEFORE) {
        say $re->source;
        my $d = PPIx::Regexp::Dumper->new($re) or die;
        $d->print();
    }

    # qr// becomes re//
    {
        my $e1 = $re->first_element;
        if ( $e1->content eq 'qr' ) {
            # S05: So you may use parens as your C<rx> delimiters, but only if you interpose whitespace
            my $spaces = ( $e1->next_sibling->delimiters eq '()' ) ? 1 : 0;
            $e1->{content} = 'rx' . ( ' ' x $spaces );
        }
    }

    # {2,5} becomes ** 2..5
    # {2,}  becomes ** 2..*
    # {,5}  becomes ** 0..5
    if ( my $sq_aref = $re->find( 'Structure::Quantifier' ) ) {
        for my $sq ( @{$sq_aref} ) {
            warn if $sq->start ->content ne '{';
            warn if $sq->finish->content ne '}';
            $sq->start ->{content} = ' ** '; # The trailing space is important, for {,5} not to become ***..5
            $sq->finish->{content} = ' ';
            my $tl_aref = $sq->find('Token::Literal')
                or warn "Empty Structure::Quantifier!!!";
            # Hmmm. 10,100 is 6 tokens, not 3!
            if ($tl_aref) {
                for my $i ( 0 .. $#{$tl_aref} ) {
                    next if $tl_aref->[$i]->content ne ',';
                    warn "XXX Probable bug in your regexp! FOO{,n} is not defined in Perl 5; translating to 0..n anyway\n";
                    $tl_aref->[$i]->{content} = ( $i == 0            ) ? '0..'
                                              : ( $i == $#{$tl_aref} ) ?  '..*'
                                              :                           '..'
                                              ;
                    last;
                }
            }
        }
    }

    #  [a-z] becomes  <[a..z]>
    # [-a-z] becomes <-[a..z]>
    if ( my $scc_aref = $re->find( 'Structure::CharClass' ) ) {
        for my $scc ( @{$scc_aref} ) {
            warn if $scc->start ->content ne '[';
            warn if $scc->finish->content ne ']';


            # If this is a CharClass with only 1 char (like PBP recommends instead of escaping),
            # replace with single-quoted string, or double-quoted if the char is a single-quote.
            # XXX Are the extra spaces needed?
            if ( $scc->children == 1 and ref $scc->child(0) eq 'PPIx::Regexp::Token::Literal' ) {
                my $q = $scc->child(0)->content eq q{'} ? q{"} : q{'};
                $scc->start ->{content} = ' ' . $q  ;
                $scc->finish->{content} = $q  . ' ' ;
                next;
            }


            $scc->start ->{content} = '<[';
            $scc->finish->{content} = ']>';

            # Handle negated ranges
            if ( $scc->negated() ) {
                # The ^ is stored in the type(), for some odd reason.
                warn if $scc->type->content ne '^';
                $scc->start->{content} = '<-[';
                $scc->type ->{content} = '';
            }

            if ( my $nr_aref = $scc->find( 'Node::Range' ) ) {
                for my $nr ( @{$nr_aref} ) {
                    my $c1 = $nr->child(1);
                    warn if $c1->content ne '-';
                    warn if $c1->class   ne 'PPIx::Regexp::Token::Operator';
                    $c1->{content} = '..';
                    $nr->child( 0)->{content} = ' ' . $nr->child( 0)->{content};
                    $nr->child(-1)->{content} =       $nr->child(-1)->{content} . ' ';
                }
            }
        }
    }

    # (?:abc) becomes [abc]
    if ( my $sm_aref = $re->find( 'Structure::Modifier' ) ) {
        for my $sm ( @{$sm_aref} ) {
            # Handling the simple case for now. Will handle more complex cases later; probably with a different approach.
            next if   $sm->type->content ne '?:';
            next if %{$sm->type->modifiers};

            warn if $sm->start ->content ne '(';
            warn if $sm->finish->content ne ')';
            $sm->start ->{content} = '[';
            $sm->finish->{content} = ']';
            $sm->type  ->{content} = '';
        }
    }

    #  (?=\s) becomes <?before \s>
    # (?<=\s) becomes <?after \s>
    if ( my $sa_aref = $re->find( 'Structure::Assertion' ) ) {
        for my $sa ( @{$sa_aref} ) {
            warn if $sa->start ->content ne '(';
            warn if $sa->finish->content ne ')';

            my $type = $sa->type->content;
            if ( $type eq '?=' ) {
                # Positive look-ahead
                $sa->start ->{content} = '<';
                $sa->finish->{content} = '>';
                $sa->type  ->{content} = '?before ';
            }
            elsif ( $type eq '?<=' ) {
                # Positive look-behind
                $sa->start ->{content} = '<';
                $sa->finish->{content} = '>';
                $sa->type  ->{content} = '?after ';
            }
            else {
                warn "Don't yet know how to handle a Structure::Assertion if type '$type':\n ", Dumper $sa;
            }

        }
    }

    if ($DUMP_AFTER) {
        my $d = PPIx::Regexp::Dumper->new($re) or die;
        $d->print();
    }

    # Use ->content instead of ->source, in order to reflects the changes we have made to the tree.
    return $re->content;
}
__END__

Relevant snippents from S05-regex.pod :

=item *

The new C<:Perl5>/C<:P5> modifier allows Perl 5 regex syntax to be
used instead.  (It does not go so far as to allow you to put your
modifiers at the end.)  For instance,

     m:P5/(?mi)^(?:[a-z]|\d){1,2}(?=\s)/

is equivalent to the Perl 6 syntax:

    m/ :i ^^ [ <[a..z]> || \d ] ** 1..2 <?before \s> /
      (?mi) ^ [<[ a..z ]>|\d] ** 1..2 (?=\s)}


=item *

The Perl 5 C<qr/pattern/> regex constructor is gone.

=item *

The Perl 6 equivalents are:

     regex { pattern }    # always takes {...} as delimiters
     rx    / pattern /    # can take (almost) any chars as delimiters

You may not use whitespace or alphanumerics for delimiters.  Space is
optional unless needed to distinguish from modifier arguments or
function parens.  So you may use parens as your C<rx> delimiters,
but only if you interpose whitespace:

     rx ( pattern )      # okay
     rx( 1,2,3 )         # tries to call rx function

(This is true for all quotelike constructs in Perl 6.)

The C<rx> form may be used directly as a pattern anywhere a normal C<//> match can.
The C<regex> form is really a method definition, and must be used in such a way that
the grammar class it is to be used in is apparent.

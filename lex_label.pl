#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;
use PPI;
use Data::Dumper; $Data::Dumper::Useqq = 1; $Data::Dumper::Sortkeys = 1;

my $BLOCK_IS_AT_SUBLEVEL = 1; # Should the actual ::Block braces appear to be its children's level, instead of it's own level?

my %lex;   # XXX Global - change to param? For every element in the tree, this holds its lexical scope level.
my %lex2;  # XXX Global - change to param? Holds the starting point element of each      lexical scope level.
my %lex2_flipped;
my @DEBUG;

my $program_path = './my_missing.pl';
die if not -e $program_path;

my $PPI_doc = PPI::Document->new( $program_path )
    or die "Could not generate PPI from file '$program_path'";
# $PPI_doc->index_locations;
# my $foo = $PPI_doc->complete; # Fails on bare blocks! PPI 1.218
# print Dumper $foo;
# say '!!!';

# XXX PPI::Statement::Compound says that do{} if $cond  is *not* a compound! How to handle?

# So far, I see no way that  a lexical scope can happen without Struct:Block, parented by either PPI::Statement::Compound or Statement::Sub
# XXX No, I still see no way a lexical scope can happen without Struct:Block, but it won't have a ::Compound or ::Sub parent if it is a `map` or `grep`; it just has a ::Statement parent then.


# PPI::Statement::Compound
#   PPI::Token::Word                'if'
#   PPI::Structure::Condition       ( ... )
#   PPI::Structure::Block           { ... }
#   PPI::Token::Word                'elsif'
#   PPI::Structure::Condition       ( ... )
#   PPI::Structure::Block           { ... }
#   PPI::Token::Word                'else'
#   PPI::Structure::Block           { ... }

# PPI::Statement::Sub
#   PPI::Token::Word                'sub'
#   PPI::Token::Word                'the_sub_name'
#   PPI::Structure::Block           { ... }


# PPI::Statement
#   PPI::Token::Symbol              '%hash'
#   PPI::Token::Operator            '='
#   PPI::Token::Word                'map'
#   PPI::Structure::Block           { ... }

use PPI::Dumper;
sub dump_it {
    die if @_ != 1;
    my ($thing_to_dump) = @_;
    my $Dumper = PPI::Dumper->new(
        $thing_to_dump,
        content    => 1,
        whitespace => 0,
        memaddr    => 1,
    ) or die;

    my @lines = $Dumper->list;

    # This code aligns all the content on the right-hand side.
    my $re = qr{
      ^
        (   \s* \d+ )
        (   \s+ \S+ )
        (?: [ ]* \t )?
        (   \S .*   )?
      $
    }msx;

    my @structs;
    my $max_len = 0;
    for my $line (@lines) {
        my ( $addr, $ws_and_class, $content ) = ( $line =~ /$re/ ) or warn;
        my $len = length $ws_and_class;
        $max_len = $len if $max_len < $len;
        push @structs, [ $addr, $ws_and_class, $content ];
    }

    for my $struct_aref (@structs) {
        my ( $addr, $ws_and_class, $content ) = @{$struct_aref};
        # $addr = sprintf '0x%016x', $addr;
        # $addr = sprintf '%016d', $addr;
        my $level1 = $lex{$addr} // '';
        # my $level2 = $lex2{$addr} ? '*' : '';
        my $level2 = $lex2_flipped{$addr} ? '*' : '';
        if ( not defined $content ) {
            # say join '   ', $addr, $ws_and_class;
            say join '   ', $addr, $level1, $level2, $ws_and_class;
        }
        else {
            $ws_and_class = sprintf "%-${max_len}s", $ws_and_class;
            # say join '   ', $addr, $ws_and_class, $content;
            say join '   ', $addr, $level1, $level2, $ws_and_class, $content;
        }
    }


    # say for @lines;
    say '---';
}

# use Scalar::Util qw(refaddr);
sub address_of {
    # Template code C<P> promises to pack a "pointer to a fixed length string".
    # Isn't this what we want? Let's try:
    #
    #     # allocate some storage and pack a pointer to it
    #     my $memory = "\x00" x $size;
    #     my $memptr = pack( 'P', $memory );
    #
    # But wait: doesn't C<pack> just return a sequence of bytes? How can we pass this
    # string of bytes to some C code expecting a pointer which is, after all,
    # nothing but a number? The answer is simple: We have to obtain the numeric
    # address from the bytes returned by C<pack>.
    #
    #     my $ptr = unpack( 'L!', $memptr );
#     $addr = refaddr( $ref )
    return sprintf '0x%016x', $_[0]->refaddr;
    # return join '', reverse unpack '(H2)*', pack 'L!', refaddr($_[0]);
}

# memaddr
#     Should the dumper print the memory addresses of each PDOM element.
#     True/false value, off by default.
# refaddr method???

if ( 1 == 0 ) {
    # XXX
    # This code was to explore the parents of ::Block nodes.
    # It might be obsolete now.

    my $blocks_aref = $PPI_doc->find( 'PPI::Structure::Block' )
        or return;

    ### dump_it($_) for @{$blocks_aref};


    # Start building a hash of what lexical level everything is at.
    # XXX What order does find() use?
    for my $block ( @{$blocks_aref} ) {
        # dump_it($block);
        my $top = $block->top;
        warn 'ok but not seen yet' if $top->class ne 'PPI::Document';
    # say "\nTop is ", join "\t", $top->class, address_of($top);

        # Walk up the tree until parent isa Compound or Sub
        my $p = $block->parent;
        while (1) {
            my $c = $p->class;
    # say "parent class is ", $c, ' ', address_of($p);
            last if $c eq 'PPI::Statement::Sub'         # sub
                 or $c eq 'PPI::Statement::Compound'    # for while if elsif else
                 or $c eq 'PPI::Statement';             # map, grep, List::MoreUtils::uniq_by(&@), etc
            die if $p == $top;
            warn "Parent is more than 1 level up! probably ok but not seen yet";
            $p = $p->parent;
        }
        my $type = $p->class eq 'PPI::Statement::Compound' ? $p->type : '<none>';  # XXX Ack! elsif/else shows as if, and empty block shows as `continue` (in PPI 1.218)!!!
        # say "parent class is ", join "\t", address_of($p), $p->class, $type;
        # say $p;
    # say "---\n";
    }
}
# XXX What does this look like?
#  my $hashref = {
#     a  => 1,
# };

# on start of block


# XXX Ack! anon subs are not ::Sub !
# Taking the code from PPI::Dumper::_dump and/or PPI::Node::find, rather than calling ->find(), so that I can add code into enter/exit points, where the original code has no hooks.
# Needs more code since indent level is always the same, and because lex level does not change on *every* recurse (just *some*).
{
    # my $level_start = 1; # Each level starts with 1, not 0.
    my $level_start = 0; # Each level starts with 1, not 0.
    # my @level = ($level_start); # XXX Global - change to param?

    # Since all the plain statements inbetween, say level 3.6 and 3.7, need to be at level 3, yet the info
    # about (6 was the last lexical sublevel we used so far in level 3) must be retained, we use the last
    # element of @level to keep that info, and omit that last element from read_level().
    # So, while within 3.7, all the plain PPI nodes secretly have @level == (3.7.0)
    # Since increments happen on entry, the only level containing 0 in its publicly-seen read_level()
    # is the MAIN level, which will show as just "0".
    my @level = ($level_start, $level_start); # XXX Global - change to param?
    # my @level = ($level_start); # XXX Global - change to param?
    sub next_level { $level[-1]++;              } # Increment.
    sub push_level { push @level, $level_start; } # Deeper.
    sub pop_level  { pop  @level;               } # Less deep.
    # sub read_level { join '.', @level           } # Turn into 5.2.6.4, etc.
    sub read_level { join '.', @level[0 .. ($#level-1)]           } # Turn into 5.2.6.4, etc.

    # Note that PPI::Node has a ->scope() method, returning a Boolean on if the node represents a lexical scope boundary.
    # This is not as useful as it would seem, since we need the start of scope to show up at the block, and ->scope()
    # is enabled for the (e.g.) `sub` or `if` statement that contains the ::Block.
    # Also, it looks like PPI::Statement::Sub returns false! XXX File a bug report!
    sub is_start_of_scope { return !! ( $_[0]->class eq 'PPI::Structure::Block' ) }

    sub determine_lexical_scope_levels {
        die if @_ != 1;
        my ($Element) = @_;
# say "Enter";
        # my $top = $Element->top;
        # warn 'ok? Not seen yet' if $top->class   ne 'PPI::Document';
        # warn 'ok? Not seen yet' if $top->refaddr != $Element->refaddr;

        # starting element; Possibly starting lexical scope
        my $element_started_scope = is_start_of_scope($Element);
# say "yes started scope" if $element_started_scope;

        next_level() if $element_started_scope;

        my $ra = $Element->refaddr; # XXX use hex version?
# Add code: If this is the start of a new level, then next/push. How to tell the difference?
        die if exists $lex{$ra};
        $lex{$ra} = read_level();
        # $lex{$ra} = $Element->isa('PPI::Node') && $Element->scope ? '!' : ' ';
        push @DEBUG, read_level;

        if ( $element_started_scope ) {
# say Dumper 'Before', \@level;
            push_level() if $element_started_scope;
# say Dumper 'After', \@level;

            # XXX Experimental; replace the lex level we just put into %lex, with the new incremented level.
            # This makes the ::Block show up at the same lex level as its contents.
            # We might not care. Play with enabling and disabling this line!
            $lex{$ra} = read_level() if $BLOCK_IS_AT_SUBLEVEL;

            die if exists $lex2{ read_level() };
            $lex2{ read_level() } = $ra;
        }

        # Recurse into our children
        if ( $Element->isa('PPI::Node') ) {
            for my $child ( @{ $Element->{children} } ) { # XXX Change to the published accessor? Node->children does not include brace tokens for PPI::Structure. Try it and see!
                # entering child
                determine_lexical_scope_levels( $child );
                # exiting child
            }
        }
        if ( $element_started_scope ) {
            pop_level() if $element_started_scope;
        }

        # leaving element; Possibly leaving lexical scope
        # pop_level() if $element_started_scope;
        # $output;
    }

}
determine_lexical_scope_levels($PPI_doc);
%lex2_flipped = reverse %lex2;
# print Dumper \%lex;
print Dumper \%lex2;
print Dumper \%lex2_flipped;
# print Dumper \@DEBUG;
dump_it($PPI_doc);


__END__
# Find all the named subroutines
my $sub_nodes = $PPI_doc->find(
      sub { $_[1]->isa('PPI::Statement::Sub') and $_[1]->name }
);

PPI::Document
isa PPI::Node
    isa PPI::Element
-
# Anything more elaborate, we go with the sub
$Document->find( sub {
      # At the top level of the file...
      $_[1]->parent == $_[0]
      and (
              # ...find all comments and POD
              $_[1]->isa('PPI::Token::Pod')
              or
              $_[1]->isa('PPI::Token::Comment')
      )
} );
    The function will be passed two arguments, the top-level "PPI::Node" you
    are searching in and the current PPI::Element that the condition is
    testing.

    The anonymous function should return one of three values. Returning true
    indicates a condition match, defined-false (0 or '') indicates no-match,
    and "undef" indicates no-match and no-descend.

    In the last case, the tree walker will skip over anything below the
    "undef"-returning element and move on to the next element at the same
    level.

    To halt the entire search and return "undef" immediately, a condition
    function should throw an exception (i.e. "die").

    Note that this same wanted logic is used for all methods documented to
    have a "\&wanted" parameter, as this one does.
-
statement
  For a "PPI::Element" that is contained (at some depth) within a
  PPI::Statement, the "statement" method will return the first parent
  Statement object lexically 'above' the Element.

  Returns a PPI::Statement object, which may be the same Element if the
  Element is itself a PPI::Statement object.

  Returns false if the Element is not within a Statement and is not itself a
  Statement.

my $Dumper = PPI::Dumper->new(
    $PPI_doc,
    content    => $content,
    whitespace => $whitespace,
) or die;

my @lines = $Dumper->list;
# use Data::Dumper; $Data::Dumper::Useqq=1;
#print Dumper \@a;

# This code aligns all the content on the right-hand side.
my $re = qr{
  ^
    (   \s* \S+ )
    (?: [ ]* \t )?
    (   \S .*   )?
  $
}msx;
my @structs;
my $max_len = 0;
for my $line (@lines) {
    my ( $ws_and_class, $content ) = ( $line =~ /$re/ ) or warn;
    my $len = length $ws_and_class;
    $max_len = $len if $max_len < $len;
    push @structs, [ $ws_and_class, $content ];
}

for my $struct_aref (@structs) {
    my ( $ws_and_class, $content ) = @{$struct_aref};
    if ( not defined $content ) {
        print $ws_and_class, "\n";
    }
    else {
        printf "%-${max_len}s   %s\n", $ws_and_class, $content;
    }
}

__END__

1 #!/usr/bin/env perl
1 use 5.010;

1 $fruit = 'apple';
1 print "$fruit\n";

1 if ( $diet = 'paleo' )
{
    $meat = 'Yes'; # `my` gets added here
}
else {
    $meat = 'Maybe';
}
print "$meat\n";


PPI::Document
  PPI::Token::Comment               '#!/usr/bin/env perl\n'
  PPI::Statement::Include
    PPI::Token::Word                'use'
    PPI::Token::Number::Float       '5.010'
    PPI::Token::Structure           ';'
  PPI::Statement
    PPI::Token::Symbol              '$fruit'
    PPI::Token::Operator            '='
    PPI::Token::Quote::Single       ''apple''
    PPI::Token::Structure           ';'
  PPI::Statement
    PPI::Token::Word                'print'
    PPI::Token::Quote::Double       '"$fruit\n"'
    PPI::Token::Structure           ';'
  PPI::Statement::Compound
    PPI::Token::Word                'if'
    PPI::Structure::Condition       ( ... )
      PPI::Statement::Expression
        PPI::Token::Symbol          '$diet'
        PPI::Token::Operator        '='
        PPI::Token::Quote::Single   ''paleo''
    PPI::Structure::Block           { ... }
      PPI::Statement
        PPI::Token::Symbol          '$meat'
        PPI::Token::Operator        '='
        PPI::Token::Quote::Single   ''Yes''
        PPI::Token::Structure       ';'
      PPI::Token::Comment           '# `my` gets added here'
    PPI::Token::Word                'else'
    PPI::Structure::Block           { ... }
      PPI::Statement
        PPI::Token::Symbol          '$meat'
        PPI::Token::Operator        '='
        PPI::Token::Quote::Single   ''Maybe''
        PPI::Token::Structure       ';'
  PPI::Statement
    PPI::Token::Word                'print'
    PPI::Token::Quote::Double       '"$meat\n"'
    PPI::Token::Structure           ';'
.
__END__
PPI::Document
  PPI::Token::Comment               '#!/usr/bin/env perl\n'
  PPI::Statement::Include
    PPI::Token::Word                'use'
    PPI::Token::Number::Float       '5.010'
    PPI::Token::Structure           ';'
  PPI::Statement
    PPI::Token::Symbol              '$fruit'
    PPI::Token::Operator            '='
    PPI::Token::Quote::Single       ''apple''
    PPI::Token::Structure           ';'
  PPI::Statement
    PPI::Token::Word                'print'
    PPI::Token::Quote::Double       '"$fruit\n"'
    PPI::Token::Structure           ';'
  PPI::Statement::Compound
    PPI::Token::Word                'if'
    PPI::Structure::Condition       ( ... )
      PPI::Statement::Expression
        PPI::Token::Symbol          '$diet'
        PPI::Token::Operator        '='
        PPI::Token::Quote::Single   ''paleo''
    PPI::Structure::Block           { ... }
      PPI::Statement
        PPI::Token::Symbol          '$meat'
        PPI::Token::Operator        '='
        PPI::Token::Quote::Single   ''Yes''
        PPI::Token::Structure       ';'
      PPI::Token::Comment           '# `my` gets added here'
    PPI::Token::Word                'else'
    PPI::Structure::Block           { ... }
      PPI::Statement
        PPI::Token::Symbol          '$meat'
        PPI::Token::Operator        '='
        PPI::Token::Quote::Single   ''Maybe''
        PPI::Token::Structure       ';'
  PPI::Statement
    PPI::Token::Word                'print'
    PPI::Token::Quote::Double       '"$meat\n"'
    PPI::Token::Structure           ';'


.
PPI::Statement::Compound
  PPI::Structure::Block           { ... }
    PPI::Statement
      PPI::Token::Symbol          '$grain'
      PPI::Token::Operator        '='
      PPI::Token::Quote::Single   ''wheat''
      PPI::Token::Structure       ';'
    PPI::Statement
      PPI::Token::Word            'print'
      PPI::Token::Quote::Double   '"$grain"'
      PPI::Token::Structure       ';'
.
PPI::Statement::Sub
  PPI::Token::Word                'sub'
  PPI::Token::Word                'foo1'
  PPI::Structure::Block           { ... }
    PPI::Statement
      PPI::Token::Word            'print'
      PPI::Token::Quote::Double   '"hi!\n"'
      PPI::Token::Structure       ';'

---
http://cpansearch.perl.org/src/MITHALDU/PPI-1.220/lib/PPI/Node.pm
    sub find {
        my $self   = shift;
        my $wanted = $self->_wanted(shift) or return undef;

        # Use a queue based search, rather than a recursive one
        my @found;
        my @queue = @{$self->{children}};
        my $ok = eval {
            while ( @queue ) {
                my $Element = shift @queue;
                my $rv      = &$wanted( $self, $Element );
                push @found, $Element if $rv;

                # Support "don't descend on undef return"
                next unless defined $rv;

                # Skip if the Element doesn't have any children
                next unless $Element->isa('PPI::Node');

                # Depth-first keeps the queue size down and provides a
                # better logical order.
                if ( $Element->isa('PPI::Structure') ) {
                    unshift @queue, $Element->finish if $Element->finish;
                    unshift @queue, @{$Element->{children}};
                    unshift @queue, $Element->start if $Element->start;
                } else {
                    unshift @queue, @{$Element->{children}};
                }
            }
            1;
        };
        if ( !$ok ) {
            # Caught exception thrown from the wanted function
            return undef;
        }

    	@found ? \@found : '';
    }

http://cpansearch.perl.org/src/MITHALDU/PPI-1.220/lib/PPI/Dumper.pm
    sub _dump {
        my $self    = ref $_[0] ? shift : shift->new(shift);
        my $Element = _INSTANCE($_[0], 'PPI::Element') ? shift : $self->{root};
        my $indent  = shift || '';
        my $output  = shift || [];

        # Print the element if needed
        my $show = 1;
        if ( $Element->isa('PPI::Token::Whitespace') ) {
            $show = 0 unless $self->{display}->{whitespace};
        } elsif ( $Element->isa('PPI::Token::Comment') ) {
            $show = 0 unless $self->{display}->{comments};
        }
        push @$output, $self->_element_string( $Element, $indent ) if $show;

        # Recurse into our children
        if ( $Element->isa('PPI::Node') ) {
            my $child_indent = $indent . $self->{indent_string};
            foreach my $child ( @{$Element->{children}} ) {
                $self->_dump( $child, $child_indent, $output );
            }
        }

        $output;
    }
    sub _dump {
        my $self    = ref $_[0] ? shift : shift->new(shift);
        my $Element = _INSTANCE($_[0], 'PPI::Element') ? shift : $self->{root};
        my $level  = shift || '';
        my $output  = shift || [];

        push @$output, $self->_element_string( $Element, $level );

        # Recurse into our children
        if ( $Element->isa('PPI::Node') ) {
            my $child_level = $level . add_a_level();
            for my $child ( @{ $Element->{children} } ) {
                # entering child
                $self->_dump( $child, $child_indent, $output );
                # exiting child
            }
        }

        $output;
    }
.

Make a separate counter that is the virtual last element of @level? Ignore last part of @level when making dot form?
Build a tree, too?
MAIN     #!/usr/bin/env perl
MAIN     use 5.010;
MAIN     
MAIN     $fruit = 'apple';
MAIN     print "$fruit\n";
MAIN     
MAIN     if ( $diet = 'paleo' )
MAIN.1?  {
MAIN.1      $meat = 'Yes'; # `my` gets added here
MAIN.1?  }
MAIN     elsif ( $diet = 'vegan' )
MAIN.2?  {
MAIN.2       $meat = 'No';
MAIN.2?  }
MAIN     else
MAIN.3?  {
MAIN.3      $meat = 'Maybe';
MAIN.3?  }
MAIN     print "$meat\n";
MAIN     
MAIN     $i = 0;
MAIN     while ($i++<5)
MAIN.4?  {
MAIN.4       $j = $i;
MAIN.4?  }
MAIN     print "$j\n";
MAIN     
MAIN     @array = grep
MAIN.5?  {
MAIN.5       $_ % 2 == 0
MAIN.5?  }
MAIN     1 .. 5;
MAIN     
MAIN     $c = 0;
MAIN     %hash = map
MAIN.6?  {
MAIN.6       $_ => $c++
MAIN.6?  }
MAIN     qw( salami baloney );
MAIN     
MAIN     # Bug! Adding this block causes Document->complete to fail!!!!
MAIN.7?  {
MAIN.7       $grain = 'wheat';
MAIN.7       print "$grain";
MAIN.7?  }
MAIN     
MAIN     sub foo1
MAIN.8?  {
MAIN.8       if ( $burned_out )
MAIN.8.1?    {
MAIN.8.1         $unstable++;
MAIN.8.1?    }
MAIN.8       if ( !$burned_out )
MAIN.8.2?    {
MAIN.8.2         $unstable--;
MAIN.8.2?    }
MAIN.8       print "hi!\n";
MAIN.8?  }

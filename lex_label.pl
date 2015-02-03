#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;
use PPI;
use Data::Dumper; $Data::Dumper::Useqq = 1; $Data::Dumper::Sortkeys = 1;

my $program_path = './my_missing.pl';

# List of things we are figuring out:
#     Where are the lexical scopes? Where do they start, and end? Which statements are in which scopes?
#     Where are the subs?           Where do they start, and end? Which statements are in which subs, or in MAINline?
#     Where are vars used (via, R, W, etc)?
#         If used in a sub, and the sub cannot isolate via my(), doesn't that infect all scopes?
#     How are vars used in each statement? Read-only, read-write, write-read, write-only?
#     Using the scope locations and RO/RW values, for each variable, determine where `my` can be added (it may be multiple locations).
#     Determine all code mods needed, and extract changes to be independent of the memory refaddrs.
#     Modify the code: Add the `my` keyword to the declaring statements, and/or insert a new `my` statement above the outermost common scope allowed by RO/RW/Sub.
#         Do this in reverse order, walking up the tree or line/rowchar order.

# XXX Need to better define my data structures!

# XXX Need to add code to deal with (at least warn on) fully qualified variable names.
# Would work better as False, to allow for 1TBS
# my $BLOCK_IS_AT_SUBLEVEL = 1; # Should the actual ::Block braces appear to be its children's level, instead of it's own level?
my $BLOCK_IS_AT_SUBLEVEL = 0; # Should the actual ::Block braces appear to be its children's level, instead of it's own level?

# Change these to a single (or couple) of hashes (HoR)???
# XXX Globals; XXX change to params?
# XXX Merge these into ELEMENTS
my %lex;            # For every element in the tree, this holds its lexical scope level.
my %lex2;           # Holds the starting point element of each      lexical scope level.
my %lex2_flipped;
my %location;       # For every element in the tree, this holds its location by refaddr, to make it easier to find without walking later.
my %is_whitespace;

my @lines_AoA;      # For each line of source, refaddrs.

# Consolidate!
my %symbols;        # HoA of '@array' => [ refaddr1, refaddr2, ... ];
my %symbol_first_seen; # HoA of '@array' => [ refaddr, $line, $rowcol ];

# my %containing_statement; # refaddr => [ element, ref]

my %addr_element;   # Every element from the PPI tree, indexed by refaddr for reverse lookup.

my @DEBUG;

# XXX Hmmm. I might want a separate array just for $Element itself, to ease dumping?
# XXX Delay this for now
# my @ELEMENTS;       # Linearly assigned AoR; Fields are:
    # INDEX         => $ELEMENTS.index_number, 
    # ELEMENT       => $Element, # pointer to the real PPI::Element ,
    # REFADDR       => $Element->refaddr,
    # LOCATION      => $Element->location == [ $line, $rowchar, $col, $logical_line, $logical_file_name ]
    # IS_WHITESPACE => Bool,
    # IS_IN_SUB     => Bool,
    # LEXICAL_SCOPE => String, # 5.8.7.3

# Note that @ELEMENTS is indexed on REFADDR via the hash %XXX.

die if not -e $program_path;

my $PPI_doc = PPI::Document->new( $program_path )
    or die "Could not generate PPI from file '$program_path'";
# XXX Add location indexing before anything else, to keep memory addresses from changing?
$PPI_doc->index_locations;
# my $foo = $PPI_doc->complete; # Fails on bare blocks! PPI 1.218
# print Dumper $foo;
# say '!!!';

# XXX PPI::Statement::Compound says that do{} if $cond  is *not* a compound! How to handle?

# So far, I see no way that  a lexical scope can happen without Struct:Block, parented by either PPI::Statement::Compound or Statement::Sub
# XXX No, I still see no way a lexical scope can happen without Struct:Block, but it won't have a ::Compound or ::Sub parent if it is a `map` or `grep`; it just has a ::Statement parent then.

use PPI::Dumper;
sub dump_it {
    die if @_ != 1;
    my ($thing_to_dump) = @_;
    my $Dumper = PPI::Dumper->new(
        $thing_to_dump,
        content    => 1,
        # whitespace => 0,
        whitespace => 1,
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
        my $level1 = sprintf '%-15s', ($lex{$addr} // '');
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

sub address_of {
    return sprintf '0x%016x', $_[0]->refaddr;
}

# memaddr
#     Should the dumper print the memory addresses of each PDOM element.
#     True/false value, off by default.
# refaddr method???

if ( 1 == 1 ) {
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

    # Code adapted from recursive _dump() in PPI/Dumper.pm
    # XXX Consider using the queuing code from PPI::Node::find() ???
    sub determine_lexical_scope_levels {
        die if @_ != 1;
        my ($Element) = @_;

        # warn 'ok? Not seen yet' if $Element->top ne 'PPI::Document';


        # starting element; Possibly starting lexical scope
        my $element_started_scope = is_start_of_scope($Element);

        next_level() if $element_started_scope;

        my $ra = $Element->refaddr; # XXX use hex version?
$addr_element{$ra} = $Element;
        die if exists $lex{$ra};
        $lex{$ra} = read_level();
        push @DEBUG, read_level;

        $is_whitespace{$ra} = 1 if $Element->class eq 'PPI::Token::Whitespace';

        my @loc = @{ $Element->location };
        my ( $line, $rowchar, $col, $logical_line, $logical_file_name ) = @loc;
        # $rowchar is the literal horizontal character, and $col is the visual column, taking into account tabbing.
        $location{$ra} = [ @loc ];
        push @{ $lines_AoA[ $line ] }, $ra;      # For each line of source, refaddrs.

        # {
        #     my $next_element_number = 1 + $#ELEMENTS;
        #     # XXX Not testted against $element_started_scope !!!
        #     push @ELEMENTS, {
        #         INDEX         => $next_element_number,
        #         ELEMENT       => $Element, # pointer to the real PPI::Element ,
        #         REFADDR       => $Element->refaddr,
        #         LOCATION      => [ @{ $Element->location } ],
        #         IS_WHITESPACE => !!($Element->class eq 'PPI::Token::Whitespace'),
        #         # IS_IN_SUB     => Bool,
        #         LEXICAL_SCOPE => read_level(),
        #     };
        # }

        if ( $element_started_scope ) {
            push_level() if $element_started_scope;

            # XXX Experimental; replace the lex level we just put into %lex, with the new incremented level.
            # This makes the ::Block show up at the same lex level as its contents.
            # We might not care. Play with enabling and disabling this line!
            # $lex{$ra} = read_level() if $BLOCK_IS_AT_SUBLEVEL;

            die if exists $lex2{ read_level() };
            $lex2{ read_level() } = $ra;
        }

        if ( $Element->class eq 'PPI::Token::Symbol' ) {
            # push @{ $symbols{ $Element->symbol} }, $ra;
            my $real_sym = $Element->symbol; # This shows @array when used as $array[3] !
            push @{ $symbols{$real_sym} }, [ $ra, read_level() ];

            $symbol_first_seen{$real_sym} //= [ $ra, $line, $rowchar ];

# XXX Need to track where a simple my() can be used, vs where a statement must be inserted.
            # XXX Need to add code to show location found, too?
            # Hmmm. $grain is only found in one block, and it is written to on the first occurance.
            # OK to add my, or my()???
            # 0.8            32     $grain = 'wheat';
            # 0.8            33     print "$grain";
            # XXX Note that any parent being a sub may change things!
            # ++ and -- are read-write. How to say it is OK to be undefined? Do I care?
            
            # 0              36 sub foo1 {
            # 0.9            37     if ( $burned_out ) {
            # 0.9.1          38         $unstable++;
            # 0.9.1          39     }
            # 0.9            40     if ( !$burned_out ) {
            # 0.9.2          41         $unstable--;
            # 0.9.2          42     }
            # 0.9            43     print "hi!\n";
            # 0              44 }
            # $unstable occurs in 0.9.1 and 0.9.2, which is more than one level.
            # Find lowest common parent, which is 0.9
            # 0.9 is one level above the earliest occurance (0.9.1), so locate my() just before statement containing the 0.9.1 block.
            
            # 0              18 $i = 0;
            # 0              19 while ($i++<5) {
            # 0.4            20     $j = $i;
            # 0              21 }
            # 0              22 print "$j\n";
            # $j must be defined at the line preceeding the statement that starts level 0.4,
            # so before the `while` on 19.

            # 0.6            !!
            # 0.7            28 %hash = map { $_ => ++$c } grep { /a/ } grep /s/, qw( salami baloney );
            # 0              !!
            # 0.8            !!
            # 0.9            29 %hash = map { $_ => ++$d } grep { /a/ } grep /s/, qw( salami baloney ); # Test redefiniion and $d not being initialized.
            # Hmmm. The line contains 0.8 and 0.9, but $d is only in 0.8.
            # It is a read-write, though.
            # $d must have its my() just before the statement that defineds 0.8.

            # XXX Need to test unknown_sub( $foo ); mechanism to determine r-o vs r-w 
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
# print Dumper \%lex2;
# print Dumper \%lex2_flipped;
# print Dumper \%location;
# print Dumper \@lines_AoA;
print Dumper \%symbols;
# print Dumper [@ELEMENTS[0..3]];
# print Dumper \@ELEMENTS;
# print Dumper \@DEBUG;
dump_it($PPI_doc);

# XXX Change from printing refaddr to using an array of Elements, with a single hash xref of refaddr-to-array-index.
# This is so we can stop debugging with refaddrs, since they change from run to run.

# Print the original file's contents, showing the lexical level beside each line.
if ( 1 == 1 ) {
    my @lines = split "\n", $PPI_doc->serialize;
    for my $i ( 0 .. $#lines ) {
    # say '---';
        my $line = $lines[$i];
        my $num  = $i + 1;
    
        my @element_addresses_in_line = @{ $lines_AoA[$num] };

        # In most structures, there is whitespace (often newline) following the
        # opening brace, but on the same line. We want to discount that whitespace
        # when determining a line's lexical level, otherwise a line with an opening
        # brace will *always* be in two levels!
        my @non_whitespace_element_addresses_in_line = grep { !$is_whitespace{$_} } @element_addresses_in_line;

        my %h;
        $h{$_}++ for map { $lex{$_} }  @non_whitespace_element_addresses_in_line;
        my @levels = sort keys %h;

        push @levels, $lex{ $element_addresses_in_line[0] } if ! @levels; # Caused by a whitespace-only line.

        # Lines can have multiple lexical levels if they are like:
        #    @a = grep { $_ > 3 } @b;
        # We list all but the last level on separate lines (to avoid messing up the indentation), and use !! as a visual marker for such occurances.
        while ( @levels > 1 ) {
            printf "%-7s\t%7s\n", shift(@levels), '!!';
        }

        die if @levels != 1;
        printf "%-7s\t%7d\t%s\n", $levels[0], $num, $line;
    }
}

# Need a structure of first occurrence of each var in each scope it appears in?
for my $symbol ( sort keys %symbols ) {
say "!!! $symbol";
    my $occurances_aref = $symbols{$symbol};
    
    for my $occurance_aref ( @{$occurances_aref} ) {
        my ( $ra, $level ) = @{$occurance_aref};
        say "$ra, $level";
    }
}

my @symbols_ordered = sort { 
       $symbol_first_seen{$a}[1] <=> $symbol_first_seen{$b}[1] # line
    or $symbol_first_seen{$a}[2] <=> $symbol_first_seen{$b}[2] # rowchar
} keys %symbol_first_seen;

# XXX Move the symbol itself into its own hash for easier sorting and unpacking.
for my $sym (@symbols_ordered) {
    my ( $ra, $line, $rowchar ) = @{ $symbol_first_seen{$sym} };
    my $Element = $addr_element{$ra};
    my $statement = $Element->statement or die; # First parent Statement object lexically 'above' the Element. (or equal to, if Element is a Statement)
    say sprintf "%-15s\t%15s\t%2d\t%2d\t%s", $sym, $ra, $line, $rowchar, $statement->refaddr;
}

# XXX Everything using refaddr must be calculated and processed to the
# point of being able to remove the refaddrs *before* doing any
# modifications. Build a complete worklist. Undef all the hashes just to be
# sure that they cannot be used by a future maintenance programmer; it
# would be a huge source of difficult bugs!

# Making two worklists; one for vars that just need a prefixed `my`, and one for 'my' statements that need to be added.
# XXX Custom code to use the new ::Variable type of statements where available?


__END__

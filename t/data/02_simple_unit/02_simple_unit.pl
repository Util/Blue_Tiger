# This file is not intended to be run by itself!
# It is just the input for 02_simple_unit.t.
# It is in a separate file, and named .pl, so that the code can be edited
# with syntax coloring.

# Where possible, we name tests according to Damian's rant from the YAPC movie:
# http://www.perl.org/yapc/2002/movies/themovie/script.txt
#    DAMIAN: Ok, so you with me?  The arrow becomes the dot, the dot becomes
#    the underscore, the underscore had no meaning but the dollar sign, at and
#    percent all mean what they did before, except when they don't.  The arrow
#    means a sub, angle brackets are iterators except when they're comparators,
#    but they're never globs, except when you're iterating over filenames.
#    Every block is a closure, every closure can be prebound, and there are a
#    couple of dozen types of context, including hyperoperated.

#---
# Name: The arrow becomes the dot.
# In:
$x->method($y);
# Out:
$x.method($y);
#---
# Name: The dot becomes the tilde.
# In:
$x = $y . $z;
# Out:
$x = $y ~ $z;
#---
# Name: The underscore had no meaning.
# In:
_private_sub(123_456_789);
# Out:
_private_sub(123_456_789);
#---
# Name: The bitwise or  (|) becomes a specific bitwise or.
# In:
$x = $y | $z;
# Out:
$x = $y +| $z;
# Warn:
At line 1, position 9, op '|' was changed to '+|', but could have been any of ( '+|', '~|', '?|' ). Verify the context!
#---
# Name: The bitwise and (&) becomes a specific bitwise and.
# In:
$x = $y & $z;
# Out:
$x = $y +& $z;
# Warn:
At line 1, position 9, op '&' was changed to '+&', but could have been any of ( '+&', '~&', '?&' ). Verify the context!
#---
# Name: The bitwise xor (^) becomes a specific bitwise xor.
# In:
$x = ^ $z;
# Out:
$x = +^ $z;
# Warn:
At line 1, position 6, op '^' was changed to '+^', but could have been any of ( '+^', '~^', '?^' ). Verify the context!
#---
# Name: The bitwise not (~) becomes a specific bitwise not.
# In:
$x = $y ~ $z;
# Out:
$x = $y +^ $z;
# Warn:
At line 1, position 9, op '~' was changed to '+^', but could have been any of ( '+^', '~^', '?^' ). Verify the context!
#---
# Name: The bitwise shift left
# In:
$x = $y << $z;
# Out:
$x = $y +< $z;
# Warn:
At line 1, position 9, op '<<' was changed to '+<', but could have been any of ( '+<', '~<' ). Verify the context!
#---
# Name: The bitwise shift right
# In:
$x = $y >> $z;
# Out:
$x = $y +> $z;
# Warn:
At line 1, position 9, op '>>' was changed to '+>', but could have been any of ( '+>', '~>' ). Verify the context!
#---
# Name: The bitwise shift left assign
# In:
$x <<= $y;
# Out:
$x +<= $y;
# Warn:
At line 1, position 4, op '<<=' was changed to '+<=', but could have been any of ( '+<=', '~<=' ). Verify the context!
#---
# Name: The bitwise shift right
# In:
$x >>= $y;
# Out:
$x +>= $y;
# Warn:
At line 1, position 4, op '>>=' was changed to '+>=', but could have been any of ( '+>=', '~>=' ). Verify the context!
#---
# Name: The concat assign
# In:
$x .= $y;
# Out:
$x ~= $y;
#---
# Name: Match binding becomes smart match
# In:
$x =~ /re/;
# Out:
$x ~~ /re/;
#---
# Name: Negated match binding becomes negated smart match
# In:
$x !~ /re/;
# Out:
$x !~~ /re/;
#---
# Name: Ternary operator
# In:
$foo = ($x) ? $y : $z;
# Out:
$foo = ($x) ?? $y !! $z;
#---
# Name: Sigils - array sigil is now @ when keyed
# In:
$foo[$bar]
# Out:
@foo[$bar]
#---
# Name: Sigils - array sigil is still @ when sliced
# In:
@foo[$bar,$baz]
# Out:
@foo[$bar,$baz]
#---
# Name: Sigils - hash sigil is now % when keyed
# In:
$foo{$bar}
# Out:
%foo{$bar}
#---
# Name: Sigils - hash sigil is now % when sliced
# In:
@foo{$bar,$baz}
# Out:
%foo{$bar,$baz}
#---
# Name: Cast: $$foo remains unchanged
# In:
$$foo
# Out:
$$foo
#---
# Name: Cast: @$foo remains unchanged
# In:
@$foo
# Out:
@$foo
#---
# Name: Cast: %$foo remains unchanged
# In:
%$foo
# Out:
%$foo
#---
# Name: Cast: &$foo remains unchanged
# In:
&$foo
# Out:
&$foo
#---
# Name: Cast: *$foo remains unchanged
# In:
*$foo
# Out:
*$foo
#---
# Name: Cast: ${$foo} -> $($foo)
# In:
${$foo}
# Out:
$($foo)
#---
# Name: Cast: @{$foo} -> @($foo)
# In:
@{$foo}
# Out:
@($foo)
#---
# Name: Cast: %{$foo} -> %($foo)
# In:
%{$foo}
# Out:
%($foo)
#---
# Name: Cast: &{$foo} -> &($foo)
# In:
&{$foo}
# Out:
&($foo)
#---
# Name: Cast: *{$foo} -> *($foo)
# In:
*{$foo}
# Out:
*($foo)
#---
# Name: Decimal points: 42 -> 42 : No change for integer
# In:
42
# Out:
42
#---
# Name: Decimal points: 42.1 -> 42.1 : No change for proper FP
# In:
42.1
# Out:
42.1
#---
# Name: Decimal points: 42. -> 42.0 : fix trailing
# In:
42.
# Out:
42.0
# Warn:
At line 1, position 1, floating point number '42.' was changed to floating point number '42.0'. Consider changing it to integer '42'.
#---
# Name: Decimal points: 42_555. -> 42_555.0 : fix trailing, even with underscores.
# In:
42_555.
# Out:
42_555.0
# Warn:
At line 1, position 1, floating point number '42_555.' was changed to floating point number '42_555.0'. Consider changing it to integer '42_555'.
#---
# Name: Keyword requires space before condition: if(condition) -> if (condition)
# In:
if($foo) {print}
unless($foo) {print}
elsif($bar) {print}
while($foo) {print}
until($foo) {print}
foreach(@foo) {print}
for(@foo) {print}
for(my $i = 0; $i < 5; $i++) {print}
given($foo) {print}
when($foo) {print}
# Out:
if ($foo) {print}
unless ($foo) {print}
elsif ($bar) {print}
while ($foo) {print}
until ($foo) {print}
foreach (@foo) {print}
for (@foo) {print}
for (my $i = 0; $i < 5; $i++) {print}
given ($foo) {print}
when ($foo) {print}
#---
# Name: Keyword requires space before condition: No change when space exists
# In:
if ($foo) {print}
unless ($foo) {print}
elsif ($bar) {print}
while ($foo) {print}
until ($foo) {print}
foreach (@foo) {print}
for (@foo) {print}
for (my $i = 0; $i < 5; $i++) {print}
given ($foo) {print}
when ($foo) {print}
# Out:
if ($foo) {print}
unless ($foo) {print}
elsif ($bar) {print}
while ($foo) {print}
until ($foo) {print}
foreach (@foo) {print}
for (@foo) {print}
for (my $i = 0; $i < 5; $i++) {print}
given ($foo) {print}
when ($foo) {print}
#---
# Name: Keyword requires space before condition: print if($foo) -> print if ($foo)
# In:
print if($foo)
print unless($foo)
print while($foo)
print until($foo)
print foreach(@foo)
print for(@foo)
print when($foo)
# Out:
print if ($foo)
print unless ($foo)
print while ($foo)
print until ($foo)
print foreach (@foo)
print for (@foo)
print when ($foo)
#---
# Name: Keyword requires space before condition: No change when space exists (postfix)
# In:
print if ($foo)
print unless ($foo)
print while ($foo)
print until ($foo)
print foreach (@foo)
print for (@foo)
print when ($foo)
# Out:
print if ($foo)
print unless ($foo)
print while ($foo)
print until ($foo)
print foreach (@foo)
print for (@foo)
print when ($foo)
#---

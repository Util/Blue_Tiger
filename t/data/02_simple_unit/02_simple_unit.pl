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

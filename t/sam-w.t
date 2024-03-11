package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam';

BEGIN {
    *_check_word_regexp = \&App::Sam::_check_word_regexp;
}

my %re;

{
    local $_ = undef;
    while ( <DATA> ) {
	chomp;
	$_ eq '__END__'
	    and last;
	m/ \A \s* (?: \# | \z ) /smx
	    and next;
	my ( $key, $val ) = split /\s+/, $_, 2;
	push @{ $re{$key} }, $val;
    }
}

foreach ( '\\w', @{ $re{OK} } ) {
    is _check_word_regexp( $_ ), 1, "OK  $_";
}

foreach ( @{ $re{BAD} } ) {
    is _check_word_regexp( $_ ), 0, "BAD $_";
}

done_testing;

1;

__DATA__
OK  \w

# The following is verbatim from ack test t/ack-w.t

# Anchors
BAD $foo
BAD foo^
BAD ^foo
BAD foo$

# Dot
OK  foo.
OK  .foo

# Parentheses
OK  (set|get)_foo
OK  foo_(id|name)
OK  func()
OK  (all in one group)
INV )start with closing paren
INV end with opening paren(
BAD end with an escaped closing paren\)

# Character classes
OK  [sg]et
OK  foo[lt]
OK  [one big character class]
OK  [multiple][character][classes]
BAD ]starting with a closing bracket
INV ending with an opening bracket[
BAD ending with an escaped closing bracket \]

# Quantifiers
OK  thpppt{1,5}
BAD }starting with an closing curly brace
BAD ending with an escaped closing curly brace\}

OK  foo+
BAD foo\+
INV +foo
OK  foo*
BAD foo\*
INV *foo
OK  foo?
BAD foo\?
INV ?foo

# Miscellaneous debris
BAD -foo
BAD foo-
BAD &mpersand
BAD ampersand&
INV function(
BAD ->method
BAD <header.h>
BAD =14
BAD /slashes/
BAD ::Class::Whatever
BAD Class::Whatever::
OK  Class::Whatever

__END__

# ex: set textwidth=72 :

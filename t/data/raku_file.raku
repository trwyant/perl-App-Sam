#! /usr/bin/env rakudo

use v6;

# This is a comment

#`(
  This is a block comment
  )

=begin pod

This is documentation

=end pod

#| This is a single-line declarator block, and therefore documentation
sub MAIN( $name='world' ) {
    say "Hello $name!";
}
#=«
    This is a multi-line declarator block, and also documentation
»
# But this is just a comment.

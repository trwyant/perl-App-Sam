package main;

use 5.010;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Raku';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/raku_file.raku';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
meta:#! /usr/bin/env rakudo
code:
code:use v6;
code:
comm:# This is a comment
code:
comm:#`(
comm:  This is a block comment
comm:  )
code:
docu:=begin pod
docu:
docu:This is documentation
docu:
docu:=end pod
code:
docu:#| This is a single-line declarator block, and therefore documentation
code:sub MAIN( $name='world' ) {
code:    say "Hello $name!";
code:}
docu:#=«
docu:    This is a multi-line declarator block, and also documentation
docu:»
comm:# But this is just a comment.
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Lisp';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/lisp_file.lisp';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
meta:#!/usr/bin/env clisp
comm:; This is a comment
docu:;;; but this is documentation
comm:#|
comm: | Is this a comment? It seems so.
comm: | #| Do they really nest? |#
comm: | Yes. This is still a comment.
comm: |#
code:(
code:  format t "Hello ~a!~%" (
code:    if ( > ( length *args* ) 0 ) ( first *args* ) "world"
code:  )
code:)
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

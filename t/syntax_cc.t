package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Cc';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/cc_file.c';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
prep:#include <stdio.h>
code:
prep:#define FOO \
prep:    "bar"
code:
comm:/* This is a single-line block comment */
code:
code:int main ( int argc, char ** argv ) {
code:    printf( "Hello %s!\n", argc > 1 ? argv[1] : "world" );
code:}
code:
comm:/*
comm: * Author: Thomas R. Wyant, III F<wyant at cpan dot org>
comm: *
comm: * Copyright (C) 2018-2024 by Thomas R. Wyant, III
comm: *
comm: * This program is distributed in the hope that it will be useful, but
comm: * without any warranty; without even the implied warranty of
comm: * merchantability or fitness for a particular purpose.
comm: *
comm: * ex: set textwidth=72 :
comm: */
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

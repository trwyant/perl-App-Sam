package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Cpp';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/cpp_file.cpp';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
prep:#include <stdio.h>
code:
code:using namespace std;
code:
docu:/**
docu: * Print the standard 'Hello, world!' message. If a command argument is
docu: * passed, it is used instead of 'world.'
docu: */
code:
code:int main( int argc, char *argv[] ) {
code:
comm:    /* Old-school printf still works. */
comm:    // As do new-school C++ comments
code:    printf( "Hello %s!\n", argc > 1 ? argv[1] : "world" );
code:
code:    return 0;
code:}
code:
comm:/*
comm: * Author: Thomas R. Wyant, III F<wyant at cpan dot org>
comm: *
comm: * Copyright (C) 2018-2026 by Thomas R. Wyant, III
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

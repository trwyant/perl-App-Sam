#include <stdio.h>

using namespace std;

/**
 * Print the standard 'Hello, world!' message. If a command argument is
 * passed, it is used instead of 'world.'
 */

int main( int argc, char *argv[] ) {

    /* Old-school printf still works. */
    // As do new-school C++ comments
    printf( "Hello %s!\n", argc > 1 ? argv[1] : "world" );

    return 0;
}

/*
 * Author: Thomas R. Wyant, III F<wyant at cpan dot org>
 *
 * Copyright (C) 2018-2023 by Thomas R. Wyant, III
 *
 * This program is distributed in the hope that it will be useful, but
 * without any warranty; without even the implied warranty of
 * merchantability or fitness for a particular purpose.
 *
 * ex: set textwidth=72 :
 */

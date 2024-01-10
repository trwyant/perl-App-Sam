#include <stdio.h>

#define FOO \
    "bar"

/* This is a single-line block comment */

int main ( int argc, char ** argv ) {
    printf( "Hello %s!\n", argc > 1 ? argv[1] : "world" );
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

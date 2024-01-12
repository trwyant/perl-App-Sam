package main;

use 5.010;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Java';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/java_file.java';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
comm:/* This is a single-line block comment. Just because. */
code:
code:import java.io.*;
code:import java.util.*;
code:
meta:@Author(
meta:    name = "Tom Wyant"
meta:)
code:
docu:/**
docu: * Implement a greeting in Java
docu: *
docu: * @author      Thomas R. Wyant, III F<wyant at cpan dot org>
docu: * @version     0.000_001
docu: */
code:
code:public class java_file {
code:
docu:    /**
docu:     * This method is the mainline. It prints a greeting to the name
docu:     * given as the first command-line argument, defaulting to "world".
docu:     *
docu:     * @param argv[]    String command line arguments.
docu:     */
code:
code:    public static void main( String argv[] ) {
code:        String name = argv.length > 0 ? argv[0] : "world";
code:        System.out.println( "Hello " + name + "|" );
code:    }
code:
code:}
code:
comm:// ex: set textwidth=72 :
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

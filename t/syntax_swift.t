package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Swift';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/swift_file.swift';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
meta:#!/usr/bin/env swift
code:
comm:/* This is a block comment.
comm: * /* Note that they nest, */
comm: * so this is still a comment.
comm: */
code:
docu:/*:
docu: * This is a Swift implementation of 'Hello world', which accepts an
docu: * optional command line parameter specifying who to greet.
docu: *
docu: * The colon on the first line makes this documentation.
docu: */
code:
comm:// Note that the following makes 'name' a manifest constant.
code:let name = CommandLine.argc > 1 ? CommandLine.arguments[ 1 ] : "world"
code:
code:print( "Hello " + name + "!" )
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

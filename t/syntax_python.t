package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Python';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/python_file.py';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
meta:#!/usr/bin/env python
comm:# This is a single-line comment
code:
comm:"""
comm:This is a multi-line comment.
comm:"""
code:import sys
code:
code:def who():
docu:    """ This function determines who we are greeting """
code:    if len( sys.argv ) > 1:
code:        return sys.argv[1] + "!"
code:    return "World!"
code:
code:print "Hello", who()
code:
comm:# ex: set filetype=python textwidth=72 autoindent :
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

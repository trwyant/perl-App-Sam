package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Shell';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/shell_file.sh';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
meta:#!/bin/sh
code:
code:x=$1
code:echo "Hello ${x:-world}!"
code:
comm:# Author: Thomas R. Wyant, III F<wyant at cpan dot org>
comm:#
comm:# Copyright (C) 2018-2024 by Thomas R. Wyant, III
comm:#
comm:# This program is distributed in the hope that it will be useful, but
comm:# without any warranty; without even the implied warranty of
comm:# merchantability or fitness for a particular purpose.
code:
comm:# ex: set textwidth=72 :
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

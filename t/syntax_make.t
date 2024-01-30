package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Make';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/make_file.mak';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
comm:# This is not a Makefile to make anything; it is just to test the \
comm:    Makefile syntax filter.
code:
code:WHO=World
code:
code:greeting:
code:	echo 'Hello ' \
code:	    '$(WHO)!'
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

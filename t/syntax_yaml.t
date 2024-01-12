package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::YAML';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/yaml_file.yml';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
meta:---
comm:# This is a comment
data:- There was a young lady named Bright,
data:- Who could travel much faster than light.
data:- '    She set out one day'
data:- '    In a relative way'
data:- And returned the previous night.
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Properties';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/properties_file.properties';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
comm:# This is a comment.
comm:! So is this, In fact, so is the next line.
comm:
data:classify = this as data
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

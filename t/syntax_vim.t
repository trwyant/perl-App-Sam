package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Vim';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/vim_file.vim';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
comm:" This is a comment
code:let name = "world"
code:echo "Hello " . name . "!"
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

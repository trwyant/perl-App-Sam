package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Batch';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/batch_file.bat';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
code:@echo off
comm:rem This is a comment
comm:@REM so is this
comm::: and, by a strange quirk of fate, so is this.
code:set name=world
code:if .%1.==.. goto greet
code:set name=%1
code::greet
code:echo Hello %name%!
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

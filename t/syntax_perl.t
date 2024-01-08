package main;

use 5.010;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Perl';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/perl_file.PL';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
meta:#!/usr/bin/env perl
code:
code:use strict;
code:use warnings;
code:
comm:# This is a comment
code:
code:printf "Hello %s!\n", @ARGV ? $ARGV[0] : 'world';
code:
meta:__END__
data:
data:This is data, kinda sorta.
data:
docu:=head1 TEST
docu:
docu:This is documentation.
docu:
docu:=cut
data:
data:# ex: set textwidth=72 :
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

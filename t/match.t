package main;

use 5.010;

use strict;
use warnings;

use open qw{ :std :encoding(utf-8) };

use Test2::V0 -target => 'App::Sam';

use lib qw{ inc };

use My::Module::Test;

App::Sam->__set_attr_default( env => 0 );

{
    my $sad = CLASS->new(
	match	=> 'ay$',
    );

    my $stdout = capture_stdout {
	$sad->process( 't/data/bright.txt' );
    };

    is $stdout, <<'EOD', 'Matched lines 3 and 4 of limmerick';
t/data/bright.txt
3:    She set out one day
4:    In a relative way
EOD

}


done_testing;

1;

# ex: set textwidth=72 :

package main;

use 5.010001;

use strict;
use warnings;

use open qw{ :std :encoding(utf-8) };

use Test2::V0 -target => 'App::Sam';
use Test2::Tools::Mock;

use lib qw{ inc };

use My::Module::Test;

my $mock = mock 'App::Sam' => (
    after	=> [
	__get_attr_defaults	=> sub {
	    $_[0]->{env}	= 0,
	},
    ],
);

{
    my $sam = CLASS->new(
	match	=> 'ay$',
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/bright.txt' );
    };

    is $stdout, <<'EOD', 'Matched lines 3 and 4 of limmerick';
t/data/bright.txt
3:    She set out one day
4:    In a relative way
EOD

}

{
    my $sam = CLASS->new(
	argv	=> [ 'ay$' ],
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/bright.txt' );
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

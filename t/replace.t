package main;

use 5.010;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam';

use lib qw{ inc };

use My::Module::Test;

App::Sam->__set_attr_default( env => 0 );

{
    my $sam = CLASS->new(
	dry_run		=> 1,	# Don't write the original back
	match		=> '\bbright\b',
	ignore_case	=> 1,
	replace		=> 'Wright',
    );

    my $stdout = capture_stdout {
	is $sam->process( 't/data/bright.txt' ), <<'EOD',
There was a young lady named Wright
Who could travel much faster than light.
    She set out one day
    In a relative way
And returned the previous night.
EOD
	'Modified the original text';
    };

    is $stdout, <<'EOD', 'Matched line 1 of limmerick';
t/data/bright.txt
1:There was a young lady named Wright
EOD
}

done_testing;

1;

# ex: set textwidth=72 :

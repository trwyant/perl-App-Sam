package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam';
use Test2::Tools::Mock;

use lib qw{ inc };

use My::Module::Test;

my $mock = mock 'App::Sam' => (
    after	=> [
	__get_attr_from_rc	=> sub {
	    if ( $_[1] eq $_[0]->__get_attr_default_file_name() ) {
		$_[0]->{env}	= 0,
	    }
	    return;
	},
    ],
);

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

    is $stdout, <<'EOD', 'Matched line 1 of limerick';
t/data/bright.txt
1:There was a young lady named Wright
EOD
}

{
    my $sam = CLASS->new(
	dry_run		=> 1,	# Don't write the original back
	match		=> '\s*bright\b',
	ignore_case	=> 1,
	argv		=> [ qw{ --remove } ],
    );

    my $stdout = capture_stdout {
	is $sam->process( 't/data/bright.txt' ), <<'EOD',
There was a young lady named
Who could travel much faster than light.
    She set out one day
    In a relative way
And returned the previous night.
EOD
	'Modified the original text';
    };

    is $stdout, <<'EOD', 'Matched line 1 of limerick';
t/data/bright.txt
1:There was a young lady named
EOD
}

done_testing;

1;

# ex: set textwidth=72 :

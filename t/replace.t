package main;

use 5.010001;

use strict;
use warnings;

use App::Sam::Util qw{ :case };
use Test2::V0 -target => 'App::Sam';

use lib qw{ inc };

use My::Module::Test;

my $mock = mock 'App::Sam' => (
    override	=> [
	__default_env	=> sub { return 0 },
    ],
);

{
    note "\nTest --replace";

    my $got;
    my $sam = CLASS->new(
	dry_run		=> \$got,
	match		=> '\bbright\b',
	match_case	=> RE_CASE_BLIND,
	replace		=> 'Wright',
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/bright.txt' );
    };

    is $got, <<'EOD',
There was a young lady named Wright
Who could travel much faster than light.
    She set out one day
    In a relative way
And returned the previous night.
EOD
	'Modified the original text';

    is $stdout, <<'EOD', 'Matched line 1 of limerick';
1:There was a young lady named Wright
EOD
}

{
    note "\nTest --remove";

    my $got;
    my $sam = CLASS->new(
	dry_run		=> \$got,
	match		=> '\s*bright\b',
	match_case	=> RE_CASE_BLIND,
	argv		=> [ qw{ --remove } ],
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/bright.txt' );
    };

    is $got, <<'EOD',
There was a young lady named
Who could travel much faster than light.
    She set out one day
    In a relative way
And returned the previous night.
EOD
	'Modified the original text';

    is $stdout, <<'EOD', 'Matched line 1 of limerick';
1:There was a young lady named
EOD
}

{
    note "\nTest --replace --confirm 'y' and 'n'";

    my $got;
    my $sam = CLASS->new(
	confirm		=> 1,
	dry_run		=> \$got,
	match		=> 'ght\b',
	# match_case	=> RE_CASE_BLIND,
	replace		=> 'te',
    );

    my $stdout = capture_stdout {
	stdin_from_file {
	    $sam->process( 't/data/bright.txt' );
	} \<<EOD,
y
n
y
EOD
    };

    is $got, <<'EOD',
There was a young lady named Brite
Who could travel much faster than light.
    She set out one day
    In a relative way
And returned the previous nite.
EOD
	'Modified the original text';

    is $stdout, undef, 'No STDOUT data when STDIN is not a terminal';
}

{
    note "\nTest --replace --confirm 'l'";

    my $got;
    my $sam = CLASS->new(
	confirm		=> 1,
	dry_run		=> \$got,
	match		=> 'ght\b',
	# match_case	=> RE_CASE_BLIND,
	replace		=> 'te',
    );

    my $stdout = capture_stdout {
	stdin_from_file {
	    $sam->process( 't/data/bright.txt' );
	} \<<EOD,
l
EOD
    };

    is $got, <<'EOD',
There was a young lady named Brite
Who could travel much faster than light.
    She set out one day
    In a relative way
And returned the previous night.
EOD
	'Modified the original text';

    is $stdout, undef, 'No STDOUT data when STDIN is not a terminal';
}

{
    note "\nTest --replace --confirm 'q'";

    my $got;
    my $sam = CLASS->new(
	confirm		=> 1,
	dry_run		=> \$got,
	match		=> 'ght\b',
	# match_case	=> RE_CASE_BLIND,
	replace		=> 'te',
    );

    my $stdout = capture_stdout {
	stdin_from_file {
	    $sam->process( 't/data/bright.txt' );
	} \<<EOD,
q
EOD
    };

    is $got, <<'EOD',
There was a young lady named Bright
Who could travel much faster than light.
    She set out one day
    In a relative way
And returned the previous night.
EOD
	'Modified the original text';

    is $stdout, undef, 'No STDOUT data when STDIN is not a terminal';
}

{
    note "\nTest --replace --confirm with end-of-file";

    my $got;
    my $sam = CLASS->new(
	confirm		=> 1,
	dry_run		=> \$got,
	match		=> 'ght\b',
	# match_case	=> RE_CASE_BLIND,
	replace		=> 'te',
    );

    my $stdout = capture_stdout {
	stdin_from_file {
	    $sam->process( 't/data/bright.txt' );
	} \<<EOD,
y
EOD
    };

    is $got, <<'EOD',
There was a young lady named Brite
Who could travel much faster than light.
    She set out one day
    In a relative way
And returned the previous night.
EOD
	'Modified the original text';

    is $stdout, undef, 'No STDOUT data when STDIN is not a terminal';
}

{
    note "\nTest --replace --confirm 'a'";

    my $got;
    my $sam = CLASS->new(
	confirm		=> 1,
	dry_run		=> \$got,
	match		=> 'ght\b',
	# match_case	=> RE_CASE_BLIND,
	replace		=> 'te',
    );

    my $stdout = capture_stdout {
	stdin_from_file {
	    $sam->process( 't/data/bright.txt' );
	} \<<EOD,
a
EOD
    };

    is $got, <<'EOD',
There was a young lady named Brite
Who could travel much faster than lite.
    She set out one day
    In a relative way
And returned the previous nite.
EOD
	'Modified the original text';

    is $stdout, undef, 'No STDOUT data when STDIN is not a terminal';
}

done_testing;

1;

# ex: set textwidth=72 :

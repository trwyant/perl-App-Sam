package main;

use 5.010001;

use strict;
use warnings;

use App::Sam::Resource;
use App::Sam::Tplt;
use App::Sam::Tplt::Color;
use App::Sam::Tplt::Under;
use B qw{ perlstring };
use Test2::V0 -target => 'App::Sam';
use Test2::Tools::Mock;
use Term::ANSIColor;

use lib 'inc';

use My::Module::Test qw{ fake_rsrc };

use constant RSRC	=> 'App::Sam::Resource';

use constant CARET	=> '^';
use constant EMPTY	=> '';
use constant SPACE	=> ' ';

{
    my $mock = mock CLASS, (
	override	=> [
	    new		=> sub {
		my ( $class, %self ) = @_;
		$self{env} //= 1;
		return bless \%self, $class;
	    },
	],
    );

    delete local $ENV{SAMRC};

    my $default_resource = fake_rsrc(
	name	=> CLASS->__get_default_resource_name(),
	alias	=> 'Defaults',
    );

    is CLASS->__get_default_resource(),
	$default_resource,
	'__get_default_resource()';

    my $global_resource = fake_rsrc(
	name	=> CLASS->__get_global_resource_name(),
    );

    is CLASS->__get_global_resource(),
	$global_resource,
	'__get_global_resource()';

    my $user_resource = fake_rsrc(
	name	=> CLASS->__get_user_resource_name(),
    );

    is CLASS->__get_user_resource(),
	$user_resource,
	'__get_user_resource()';

    my $project_resource = fake_rsrc(
	name	=> CLASS->__get_project_resource_name(),
    );

    is CLASS->__get_project_resource(),
	$project_resource,
	'__get_project_resource()';

    is [ CLASS->new()->__get_resources( [] ) ], [
	$default_resource,
	$global_resource,
	$user_resource,
	$project_resource,
	fake_rsrc( name	=> 'new()', data => [], getopt => 0 ),
    ], '__get_resources( [] )';

    is [ CLASS->new()->__get_resources( [ argv => [] ] ) ], [
	$default_resource,
	$global_resource,
	$user_resource,
	$project_resource,
	fake_rsrc( name	=> 'new()', data => [ argv => [] ], getopt => 0 ),
    ], '__get_resources( [ argv => [] ] )';

    is [ CLASS->new( ignore_sam_defaults => 1 )->__get_resources( [] ) ], [
	$global_resource,
	$user_resource,
	$project_resource,
	fake_rsrc( name	=> 'new()', data => [], getopt => 0 ),
    ], '__get_resources( [] ) with ignore_sam_defaults => 1';

    is [ CLASS->new( env => 0 )->__get_resources( [] ) ], [
	$default_resource,
	fake_rsrc( name	=> 'new()', data => [], getopt => 0 ),
    ], '__get_resources( [] ) with env => 0';
}

{
    my $defaults;
    my $mock = mock CLASS, (
	override	=> [
	    new		=> sub {
		my ( $class, %self ) = @_;
		$self{env} //= 0;
		return bless \%self, $class;
	    },
	    __get_default_resource	=> sub {
		return App::Sam::Resource->new(
		    name	=> CLASS->__get_default_resource_name(),
		    data	=> $defaults,
		);
	    },
	],
    );

    delete local $ENV{SAMRC};

    is CLASS->new()->__get_attr_from_resource(
	fake_rsrc(
	    name	=> 'new()',
	    data	=> [
	    ],
	    getopt	=> 0,
	),
    ), { env => 0 }, '__get_attr_from_resource() empty args';

    is CLASS->new()->__get_attr_from_resource(
	fake_rsrc(
	    name	=> 'new()',
	    data	=> [
		env	=> 1,
		count	=> 1,
	    ],
	    getopt	=> 0,
	),
    ), {
	count	=> 1,
	env	=> 0,
	flags	=> 0,
	_defer	=> {
	    env	=> 1,
	},
    }, '__get_attr_from_resource() override env';

    is CLASS->new()->__get_attr_from_resource(
	fake_rsrc(
	    name	=> 'samrc',
	    data	=> \<<'EOD',
--color-match=magenta on_black
--ignore-sam-defaults
EOD
	),
    ), {
	color_match	=> 'magenta on_black',
	env		=> 0,
	_defer	=> {
	    ignore_sam_defaults	=> 1,
	},
	flags		=> 0,
    }, '__get_attr_from_resource() parse file';

    is CLASS->new()->__get_attr_from_resource(
	fake_rsrc(
	    name	=> 'new()',
	    data	=> [
		argv	=> [ qw{ --color } ],
	    ],
	    getopt	=> 0,
	),
    ), {
	color	=> 1,
	env	=> 0,
	flags	=> 0,
    }, '__get_attr_from_resource() argv';

    is CLASS->new()->__get_attr_from_resource(
	fake_rsrc(
	    name	=> CLASS->__get_default_resource_name(),
	    data	=> \<<'EOD'
# This is a comment
--color
--color-match=black on_magenta
EOD
	), fake_rsrc(
	    name	=> 't/data/no-such-file',
	), fake_rsrc(
	    name	=> 'new()',
	    data	=> [ color => 0 ],
	    getopt	=> 0,
	),
    ), {
	color		=> 0,
	color_match	=> 'black on_magenta',
	env		=> 0,
	flags		=> 0,
    }, '__get_attr_from_resource() multiple resources';

    $defaults = \<<'EOD';
# This is a comment
--color
EOD
    my $sam = CLASS->new();

    is $sam->__get_attr_from_resource( $sam->__get_resources( [
		context => 1,
	    ] ) ),
    {
	after_context	=> 1,
	before_context	=> 1,
	color	=> 1,
	env	=> 0,
	flags	=> 0,
    }, '__get_attr_from_resource( __get_resources() )';
}

{
    my $tplt = App::Sam::Tplt->new(
	filename	=> 'fu.bar',
    );


    local $_ = 'Able was I ere I saw Elba.';
    local $. = 42;

    while ( m/ \b ( was ) \b /smxgc ) {

	# NOTE that we have to do this by hand because we are making
	# such low-level entry into the system. These are candidates for
	# moving into a context attribute for easy cleanup.
	$tplt->{match_end} = [ @+ ];
	$tplt->{match_start} = [ @- ];
	$tplt->{matched} = defined pos;
	# $tplt->{colored} (not used in testing, but still context)

	foreach my $test (
	    [ '\\0', "\0" ],
	    [ '\\n', "\n" ],
	    [ '$1', 'was' ],
	    [ '$`', 'Able ' ],
	    [ '$&', 'was' ],
	    [ '$\'', ' I ere I saw Elba.' ],
	    [ '$f', 'fu.bar' ],
	    [ '$c', 6 ],
	    [ '$.', 42 ],
	) {
	    my ( $item, $want ) = @{ $test };
	    is $tplt->__format_item( $item ), $want,
		"Processing item '$item' gave '@{[ perlstring $want ] }'";
	}
    }
}

{
    my $tplt = App::Sam::Tplt::Color->new(
	color_colno	=> 'bold yellow',
	color_lineno	=> 'bold yellow',
	color_match	=> 'black on_yellow',
	filename	=> 'fu.bar',
    );


    local $_ = "Able was I ere I saw Elba.\n";
    local $. = 42;

    while ( m/ \b ( was ) \b /smxgc ) {

	# NOTE that we have to do this by hand because we are making
	# such low-level entry into the system. These are candidates for
	# moving into a context attribute for easy cleanup.
	$tplt->{match_end} = [ @+ ];
	$tplt->{match_start} = [ @- ];
	$tplt->{matched} = defined pos;
	# $tplt->{colored} (not used in testing, but still context)

	foreach my $test (
	    [ '$.', colored $., 'bold yellow' ],
	    [ '$c', colored 6, 'bold yellow' ],
	    [ '$&', colored 'was', 'black on_yellow' ],
	) {
	    my ( $item, $want ) = @{ $test };
	    is $tplt->__format_item( $item ), $want,
		"Processing colored item '$item' gave '@{[
		perlstring $want ] }'";
	}
    }
}

{
    my $tplt = App::Sam::Tplt::Under->new(
	filename	=> 'fu.bar',
    );


    local $_ = 'Able was I ere I saw Elba.';
    local $. = 42;

    while ( m/ \b ( was ) \b /smxgc ) {

	# NOTE that we have to do this by hand because we are making
	# such low-level entry into the system. These are candidates for
	# moving into a context attribute for easy cleanup.
	$tplt->{match_end} = [ @+ ];
	$tplt->{match_start} = [ @- ];
	$tplt->{matched} = defined pos;
	# $tplt->{colored} (not used in testing, but still context)

	foreach my $test (
	    [ '\\0', EMPTY ],
	    [ '\\n', "\n" ],
	    [ '$1', SPACE x 3 ],
	    [ '$`', SPACE x 5 ],
	    [ '$&', CARET x 3 ],
	    [ '$\'', SPACE x 18 ],
	    [ '$f', SPACE x 6 ],
	    [ '$c', SPACE ],
	    [ '$.', SPACE x 2 ],
	) {
	    my ( $item, $want ) = @{ $test };
	    is $tplt->__format_item( $item ), $want,
		"Processing underline item '$item' gave '@{[
		perlstring $want ] }'";
	}
    }
}

{
    my $tplt = App::Sam::Tplt->new(
	filename	=> 'fu.bar',
	replace_tplt	=> '<$&>',
    );

    local $_ = 'Able was I ere I saw Elba.';
    local $. = 42;
    $tplt->init();

    while ( m/ \b ( was ) \b /smxgc ) {

	foreach my $test (
	    [ '\\0', "\0" ],
	    [ '\\n', "\n" ],
	    [ '$1', 'was' ],
	    [ '$`', 'Able ' ],
	    [ '$&', 'was' ],
	    [ '$r', '<was>' ],
	    [ '$\'', ' I ere I saw Elba.' ],
	    [ '$f', 'fu.bar' ],
	    [ '$c', 6 ],
	    [ '$.', 42 ],
	) {
	    my ( $match, $want ) = @{ $test };
	    $tplt->match_tplt( $match );
	    is $tplt->match(), $want,
		"Formatting template '$match' gave '@{[ perlstring $want ] }'";
	}
    }
}

{
    my $tplt = App::Sam::Tplt::Color->new(
	color_colno	=> 'bold yellow',
	color_lineno	=> 'bold yellow',
	color_match	=> 'black on_yellow',
	filename	=> 'fu.bar',
	replace_tplt	=> '<$&>',
    );


    local $_ = "Able was I ere I saw Elba.\n";
    local $. = 42;
    $tplt->init();

    while ( m/ \b ( was ) \b /smxgc ) {

	foreach my $test (
	    [ '$.', colored $., 'bold yellow' ],
	    [ '$c', colored 6, 'bold yellow' ],
	    [ '$&', colored 'was', 'black on_yellow' ],
	    [ '$r', colored '<was>', 'black on_yellow' ],
	) {
	    my ( $match, $want ) = @{ $test };
	    $tplt->match_tplt( $match );
	    is $tplt->match(), $want,
		"Formatting colored template '$match' gave '@{[
		perlstring $want ] }'";
	}
    }
}

{
    my $tplt = App::Sam::Tplt::Under->new(
	filename	=> 'fu.bar',
	replace_tplt	=> '<$&>',
    );


    local $_ = 'Able was I ere I saw Elba.';
    local $. = 42;
    $tplt->init();

    while ( m/ \b ( was ) \b /smxgc ) {

	foreach my $test (
	    [ '\\0', EMPTY ],
	    [ '\\n', "\n" ],
	    [ '$1', SPACE x 3 ],
	    [ '$`', SPACE x 5 ],
	    [ '$&', CARET x 3 ],
	    [ '$r', CARET x 5 ],
	    [ '$\'', SPACE x 18 ],
	    [ '$f', SPACE x 6 ],
	    [ '$c', SPACE ],
	    [ '$.', SPACE x 2 ],
	) {
	    my ( $match, $want ) = @{ $test };
	    $tplt->match_tplt( $match );
	    is $tplt->match(), $want,
		"Processing underline template '$match' gave '@{[
		perlstring $want ] }'";
	}
    }
}

{
    my $tplt = App::Sam::Tplt->new(
	ofs	=> ',',
    );

    is $tplt->execute_template(
	'$1-$S$*',
	capt	=> [ qw{ zero one two three four } ],
    ), 'one-two,three,four', 'execute_template() specifying {capt} and {ofs}';
}

done_testing;

1;

# ex: set textwidth=72 :

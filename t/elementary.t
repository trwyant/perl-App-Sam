package main;

use 5.010001;

use strict;
use warnings;

use App::Sam::Tplt;
use App::Sam::Tplt::Color;
use App::Sam::Tplt::Under;
use B qw{ perlstring };
use Test2::V0 -target => 'App::Sam';
use Test2::Tools::Mock;
use Term::ANSIColor;

use constant CARET	=> '^';
use constant EMPTY	=> '';
use constant SPACE	=> ' ';

{
    my $tplt = App::Sam::Tplt->new(
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

    local $_ = "Able was I ere I saw Elba.\n";
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


    local $_ = "Able was I ere I saw Elba.\n";
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

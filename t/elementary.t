package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam';
use Test2::Tools::Mock;
use Term::ANSIColor;

{
    my $mock = mock CLASS, (
	override	=> [
	    new		=> sub {
		return bless {
		    _process	=> {
			filename	=> 'fu.bar',
		    },
		}, CLASS;
	    },
	],
    );

    my $sam = CLASS->new();

    note 'Template processing';

    local $_ = 'There was a young lady named Bright';
    local $. = 42;

    # NOTE that we do this in a while() loop because that's how we
    # expect to be called for real.
    while ( m/ \b w ( a ) s /smxg ) {

	is $sam->__process_template( '$1' ), 'a', q/Template '$1'/;
	is $sam->__process_template( '$`' ), 'There ', q/Template '$`'/;
	is $sam->__process_template( '$&' ), 'was', q/Template '$&'/;
	is $sam->__process_template( q/$'/ ), ' a young lady named Bright',
	    q/Template '$\''/;
	is $sam->__process_template( '$f' ), 'fu.bar', q/Template '$f'/;
	is $sam->__process_template( '$.' ), 42, q/Template '$.'/;
	is $sam->__process_template( '$c' ), 7, q/Template '$c'/;
	is $sam->__process_template( '\\t' ), "\t", q/Template '\\t'/;
	is $sam->__process_template( '\\n' ), "\n", q/Template '\\n'/;
	is $sam->__process_template( '\\r' ), "\r", q/Template '\\r'/;
	is $sam->__process_template( '$_' ),
	    'There was a young lady named Bright',
	    q/Template '$_'/;
	is $sam->__process_template( '$f:$c:$&' ), 'fu.bar:7:was',
	    q/Template '$f:$c:$&'/;

	{
	    local $sam->{color} = 1;
	    local $sam->{color_colno} = 'bold yellow';
	    local $sam->{color_lineno} = 'bold yellow';
	    local $sam->{color_match} = 'black on_yellow';
	    is $sam->__process_template( '$.' ),
		colored( 42, 'bold yellow' ),
		q/Template '$.', coloried/;
	    is $sam->__process_template( '$c' ),
		colored( 7, 'bold yellow' ),
		q/Template '$c', coloried/;
	    is $sam->__process_template( '$&' ),
		colored( 'was', 'black on_yellow' ),
		q/Template '$&', coloried/;
	    # NOTE that there is no point in testing the file name here,
	    # because it is not colorized by the templating engine.
	}

	$_ = 'A foo fu fool';
	delete $sam->{_process}{colno};
	my @want = ( 'A <foo>', ' <fu>' );
	# Normally _process_match() does this, but we're farther down in the
	# weeds than that.
	$sam->{_tplt}{pos} = pos( $_ ) // 0;
	while ( m/ \b f [ou]+ \b /smxg ) {
	    my $w = shift @want;
	    is $sam->__process_template( '$u<$&>' ), $w, q/Template '$u<$&>'/;
	}
	is $sam->__process_template( '$u<$&>' ),
	    ' fool<>', q/Template '$u<$&>'/;

    }
}

done_testing;

1;

# ex: set textwidth=72 :

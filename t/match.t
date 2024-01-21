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

{
    my $sam = CLASS->new(
	f	=> 1,
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data' );
    };

    is $stdout, <<'EOD', '-f listed everything in t/data';
t/data/bright.txt
t/data/cc_file.c
t/data/cpp_file.cpp
t/data/fortran_file.for
t/data/java_file.java
t/data/json_file.json
t/data/make_file.mak
t/data/perl_file.PL
t/data/properties_file.properties
t/data/python_file.py
t/data/raku_file.raku
t/data/shell_file.sh
t/data/vim_file.vim
t/data/yaml_file.yml
EOD
}

{
    my $sam = CLASS->new(
	f	=> 1,
	known_types	=> 1,
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data' );
    };

    is $stdout, <<'EOD', '-fk listed only known types in t/data';
t/data/cc_file.c
t/data/cpp_file.cpp
t/data/fortran_file.for
t/data/java_file.java
t/data/json_file.json
t/data/make_file.mak
t/data/perl_file.PL
t/data/properties_file.properties
t/data/python_file.py
t/data/raku_file.raku
t/data/shell_file.sh
t/data/vim_file.vim
t/data/yaml_file.yml
EOD
}


done_testing;

1;

# ex: set textwidth=72 :

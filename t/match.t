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
	match		=> 'ay$',
	with_filename	=> 0,
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/bright.txt' );
    };

    is $stdout, <<'EOD', 'Matched lines 3 and 4 of limmerick';
3:    She set out one day
4:    In a relative way
EOD
}

{
    my $sam = CLASS->new(
	match		=> '\A',
	show_syntax	=> 1,
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/perl_file.PL' );
    };

    is $stdout, <<'EOD', 'Showed Perl syntax classifications';
t/data/perl_file.PL
1:meta:#!/usr/bin/env perl
2:code:
3:code:use strict;
4:code:use warnings;
5:code:
6:comm:# This is a comment
7:code:
8:code:printf "Hello %s!\n", @ARGV ? $ARGV[0] : 'world';
9:code:
10:meta:__END__
11:data:
12:data:This is data, kinda sorta.
13:data:
14:docu:=head1 TEST
15:docu:
16:docu:This is documentation.
17:docu:
18:docu:=cut
19:data:
20:data:# ex: set textwidth=72 :
EOD
}

{
    my $sam = CLASS->new(
	match		=> '\A',
	syntax		=> [ 'code' ],
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/perl_file.PL' );
    };

    is $stdout, <<'EOD', 'Showed Perl syntax classifications';
t/data/perl_file.PL
2:code:
3:code:use strict;
4:code:use warnings;
5:code:
7:code:
8:code:printf "Hello %s!\n", @ARGV ? $ARGV[0] : 'world';
9:code:
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
	file	=> 't/data/match_file',
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/bright.txt' );
    };

    is $stdout, <<'EOD',
t/data/bright.txt
1:There was a young lady named Bright
EOD
	'Matched line 1 of limmerick per --match t/data/match_file';
}

{
    my $sam = CLASS->new(
	f	=> 1,
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data' );
    };

    is $stdout, <<'EOD', '-f listed everything in t/data';
t/data/batch_file.bat
t/data/bright.txt
t/data/cc_file.c
t/data/cpp_file.cpp
t/data/fortran_file.for
t/data/java_file.java
t/data/json_file.json
t/data/make_file.mak
t/data/match_file
t/data/perl_file.PL
t/data/properties_file.properties
t/data/python_file.py
t/data/raku_file.raku
t/data/shell_file.sh
t/data/sql_file.sql
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
t/data/batch_file.bat
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
t/data/sql_file.sql
t/data/vim_file.vim
t/data/yaml_file.yml
EOD
}

{
    my $sam = CLASS->new(
	g	=> 1,
	match	=> '\.PL\z',
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data' );
    };

    is $stdout, <<'EOD', q(-g '\.PL\z' listed only .PL files in t/data);
t/data/perl_file.PL
EOD
}

{
    my $sam = CLASS->new(
	match	=> '(?:Thomas|Wyant)',
	output	=> '$f:$.:$c:$&',
	heading	=> 0,
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/sql_file.sql' );
    };
    is $stdout, <<'EOD', q(--output);
t/data/sql_file.sql:6:12:Thomas
t/data/sql_file.sql:6:22:Wyant
t/data/sql_file.sql:8:31:Thomas
t/data/sql_file.sql:8:41:Wyant
EOD
}

{
    my $sam = CLASS->new(
	match	=> 'Wyant',
	files_with_matches	=> 1,
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/' );
    };
    is $stdout, <<'EOD', q(--files-with-matches);
t/data/cc_file.c
t/data/cpp_file.cpp
t/data/fortran_file.for
t/data/java_file.java
t/data/shell_file.sh
t/data/sql_file.sql
EOD
}

{
    my $sam = CLASS->new(
	match	=> 'Wyant',
	files_without_matches	=> 1,
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/' );
    };
    is $stdout, <<'EOD', q(--files-without-matches);
t/data/batch_file.bat
t/data/bright.txt
t/data/json_file.json
t/data/make_file.mak
t/data/match_file
t/data/perl_file.PL
t/data/properties_file.properties
t/data/python_file.py
t/data/raku_file.raku
t/data/vim_file.vim
t/data/yaml_file.yml
EOD
}

{
    my $sam = CLASS->new(
	match	=> 'Bright',
	underline	=> 1,
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/bright.txt' );
    };

    is $stdout, <<'EOD', '--underline';
t/data/bright.txt
1:There was a young lady named Bright
                               ^^^^^^
EOD
}


done_testing;

1;

# ex: set textwidth=72 :

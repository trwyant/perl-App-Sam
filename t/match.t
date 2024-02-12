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

=begin comment

{
    my $sam = CLASS->new(
	match	=> 'ay$',
    );

    my $stdout = capture_stdout {
	is $sam->process( 't/data/bright.txt' ), 1, 'Matches in 1 file';
    };

    is $stdout, <<'EOD', 'Matched lines 3 and 4 of limmerick';
t/data/bright.txt
3:    She set out one day
4:    In a relative way
EOD
}

{
    my $sam = CLASS->new(
	match	=> 'ay$',
	line	=> 0,
    );

    my $stdout = capture_stdout {
	is $sam->process( 't/data/bright.txt' ), 1, 'Matches in 1 file';
    };

    is $stdout, <<'EOD', 'Matched lines 3 and 4 of limmerick';
t/data/bright.txt
    She set out one day
    In a relative way
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

=end comment

=cut

{
    my $sam = CLASS->new(
	file	=> 't/data/match_file',
    );

    my $stdout = capture_stdout {
	is $sam->process( 't/data/bright.txt' ), 1, 'Matches in 1 file';
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
	is $sam->process( 't/data' ), 18, '-f t/data found 17 files';
    };

    is $stdout, <<'EOD', '-f listed everything in t/data';
t/data/batch_file.bat
t/data/bright.txt
t/data/cc_file.c
t/data/cpp_file.cpp
t/data/files_from
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
	is $sam->process( 't/data' ), 15, '-fk t/data found 15 files';
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
	match		=> 'Wyant',
	max_count	=> 1,
    );

    my $stdout = capture_stdout {
	is $sam->process( 't/data/sql_file.sql' ), 1, '--max-count=1';
    };
    is $stdout, <<'EOD', q(--output);
t/data/sql_file.sql
6: * Author: Thomas R. Wyant, III F<wyant at cpan dot org>
EOD
}

{
    my $sam = CLASS->new(
	match	=> 'Wyant',
	files_with_matches	=> 1,
    );

    my $stdout = capture_stdout {
	is $sam->process( 't/data/' ), 6, '--files-with-matches found 6';
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
	files_with_matches	=> 1,
	print0			=> 1,
    );

    my $stdout = capture_stdout {
	is $sam->process( 't/data/' ), 6, '--files-without-matches found 6';
    };
    
    my $want = <<'EOD';
t/data/cc_file.c
t/data/cpp_file.cpp
t/data/fortran_file.for
t/data/java_file.java
t/data/shell_file.sh
t/data/sql_file.sql
EOD
    $want =~ s/ \n /\0/smxg;

    is $stdout, $want, q(--files-with-matches);
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
t/data/files_from
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
	match	=> 'day',
	after_context	=> 1,
	before_context	=> 1,
    );

    my $stdout = capture_stdout {
	is $sam->process( 't/data/bright.txt' ), 1, 'Matched 1 line';
    };

    is $stdout, <<'EOD', '--context=1 displayed 3 lines';
t/data/bright.txt
2:Who could travel much faster than light.
3:    She set out one day
4:    In a relative way
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

{
    my $sam = CLASS->new(
	match	=> 'Bright',
	s	=> 1,
    );

    my $stdout = capture_stdout {
	my $warnings = warnings {
	    is $sam->process( 't/data/fubar.txt' ), 0,
		'Found nothing in non-existent file';
	};
	is $warnings, [], '-s suppressed warning';
    };

    is $stdout, undef, '-s, searching non-existent file';
}

{
    my $sam = CLASS->new(
	1	=> 1,
	match	=> 'Wyant',
	argv	=> [ 't/data' ]
    );

    my $stdout = capture_stdout {
	is $sam->process(), 1, '-1 quit after first match';
    };

    is $stdout, <<'EOD', '-1 found correct data';
t/data/cc_file.c
13: * Author: Thomas R. Wyant, III F<wyant at cpan dot org>
EOD
}

{
    my $sam = CLASS->new(
	filter	=> 1,
	match	=> 'Wyant',
    );

    my $stdout = capture_stdout {
	stdin_from_file {
	    $sam->process();
	} 't/data/files_from';
    };

    is $stdout, <<'EOD', '--filter';
t/data/sql_file.sql
6: * Author: Thomas R. Wyant, III F<wyant at cpan dot org>
8: * Copyright (C) 2018-2023 by Thomas R. Wyant, III
EOD
}

{
    my $sam = CLASS->new(
	range_start	=> 'day',
	match		=> '\A',
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/bright.txt' );
    };

    is $stdout, <<'EOD', '--range-start';
t/data/bright.txt
3:    She set out one day
4:    In a relative way
5:And returned the previous night.
EOD
}

{
    my $sam = CLASS->new(
	range_end	=> 'way',
	match		=> '\A',
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/bright.txt' );
    };

    is $stdout, <<'EOD', '--range-end';
t/data/bright.txt
1:There was a young lady named Bright
2:Who could travel much faster than light.
3:    She set out one day
4:    In a relative way
EOD
}

{
    my $sam = CLASS->new(
	range_start	=> 'day',
	range_end	=> 'way',
	match		=> '\A',
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/bright.txt' );
    };

    is $stdout, <<'EOD', '--range-start, --range-end';
t/data/bright.txt
3:    She set out one day
4:    In a relative way
EOD
}

{
    my $sam = CLASS->new(
	range_start	=> 'one',
	range_end	=> 'day',
	match		=> '\A',
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/bright.txt' );
    };

    is $stdout, <<'EOD', '--range-start, --range-end match on same line';
t/data/bright.txt
3:    She set out one day
EOD
}

{
    my $sam = CLASS->new(
	proximate	=> 1,
	match		=> 'Wyant',
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/sql_file.sql' );
    };

    is $stdout, <<'EOD', '--proximate';
t/data/sql_file.sql
6: * Author: Thomas R. Wyant, III F<wyant at cpan dot org>

8: * Copyright (C) 2018-2023 by Thomas R. Wyant, III
EOD
}

done_testing;

1;

# ex: set textwidth=72 :

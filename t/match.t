package main;

use 5.010001;

use strict;
use warnings;

use open qw{ :std :encoding(utf-8) };

use File::Basename qw{ basename };
use Scalar::Util qw{ openhandle };
use Test2::V0 -target => 'App::Sam';

use lib qw{ inc };

use My::Module::Test;

use constant ALL_FILES		=> <<'EOD';
t/data/.samrc
t/data/ada_file.adb
t/data/batch_file.bat
t/data/bright.txt
t/data/cc_file.c
t/data/cpp_file.cpp
t/data/files_from
t/data/fortran_file.for
t/data/java_file.java
t/data/json_file.json
t/data/lisp_file.lisp
t/data/make_file.mak
t/data/match_file
t/data/pascal_file.pas
t/data/perl_file.PL
t/data/properties_file.properties
t/data/python_file.py
t/data/raku_file.raku
t/data/shell_file.sh
t/data/sql_file.sql
t/data/swift_file.swift
t/data/vim_file.vim
t/data/yaml_file.yml
EOD
use constant ALL_FILES_COUNT	=> ALL_FILES =~ tr/\n/\n/;
use constant KNOWN_FILES	=> do {
    my %unknown = map {; "t/data/$_\n" => 1 } qw{ .samrc bright.txt files_from
    match_file };
    join '', grep { ! $unknown{$_} } split /(?<=\n)/, ALL_FILES;
};
use constant KNOWN_FILES_COUNT	=> KNOWN_FILES =~ tr/\n/\n/;

my $mock = mock 'App::Sam' => (
    override	=> [
	__default_env	=> sub { return 0 },
    ],
);

{
    my $sam = CLASS->new(
	match	=> 'ay$',
    );

    my $stdout = capture_stdout {
	is $sam->process( 't/data/bright.txt' ), 1, 'Matches in 1 file';
    };

    is $stdout, <<'EOD', 'Matched lines 3 and 4 of limerick';
3:    She set out one day
4:    In a relative way
EOD
}

{
    my $sam = CLASS->new(
	match	=> 'ay$',
	with_filename	=> 1,
	line	=> 0,
    );

    my $stdout = capture_stdout {
	is $sam->process( 't/data/bright.txt' ), 1, 'Matches in 1 file';
    };

    is $stdout, <<'EOD', 'Matched lines 3 and 4 of limerick';
t/data/bright.txt
    She set out one day
    In a relative way
EOD
}

{
    my $sam = CLASS->new(
	match		=> 'ay$',
    );

    my $stdout = capture_stdout {
	$sam->process( 't/data/bright.txt' );
    };

    is $stdout, <<'EOD', 'Matched lines 3 and 4 of limerick';
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

    is $stdout, <<'EOD', 'Matched lines 3 and 4 of limerick';
3:    She set out one day
4:    In a relative way
EOD
}

{
    my $sam = CLASS->new(
	file	=> 't/data/match_file',
    );

    my $stdout = capture_stdout {
	is $sam->process( 't/data/bright.txt' ), 1, 'Matches in 1 file';
    };

    is $stdout, <<'EOD',
1:There was a young lady named Bright
EOD
	'Matched line 1 of limerick per --match t/data/match_file';
}

{
    my $sam = CLASS->new(
	f	=> 1,
    );

    my $stdout = capture_stdout {
	is $sam->process( 't/data' ), ALL_FILES_COUNT,
	    "-f t/data found @{[ ALL_FILES_COUNT ]} files";
    };

    is $stdout, ALL_FILES, '-f listed everything in t/data';
}

{
    my $sam = CLASS->new(
	f	=> 1,
	known_types	=> 1,
    );

    my $stdout = capture_stdout {
	is $sam->process( 't/data' ), KNOWN_FILES_COUNT,
	    "-fk t/data found @{[ KNOWN_FILES_COUNT ]} files";
    };

    is $stdout, KNOWN_FILES, '-fk listed only known types in t/data';
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
	match		=> '(?:Thomas|Wyant)',
	output		=> '$c:$&',
	heading		=> 0,
	with_filename	=> 1,
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
	is $sam->process( 't/data/' ), 6, '--files-with-matches found 6';
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
t/data/.samrc
t/data/ada_file.adb
t/data/batch_file.bat
t/data/bright.txt
t/data/files_from
t/data/json_file.json
t/data/lisp_file.lisp
t/data/make_file.mak
t/data/match_file
t/data/pascal_file.pas
t/data/perl_file.PL
t/data/properties_file.properties
t/data/python_file.py
t/data/raku_file.raku
t/data/swift_file.swift
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
2-Who could travel much faster than light.
3:    She set out one day
4-    In a relative way
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

SKIP: {
    openhandle( *STDIN )
	or skip q/Fails if STDIN has been closed. I don't know why./, 2;
    my $stdout = capture_stdout {
	my $sam = CLASS->new(
	    1	=> 1,
	    match	=> 'Wyant',
	    argv	=> [ 't/data' ]
	);
	is $sam->process(), 1, '-1 quit after first match';
    };

    is $stdout, <<'EOD', '-1 found correct data';
t/data/cc_file.c
13: * Author: Thomas R. Wyant, III F<wyant at cpan dot org>
EOD
}

{
    my $stdout = capture_stdout {
	stdin_from_file {
	    my $sam = CLASS->new(
		filter		=> 1,
		match		=> 'Wyant',
		with_filename	=> 0,
	    );
	    $sam->process();
	} 't/data/sql_file.sql';
    };

    is $stdout, <<'EOD', '--filter';
6: * Author: Thomas R. Wyant, III F<wyant at cpan dot org>
8: * Copyright (C) 2018-2024 by Thomas R. Wyant, III
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
6: * Author: Thomas R. Wyant, III F<wyant at cpan dot org>

8: * Copyright (C) 2018-2024 by Thomas R. Wyant, III
EOD
}

{
    # FIXME This is an unsatisfactory test because it does not actually
    # execute a search. This is because I have no control over the Perl
    # source, so the search results could change unexpectedly. Fixing
    # this requires a way to mock the relevant keys in %Config.

    my $sam = CLASS->new(
	perldoc	=> 'a',
    );

    is $sam, hash {
	field perldoc	=> 'all';
	field type	=> { perl => 0 };
	field syntax	=> { documentation => 1 };
	etc;
    }, '--perlfaq=all was expanded';

    # FIXME I would like to at least test the directories being
    # searched, but to do that I would have to reproduce the code being
    # tested, which seems pointless.    
}

{
    my $sam = CLASS->new(
	perldoc	=> 'f',
	f	=> 1,
    );

    is $sam, hash {
	field perldoc	=> 'faq';
	field type	=> { perlfaq => 0 };
	field syntax	=> { documentation => 1 };
	etc;
    }, '--perlfaq=f was expanded';

    my $stdout = capture_stdout {
	$sam->process();
    };

    # FIXME this is theoretically unsatisfactory for the same reasons as
    # the previous test, but less so because I think the number of FAQ
    # files is unlikely to change. I still do not test that I found the
    # right files, just that I found files with the expected base names.
    my @got = map { basename $_ } split /\n/, $stdout;
    my @want = map { "perlfaq$_.pod" } '', 1 .. 9;
    is \@got, \@want, 'perlfaq=f searches correct files';
}

done_testing;

1;

# ex: set textwidth=72 :

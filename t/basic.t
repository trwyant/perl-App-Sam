package main;

use strict;
use warnings;

use Cwd 3.08 ();
use Test2::V0;
use Test2::Plugin::BailOnFail;
use Test2::Tools::LoadModule;
use Test2::Tools::Mock;

use lib qw{ inc };

use My::Module::Test;

use constant CWD	=> Cwd::getcwd();
use constant REF_ARRAY	=> ref [];
use constant REF_CODE	=> ref sub {};

diag $_ for dependencies_table;

load_module_ok 'App::Sam::Util';

is App::Sam::Util::__me(), 'basic.t', '__me() returns base name of script';

load_module_ok 'App::Sam::Resource';

load_module_ok 'App::Sam::Tplt';

load_module_ok 'App::Sam::Tplt::Color';

load_module_ok 'App::Sam::Tplt::Under';

load_module_ok 'App::Sam::Syntax';

load_module_ok 'App::Sam::Syntax::_cc_like';

foreach my $syntax ( qw{ Ada Batch Cc Cpp Data Fortran Java Lisp Make
    Pascal Perl Properties Python Raku Shell SQL Swift Vim YAML } ) {
    my $class = "App::Sam::Syntax::$syntax";

    load_module_ok $class;

    can_ok $class, qw{ __classifications __classify };
}

load_module_ok 'App::Sam';

{
    my $mock = mock 'App::Sam' => (
	override	=> [
	    __default_env	=> sub { 0 },
	],
    );

    my $sam;
    my $warning;



    is dies { $sam = App::Sam->new() }, undef, 'Can instantiate App::Sam';
    isa_ok $sam, 'App::Sam';

    is $sam, {
	argv			=> [],
	color_colno		=> 'bold yellow',
	color_filename		=> 'bold green',
	color_lineno		=> 'bold yellow',
	color_match		=> 'black on_yellow',
	die			=> F,
	dump			=> F,
	_eol			=> "\n",
	encoding		=> '',
	env			=> F,
	filter			=> E,	# Default depends on environment
	flags			=> 0,
	ignore_sam_defaults	=> F,
	ignore_directory	=> hash { etc },
	ignore_file		=> hash { etc },
	invert_match		=> F,
	_munger		=> validator( sub { REF_CODE eq ref } ),
	recurse		=> T,
	sort_files		=> T,
	syntax_add		=> hash {	# Ensure Perl's syntax is defined.
	    field type	=> hash {
		field	perl		=> 'Perl';
		field	perltest	=> 'Perl';
		field	pod		=> 'Perl';
		etc;
	    };
	    etc;
	},
	_syntax_def		=> hash {
	    field Perl	=> {
		type	=> [ qw{ perl perltest pod } ],
	    };
	    etc;
	},
	type_add		=> hash {
	    field ext	=> hash {	# Ensure Perl is defined.
		field pl	=> [ 'perl' ];
		field pod	=> [ 'perl', 'pod' ];
		field psgi	=> [ 'perl' ];
		field t		=> [ 'perl', 'perltest' ];
		etc;
	    };
	    # NOTE firstlinematch is an unordered array, which I believe
	    # makes it a bag.
	    field firstlinematch => bag {
		item validator sub {
		    REF_ARRAY eq ref $_ &&
		    @{ $_ } == 2 &&
		    'perl' eq $_->[0] &&
		    REF_CODE eq ref $_->[1]
		};
#		FIXME why isn't the below equivalent to the above?
#		item array {
#		    string 'perl';
#		    validator sub { REF_CODE eq ref };
#		    end;
#		};
		etc;
	    };
	    etc;
	},
	_type_def		=> hash {
	    field perl	=> {
		ext			=> [
		    map { '.' . App::Sam::Util::__fold_case( $_ ) }
		    qw{ pl pm pod t psgi } ],
		firstlinematch	=> [ '/^#!.*\bperl/' ],
	    };
	    etc;
	},
    }, 'Got expected object';

    $warning = warnings { $sam->__carp( 'Fish' ) };
    is $warning, [
	match qr/ \A Fish \s at \b /smx,
    ], '__carp() gives correct warning';

    $warning = dies { $sam->__croak( 'Frog' ) };
    like $warning, qr/ \A Frog \s at \b /smx,
	'__croak() dies with correct message';

    $warning = dies { $sam->__confess( 'Mea culpa' ) };
    like $warning, qr/ \A Bug \s - \s Mea \s culpa \s at \b /smx,
	'__confess() dies with correct message';

    ok $sam->__ignore( directory => '.git' ),
	q/Directory '.git' is ignored'/;

    ok $sam->__ignore( directory => 'blib' ),
	q/Directory 'blib' is ignored'/;

    ok ! $sam->__ignore( directory => 'lib' ),
	q/Directory 'lib' is not ignored'/;

    ok $sam->__ignore( file => '.DS_Store' ),
	q/File '.DS_Store' is ignored'/;

    ok $sam->__ignore( file => 'fubar.so' ),
	q/File 'fubar.so' is ignored'/;

    ok $sam->__ignore( file => '_fubar.swp' ),
	q/File '_fubar.swp' is ignored'/;

    ok ! $sam->__ignore( file => 'fubar.PL' ),
	q/File 'fubar.PL' is not ignored'/;

    is [ $sam->__file_type( 'lib/App/Sam.pm' ) ], [ qw{ perl } ],
	q<lib/App/Sam.pm is type 'perl'>;

    is [ $sam->__file_type( 't/basic.t' ) ], [ qw{ perl perltest } ],
	q<t/basic.t is types 'perl' and 'perltest'>;

    is [ $sam->__file_type( 'README' ) ], [],
	q<README has no type>;

    ok $sam->__ignore( directory => 'blib' ), q<directory 'blib' is ignored>;

    is [ $sam->files_from( \<<'EOD' ) ], [ 't/data/limerick.t' ], 'files_from()';
t/data/limerick.t
EOD

    {
	chdir 't/data';
	delete local $ENV{SAMRC};
	local $sam->{env} = 1;
	if ( $sam->IS_WINDOWS ) {
	    # TODO Windows code
	} else {
	    is [ $sam->__get_resources() ],
		[
		    $sam->__get_default_resource(),
		    fake_rsrc( name => Cwd::abs_path( '/etc/samrc' ) ),
		    fake_rsrc( name => Cwd::abs_path(
			    App::Sam::Util::__expand_tilde( '~/.samrc' ) ) ),
		    fake_rsrc( name => Cwd::abs_path( '.samrc' ) ),
		],
		'Resource file names under anything but Windows';
	}
    }
    chdir CWD;

    like capture_stdout {
	$sam->help_types()
    }, qr/ \b objc \s+ \.m \s+ .h \b /smx,
	'help_types includes Objective C';



    is dies { $sam = App::Sam->new( die => 1 ) }, undef,
	'Can instantiate App::Sam with die => 1';
    isa_ok $sam, 'App::Sam';

    $warning = warnings { $sam->__carp( 'Fish' ) };
    is $warning, [
	"basic.t: Fish.\n"
    ], '__carp() gives correct warning';

    $warning = dies { $sam->__croak( 'Frog' ) };
    is $warning, "basic.t: Frog.\n",
	'__croak() dies with correct message';

    $warning = dies { $sam->__confess( 'Mea culpa' ) };
    like $warning, qr/ \A basic \. t: \s Bug \s - \s Mea \s culpa \s at \b /smx,
	'__confess() dies with correct message';



    is dies { $sam = App::Sam->new(
	    type	=> [ qw{ perl no-perltest } ],
	) }, undef,
	'Can instantiate App::Sam with type => [ qw{ perl no-perltest } ]';
    isa_ok $sam, 'App::Sam';

    ok $sam->__ignore( file => 't/basic.t' ),
    't/basic.t is ignored under type => [ qw{ perl no-perltest } ]';

    ok ! $sam->__ignore( file => 'lib/App/Sam.pm' ),
    'lib/App/Sam.pm is not ignored under type => [ qw{ perl no-perltest } ]';



    is dies { App::Sam->new(
		f		=> 1,
		match	=> '/foo/',
	    )
	}, match( qr/\AArguments 'f' and 'match' can not be used together\b/ ),
	q/Can not use attributes 'f' and 'match' together/;



    is dies { App::Sam->new(
		die	=> 1,
		argv	=> [ qw{ -f --match /foo/ } ],
	    )
	}, "basic.t: Options '-f' and '--match' can not be used together.\n",
	q/Can not use options '-f' and '--match' together/;



    is dies { $sam = App::Sam->new(
	    samrc	=> \<<'EOD',
--backup=.bak
--encoding
iso-latin-1
--type-del=perl
EOD
	) }, undef, 'Can instantiate App::Sam with samrc';
    isa_ok $sam, 'App::Sam';

    is $sam, hash {
	field backup	=> '.bak';
	field encoding	=> 'iso-latin-1';
	field syntax_add	=> hash {
	    field type	=> hash {
		field perl	=> DNE;
		etc;
	    };
	    etc;
	};
	field _syntax_def	=> hash {
	    field Perl	=> {
		type	=> [ qw{ perltest pod } ],
	    };
	    etc;
	};
	field type_add	=> hash {
	    field ext	=> hash {
		field PL	=> DNE;
		field pl	=> DNE;
		field pod	=> [ 'pod' ];
		field psgi	=> DNE;
		field t	=> [ 'perltest' ];
		etc;
	    };
	    field firstlinematch => validator sub {
		REF_ARRAY eq ref
		    or return 0;
		foreach ( @{ $_ } ) {
		    REF_ARRAY eq ref
			and @{ $_ } == 2
			and 'perl' eq $_->[0]
			and REF_CODE eq ref $_->[1]
			and return 0;
		}
		return 1;
	    };
	    # FIXME firstlinematch is an unordered array, which I believe
	    # makes it a bag. How do I test if something is NOT in the
	    # unordered array?
	    etc;
	};
	field _type_def	=> hash {
	    field perl	=> DNE;
	    etc;
	};
	etc;
    }, 'Got expected object';
}

{
    my $mock = mock 'App::Sam' => (
	override => [
	    __get_resources => sub {
		return $_[0]->__get_default_resource();
	    },
	],
    );

    local $ENV{SAM_COLOR_COLNO} = 'bold red on_yellow';
    local $ENV{SAM_COLOR_FILENAME} = 'bold green on_yellow';
    local $ENV{SAM_COLOR_LINENO} = 'dark red on_yellow';
    local $ENV{SAM_COLOR_MATCH} = 'white on_black';

    my $sam;
    is dies { $sam = App::Sam->new() }, undef, 'Can instantiate App::Sam';

    is $sam, hash {
	field color_colno	=> $ENV{SAM_COLOR_COLNO};
	field color_filename	=> $ENV{SAM_COLOR_FILENAME};
	field color_lineno	=> $ENV{SAM_COLOR_LINENO};
	field color_match	=> $ENV{SAM_COLOR_MATCH};
	etc;
    }, 'Picked up colors from environment variables';
}

all_modules_tried_ok;

done_testing;

1;

# ex: set textwidth=72 :

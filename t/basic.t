package main;

use strict;
use warnings;

use Test2::V0;
use Test2::Plugin::BailOnFail;
use Test2::Tools::LoadModule;

use lib qw{ inc };

use My::Module::Test;

use constant REF_CODE	=> ref sub {};

diag $_ for dependencies_table;

load_module_ok 'App::Sam';

# NOTE Not to be used except for testing.
App::Sam->__set_attr_default(
    env		=> 0,		# User rc could cause test failures
    match	=> '/foo/',	# Match argument is required
);

my $sam;
my $warning;



$warning = dies { $sam = App::Sam->new() };
is $warning, undef, 'Can instantiate App::Sam';
isa_ok $sam, 'App::Sam';

is $sam, {
    backup		=> '',
    color_filename	=> 'bold green',
    color_lineno	=> 'bold yellow',
    color_match		=> 'black on_yellow',
    encoding		=> 'utf-8',
    env			=> 0,
    ignore_sam_defaults	=> undef,
    ignore_directory	=> array { etc() },
    _ignore_directory	=> hash { etc() },
    ignore_file		=> array { etc() },
    _ignore_file	=> hash { etc() },
    match		=> '/foo/',
    munger		=> D,
    _munger		=> validator( sub { REF_CODE eq ref } ),
    type_add		=> array { etc() },
    _type_add		=> hash { etc() },
    _type_def		=> hash { etc() },
}, 'Got expected object';

is $sam->__me(), 'basic.t', '__me() returns base name of script';

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

is [ $sam->__type( 'lib/App/Sam.pm' ) ], [ qw{ perl } ],
    q<lib/App/Sam.pm is type 'perl'>;

is [ $sam->__type( 't/basic.t' ) ], [ qw{ perl perltest } ],
    q<t/basic.t is types 'perl' and 'perltest'>;

is [ $sam->__type( 'README' ) ], [],
    q<README has no type>;

ok $sam->__ignore( directory => 'blib' ), q<directory 'blib' is ignored>;



ok lives { $sam = App::Sam->new( die => 1 ) },
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



ok lives { $sam = App::Sam->new(
	type	=> [ qw{ perl no-perltest } ],
    ) },
    'Can instantiate App::Sam with type => [ qw{ perl no-perltest } ]';
isa_ok $sam, 'App::Sam';

ok $sam->__ignore( file => 't/basic.t' ),
't/basic.t is ignored under type => [ qw{ perl no-perltest } ]';

ok ! $sam->__ignore( file => 'lib/App/Sam.pm' ),
'lib/App/Sam.pm is not ignored under type => [ qw{ perl no-perltest } ]';



done_testing;

1;

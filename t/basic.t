package main;

use strict;
use warnings;

use Test2::V0;
use Test2::Plugin::BailOnFail;
use Test2::Tools::LoadModule;

use lib qw{ inc };

use My::Module::Test;

diag $_ for dependencies_table;

load_module_ok 'App::Sam';

App::Sam->__set_attr_default( env => 0 );

my $sad;
my $warning;



ok lives { $sad = App::Sam->new() }, 'Can instantiate App::Sam';
isa_ok $sad, 'App::Sam';

is $sad, {
    backup		=> '',
    color_filename	=> 'bold green',
    color_lineno	=> 'bold yellow',
    color_match		=> 'black on_yellow',
    encoding		=> 'utf-8',
    env			=> 0,
    ignore_sad_defaults	=> undef,
    ignore_directory	=> array { etc() },
    _ignore_directory	=> hash { etc() },
    ignore_file		=> array { etc() },
    _ignore_file	=> hash { etc() },
    type_add		=> array { etc() },
    _type_add		=> hash { etc() },
    _type_def		=> hash { etc() },
}, 'Got expected object';

is $sad->__me(), 'basic.t', '__me() returns base name of script';

$warning = warnings { $sad->__carp( 'Fish' ) };
is $warning, [
    match qr/ \A Fish \s at \b /smx,
], '__carp() gives correct warning';

$warning = dies { $sad->__croak( 'Frog' ) };
like $warning, qr/ \A Frog \s at \b /smx,
    '__croak() dies with correct message';

$warning = dies { $sad->__confess( 'Mea culpa' ) };
like $warning, qr/ \A Bug \s - \s Mea \s culpa \s at \b /smx,
    '__confess() dies with correct message';

ok $sad->__ignore( directory => '.git' ),
    q/Directory '.git' is ignored'/;

ok $sad->__ignore( directory => 'blib' ),
    q/Directory 'blib' is ignored'/;

ok ! $sad->__ignore( directory => 'lib' ),
    q/Directory 'lib' is not ignored'/;

ok $sad->__ignore( file => '.DS_Store' ),
    q/File '.DS_Store' is ignored'/;

ok $sad->__ignore( file => 'fubar.so' ),
    q/File 'fubar.so' is ignored'/;

ok $sad->__ignore( file => '_fubar.swp' ),
    q/File '_fubar.swp' is ignored'/;

ok ! $sad->__ignore( file => 'fubar.PL' ),
    q/File 'fubar.PL' is not ignored'/;


ok lives { $sad = App::Sam->new( die => 1 ) },
    'Can instantiate App::Sam with die => 1';
isa_ok $sad, 'App::Sam';

$warning = warnings { $sad->__carp( 'Fish' ) };
is $warning, [
    "basic.t: Fish.\n"
], '__carp() gives correct warning';

$warning = dies { $sad->__croak( 'Frog' ) };
is $warning, "basic.t: Frog.\n",
    '__croak() dies with correct message';

$warning = dies { $sad->__confess( 'Mea culpa' ) };
like $warning, qr/ \A basic \. t: \s Bug \s - \s Mea \s culpa \s at \b /smx,
    '__confess() dies with correct message';

done_testing;

1;

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
    override	=> [
	__default_env	=> sub { return 0 },
    ],
);

{
    my $sam = CLASS->new(
    );

    is $sam->file_type_is( 't/data/perl_file.PL', 'perl' ), 'perl',
	'perl_file.PL is a perl file';

    is $sam->file_type_is( 't/data/sql_file.sql', 'perl' ), undef,
	'sql_file.sql is not a perl file';
}

done_testing;

1;

# ex: set textwidth=72 :

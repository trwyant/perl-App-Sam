package main;

use 5.010001;

use strict;
use warnings;

use open qw{ :std :encoding(utf-8) };

use File::stat;
use Test2::V0 -target => 'App::Sam';
use Test2::Tools::Mock;

use lib qw{ inc };

use My::Module::Test;

our $MOCK_MTIME;	# So I can localize.

my $mock = mock 'App::Sam' => (
    override	=> [
	__default_env	=> sub { return 0 },
	stat	=> sub (_) {
	    my ( $arg ) = @_;
	    if ( ! defined $MOCK_MTIME ) {
		return CORE::stat( $arg );
	    } elsif ( wantarray ) {
		my @stat = CORE::stat( $arg );
		$stat[9] = $MOCK_MTIME;
		return @stat;
	    } else {
		my $stat = stat( $arg );
		# FIXME encapsulation violation. The next line makes use
		# of the fact that the object is based on Class::Struct.
		$stat->mtime( $MOCK_MTIME );
		return $stat;
	    }
	}
    ],
);

{
    my $sam = CLASS->new();

    is $sam->file_type_is( 't/data/perl_file.PL', 'perl' ), 'perl',
	'perl_file.PL is a perl file';

    is $sam->file_type_is( 't/data/sql_file.sql', 'perl' ), undef,
	'sql_file.sql is not a perl file';
}

{
    my $now = time;
    my $sam = CLASS->new(
	mod_before	=> \$now,
    );

    local $MOCK_MTIME = $now - 86_400;	# A day ago
    ok ! $sam->__ignore( file => 'README' ),
	'Select file modified before now';
    local $MOCK_MTIME = $now + 86_400;	# A day from now
    ok $sam->__ignore( file => 'README' ),
	'Ignore file not modified before now';
}

{
    my $now = time;
    my $sam = CLASS->new(
	mod_since	=> \$now,
    );

    local $MOCK_MTIME = $now - 86_400;	# A day ago
    ok $sam->__ignore( file => 'README' ),
	'Ignore file noy modified since now';
    local $MOCK_MTIME = $now + 86_400;	# A day from now
    ok ! $sam->__ignore( file => 'README' ),
	'Select file modified since now';
}

done_testing;

1;

# ex: set textwidth=72 :

package main;

use 5.010001;

use strict;
use warnings;

use ExtUtils::Manifest qw{ maniread };
use Test2::V0 -target => 'App::Sam';

note 'Ensure that every syntax module is associated with files';

my $sam = CLASS->new(
    env		=> 0,
    match	=> '/foo/',
);

my $manifest = maniread();

foreach ( sort keys %{ $manifest } ) {
    my ( $name ) = m| \A lib/App/Sam/Syntax/ ( [[:alpha:]] \w+ ) [.] pm \z |smx
	or next;
    ok $sam->{_syntax_def}{$name}, "Syntax $name is associated with files";
}

done_testing;

1;

# ex: set textwidth=72 :

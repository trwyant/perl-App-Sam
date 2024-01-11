package main;

use 5.006;

use strict;
use warnings;

use ExtUtils::Manifest qw{ maniread };
use App::Sam::Util qw{ @CARP_NOT };
use Test2::V0;

my @modules;
foreach my $fn ( sort keys %{ maniread() } ) {
    local $_ = $fn;
    s< \A lib/ ><>smx
	or next;
    s< [.] pm \z ><>smx
	or next;
    s< / ><::>smxg;
    push @modules, $_;

    local $/ = undef;
    open my $fh, '<:encoding(utf-8)', $fn
	or do {
	fail "Unable to open $fn: $!";
	next;
    };
    my $content = <$fh>;
    close $fh;

    ok $content =~ m/ \@CARP_NOT \b /smx,
	"$_ references \@CARP_NOT";
}
is \@CARP_NOT, \@modules,
    'Ensure that @App::Sam::Util::CARP_NOT is correct';

done_testing;

1;

# ex: set textwidth=72 :

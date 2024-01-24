package main;

use 5.010001;

use strict;
use warnings;

use App::Sam;
use Readonly;
use Test2::V0;
use Test2::Tools::LoadModule;

# Prevent Test::Pod::Coverage from trying to load My::Option::Coverage
$INC{'My/Option/Coverage.pm'} = __FILE__;

Readonly::Scalar my $PACKAGE => 'script/sam';

load_module_or_skip_all 'Test::Pod::Coverage', 1.00;

pod_coverage_ok (
    $PACKAGE,
    { coverage_class => 'My::Option::Coverage' },
    "Option documentation coverage in $PACKAGE",
);

done_testing;

package My::Option::Coverage;

use parent qw{ Pod::Coverage };

sub _get_syms {
    my ( $self, $package ) = @_;
    my %rslt;
    foreach my $attr_spec ( values %App::Sam::ATTR_SPEC ) {
	$attr_spec->{flags} & App::Sam::FLAG_IS_OPT()
	    or next;
	foreach ( $attr_spec->{name}, @{ $attr_spec->{alias}
	    || [] } ) {
	    m/ _ /smx
		and next;
	    my $attr_name = "$_";	# Force expression
	    substr $attr_name, 0, 0, length( $attr_name ) == 1 ? '-' : '--';
	    $rslt{$attr_name} = 1;
	}
    }
    # We assume that if we have both --no-fubar and --nofubar, the
    # latter does not need to be considered.
    foreach ( keys %rslt ) {
	s/ \A --no \K - //smx
	    and delete $rslt{$_};
    }
    return( sort keys %rslt );
}

1;

# ex: set textwidth=72 :

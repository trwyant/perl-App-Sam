package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam';
use App::Sam::Util qw{ __syntax_types };

sub validate;

note 'Syntax validation';

validate [], {}, 'Nuthing to validate';

validate [ qw{ code } ], { syntax => { code => 1 } };

validate [ qw{ code meta } ],
    { syntax => { code => 1, metadata => 1 } };

validate [ qw{ code meta nocode } ],
    { syntax => { metadata => 1 } };

validate [ qw{ code meta no-code nometa } ],
    {};

validate [ qw{ no-meta } ],
    { syntax => {
	    map { $_ => 1 } grep { $_ ne 'metadata' } __syntax_types() } };

done_testing;

sub validate {
    my ( $syntax, $want, $name ) = @_;
    $syntax //= [];
    ref $syntax
	or $syntax = [ $syntax ];
    $name //= join ', ', map { "'$_'" } @$syntax;
    @$syntax == 1
	and $syntax = $syntax->[0];
    my $ctx = context;
    my $sam = bless +{}, CLASS;
    state $validate = CLASS->can( '__validate_syntax' );
    $validate->( $sam, undef, undef, $syntax );
    my $rslt = is $sam, $want, $name;
    $ctx->release();
    return $rslt;
}

1;

# ex: set textwidth=72 :

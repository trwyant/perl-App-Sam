package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam';
use App::Sam::Util qw{ __fold_case };

use constant EXT_PL	=> __fold_case( 'PL' );
use constant EXT_PM	=> __fold_case( 'pm' );
use constant EXT_DOT_PL	=> '.' . EXT_PL;
use constant EXT_DOT_PM	=> '.' . EXT_PM;

use constant IS_CODE	=> meta { prop reftype => 'CODE' };

is got(), want(), 'No properties';

is got( '--type-add=perl:ext:PL,pm' ),
want(
    _type_def	=> {
	perl	=> {
	    ext	=> [ EXT_DOT_PL, EXT_DOT_PM ],
	},
    },
    type_add	=> {
	ext	=> {
	    EXT_PL,	[ qw{ perl } ],
	    EXT_PM,	 [ qw{ perl } ],
	},
    },
), 'Add type perl as .PL and .pm';

is got(
    '--type-add=perl:ext:PL,pm',
    '--type-add=perl:firstlinematch:/perl/',
),
want(
    _type_def	=> {
	perl	=> {
	    ext	=> [ EXT_DOT_PL, EXT_DOT_PM ],
	    firstlinematch	=> [
		'/perl/',
	    ],
	},
    },
    type_add	=> {
	ext	=> {
	    EXT_PL,	 [ qw{ perl } ],
	    EXT_PM,	 [ qw{ perl } ],
	},
	firstlinematch	=> [
	    [ perl => IS_CODE ],
	],
    },
), 'Add type perl as .pl and .pm, plus first line matches /perl/';

is got(
    '--type-add=perl:firstlinematch:/perl/',
    '--type-set=perl:ext:PL,pm',
), want(
    _type_def	=> {
	perl	=> {
	    ext	=> [ EXT_DOT_PL, EXT_DOT_PM ],
	},
    },
    type_add	=> {
	ext	=> {
	    EXT_PL,	 [ qw{ perl } ],
	    EXT_PM,	 [ qw{ perl } ],
	},
    },
), 'type-set replaces previous definition';

is got(
    '--type-set=perl:ext:PL,pm',
    '--type-del=perl',
), want(),
'type-set followed by type-del';

is got(
    '--type-add=perl:ext:PL,pm',
    '--syntax-add=Perl:type:perl',
), want (
    _syntax_def	=> {
	Perl	=> {
	    type	=> [ 'perl' ],
	},
    },
    _type_def	=> {
	perl	=> {
	    ext	=> [ EXT_DOT_PL, EXT_DOT_PM ],
	},
    },
    syntax_add	=> {
	type	=> {
	    perl	=> 'Perl',
	},
    },
    type_add	=> {
	ext	=> {
	    EXT_PL,	 [ qw{ perl } ],
	    EXT_PM,	 [ qw{ perl } ],
	},
    },
), 'Syntax Perl based on type perl';

is got(
    '--type-add=perl:ext:PL,pm',
    '--syntax-add=Perl:type:perl',
    '--type-del=perl',
), want (
), 'Deleting type deletes syntax based on it';

is got(
    '--type-add=perl:ext:PL,pm',
    '--syntax-add=Perl:type:perl',
    '--syntax-add=Perl:ext:PL,pm',
    '--type-del=perl',
), want (
    _syntax_def	=> {
	Perl	=> {
	    ext	=> [ EXT_DOT_PL, EXT_DOT_PM ],
	},
    },
    syntax_add	=> {
	ext	=> {
	    EXT_PL,	 [ 'Perl' ],
	    EXT_PM,	 [ 'Perl' ],
	},
    },
), 'Syntax can survive type deletion if has other bases than type';

is got(
    '--syntax-add=Unknown:fallback',
), want(
    _syntax_def	=> {
	Unknown	=> {
	    fallback	=> 1,
	},
    },
    syntax_add	=> {
	fallback	=> 'Unknown',
    }
), 'Add fallback syntax.';

is got(
    '--syntax-add=Unknown:fallback',
    '--syntax-add=Perl:fallback',
), want(
    _syntax_def	=> {
	Perl	=> {
	    fallback	=> 1,
	},
    },
    syntax_add	=> {
	fallback	=> 'Perl',
    }
), 'Only one fallback syntax.';

is got(
    '--syntax-add=Unknown:fallback',
    '--syntax-del=Unknown',
), want(), 'Fallback deletes properly';

done_testing;

my @keyz;

BEGIN {
    @keyz = qw{ _syntax_def syntax_add _type_def type_add };
}

sub got {
    my @arg = @_;
    my $sam = CLASS->new(
	ignore_sam_defaults	=> 1,
	env			=> 0,
	argv	=> \@arg,
    );
    my %rslt;
    foreach ( @keyz ) {
	exists $sam->{$_}
	    and $rslt{$_} = $sam->{$_};
    }
    return \%rslt;
}

sub want {
    my %rslt = @_;
    $rslt{$_} ||= {} for @keyz;
    return \%rslt;
}

1;

# ex: set textwidth=72 :

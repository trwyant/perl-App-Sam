package App::Sam;

use 5.010001;

use strict;
use warnings;

use utf8;

use App::Sam::Util qw{ :carp __syntax_types @CARP_NOT };
use File::Next ();
use File::Basename ();
use File::Spec;
use Errno qw{ :POSIX };
use File::ShareDir;
use File::Temp ();
use Getopt::Long ();
use List::Util ();
use Module::Load ();
use Readonly;
use Scalar::Util ();
use Term::ANSIColor ();
use Text::Abbrev ();

our $VERSION = '0.000_001';

use constant CLR_EOL	=> "\e[K";

use constant IS_WINDOWS	=> {
    MSWin32	=> 1,
}->{$^O} || 0;

use constant REF_ARRAY	=> ref [];
use constant REF_SCALAR	=> ref \0;

use constant STOP	=> 'STOP';

use enum qw{ BITMASK:FLAG_
    FAC_NO_MATCH_PROC FAC_SYNTAX FAC_TYPE
    IS_ATTR IS_OPT
    PROCESS_EARLY PROCESS_NORMAL PROCESS_LATE
};

=begin comment

BEGIN {
    my @flags;
    foreach my $sym ( sort keys %App::Sam:: ) {
	$sym =~ m/ \A FLAG_ /smx
	    or next;
	my $code = __PACKAGE__->can( $sym )
	    or next;
	push @flags, [ $sym, $code->() ];
    }

    sub __flags_to_names {
	my $mask = $_[-1];
	my @rslt;
	foreach my $item ( @flags ) {
	    $item->[1] & $mask
		or next;
	    push @rslt, $item->[0];
	}
	return @rslt;
    }
}

=end comment

=cut

use constant FLAG_DEFAULT	=> FLAG_IS_ATTR | FLAG_IS_OPT |
    FLAG_PROCESS_NORMAL;
use constant FLAG_FACILITY	=> FLAG_FAC_NO_MATCH_PROC |
    FLAG_FAC_SYNTAX | FLAG_FAC_TYPE;
use constant FLAG_PROCESS_SPECIAL => FLAG_PROCESS_EARLY | FLAG_PROCESS_LATE;

# To be filled in (and made read-only) later.
our %ATTR_SPEC;

sub new {
    my ( $class, @raw_arg ) = @_;

    @raw_arg % 2
	and __croak( (), 'Odd number of arguments to new()' );

    # This rigamarole is because some of the arguments need to be
    # processed out of order.
    my @bad_arg;
    my @cooked_arg;
    my %priority_arg;
    while ( @raw_arg ) {
	my ( $arg_name, $arg_val ) = splice @raw_arg, 0, 2;
	if ( ! $ATTR_SPEC{$arg_name} ||
	    ! ( $ATTR_SPEC{$arg_name}{flags} & FLAG_IS_ATTR )
	) {
	    push @bad_arg, $arg_name;
	} elsif ( $ATTR_SPEC{$arg_name}{flags} & FLAG_PROCESS_SPECIAL ) {
	    $priority_arg{$arg_name} = $arg_val;
	} else {
	    push @cooked_arg, [ $arg_name, $arg_val ];
	}
    }

    my $argv = $priority_arg{argv};

    my $self = bless {
	ignore_sam_defaults	=> $priority_arg{ignore_sam_defaults} // 0,
	die		=> $priority_arg{die} // 0,
	color_colno	=> 'bold yellow',
	color_filename	=> 'bold green',
	color_lineno	=> 'bold yellow',
	color_match	=> 'black on_yellow',
	env		=> $priority_arg{env} // 1,
	flags		=> 0,
	recurse		=> 1,
	sort_files	=> 1,
    }, $class;

    if ( REF_ARRAY eq ref $argv ) {
	$self->{argv} = $argv;
	$self->__get_option_parser( 1 )->getoptionsfromarray( $argv,
	    $self, $self->__get_opt_specs( FLAG_PROCESS_EARLY ) );
    } elsif ( defined $argv ) {
	$self->__croak( 'Argument argv must be an ARRAY reference' );
    }

    @bad_arg
	and $self->__croak( "Unknown new() arguments @bad_arg" );

    if ( $self->{env} ) {
	foreach my $ele ( qw{ colno filename lineno match } ) {
	    my $env_var_name = "SAM_COLOR_\U$ele";
	    defined( my $attr_val = $ENV{$env_var_name} )
		or next;
	    my $attr_name = "color_$ele";
	    if ( $self->__validate_color( undef, $attr_name, $attr_val ) ) {
		$self->{$attr_name} = $attr_val;
	    } else {
		$self->__carp( "Environment variable $env_var_name ",
		    "contains an imvalid value. Ignored." );
	    }
	}
    }

    foreach my $file ( $self->__get_rc_file_names() ) {
	$self->__get_attr_from_rc( $file );
    }

    if ( my $file = $priority_arg{samrc} ) {
	$self->__get_attr_from_rc( $file, 1 );	# Required to exist
    }

    foreach my $argument ( @cooked_arg ) {
	my ( $attr_name, $attr_val ) = @{ $argument };
	$ATTR_SPEC{$attr_name}
	    or $self->__croak( "Invalid argument '$attr_name' to new()" );
	$self->__validate_attr( $attr_name, $attr_val )
	    or $self->__croak( "Invalid $attr_name value '$attr_val'" );
    }

    $argv
	and $self->__get_attr_from_rc( $argv );

    $self->__incompat_arg( qw{ f match } );
    $self->__incompat_arg( qw{ f g files_with_matches
	files_without_matches replace max_count } );
    $self->__incompat_arg( qw{ replace 1 } );
    $self->__incompat_arg( qw{ file match } );
    $self->__incompat_arg( qw{ count passthru } );
    $self->__incompat_arg( qw{ underline output } );

    unless ( $self->{f} || defined $self->{match} ) {
	if ( $self->{file} ) {
	    my @pat;
	    foreach my $file ( @{ $self->{file} } ) {
		open my $fh, '<:encoding(utf-8)', $file
		    or $self->__croak( "Failed to open $file: $!" );
		while ( <$fh> ) {
		    chomp;
		    m/ \A \( /smx
			and m/ \) \z /smx
			or $_ = "(?:$_)";
		    push @pat, $_;
		}
		close $fh;
	    }
	    if ( @pat > 1 ) {
		local $" = '|';
		$self->{match} = "(?|@pat)";
	    } elsif ( @pat == 1 ) {
		$self->{match} = $pat[0];
	    }
	} elsif ( $argv && @{ $argv } ) {
	    $self->{match} = shift @{ $argv };
	}
    }


    {
	no warnings qw{ once };
	$Carp::Verbose
	    and delete $self->{die};
    }

    defined $self->{backup}
	and $self->{backup} eq ''
	and delete $self->{backup};

    foreach my $attr_name ( qw{ ignore_file ignore_directory not } ) {
	$self->{$attr_name}	# Prevent autovivification
	    and $self->{$attr_name}{match}
	    or next;
	my $str = join ' || ', map { "m $_" }
	    List::Util::uniqstr( @{ $self->{$attr_name}{match} } );
	$self->{$attr_name}{match} = $self->__compile_match( $attr_name,
	    $str );
    }

    foreach my $prop ( qw{ syntax type } ) {

	my $attr = "${prop}_add";
	foreach my $kind ( qw{ ext is } ) {
	    foreach my $prop_spec ( values %{ $self->{$attr}{$kind} || {} } ) {
		@{ $prop_spec } = List::Util::uniqstr( @{ $prop_spec } );
	    }
	}

	foreach my $kind ( qw{ match firstlinematch } ) {
	    my %uniq;
	    @{ $self->{$attr}{$kind} } =
		map { pop @{ $_ }; $_ }
		grep { ! $uniq{$_->[2]}++ }
		@{ $self->{$attr}{$kind} || [] }
		or delete $self->{$attr}{$kind};
	}

	$attr = "_${prop}_def";
	foreach my $thing ( values %{ $self->{$attr} } ) {
	    foreach my $prop_spec ( values %{ $thing } ) {
		@{ $prop_spec } = List::Util::uniqstr( @{ $prop_spec } );
	    }
	}
    }

    delete $self->{filter}
	and $self->__validate_files_from( undef, files_from => '-' );

    if ( $self->{range_start} || $self->{range_end} ) {
	state $range_val = {
	    range_start	=> 1,
	    range_end	=> 0,
	};
	my @str;
	foreach ( sort keys %{ $range_val } ) {
	    defined $self->{$_}
		or next;
	    $self->__compile_match( $_, "m ($self->{$_})" );
	    push @str, "$self->{$_}(?{ \$self->{_process}{in_range} = $range_val->{$_} })";
	}
	local $" = '|';
	$self->{_range} = $self->__compile_match( _range => "m (@str)g" );
    }

    $self->__make_munger();

    return $self;
}

sub __compile_match {
    my ( $self, $attr_name, $attr_val ) = @_;
    local $@ = undef;
    my $code = eval "sub { $attr_val }" ## no critic (ProhibitStringyEval)
	or do {
	my $method = substr( $attr_name, 0, 1 ) eq '_' ?
	    '__confess' : '__croak';
	$self->$method( "Invalid $attr_name match: $@" );
    };
    return $code;
}

sub create_samrc {
    my ( $self, $exit ) = @_;
    $exit //= caller eq __PACKAGE__;
    my $default_file = $self->__get_attr_default_file_name();
    local $_ = undef;	# while (<>) does not localize $_
    open my $fh, '<:encoding(utf-8)', $default_file
	or $self->__croak( "Failed to open $default_file: $!" );
    while ( <$fh> ) {
	$. == 1
	    and s/==VERSION==/$VERSION/;
	print;
    }
    close $fh;
    $exit and exit;
    return;
}

sub _accum_opt_for_dump {
    my ( $self, $line ) = @_;
    chomp $line;
    if ( delete $self->{_dump}{want_arg} ) {
	$self->{_dump}{accum}[-1][0] .= " $line";
    } else {
	$line =~ s/ \A \s+ //smx;
	$line =~ m/ \A --? ( [\w-]+ ) /smx
	    or return;
	( my $key = $1 ) =~ tr/-/_/;
	push @{ $self->{_dump}{accum} }, [ $line, $key ];
	$line =~ m/ = /smx
	    and return;
	my $attr_spec = $ATTR_SPEC{$key}
	    or return;
	$attr_spec->{type} =~ m/ \A = /smx
	    or return;
	$self->{_dump}{want_arg} = 1;
    }
    return;
}

sub _display_opt_for_dump {
    my ( $self, $name ) = @_;
    $self->{_dump}{accum}
	or return;
    say $name;
    say '=' x length $name;
    say "  $_->[0]" for
	sort { $a->[1] cmp $b->[1] } @{ $self->{_dump}{accum} };
    return;
}

{
    Readonly::Array my @COLORS => (
	qw{ black red green yellow blue magenta cyan white } );
    Readonly::Scalar my $BOLD	=> 'bold';
    Readonly::Scalar my $LEADER => ' ' x length $BOLD;
    sub help_colors {
	my ( undef, $exit ) = @_;	# Invocant unused.
	$exit //= caller eq __PACKAGE__;

	print <<'EOD';

The sam program allows customization of the colors used when presenting
matches to the user. The heavy lifting is done by the Term::ANSIColor
module, and you can specify colors any way that module accepts.

What follows is a palette specified using the eight-color scheme for
both foreground and background colors.

EOD
	say $LEADER, map { _help_colors_cell( $_ ) } @COLORS;
	say $LEADER, map { _help_colors_cell( '-------' ) } @COLORS;
	say $LEADER, map { _help_colors_cell( $_, $_ ) } @COLORS;
	say $BOLD, map { _help_colors_cell( $_, "$BOLD $_" ) } @COLORS;

	foreach my $bg ( map { " on_$_" } @COLORS ) {
	    say '';
	    say $LEADER,
		( map { _help_colors_cell( $_, "$_$bg" ) } @COLORS),
		$bg;
	    say $BOLD,
		( map { _help_colors_cell( $_, "$BOLD $_$bg" ) } @COLORS ),
		$bg;
	}

	$exit and exit;
	return;
    }
}

sub _help_colors_cell {
    my ( $text, $color ) = @_;
    my $cell = sprintf '%-7s', substr $text, 0, 7;
    $color
	and $cell = Term::ANSIColor::colored( $cell, $color );
    return " $cell";
}

sub help_syntax {
    my ( $self, $exit ) = @_;
    $exit //= caller eq __PACKAGE__;
    my $syntax_wid = List::Util::max( map { length } keys %{
	$self->{_syntax_def} } );
    print <<'EOD';
The following is the list of file syntaxes supported by sam. You can
specify a file syntax to search with --syntax=SYNTAX.

EOD
    foreach my $syntax ( sort keys %{ $self->{_syntax_def} } ) {
	my $syntax_def = $self->{_syntax_def}{$syntax};
	my @defs;
	foreach my $kind ( qw{ is ext match firstlinematch type } ) {
	    $syntax_def->{$kind}
		and @{ $syntax_def->{$kind} }
		or next;
	    state $prefix = {
		is	=> [],
		ext	=> [],
		match	=> [ 'Filename matches' ],
		firstlinematch	=> [ 'First line matches' ],
		type	=> [ 'Type' ],
	    };
	    push @defs, join ' ', @{ $prefix->{$kind} }, @{
	    $syntax_def->{$kind } };
	}
	printf "    %-*s %s\n", $syntax_wid, $syntax, join '; ', @defs;
    }
    $exit and exit;
    return;
}

sub help_types {
    my ( $self, $exit ) = @_;
    $exit //= caller eq __PACKAGE__;
    my $type_wid = List::Util::max( map { length } keys %{
	$self->{_type_def} } );
    print <<'EOD';
The following is the list of filetypes supported by sam. You can specify
a filetype to include with --type=TYPE. You can exclude a filetype with
--type=noTYPE.

Note that some files may appear in multiple types. For example, a file
called Rakefile is both Ruby (--type=ruby) and Rakefile
(--type=rake).

EOD
    foreach my $type ( sort keys %{ $self->{_type_def} } ) {
	my $type_def = $self->{_type_def}{$type};
	my @defs;
	foreach my $kind ( qw{ is ext match firstlinematch } ) {
	    $type_def->{$kind}
		and @{ $type_def->{$kind} }
		or next;
	    state $prefix = {
		is	=> [],
		ext	=> [],
		match	=> [ 'Filename matches' ],
		firstlinematch	=> [ 'First line matches' ],
	    };
	    push @defs, join ' ', @{ $prefix->{$kind} }, @{
	    $type_def->{$kind } };
	}
	printf "    %-*s %s\n", $type_wid, $type, join '; ', @defs;
    }
    $exit and exit;
    return;
}

sub __color {
    my ( $self, $kind, $text ) = @_;
    $self->{color}
	or return $text;
    state $uncolored = { map { $_ => 1 } '', "\n" };
    $uncolored->{$text}
	and return $text;
    defined( my $color = $self->{"color_$kind"} )
	or $self->__confess( "Invalid color kind '$kind'" );
    $self->{_process}{colored} = 1;
    return Term::ANSIColor::colored( $text, $color );
}

sub dumped {
    my ( $self ) = @_;
    return $self->{dump};
}

sub files_from {
    my ( $self, @file_list ) = @_;
    if ( @file_list ) {
	my @rslt;
	foreach my $file ( @file_list ) {
	    my $encoding = $self->__get_encoding( $file, 'utf-8' );
	    local $_ = undef;	# while (<>) does not localize $_
	    my $fh;
	    if ( $file eq '-' ) {
		$fh = \*STDIN;
	    } else {
		open $fh, "<$encoding", $file	## no critic (RequireBriefOpen)
		    or $self->__croak( "Failed to open $file: $!" );
	    }
	    while ( <$fh> ) {
		m/ \S /smx
		    or next;
		chomp;
		$self->{filter_files_from}
		    and $self->__ignore( file => $_ )
		    and next;
		push @rslt, $_;
	    }
	    # NOTE no explicit close here, because $fh might alias
	    # STDIN.
	}
	return @rslt;
    } elsif ( $self->{files_from} && @{ $self->{files_from} } ) {
	return $self->files_from( @{ $self->{files_from} || [] } );
    }
    return;
}

sub _file_property {
    ( my ( $self, $property, $path ), local $_ ) = @_;
    my $prop_spec = $self->{"${property}_add"} || {};
    $_ //= ( File::Spec->splitpath( $path ) )[2];
    my @rslt;

    $prop_spec->{is}{$_}
	and push @rslt, @{ $prop_spec->{is}{$_} };

    m/ [.] ( [^.]* ) \z /smx
	and $prop_spec->{ext}{$1}
	and push @rslt, @{ $prop_spec->{ext}{$1} };

    if ( my $match = $prop_spec->{match} ) {
	foreach my $m ( @{ $match } ) {
	    $m->[1]->()
		and push @rslt, $m->[0];
	}
    }

    if (
	my $match = $prop_spec->{firstlinematch}
	    and open my $fh, '<' . $self->__get_encoding( $path ), $path
    ) {
	local $_ = <$fh>;
	close $fh;
	foreach my $m ( @{ $match } ) {
	    $m->[1]->()
		and push @rslt, $m->[0];
	}
    }

    if ( my $type_map = $prop_spec->{type} ) {
	foreach my $type (
	    $self->{_process}{type} ?
	    @{ $self->{_process}{type} } :
	    $self->__file_type( $path, $_ )
	) {
	    $type_map->{$type}
		and push @rslt, $type_map->{$type};
	}
    }

    return List::Util::uniqstr( sort @rslt );
}

sub __file_syntax {
    my ( $self, @arg ) = @_;
    return $self->_file_property( syntax => @arg );
}

sub __file_syntax_del {
    my ( $self, $syntax ) = @_;
    delete $self->{_syntax_def}{$syntax};
    foreach my $type ( keys %{ $self->{syntax_add}{type} } ) {
	$syntax eq $self->{syntax_add}{type}{$type}
	    and delete $self->{syntax_add}{type}{$type};
    }
    return;
}

sub __file_type {
    my ( $self, @arg ) = @_;
    return $self->_file_property( type => @arg );
}

sub __file_type_del {
    my ( $self, $type, $really ) = @_;
    my $def = $self->{type_add};
    foreach my $kind ( qw{ is ext } ) {
	foreach my $key ( keys %{ $def->{$kind} } ) {
	    @{ $def->{$kind}{$key} } = grep { $_ ne $type }
		@{ $def->{$kind}{$key} }
		or delete $def->{$kind}{$key};
	}
    }
    foreach my $kind ( qw{ match firstlinematch } ) {
	@{ $def->{$kind} } = grep { $_->[0] ne $type } @{ $def->{$kind} };
    }
    delete $self->{_type_def}{$type};
    if ( $really ) {
	foreach my $syntax ( keys %{ $self->{_syntax_def} } ) {
	    @{ $self->{_syntax_def}{$syntax}{type} } = grep { $_ ne $type }
		@{ $self->{_syntax_def}{$syntax}{type} }
		or delete $self->{_syntax_def}{$syntax}{type};
	    keys %{ $self->{_syntax_def}{$syntax} }
		or delete $self->{_syntax_def}{$syntax};
	}
	delete $self->{syntax_add}{type}{$type};
    }
    return;
}

{
    # The following keys are defined:
    # {name} - the name of the attribute, with underscores rather than
    #         dashes. This is required.
    # {type} - the type of the associated option, expressed as a
    #         GetOpt::Long suffix. Required.
    # {alias} - A reference to an array of aliases to the option. The
    #         variants with dashes rather than underscores need not be
    #         specified here as they will be generated. Does not apply
    #         to attribute processing. Optional.
    # {validate} - The name of the method used to validate the
    #         attribute. Optional.
    # {arg} - Available for use by the {validate} code.
    # {flags} - This is a bit mask specifying special processing. The
    #         value must be the bitwise OR of the following values:
    #         FLAG_IS_ATTR - The entry is an attribute
    #         FLAG_IS_OPT -- The entry is an option
    #         FLAG_PROCESS_EARLY -- Process the attribute early.
    #         FLAG_PROCESS_NORMAL - Process the attribute normally.
    #         FLAG_PROCESS_LATE --- Process the attribute late.
    #         FLAG_FAC_NO_MATCH_PROC - No match processing
    #         FLAG_FAC_SYNTAX - A symtax module must be instantiated
    #         FLAG_FAC_TYPE - The file type needs to be computed
    #         NOTE that the FLAG_PROCESS_* items only apply to
    #         attributes, and therefore imply FLAG_IS_ATTR. Optional. If
    #         not provided, the default is FLAG_IS_ATTR | FLAG_IS_OPT |
    #         FLAG_PROCESS_NORMAL.
    my %attr_spec_hash = (
	1		=> {
	    type	=> '',
	},
	after_context	=> {
	    type	=> '=i',
	    alias	=> [ 'A' ],
	},
	argv	=> {
	    type	=> '=s@',
	    flags	=> FLAG_PROCESS_LATE
	},
	backup	=> {
	    type	=> '=s',
	},
	no_backup	=> {
	    type	=> '',
	    flags	=> FLAG_IS_OPT,
	    alias	=> [ 'nobackup' ],
	    validate	=> '__validate_fixed_value',
	    arg		=> [ 'backup' ],
	},
	before_context	=> {
	    type	=> '=i',
	    alias	=> [ 'B' ],
	},
	break	=> {
	    type	=> '!',
	},
	color	=> {
	    type	=> '!',
	    alias	=> [ qw{ colour } ],
	},
	color_colno	=> {
	    type	=> '=s',
	    validate	=> '__validate_color',
	},
	color_filename	=> {
	    type	=> '=s',
	    validate	=> '__validate_color',
	},
	color_lineno	=> {
	    type	=> '=s',
	    validate	=> '__validate_color',
	},
	color_match	=> {
	    type	=> '=s',
	    validate	=> '__validate_color',
	},
	column	=> {
	    type	=> '!',
	},
	context		=> {
	    type	=> '=i',
	    alias	=> [ 'C' ],
	    flags	=> FLAG_IS_OPT,
	    validate	=> '__validate_gang_set',
	    arg		=> [ qw{ before_context after_context } ],
	},
	count	=> {
	    type	=> '!',
	    alias	=> [ 'c' ],
	},
	create_samrc	=> {
	    type	=> '',
	    validate	=> 'create_samrc',
	},
	die	=> {
	    type	=> '!',
	    flags	=> FLAG_IS_ATTR,
	},
	dry_run	=> {
	    type	=> '!',
	},
	dump	=> {
	    type	=> '!',
	    flags	=> FLAG_IS_OPT | FLAG_PROCESS_EARLY,
	},
	group		=> {
	    type	=> '!',
	    flags	=> FLAG_IS_OPT,
	    validate	=> '__validate_gang_set',
	    arg		=> [ qw{ break heading } ],
	},
	encoding	=> {
	    type	=> '=s',
	},
	env	=> {
	    type	=> '!',
	    flags	=> FLAG_IS_OPT | FLAG_PROCESS_EARLY,
	},
	f	=> {
	    type	=> '!',
	    flags	=> FLAG_FAC_NO_MATCH_PROC,
	},
	g	=> {
	    type	=> '!',	# The expression comes from --match.
	    flags	=> FLAG_FAC_NO_MATCH_PROC,
	},
	file		=> {
	    type	=> '=s@',
	    validate	=> '__validate_files_from',
	},
	files_from	=> {
	    type	=> '=s@',
	    validate	=> '__validate_files_from',
	},
	files_with_matches	=> {
	    type	=> '!',
	    alias	=> [ 'l' ],
	    validate	=> '__validate_radio',
	    arg		=> [ 'files_without_matches' ],
	    flags	=> FLAG_FAC_NO_MATCH_PROC,
	},
	files_without_matches	=> {
	    type	=> '!',
	    alias	=> [ 'L' ],
	    validate	=> '__validate_radio',
	    arg		=> [ 'files_with_matches' ],
	    flags	=> FLAG_FAC_NO_MATCH_PROC,
	},
	filter		=> {
	    type	=> '!',
	},
	filter_files_from	=> {
	    type	=> '!',
	},
	flush		=> {
	    type	=> '!',
	},
	follow		=> {
	    type	=> '!',
	},
	heading		=> {
	    type	=> '!',
	},
	ignore_case	=> {
	    alias	=> [ qw{ i } ],
	    type	=> '!',
	},
	I	=> {
	    type	=> '|',
	    flags	=> FLAG_IS_OPT,
	    validate	=> '__validate_inverted_value',
	    arg		=> 'ignore_case',
	},
	ignore_directory	=> {
	    type	=> '=s@',
	    validate	=> '__validate_ignore',
	},
	ignore_file	=> {
	    type	=> '=s@',
	    validate	=> '__validate_ignore',
	},
	ignore_sam_defaults	=> {
	    type	=> '!',
	    flags	=> FLAG_IS_OPT | FLAG_PROCESS_EARLY,
	},
	invert_match	=> {
	    type	=> '!',
	    alias	=> [ 'v' ],
	},
	known_types	=> {
	    type	=> '!',
	    alias	=> [ 'k' ],
	    flags	=> FLAG_FAC_TYPE,
	},
	line		=> {
	    type	=> '!',
	},
	literal	=> {
	    type	=> '!',
	    alias	=> [ 'Q' ],
	},
	max_count	=> {
	    type	=> '=i',
	    alias	=> [ 'm' ],
	},
	n		=> {
	    type	=> '!',
	    validate	=> '__validate_inverted_value',
	    arg		=> 'recurse',
	},
	no_filename	=> {
	    type	=> '',
	    alias	=> [ 'h' ],
	    validate	=> '__validate_inverted_value',
	    arg		=> 'with_filename',
	    flags	=> FLAG_IS_OPT,
	},
	with_filename	=> {
	    type	=> '',
	    alias	=> [ 'H' ],
	},
	not		=> {
	    type	=> '=s@',
	    validate	=> '__validate_not'
	},
	o		=> {
	    type	=> '',
	    validate	=> '__validate_fixed_value',
	    arg		=> [ output	=> '$&' ],
	},
	output		=> {
	    type	=> '=s',
	},
	passthru	=> {
	    type	=> '!',
	    alias	=> [ 'passthrough' ],
	},
	print0		=> {
	    type	=> '!',
	},
	recurse		=> {
	    type	=> '!',
	    alias	=> [ qw{ r R } ],
	},
	type_add	=> {
	    type	=> '=s@',
	    validate	=> '__validate_file_property_add',
	},
	type_del	=> {
	    type	=> '=s@',
	    validate	=> '__validate_file_property_add',
	},
	type_set	=> {
	    type	=> '=s@',
	    validate	=> '__validate_file_property_add',
	},
	syntax_add	=> {
	    type	=> '=s@',
	    validate	=> '__validate_file_property_add',
	},
	syntax_del	=> {
	    type	=> '=s@',
	    validate	=> '__validate_file_property_add',
	},
	syntax_set	=> {
	    type	=> '=s@',
	    validate	=> '__validate_file_property_add',
	},
	match	=> {
	    type	=> '=s',
	},
	range_end	=> {
	    type	=> '=s',
	},
	range_start	=> {
	    type	=> '=s',
	},
	replace	=> {
	    type	=> '=s',
	},
	remove		=> {
	    type	=> '',
	    flags	=> FLAG_IS_OPT,
	    validate	=> '__validate_fixed_value',
	    arg		=> [ replace	=> '' ],
	},
	no_replace	=> {
	    type	=> '',
	    flags	=> FLAG_IS_OPT,
	    alias	=> [ qw{ noreplace no_remove no-remove noremove } ],
	    validate	=> '__validate_fixed_value',
	    arg		=> [ 'replace' ],
	},
	s	=> {
	    type	=> '!',
	},
	samrc	=> {
	    type	=> '=s',
	    flags	=> FLAG_IS_OPT | FLAG_PROCESS_LATE,
	},
	show_syntax	=> {
	    type	=> '!',
	    flags	=> FLAG_FAC_SYNTAX,
	},
	show_types	=> {
	    type	=> '!',
	    flags	=> FLAG_FAC_TYPE,
	},
	sort_files	=> {
	    type	=> '!',
	},
	syntax	=> {
	    type	=> '=s@',
	    validate	=> '__validate_syntax',
	    flags	=> FLAG_FAC_SYNTAX,
	},
	type	=> {
	    type	=> '=s@',
	    alias	=> [ 't' ],
	    validate	=> '__validate_type',
	    flags	=> FLAG_FAC_TYPE,
	},
	underline	=> {
	    type	=> '!',
	},
	word_regexp	=> {
	    type	=> '!',
	    alias	=> [ qw/ w / ],
	},
	x		=> {
	    type	=> '',
	    flags	=> FLAG_IS_OPT,
	    validate	=> '__validate_fixed_value',
	    arg		=> [ files_from	=> '-' ],
	},
	help_colors	=> {
	    type	=> '',
	    validate	=> 'help_colors',
	},
	help_syntax	=> {
	    type	=> '',
	    validate	=> 'help_syntax',
	},
	help_types	=> {
	    type	=> '',
	    validate	=> 'help_types',
	},
    );

    foreach my $key ( keys %attr_spec_hash ) {
	my $val = $attr_spec_hash{$key};
	$val->{name} = $key;
	if ( $key =~ m/ _ /smx ) {
	    ( my $alias = $key ) =~ s/ _ /-/smxg;
	    push @{ $val->{alias} }, $alias;
	}

	defined $val->{flags}
	    or $val->{flags} = FLAG_DEFAULT;

	if ( $val->{flags} & ~ FLAG_FACILITY ) {
	    if ( $val->{flags} & ( FLAG_PROCESS_EARLY |
		    FLAG_PROCESS_NORMAL | FLAG_PROCESS_LATE ) ) {
		$val->{flags} |= FLAG_IS_ATTR;
	    }
	} else {
	    $val->{flags} |= FLAG_DEFAULT;
	}

	if ( $val->{flags} & FLAG_FACILITY ) {
	    ( $val->{flags} & FLAG_FAC_SYNTAX )
		and $val->{flags} |= FLAG_FAC_TYPE;
	    $val->{validate} //= $val->{type} =~ m/ \A \@ \z /smx ?
		'__validate_accept_array' : '__validate_accept_scalar';
	}
    }

    Readonly::Hash %ATTR_SPEC => %attr_spec_hash;
}

sub __get_opt_specs {
    my ( $self, $flags ) = @_;
    my @opt_spec;
    foreach ( values %ATTR_SPEC ) {
	next unless $_->{flags} & FLAG_IS_OPT;
	$flags
	    and not $_->{flags} & $flags
	    and next;
	push @opt_spec, join( '|', $_->{name}, @{ $_->{alias} || []
	    } ) . $_->{type}, $self->__get_validator( $_, 1 );
    }
    return @opt_spec;
}

# NOTE the File::Share dodge is from David Farrell's
# https://www.perl.com/article/66/2014/2/7/3-ways-to-include-data-with-your-Perl-distribution/
sub __get_attr_default_file_name {
    return File::ShareDir::dist_file( 'App-Sam', 'default_samrc' );
}

{
    my %rc_cache;

    # TODO __clear_rc_cache()

    # Get attributes from resource file.
    sub __get_attr_from_rc {
	my ( $self, $file, $required ) = @_;
	my $arg = $file;
	local $self->{_dump} = {};
	if ( REF_ARRAY eq ref $file ) {
	    if ( $self->{dump} ) {
		$self->_accum_opt_for_dump( $_ ) for @{ $file };
		$self->_display_opt_for_dump( 'ARGV' );
	    }
	} else {
	    if ( not ref( $file ) and $arg = $rc_cache{$file} ) {
		ref $arg
		    or $self->__croak( $arg );
		$arg = [ @{ $arg } ];	# Clone, since GetOpt modifies
	    } elsif ( open my $fh,	## no critic (RequireBriefOpen)
		'<' . $self->__get_encoding( $file, 'utf-8' ),
		$file
	    ) {
		local $_ = undef;	# while (<>) does not localize $_
		$arg = [];
		while ( <$fh> ) {
		    m/ \A \s* (?: \z | \# ) /smx
			and next;
		    chomp;
		    s/ \A \s+ //smx;
		    push @{ $arg }, $_;
		    $self->{dump}
			and $self->_accum_opt_for_dump( $_ );
		}
		close $fh;
		$rc_cache{$file} = [ @{ $arg } ];
		if ( $self->{dump} ) {
		    state $dflt = $self->__get_attr_default_file_name();
		    my $display = $file eq $dflt ? 'Default' : $file;
		    $self->_display_opt_for_dump( $display );
		}
	    } elsif ( $! == ENOENT && ! $required ) {
		$rc_cache{$file} = [];
		return;
	    } else {
		$self->__croak( $rc_cache{$file} =
		    "Failed to open resource file $file: $!" );
	    }
	}
	{
	    my @warning;
	    local $SIG{__WARN__} = sub { push @warning, @_ };
	    $self->__get_option_parser()->getoptionsfromarray(
		$arg, $self, $self->__get_opt_specs( ~ FLAG_PROCESS_EARLY ) )
		or do {
		    chomp @warning;
		    my $msg = join '; ', @warning;
		    ref $file
			or $msg .= " in $file";
		    REF_ARRAY eq ref $file
			or $rc_cache{$file} = $msg;
		    $self->__croak( $msg );
	    };
	}
	@{ $arg }
	    and not REF_ARRAY eq ref $file
	    and $self->__croak( $rc_cache{$file} =
	    "Non-option content in $file" );
	return;
    }
}

# Given an argument spec, return code to validate it.
sub __get_validator {
    my ( $self, $attr_spec, $die ) = @_;
    ref $attr_spec
	or $attr_spec = $ATTR_SPEC{$attr_spec}
	or $self->__confess( "Undefined attribute '$_[1]'" );
    if ( my $method = $attr_spec->{validate} ) {
	if ( my $facility = $attr_spec->{flags} & FLAG_FACILITY ) {
	    # NOTE we count on the attribute spec setup code to have
	    # provided a validator if the facility was specified
	    $die
		and return sub {
		$self->$method( $attr_spec, @_ )
		    or die "Invalid value --$_[0]=$_[1]\n";
		$self->{flags} |= $facility;
		return 1;
	    };
	    return sub {
		return $self->$method( $attr_spec, @_ ) &&
		( $self->{flags} |= $facility );
	    };
	} else {
	    $die
		and return sub {
		$self->$method( $attr_spec, @_ )
		    or die "Invalid value --$_[0]=$_[1]\n";
		return 1;
	    };
	    return sub {
		return $self->$method( $attr_spec, @_ );
	    };
	}
    }
    return;
}

# Validate an attribute given its name and value
sub __validate_attr {
    my ( $self, $attr_name, $attr_val ) = @_;
    my $attr_spec = $ATTR_SPEC{$attr_name}
	or $self->__confess( "Unknown attribute '$attr_name'" );
    if ( my $code = $self->__get_validator( $attr_spec ) ) {
	$code->( $attr_name, $attr_val )
	    or return 0;
    } elsif ( $attr_spec->{type} =~ m/ \@ \z /smx ) {
	push @{ $self->{$attr_name} },
	    REF_ARRAY eq ref $attr_val ? @{ $attr_val } : $attr_val;
    } else {
	$self->{$attr_name} = $attr_val;
    }
    return 1;
}

sub __get_option_parser {
    my ( undef, $pass_thru ) = @_;
    $pass_thru = $pass_thru ? 1 : 0;
    state $opt_psr = [];
    return $opt_psr->[$pass_thru] ||= do {
	my $p = Getopt::Long::Parser->new();
	$p->configure( qw{
	    bundling no_ignore_case } );
	$pass_thru
	    and $p->configure( qw{ pass_through } );
	$p;
    };
}

sub __get_encoding {
    my ( $self, $file, $encoding ) = @_;
    ref $file
	and return '';
    $encoding //= $self->{encoding};
    if ( defined $file ) {
	# TODO file-specific
    }
    return ":encoding($encoding)";
}

sub __get_rc_file_names {
    my ( $self ) = @_;
    my @rslt;
    unless ( $self->{ignore_sam_defaults} ) {
	push @rslt, $self->__get_attr_default_file_name();
    }
    if ( $self->{env} ) {
	if ( IS_WINDOWS ) {
	    $self->__croak( 'TODO - Windows resource files' );
	} else {
	    push @rslt, '/etc/samrc', $ENV{SAMRC} // "$ENV{HOME}/.samrc";
	    # TODO Ack semantics for project file
	    push @rslt, '.samrc';
	}
    }
    return @rslt;
}

sub __incompat_arg {
    my ( $self, @opt ) = @_;
    my @have;
    foreach ( @opt ) {
	exists $self->{$_}
	    or next;
	$ATTR_SPEC{$_}{type} eq '!'
	    and not $self->{$_}
	    and next;
	push @have, $_;
    }
    if ( @have > 1 ) {
	my $name = 'Arguments';
	if ( $self->{die} ) {
	    @have = map { length > 1 ? "--$_" : "-$_" } @have;
	    tr/_/-/ for @have;
	    $name = 'Options';
	}
	@have = map { "'$_'" } @have;
	if ( @have > 2 ) {
	    $self->__croak(
		sprintf '%s %s can not be used together', $name, @have );
	} else {
	    $self->__croak(
		sprintf '%s %s and %s can not be used together', $name,
		@have );
	}
    }
    return;
}

sub __make_munger {
    my ( $self ) = @_;
    my $modifier = '';
    $self->{ignore_case}
	and $modifier .= 'i';

    defined( my $match = $self->{match} )
	or do {
	$self->{_munger} = sub {
	    $_[0]->__croak( 'No match string specified' );
	};
	return;
    };

    $self->{literal}
	and $match = quotemeta $match;
    if ( $self->{word_regexp} ) {
	$match =~ s/ \A (?= \w ) /\\b/smx;
	$match =~ s/ (?<= \w ) \z /\\b/smx;
    }
    my $str;
    $str = "m($match)$modifier";
    my $code = eval "sub { $str }"	## no critic (ProhibitStringyEval)
	or $self->__croak( "Invalid match '$match': $@" );
    if ( $self->{flags} & FLAG_FAC_NO_MATCH_PROC ) {
	# Do nothing -- we just want to know if we have a match.
    } elsif ( defined $self->{output} ) {
	$self->{_tplt_leader} = $self->{_tplt_trailer} = '';
	$self->{output} =~ s/ (?<! \n ) \z /\n/smx;
	$str = '$_[0]->_process_callback() while ' . $str . 'g';
	$code = eval "sub { $str }"	## no critic (ProhibitStringyEval)
	    or $self->__confess( "Invalid match '$str': $@" );
    } else {
	my @leader;
	$self->{with_filename}
	    and not $self->{heading}
	    and push @leader, '$f';
	$self->{line}
	    and push @leader, '$.';
	$self->{column}
	    and push @leader, '$c';
	( $self->{syntax} || $self->{show_syntax} )
	    and push @leader, '$s';
	{
	    local $" = ':';
	    $self->{_tplt_leader} = @leader ? "@leader:" : '';
	}
	$self->{_tplt_trailer} = '$p';
	$self->{output} = '$p$&';
	$str = '$_[0]->_process_callback() while ' . $str . 'g';
	$code = eval "sub { $str }"	## no critic (ProhibitStringyEval)
	    or $self->__confess( "Invalid match '$str': $@" );
    }
    $self->{_munger} = $code;
    return;
}

sub __me {
    state $me = ( File::Spec->splitpath( $0 ) )[2];
    return $me;
}

sub __ignore {
    ( my ( $self, $kind, $path ), local $_ ) = @_;
    my $prop_spec = $self->{"ignore_$kind"}
	or $self->__confess( "Invalid ignore kind '$kind'" );
    $_ //= ( File::Spec->splitpath( $path ) )[2];
    $prop_spec->{is}{$_}
	and return 1;
    m/ [.] ( [^.]* ) \z /smx
	and $prop_spec->{ext}{$1}
	and return 1;
    $prop_spec->{match}
	and $prop_spec->{match}->()
	and return 1;
    if ( $kind eq 'file' && $self->{type} ) {

	# Encoding: undef = unspecified, 0 = accept, 1 = skip
	my $want_type;
	foreach my $type ( $self->__file_type( $path, $_ ) ) {
	    my $skip = $self->{type}{$type}
		and return 1;
	    $want_type //= $skip;
	}
	return ! defined $want_type;
    }
    return 0;
}

sub __print {	## no critic (RequireArgUnpacking)
    my ( $self ) = @_;
    my $line = join '', @_[ 1 .. $#_ ];
    if ( $self->{print0} ) {
	$line =~ s/ \n \z /\0/smx;
	$self->{_process}{colored}
	    and $line .= CLR_EOL;
    }
    # We do this even with --print0, because the output may contain
    # embedded new lines -- in fact, that is what --print0 is all about.
    # NOTE that ack uses "\e[0m\e[K" here. But "\e[K" suffices for me.
    $self->{_process}{colored}
	and $line =~ s/ (?= \n ) / CLR_EOL /smxge;
    print $line;
    return;
}

sub process {
    my ( $self, @files ) = @_;

    @files
	or @files = (
	$self->files_from(),
	@{ $self->{argv} || [] },
    );

    my $files_matched;

    foreach my $file ( @files ) {

	my $rslt = ( ref( $file ) || ! -d $file ) ?
	    $self->_process_file( $file ) :
	    $self->_process_dir( $file );
	$files_matched += $rslt;
	$rslt eq STOP
	    and last;
    }

    if ( caller eq __PACKAGE__ ) {
	# We need to preserve the STOP information if we're being called
	# recursively, but to ditch it otherwise.
	return $self->_process_result( $files_matched );
    } else {
	$self->{count}
	    and not $self->{with_filename}
	    and $self->__say( $self->{_total_count} // 0 );
	return $files_matched;
    }
}

# NOTE: Call this ONLY from inside process().
sub _process_dir {
    my ( $self, $file ) = @_;
    my $iterator = $self->__get_file_iterator( $file );
    my $files_matched = 0;
    while ( defined( my $fn = $iterator->() ) ) {
	my $rslt = $self->process( $fn );
	$files_matched += $rslt;
	$rslt eq STOP
	    and return $self->_process_result( $files_matched );
    }
    return $files_matched;
}

# NOTE: Call this ONLY from inside process().
sub _process_file {
    my ( $self, $file ) = @_;

    local $self->{_process} = {
	filename	=> $self->__color( filename => $file ),
    };

    $self->{_range}
	and $self->{_process}{in_range} = $self->{range_start} ? 0 : 1;

    -B $file
	and return 0;

    $self->{_process}{type} = [ $self->__file_type( $file ) ]
	if $self->{flags} & FLAG_FAC_TYPE;

    $self->{known_types}
	and not @{ $self->{_process}{type} }
	and return 0;

    $self->{flush}
	and local $| = 1;

    my @show_types;
    $self->{show_types}
	and push @show_types, join ',', @{ $self->{_process}{type} };

    if ( $self->{flags} & FLAG_FAC_SYNTAX ) {
	if ( my ( $class ) = $self->__file_syntax( $file ) ) {
	    $self->{_process}{syntax_obj} =
		$self->{_syntax_obj}{$class} ||=
		"App::Sam::Syntax::$class"->new( die => $self->{die} );
	}

	# If --syntax was specified and we did not find a syntax
	# object OR it does not produce the requested syntax, ignore
	# the file.
	if ( $self->{syntax} ) {
	    $self->{_process}{syntax_obj}
		or return 0;
	    List::Util::first( sub { $self->{syntax}{$_} },
		$self->{_process}{syntax_obj}->__classifications() )
		or return 0;
	}
    }

    if ( $self->{f} || $self->{g} ) {
	if ( $self->{g} ) {
	    local $_ = $file;
	    $self->{_munger}->( $self ) xor $self->{invert_match}
		or return 0;
	}
	$self->__say( join ' => ', $file, @show_types );
	return $self->_process_result( 1 );
    }

    my $encoding = $self->__get_encoding( $file );
    open my $fh, "<$encoding", $file	## no critic (RequireBriefOpen)
	or do {
	$self->{s}
	    or $self->__carp( "Failed to open $file for input: $!" );
	return 0;
    };

    my $mod_fh;
    if ( defined $self->{replace} ) {
	if ( REF_SCALAR eq ref $self->{dry_run} ) {
	    open $mod_fh, '>:raw', $self->{dry_run}	## no critic (RequireBriefOpen)
		or $self->__confess( "Failed to open scalar ref: $!" );
	} elsif ( $self->{dry_run} || ref $file ) {
	    # Do nothing
	} else {
	    $mod_fh = File::Temp->new(
		DIR	=> File::Basename::dirname( $file ),
	    );
	}
    }

    my $lines_matched = 0;
    local $_ = undef;	# while (<>) does not localize $_
    my @before_context;
    while ( <$fh> ) {

	delete $self->{_process}{colored};

	$self->{_process}{syntax_obj}
	    and $self->{_process}{syntax} =
		$self->{_process}{syntax_obj}->__classify();

	if ( $self->{_process}{matched} = $self->_process_match() ) {
	    if ( $self->{files_with_matches} && ! $self->{count} ) {
		$self->__say( join ' => ', $self->{_process}{filename}, @show_types );
		return $self->_process_result( 1 );
	    }
	    $lines_matched++;
	}

	$mod_fh
	    and print { $mod_fh } $self->{_tplt}{replace};

	if ( $self->_process_display_p() ) {

	    if ( ! $self->{_process}{header} ) {
		$self->{_process}{header} = 1;
		$self->{_want_break}
		    and $self->__say( '' );
		$self->{_want_break} = $self->{break};
		$self->{heading}
		    and $self->{with_filename}
		    and $self->__say(
			join ' => ',
			$self->{_process}{filename},
			@show_types,
		    );
	    }

	    $self->__print( $_ ) for @before_context;
	    @before_context = ();
	    $self->__print( $self->{_tplt}{line} );
	    if ( $self->{_tplt}{ul_spec} ) {
		my $line = '';
		foreach ( @{ $self->{_tplt}{ul_spec} } ) {
		    $line .= ' ' x $_->[0];
		    $line .= '^' x $_->[1];
		}
		$self->__say( $line );
	    }

	} elsif ( $self->{before_context} ) {

	    push @before_context, $self->{_tplt}{line};
	    @before_context > $self->{before_context}
		and splice @before_context, 0, @before_context -
		    $self->{before_context};
	}

	$self->{max_count}
	    and $lines_matched >= $self->{max_count}
	    and last;

	$self->{1}
	    and $lines_matched
	    and last;
    }
    close $fh;

    if ( $self->{files_without_matches} && ! $lines_matched ) {
	$self->__say( join ' => ', $file, @show_types );
	return $self->_process_result( 1 );
    }

    if ( $self->{count} ) {
	if ( $self->{with_filename} ) {
	    ( $lines_matched || ! $self->{files_with_matches} )
		and $self->__say( join ' => ', sprintf(
		    '%s:%d', $self->{_process}{filename}, $lines_matched ),
		@show_types );
	} else {
	    $self->{_total_count} += $lines_matched;
	}
    }

    if ( defined( $self->{replace} ) && ! $self->{dry_run} &&
	$lines_matched && ! ref $file
    ) {
	if ( defined $self->{backup} ) {
	    my $backup = "$file$self->{backup}";
	    rename $file, $backup
		or $self->__croak(
		"Failed to rename $file to $backup: $!" );
	}

	$mod_fh->unlink_on_destroy( 0 );
	rename "$mod_fh", $file
	    or $self->__croak(
	    "Failed to rename $mod_fh to $file: $!" );
    }

    return $self->_process_result( $lines_matched ? 1 : 0 );
}

# Return a true value if the current line is to be displayed.
# NOTE: Call this ONLY from inside process(). This is broken out because
# I expect it to get complicated if I implement match inversion,
# context, etc.
sub _process_display_p {
    my ( $self ) = @_;

    $self->{count}
	and return 0;

    $self->{files_without_matches}
	and return 0;

    if ( $self->{_process}{matched} ) {
	$self->{after_context}
	    and $self->{_process}{after_context} =
		$self->{after_context} + 1;
	return 1;
    }

    $self->{_process}{after_context}
	and --$self->{_process}{after_context}
	and return 1;

    $self->{passthru}
	and return 1;

    return 0;
}

# Perform a match if appropriate. By default, returns true if a match
# was performed and succeeded, and false otherwise. But --invert-match
# inverts this.
# NOTE: Call this ONLY from inside process(). This is broken out because
# I expect it to get complicated if I implement ranges, syntax, etc.
# NOTE ALSO: the current line is in $_.
sub _process_match {
    my ( $self ) = @_;

    $self->{flags} & FLAG_FAC_NO_MATCH_PROC
	and return $self->{_munger}->( $self );

    if ( $self->{_range} ) {
	my $in_range = $self->{_process}{in_range};
	$in_range ||= $self->{_process}{in_range}
	    while $self->{_range}->( $self );
	$self->{_process}{in_range}
	    or $in_range
	    or return $self->{invert_match};
    }

    $self->{not}{match}
	and $self->{not}{match}->()
	and return $self->{invert_match};
    if ( $self->{syntax} && defined $self->{_process}{syntax} ) {
	$self->{syntax}{$self->{_process}{syntax}}
	    or return $self->{invert_match};
    }
    pos( $_ ) = 0;
    $self->{_tplt} = {
	pos	=> 0,
    };
    $self->{_munger}->( $self );
    $self->_process_callback();		# Flush buffer.
    return( $self->{_tplt}{num_matches} xor $self->{invert_match} );
}

# NOTE that this is to be called only to process a match, including
# exactly once to process a failed match. In practice this means only in
# the subroutine built by __make_munger(), or immediately after this is
# called in _process_match().
sub _process_callback {
    my ( $self ) = @_;
    $self->{_tplt}{capt} = [];
    unless ( defined $self->{_tplt}{line} ) {
	$self->{_tplt}{line} = $self->__process_template(
	    $self->{_tplt_leader} );
	$self->{underline}
	    and $self->{_tplt}{ul_pos} = -
		$self->_process_underline_leader_len();
    }

    if ( defined pos ) {	# We're being called from a successful match

	if ( defined $self->{replace} ) {
	    local $self->{color} = 0;
	    $self->{_tplt}{capt}[0] = $self->__process_template(
		$self->{replace} );
	    $self->{_tplt}{replace} .= $self->__process_template( '$p$&' );
	}

	$self->{_tplt}{line} .= $self->__process_template(
	    $self->{output} );

	if ( $self->{underline} ) {
	    push @{ $self->{_tplt}{ul_spec} }, [
		$-[0] - $self->{_tplt}{ul_pos},
		$+[0] - $-[0],
	    ];
	    $self->{_tplt}{ul_pos} = $+[0];
	}

	$self->{_tplt}{num_matches}++;

	$self->{_tplt}{pos} = pos $_;

    } else {	# We're being called to flush tne buffer

	defined $self->{replace}
	    and $self->{_tplt}{replace} .= $self->__process_template( '$p' );
	$self->{_tplt}{line} .= $self->__process_template(
	    $self->{_tplt_trailer} );
    }

    return;
}

sub _process_result {
    my ( $self, $val ) = @_;
    $self->{1}
	and $val
	and return Scalar::Util::dualvar( $val, STOP );
    return $val;
}

# Process a --output template, returning the result.
# NOTE: Call this ONLY from inside process(). This is broken out because
# I expect it to get complicated if I implement ranges, syntax, etc.
# NOTE ALSO: the current line is in $_.
# FIXME? This code expects to be called in a while() statement iterating
# over an m/.../g, and then once more to process the rest of the buffer.
# If pos() is undefined it means the match failed and therefore we're
# flushing the buffer. This can be scuppered by m/.../gc. The
# alternative is an argument to indicate we're flushing.
sub __process_template {
    my ( $self, $tplt ) = @_;
    defined $tplt
	or $self->__confess( 'Undefined template' );
    $self->{_tplt}{m} = [ defined pos ? @- : ( length ) ];
    $self->{_tplt}{p} = [ defined pos ? @+ : ( length ) ];
    {	# Hope: match vars localized to block
	$tplt =~ s( ( [\\\$] ) ( . ) )
	    ( $self->_process_template_item( $1, $2 ) )smxge;
    }
    return $tplt;
}

# Process an individual --output template item.
# NOTE: Call this only from the substitution replacement in
# __process_template().
sub _process_template_item {
    my ( $self, $kind, $item ) = @_;
    state $capt = sub {
	$_[0]->{_tplt}{capt}[$_[1]] // substr $_,
	$_[0]->{_tplt}{m}[$_[1]],
	$_[0]->{_tplt}{p}[$_[1]] - $_[0]->{_tplt}{m}[$_[1]]
    };
    state $hdlr = {
	'\\'	=> {
	    0	=> sub { "\0" },
	    a	=> sub { "\a" },
	    b	=> sub { "\b" },
	    e	=> sub { "\e" },
	    f	=> sub { "\f" },
	    n	=> sub { "\n" },
	    r	=> sub { "\r" },
	    t	=> sub { "\t" },
	},
	'$'	=> {
	    1	=> sub { $capt->( $_[0], 1 ) },
	    2	=> sub { $capt->( $_[0], 2 ) },
	    3	=> sub { $capt->( $_[0], 3 ) },
	    4	=> sub { $capt->( $_[0], 4 ) },
	    5	=> sub { $capt->( $_[0], 5 ) },
	    6	=> sub { $capt->( $_[0], 6 ) },
	    7	=> sub { $capt->( $_[0], 7 ) },
	    8	=> sub { $capt->( $_[0], 8 ) },
	    9	=> sub { $capt->( $_[0], 9 ) },
	    _	=> sub { "$_" },
	    '.'	=> sub { $_[0]->__color( lineno => $. ) },
	    '`'	=> sub { substr $_, 0, $_[0]->{_tplt}{m}[0] },
	    '&'	=> sub { $_[0]->__color( match => $capt->( $_[0], 0 ) ) },
	    "'"	=> sub { substr $_, $_[0]->{_tplt}{p}[0] },
	    c	=> sub { $_[0]->__color( colno => $_[0]{_tplt}{m}[0] + 1 ) },
	    f	=> sub { $_[0]->{_process}{filename} },
	    p	=> sub {
		return substr $_, $_[0]{_tplt}{pos},
		    $_[0]{_tplt}{m}[0] - $_[0]{_tplt}{pos};
	    },
	    s	=> sub { substr $_[0]{_process}{syntax} // '', 0, 4 },
	},
    };
    my $code = $hdlr->{$kind}{$item}
	or return $item;
    return $code->( $self );
}

# Determine the length of the leader of the current line, in characters.
# In practice, this should probably only be called from
# _process_callback().
sub _process_underline_leader_len {
    my ( $self ) = @_;
    $self->{color}
	or return length $self->{_tplt}{line};
    local $self->{color} = 0;
    return length $self->__process_template( $self->{_tplt_leader} );
}

sub __get_file_iterator {
    my ( $self, $file ) = @_;
    my $descend_filter = $self->{recurse} ? sub {
	! $self->__ignore( directory => $File::Next::dir, $_ );
    } : sub { 0 };
    return File::Next::files( {
	    file_filter	=> sub {
		! $self->__ignore( file => $File::Next::name, $_ ) },
	    follow_symlinks	=> $self->{follow},
	    descend_filter	=> $descend_filter,
	    sort_files	=> $self->{sort_files},
	}, $file );
}

sub __say {
    push @_, "\n";
    goto &__print;
}

sub __set_attr {
    my ( $self, $attr_name, @attr_val ) = @_;
    defined $attr_name
	or $self->__confess( 'Undefined attribute name' );
    my $attr_spec = $ATTR_SPEC{$attr_name}
	or $self->__confess( "Unknown attribute name '$attr_name'" );
    if ( my $method = $attr_spec->{validate} ) {
	return $self->$method( $attr_spec, $attr_name, @attr_val );
    } elsif ( @attr_val ) {
	# FIXME handle array attributes.
	$self->{$attr_name} = $attr_val[0];
    } else {
	delete $self->{$attr_name};
    }
    return 1;
}

sub __validate_accept_scalar {
    my ( $self, undef, $attr_name, $attr_val ) = @_;
    $self->{$attr_name} = $attr_val;
    return 1;
}

sub __validate_accept_array {
    my ( $self, undef, $attr_name, $attr_val ) = @_;
    push @{ $self->{$attr_name} }, REF_ARRAY eq ref $attr_val ?
	@{ $attr_val } : $attr_val;
    return 1;
}

sub __validate_fixed_value {
    my ( $self, $attr_spec ) = @_;	# $attr_name, $attr_val unused
    REF_ARRAY eq ref $attr_spec->{arg}
	or $self->__confess( "$attr_spec->{name} arg must be an array ref" );
    return $self->__set_attr( @{ $attr_spec->{arg} } );
}

sub __validate_color {
    my ( $self, undef, $attr_name, $attr_val ) = @_;	# $attr_spec unused
    Term::ANSIColor::colorvalid( $attr_val )
	or return 0;
    $self->{$attr_name} = $attr_val;
    return 1;
}

sub __validate_file_property_add {
    my ( $self, undef, $attr_name, $attr_val ) = @_;	# $attr_spec unused
    my ( $prop_name, $action ) = $attr_name =~ m/ \A ( .* ) _ ( .* ) \z /smx
	or $self->__confess( "Invalid attribute name '$attr_name'" );

    my $validate_prop_val = {
	syntax	=> sub {
	    my ( undef, $prop_val ) = @_;	# Invocant unused
	    local $@ = undef;
	    return eval {
		Module::Load::load( "App::Sam::Syntax::$prop_val" );
		1;
	    } || 0;
	},
    }->{$prop_name} || sub { 1 };

    foreach ( ref $attr_val ? @{ $attr_val } : $attr_val ) {
	my ( $prop_val, $kind, $data ) = split /:/, $_, 3;

	$validate_prop_val->( $self, $prop_val )
	    or return 0;

	defined $data
	    or ( $kind, $data ) = ( is => $kind );

	state $validate_kind = {
	    ext	=> sub {
		my ( $self, $prop_name, $prop_val, $data ) = @_;
		my @item = split /,/, $data;
		push @{ $self->{"${prop_name}_add"}{ext}{$_} }, $prop_val
		    for @item;
		push @{ $self->{"_${prop_name}_def"}{$prop_val}{ext} },
		    map { ".$_" } @item;
		return 1;
	    },
	    is	=> sub {
		my ( $self, $prop_name, $prop_val, $data ) = @_;
		push @{ $self->{"${prop_name}_add"}{is}{$data} }, $prop_val;
		push @{ $self->{"_${prop_name}_def"}{$prop_val}{is} }, $data;
		return 1;
	    },
	    match	=> sub {
		my ( $self, $prop_name, $prop_val, $data ) = @_;
		local $@ = undef;
		my $code = eval "sub { $data }"	## no critic (ProhibitStringyEval)
		    or return 0;
		push @{ $self->{"${prop_name}_add"}{match} },
		    [ $prop_val, $code, "$prop_val:$data" ];
		push @{ $self->{"_${prop_name}_def"}{$prop_val}{match} }, $data;
		return 1;
	    },
	    firstlinematch	=> sub {
		my ( $self, $prop_name, $prop_val, $data ) = @_;
		local $@ = undef;
		my $code = eval "sub { $data }"	## no critic (ProhibitStringyEval)
		    or return 0;
		push @{ $self->{"${prop_name}_add"}{firstlinematch} },
		    [ $prop_val, $code, "$prop_val:$data" ];
		push @{ $self->{"_${prop_name}_def"}{$prop_val}
		    {firstlinematch} }, $data;
		return 1;
	    },
	    type	=> sub {
		# my ( $self, $syntax, $data ) = @_;
		my ( $self, $prop_name, $prop_val, $data ) = @_;
		$prop_name eq 'type'
		    and return 0;
		my @item = split /,/, $data;
		foreach ( @item ) {
		    $self->{_type_def}{$_}
			or return 0;
		    $self->{"${prop_name}_add"}{type}{$_} = $prop_val;
		    push @{ $self->{"_${prop_name}_def"}{$prop_val}{type} }, $_;
		}
		return 1;
	    },
	};
	my $code = $validate_kind->{$kind}
	    or return 0;
	state $handler = {
	    add	=> sub { 1 },
	    del	=> sub {
		my ( $self, $prop_name, $prop_val ) = @_;
		my $method = "__file_${prop_name}_del";
		$self->$method( $prop_val, 1 );
		return 0;
	    },
	    set	=> sub {
		my ( $self, $prop_name, $prop_val ) = @_;
		my $method = "__file_${prop_name}_del";
		$self->$method( $prop_val );
		return 1;
	    },
	};
	my $setup = $handler->{$action}
	    or $self->__confess( "Unknown action handler '$action'" );

	$setup->( $self, $prop_name, $prop_val )
	    or next;

	$code->( $self, $prop_name, $prop_val, $data )
	    or return 0;
    }
    return 1;
}

sub __validate_files_from {
    my ( $self, undef, $attr_name, $attr_val ) = @_;	# $attr_spec unused
    not ref $attr_val
	or REF_ARRAY eq ref $attr_val
	or return 0;
    foreach ( ref $attr_val ? @{ $attr_val } : $attr_val ) {
	$_ eq '-'
	    or -r
	    or return 0;
	push @{ $self->{$attr_name} }, $_;
    }
    return 1;
}

sub __validate_gang_set {
    my ( $self, $attr_spec, undef, $attr_val ) = @_;	# $attr name unused
    REF_ARRAY eq ref $attr_spec->{arg}
	or $self->__confess( 'arg must be an array ref' );
    foreach my $attr_name ( @{ $attr_spec->{arg} } ) {
	$self->__set_attr( $attr_name, $attr_val )
	    or return 0;
    }
    return 1;
}

sub __validate_inverted_value {
    my ( $self, $attr_spec, undef, $attr_val ) = @_;	# $attr name unused
    return $self->__set_attr( $attr_spec->{arg}, ! $attr_val );
}

sub __validate_ignore {
    my ( $self, undef, $attr_name, $attr_val ) = @_;	# $attr_spec unused
    foreach ( ref $attr_val ? @{ $attr_val } : $attr_val ) {
	my ( $kind, $data ) = split /:/, $_, 2;
	defined $data
	    or ( $kind, $data ) = ( is => $kind );
	state $validate_kind = {
	    ext	=> sub {
		my ( $self, $attr_name, $data ) = @_;
		my @item = split /,/, $data;
		@{ $self->{$attr_name}{ext} }{ @item } = ( ( 1 ) x @item );
		return 1;
	    },
	    is	=> sub {
		my ( $self, $attr_name, $data ) = @_;
		$self->{$attr_name}{is}{$data} = 1;
		return 1;
	    },
	    match	=> sub {
		my ( $self, $attr_name, $data ) = @_;
		local $@ = undef;
		eval "qr $data"	## no critic (ProhibitStringyEval)
		    or return 0;
		push @{ $self->{$attr_name}{match} }, $data;
		return 1;
	    },
	};
	my $code = $validate_kind->{$kind}
	    or return 0;
	$code->( $self, $attr_name, $data )
	    or return 0;
    }
    return 1;
}

sub __validate_not {
    my ( $self, undef, $attr_name, $attr_val ) = @_;	# $attr_spec, unused.
    foreach ( ref $attr_val ? @{ $attr_val } : $attr_val ) {
	local $@ = undef;
	eval "qr($_)"		## no critic (ProhibitStringyEval)
	    or return 0;
	# NOTE functionally the expressions could be stored directly in
	# {not}, but the {match} means I can process this with the same
	# code that processes ignore_directory and ignore_file.
	push @{ $self->{$attr_name}{match} }, "($_)";
    }
    return 1;
}

# This creates a group of Boolean options at most one of which can be
# set. The {arg} contains the names of options to be reset if the main
# one is set.
sub __validate_radio {
    my ( $self, $attr_spec, $attr_name, $attr_val ) = @_;
    if ( $attr_val ) {
	delete $self->{$_} for @{ $attr_spec->{arg} };
    }
    $self->{$attr_name} = $attr_val;
    return 1;
}

sub __validate_syntax {
    my ( $self, undef, undef, $attr_val ) = @_;	# $attr_spec, $attr_name unused
    foreach ( ref $attr_val ? @{ $attr_val } : $attr_val ) {
	state $valid = Text::Abbrev::abbrev( __syntax_types() );
	my $expansion = $valid->{$_}
	    or return 0;
	$self->{syntax}{$expansion} = 1;
    }
    return 1;
}

sub __validate_type {
    my ( $self, undef, undef, $attr_val ) = @_;	# $attr_spec, $attr_name unused
    foreach ( ref $attr_val ? @{ $attr_val } : $attr_val ) {
	my $neg;
	if ( $self->{_type_def}{$_} ) { 
	    $self->{type}{$_} = 0;
	} elsif ( ( $neg = $_ ) =~ s/ \A no-? //smxi && (
		$self->{_type_def}{$neg} ) ) {
	    $self->{type}{$neg} = 1;
	} else {
	    return 0;
	}
    }
    return 1;
}

1;

__END__

=head1 NAME

App::Sam - Search and (possibly) modify files

=head1 SYNOPSIS

 use App::Sam;
 my $sam = App::Sam->new(
   backup  => '.bak',
   match   => '\bfoo\b',
   replace => 'bar',
 );
 $sam->process( 'foo.txt' );

=head1 DESCRIPTION

This Perl object finds strings in files, possibly modifying them. It was
inspired by L<ack|ack>.

=head1 METHODS

This class supports the following public methods:

=head2 new

 my $sam = App::Sam->new();

This static method instantiates an application object. It takes the
following named arguments:

=over

=item C<1>

See L<-1|sam/-1> in the L<sam|sam> documentation.

=item C<after_context>

See L<--after-context|sam/--after-context> in the L<sam|sam>
documentation.

=item C<argv>

This argument specifies a reference to an array which is to be processed
for command-line options by L<Getopt::Long|Getopt::Long>. It is
processed after all other arguments. The command-line options correspond
to other arguments, and either override (usually) or otherwise
modify them (things like C<type_add>, C<type_del>, and C<type_set>).
Unknown options result in an exception.

The argument must refer to an array that can be modified. After this
argument is processed, non-option arguments remain in the array.

=item C<backup>

See L<--backup|sam/--backup> in the L<sam|sam> documentation. A value of
C<undef> or C<''> specifies no backup.

=item C<before_context>

See L<--before-context|sam/--before-context> in the L<sam|sam>
documentation.

=item C<break>

See L<--break|sam/--break> in the L<sam|sam> documentation. The default
is false.

=item C<color>

See L<--color|sam/--color> in the L<sam|sam> documentation. The default
is false.

=item C<color_colno>

See L<--color-colno|sam/--color-colno> in the L<sam|sam> documentation.

=item C<color_filename>

See L<--color-filename|sam/--color-filename> in the L<sam|sam> documentation.

=item C<color_lineno>

See L<--color-lineno|sam/--color-lineno> in the L<sam|sam> documentation.

=item C<color_match>

See L<--color-match|sam/--color-match> in the L<sam|sam> documentation.

=item C<column>

See L<--column|sam/--column> in the L<sam|sam> documentation.

=item C<count>

See L<--count|sam/--count> in the L<sam|sam> documentation.

=item C<create_samrc>

See L<--create-samrc|sam/--create-samrc> in the L<sam|sam>
documentation.

=item C<die>

This Boolean argument specifies how warnings and errors are delivered. A
true value specifies C<warn()> or C<die()> respectively. A false value
specifies C<Carp::carp()> or C<Carp::croak()> respectively. The default
is false. A true value will be ignored if C<$Carp::verbose> is true.

=item C<dry_run>

See L<--dry-run|sam/--dry-run> in the L<sam|sam> documentation.

=item C<dump>

See L<--dump|sam/--dump> in the L<sam|sam> documentation. B<Note> that
if this argument is true, L<match|/match> need not be specified. This
does not necessarily mean you get a working object, though. It just
means you get an exception when you call L<process()|/process>.

=item C<encoding>

See L<--encoding|sam/--encoding> in the L<sam|sam> documentation.

=item C<env>

See L<--env|sam/--env> in the L<sam|sam> documentation.

=item C<f>

See L<-f|sam/-f> in the L<sam|sam> documentation.

=item C<file>

See L<--file|sam/--file> in the L<sam|sam> documentation.

=item C<files_from>

See L<--files-from|sam/--files-from> in the L<sam|sam> documentation.

B<Note> that the files are not actually read until
L<files_from()|/files_from> is called. The only validation before that
is that the C<-r> operator must report them as readable, though this is
not definitive in the presence of Access Control Lists.

=item C<files_with_matches>

See L<--files-with-matches|sam/--files-with-matches> in the L<sam|sam>
documentation.

=item C<files_without_matches>

See L<--files-without-matches|sam/--files-without-matches> in the
L<sam|sam> documentation.

=item C<--filter>

See L<--filter|sam/--filter> in the L<sam|sam> documentation. Note that,
unlike L<sam|sam>, the default is false.

=item C<filter_files_from>

See L<--filter-files-from|sam/--filter-files-from> in the L<sam|sam>
documentation.

=item C<flush>

See L<--flush|sam/--flush> in the L<sam|sam> documentation.

=item C<follow>

See L<--follow|sam/--follow> in the L<sam|sam> documentation.

=item C<g>

See L<-g|sam/-g> in the L<sam|sam> documentation. B<Note> that as an
argument to C<new()>, C<g> is a Boolean flag. The match string is
specified in argument L<C<match>|/match>

=item C<heading>

See L<--heading|sam/--heading> in the L<sam|sam> documentation.

=item C<help_colors>

See L<--help-colors|sam/--help-colors> in the L<sam|sam> documentation.

=item C<help_syntax>

See L<--help-syntax|sam/--help-syntax> in the L<sam|sam> documentation.

=item C<help_types>

See L<--help-types|sam/--help-types> in the L<sam|sam> documentation.

=item C<ignore_case>

See L<--ignore-case|sam/--ignore-case> in the L<sam|sam> documentation.

=item C<ignore_directory>

See L<--ignore-directory|sam/--ignore-directory> in the L<sam|sam>
documentation. The argument is a reference to an array of
L<file selectors|sam/FILE SELECTORS>.

=item C<ignore_file>

See L<--ignore-file|sam/--ignore-file> in the L<sam|sam>
documentation. The argument is a reference to an array of
L<file selectors|sam/FILE SELECTORS>.

=item C<ignore_sam_defaults>

See L<--ignore-sam-defaults|sam/--ignore-sam-defaults> in the L<sam|sam>
documentation.

=item C<invert_match>

See L<--known-types|sam/--known-types> in the L<sam|sam> documentation.

=item C<known_types>

See L<--known-types|sam/--known-types> in the L<sam|sam> documentation.

=item C<line>

See L<--line|sam/--line> in the L<sam|sam> documentation.

=item C<literal>

See L<--literal|sam/--literal> in the L<sam|sam> documentation.

=item C<match>

See L<--match|sam/--match> in the L<sam|sam> documentation. If legal but
not specified, the first non-option argument in C<argv> will be used.

If this argument is not specified, L<process()|/process> will throw an
exception.

=item C<max_count>

See L<--max-count|sam/--max-count> in the L<sam|sam> documentation.

=item C<not>

See L<--not|sam/--not> in the L<sam|sam> documentation. The value is a
reference to an array.

=item C<output>

See L<--output|sam/--output> in the L<sam|sam> documentation. The value
is a template as described in that documentation.

=item C<passthru>

See L<--passthru|sam/--passthru> in the L<sam|sam> documentation.

=item C<print0>

See L<--print0|sam/--print0> in the L<sam|sam> documentation.

=item C<range_end>

See L<--range-end|sam/--range-end> in the L<sam|sam> documentation.

=item C<range_start>

See L<--range-start|sam/--range-start> in the L<sam|sam> documentation.

=item C<recurse>

See L<--recurse|sam/--recurse> in the L<sam|sam> documentation.

=item C<replace>

See L<--replace|sam/--replace> in the L<sam|sam> documentation.

=item C<s>

See L<-s|sam/-s> in the L<sam|sam> documentation.

=item C<samrc>

See L<--samrc|sam/--samrc> in the L<sam|sam> documentation.

=item C<show_syntax>

See L<--show-syntax|sam/--show-syntax> in the L<sam|sam> documentation.

=item C<show_types>

See L<--show-types|sam/--show-types> in the L<sam|sam> documentation.

=item C<sort_files>

See L<--sort-files|sam/--sort-files> in the L<sam|sam> documentation.

=item C<syntax>

See L<--syntax|sam/--syntax> in the L<sam|sam> documentation.

This argument takes either a scalar syntax type or a reference to an
array of them. Syntax type names can be abbreviated as long as the
abbreviation is unique.

=item C<syntax_add>

See L<--syntax-add|sam/--syntax-add> in the L<sam|sam> documentation.

=item C<syntax_del>

See L<--syntax-del|sam/--syntax-del> in the L<sam|sam> documentation.

=item C<syntax_set>

See L<--syntax-set|sam/--syntax-set> in the L<sam|sam> documentation.

=item C<type>

See L<--type|sam/--type> in the L<sam|sam> documentation. The argument
is either a scalar type or a reference to an array of types, which may
be prefixed by C<'no'> or C<'no-'> to reject the type.

=item C<type_add>

See L<--type-add|sam/--type-add> in the L<sam|sam> documentation.

=item C<type_del>

See L<--type-del|sam/--type-del> in the L<sam|sam> documentation.

=item C<type_set>

See L<--type-set|sam/--type-set> in the L<sam|sam> documentation.

=item C<underline>

See L<--underline|sam/--underline> in the L<sam|sam> documentation.

=item C<with_filename>

See L<--with-filename|sam/--with-filename> in the L<sam|sam>
documentation.

=item C<word_regexp>

See L<--word-regexp|sam/--word-regexp> in the L<sam|sam> documentation.

=back

=head2 create_samrc

 $sam->create_samrc( $exit )

This method prints the default configuration to C<STDOUT>. If the
argument is true, it exits. Otherwise it returns. The default for
C<$exit> is true if called from the C<$sam> object.

=head2 dumped

This method returns the value of the L<dump|/dump> argument.

=head2 files_from

Given the name of one or more files, this method reads them and returns
its contents, one line at a time, and C<chomp>-ed. These are assumed to
be file names, and will be filtered if C<filter_files_from> is true.

If called without arguments, reads the files specified by the
C<files_from> argument to L<new()|/new>, if any, and returns their
possibly-filtered contents.

=head2 help_colors

 $sam->help_colors( $exit );

This method prints to F<STDOUT> a color palette specified using the
eight-color scheme for both foreground and background colors. If the
argument is true, it exits; otherwise it returns. The default for
C<$exit> is true if called from the C<$sam> object (which happens if
argument C<help_types> is true or option C<--help-types> is asserted),
and false otherwise.

=head2 help_syntax

 $sam->help_syntax( $exit )

This method prints help for the defined syntax types to F<STDOUT>. If
the argument is true, it exits; otherwise it returns. The default for
C<$exit> is true if called from the C<$sam> object (which happens if
argument C<help_types> is true or option C<--help-types> is asserted),
and false otherwise.

=head2 help_types

 $sam->help_types( $exit )

This method prints help for the defined file types to C<STDOUT>. If the
argument is true, it exits; otherwise it returns. The default for
C<$exit> is true if called from the C<$sam> object (which happens if
argument C<help_types> is true or option C<--help-types> is asserted),
and false otherwise.

The output is similar but not identical to L<ack|ack> C<--help-types>.

=head2 process

 $sam->process( @files )

This method processes one or more files or directories. Match output is
written to F<STDOUT>. If any files are modified, the modified file is
written unless L<dry_run|/dry_run> is true. The number of files
containing matches returned.

If no arguments are passed, the contents of the
L<files_from|/files_from> and L<argv|/argv> arguments to L<new()|/new>
are used.

An argument can be a scalar reference, but in this case modifications
are not written.

Binary files are ignored.

If the file is a directory, any files in the directory are processed
provided they are not ignored.

=head1 SEE ALSO

L<ack|ack>

=head1 SUPPORT

Support is by the author. Please file bug reports at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=App-Sam>,
L<https://github.com/trwyant/perl-App-Sam/issues/>, or in
electronic mail to the author.

=head1 AUTHOR

Thomas R. Wyant, III F<wyant at cpan dot org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2023-2024 by Thomas R. Wyant, III

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl 5.10.0. For more details, see the full text
of the licenses in the directory LICENSES.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=cut

# ex: set textwidth=72 :

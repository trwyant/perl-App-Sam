package App::Sam;

use 5.010001;

use strict;
use warnings;

use charnames qw{ :full :short };
use if charnames->VERSION >= 1.30, charnames => ':loose';

use utf8;

use App::Sam::Resource;
use App::Sam::Tplt;
use App::Sam::Tplt::Color;
use App::Sam::Tplt::Under;
use App::Sam::Util qw{
    :carp :case :syntax :term_ansi __expand_tilde __syntax_types @CARP_NOT
};
use Config;
use Cwd ();
use File::Next ();
use File::Basename ();
use File::Spec;
use Errno qw{ :POSIX };
use File::ShareDir;
use File::Temp ();
use Getopt::Long 2.33 ();	# for O-O interface, auto_version
use List::Util 1.45;	# for uniqstr()
use Module::Load ();
use Readonly;
use Scalar::Util ();
use Term::ANSIColor ();
use Text::ParseWords ();
use Text::Abbrev ();

our $VERSION = '0.000_006';

use constant IS_WINDOWS	=> {
    MSWin32	=> 1,
}->{$^O} || 0;

use constant TOOD_WIN_RSRC	=> 'Windows resource files';

use constant REF_ARRAY	=> ref [];
use constant REF_SCALAR	=> ref \0;

use constant STOP	=> 'STOP';

use constant TPLT_FLUSH	=> '$p\\n';
use constant TPLT_MATCH	=> '$p$&';

use enum qw{ BITMASK:
    FLAG_FAC_NO_MATCH_PROC
    FLAG_FAC_SYNTAX
    FLAG_FAC_TYPE
    FLAG_IS_ATTR
    FLAG_IS_OPT
    FLAG_DMP_NON_OPT
    FLAG_DMP_NOT
};

use enum qw{ ENUM:
    TYPE_WANTED=0
    TYPE_NOT_WANTED
};

Readonly::Scalar my $DIR_SEP => IS_WINDOWS ? "\\/" : File::Spec->catfile(
    '', '' );

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

# NOTE many of the following have (at the moment) identical values but
# different intended semantics:

# FLAG_FAC is intended for testing whether any of the FLAG_FAC_*
# bits is set.
use constant FLAG_FAC	=> FLAG_FAC_NO_MATCH_PROC |
    FLAG_FAC_SYNTAX | FLAG_FAC_TYPE;
# FLAG_IS is intended for testing whether any of the FLAG_IS_*
# bits is set.
use constant FLAG_IS	=> FLAG_IS_ATTR | FLAG_IS_OPT;
# FLAG_IS_DEFAULT is intended to be the default if none of the FLAG_IS_*
# bits are set.
use constant FLAG_IS_DEFAULT	=> FLAG_IS_ATTR | FLAG_IS_OPT;
# FLAG_DEFAULT is intended to be the default if none of the FLAG_* bits
# is set.
use constant FLAG_DEFAULT	=> FLAG_IS_DEFAULT;

Readonly::Scalar my $GT		=> "\N{GREATER-THAN SIGN}";
Readonly::Scalar my $LP		=> "\N{LEFT PARENTHESIS}";
Readonly::Scalar my $RCB	=> "\N{RIGHT CURLY BRACKET}";
Readonly::Scalar my $RP		=> "\N{RIGHT PARENTHESIS}";

# To be filled in (and made read-only) later.
our %ATTR_SPEC;

sub new {
    my ( $class, @arg ) = @_;

    state $default = bless {
	argv		=> [],
	color_colno	=> 'bold yellow',
	color_filename	=> 'bold green',
	color_lineno	=> 'bold yellow',
	color_match	=> 'black on_yellow',
	die		=> 0,
	dump		=> 0,
	flags		=> 0,
	ignore_sam_defaults	=> 0,
	invert_match	=> 0,
	recurse		=> 1,
	sort_files	=> 1,
    }, __PACKAGE__;

    my $self = bless {}, $class;

    # The loop is pure defensive programming. I can't imagine going
    # around more than twice.
    my $deferred;
    for ( 0 .. 2 ) {

	%{ $self } = %{ $default };
	$self->{env} = __default_env();
	$deferred
	    and @{ $self }{ keys %{ $deferred } } = values %{ $deferred };

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

	$self->__get_attr_from_resource(
	    $self->__get_resources( [ @arg ] ) );

	$deferred = delete $self->{_defer}
	    or last;
    }

    delete $self->{_already_loaded};

    $self->__incompat_arg( qw{ f match } );
    $self->__incompat_arg( qw{ f g files_with_matches
	files_without_matches replace } );
    $self->__incompat_arg( qw{ replace 1 } );
    $self->__incompat_arg( qw{ file match } );
    $self->__incompat_arg( qw{ count passthru } );
    $self->__incompat_arg( qw{ underline output } );
    $self->__incompat_arg( qw{ perldoc type } );
    $self->__incompat_arg( qw{ perldoc filter } );
    if ( $self->{ack_mode} ) {
	if ( $self->{show_types} ) {
	    $self->{f}
		or $self->{g}
		or $self->__croak(
		$self->{die} ?
		'--show-types can only be used with -f or -g' :
		'show_types can only be used with f or g'
	    );
	}
    }

    $self->{filter} //= Scalar::Util::openhandle( *STDIN ) ? -p STDIN : !1;

    unless ( $self->{f} || defined $self->{match} ) {
	if ( $self->{file} ) {
	    my @pat;
	    foreach my $file ( @{ $self->{file} } ) {
		local $_ = undef;	# while (<>) does not localize $_
		open my $fh, '<:encoding(utf-8)', $file
		    or $self->__croak( "Unable to open $file: $!" );
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
	} elsif ( @{ $self->{argv} } ) {
	    $self->{match} = shift @{ $self->{argv} };
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
	my $str = join ' || ', map { "m $_" . $self->_get_re_modifiers( $_ ) }
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
	    push @str, "$self->{$_}(?{ \$self->{_process_file}{in_range} = $range_val->{$_} })";
	}
	local $" = '|';
	$self->{_range} = $self->__compile_match( _range => "m (@str)g" );
    }

    if ( $self->{known_types} ) {
	foreach my $type ( keys %{ $self->{_type_def} } ) {
	    exists $self->{type}{$type}
		or $self->{type}{$type} = TYPE_WANTED;
	}
	$self->{_type_wanted} = 1;
    }

    if ( $self->{max_count} && ( $self->{f} || $self->{g} ||
	    $self->{files_with_matches} ||
	    $self->{files_without_matches} ) ) {
	$self->{_max_files_wanted} = $self->{max_count};
    } 

    $self->{_eol} = $self->{print0} ? "\0" : "\n";

    if ( $self->{filter} ) {
	my $encoding = $self->__get_encoding();
	if ( defined( $encoding ) && $encoding ne '' ) {
	    binmode STDIN, $encoding
		or $self->__croak( "Unable to set STDIN to $encoding: $!" );
	}
    }

    if ( defined( my $perldoc = $self->{perldoc} ) ) {
	state $type_map = {
	    all		=> 'perl',
	    core	=> 'perl',
	    delta	=> 'perldelta',
	    faq		=> 'perlfaq',
	};
	my $type = $type_map->{$perldoc};
	$self->{_type_def}{$type}
	    or $self->__croak(
	    "--perldoc=$perldoc requires file type '$type' to be defined"
	);
	$self->{_syntax_def}{Perl}
	    or $self->__croak(
	    "--perldoc=$perldoc requires syntax type 'Perl' to be defined"
	);
	$self->{type}{$type} = TYPE_WANTED;
	$self->{syntax}
	    or $self->{syntax}{+SYNTAX_DOCUMENTATION} = 1;
    }

    not $self->{ack_mode}
	and $self->{type}
	and $self->{_type_wanted} = List::Util::any
	    { $_ == TYPE_WANTED } values %{ $self->{type} };

    $self->__make_munger();

    return $self;
}

# Perform the ack (or at least ack-like) check on a regex before
# wrapping it in \b assertions. Returns true if the check passes, and
# false if it fails.
sub _check_word_regexp {
    ( local $_ ) = @_;

    # Can start with \w, \d, a word character, open parens or square
    # brackets, or a dot.
    m/ \A (?: \\ [wd] | [\w([.] ) /smx
	or return 0;
    {	# Single-iteration loop
	# Can end with a word character, provided it is not escaped
	m/ ( \\* ) \w \z /smx
	    and not length( $1 ) % 2
	    and last;
	# Can end with w or d privided it IS escaped.
	m/ ( \\* ) [wd] \z /smx
	    and length( $1 ) % 2
	    and last;
	# Can end with close parens, square brackets, or
	# braces, or +, ?, *, or . provided it is not escaped. {
	m/ ( \\* ) ( [])}+?*.] ) /smx
	    and not length( $1 ) % 2
	    and last;
	# Out of options.
	return 0;
    }
    return 1;
}

sub __chomp {
    $_[0] =~ s/ ( \n | \r \n? ) \z //smx
	and return "$1";
    return undef;	## no critic (ProhibitExplicitReturnUndef)
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
    my $default_file = $self->__get_default_resource_name();
    say '--ignore-sam-defaults';
    local $_ = undef;	# while (<>) does not localize $_
    open my $fh, '<:encoding(utf-8)', $default_file
	or $self->__croak( "Unable to open $default_file: $!" );
    while ( <$fh> ) {
	$. == 1
	    and s/==VERSION==/$VERSION/;
	print;
    }
    close $fh;
    $exit and exit;
    return;
}

sub __dump_data {
    my ( $self, $attr_spec, $attr_name, $attr_val ) = @_;
    $self->{_dump}
	or return;

    # FIXME the fact that this does not fire means that the attribute
    # name is redundant. Remove it, and this check.
    $attr_spec->{name} ne $attr_name
	and $self->__confess( "Attrib '$attr_name' spec has name '$attr_spec->{name}'" );

    $attr_spec->{flags} & FLAG_DMP_NOT
	and return;

    $self->_dump_title();

    my $leader = $self->{_dump}{indent};
    my $type = $attr_spec->{type};

    if ( $attr_spec->{flags} & FLAG_DMP_NON_OPT ) {
	foreach ( ref $attr_val ? @{ $attr_val } : $attr_val ) {
	    say $leader, $_;
	}
    } elsif ( $self->{_dump}{rsrc}[-1]->getopt() ) {
	( my $dump_name = $attr_name ) =~ tr/_/-/;
	$leader .= length( $attr_name ) > 1 ? '--' : '-';

	if ( $type eq '' ) {
	    say $leader, $dump_name;
	} elsif ( $type eq '!' ) {
	    $attr_val
		or $leader .= length( $dump_name ) > 1 ? 'no-' : 'no';
	    say $leader, $dump_name;
	} else {
	    say $leader, "$dump_name=$_"
		for ref $attr_val ? @{ $attr_val } : $attr_val;
	}
    } else {
	say "$leader$attr_name => ", _dump_format(
	    $attr_val );
    }

    unless ( defined $attr_spec->{validate} ) {
	if ( $type =~ m/ \@ /smx ) {
	    defined $self->{$attr_name}
		and REF_ARRAY ne ref $self->{$attr_name}
		and $self->__confess( "attr $attr_name is $self->{$attr_name}" );
	    push @{ $self->{$attr_name} }, ref $attr_val ?
		@{ $attr_val } : $attr_val;
	} else {
	    $self->{$attr_name} = $attr_val;
	}
    }
    return;
}

# NOTE -- DO NOT call this unless you already know you are dumping
sub _dump_title {
    my ( $self ) = @_;
    if ( $self->{_dump}{title} ) {
	$self->{_dump}{rsrc}[-1]->dump_alias( ' ' x (
		$self->{_dump}{nest} * 2 - 2 ) );
	$self->{_dump}{title} = 0;
    }
    return;
}

sub _dump_format {
    my ( $arg ) = @_;
    if ( REF_ARRAY eq ref $arg ) {
	return sprintf '[ %s ]',
	    join ', ', map { _dump_format( $_ ) } @{ $arg };
    } elsif ( ! defined $arg ) {
	return 'undef';
    } elsif ( Scalar::Util::looks_like_number( $arg ) ) {
	return "$arg";
    } else {
	$arg =~ s/ (?= [\\'] ) /\\/smxg;
	return "'$arg'";
    }
}

sub __dump_start {
    my ( $self, $rsrc ) = @_;
    $self->{dump}
	or return;

    $self->{_dump} ||= {
	rsrc	=> [],
	indent	=> '',
	nest	=> 0,
    };

    $self->{_dump}{title} = 1;

    if ( $rsrc->indent() ) {
	$self->{_dump}{nest}++;
	$self->{_dump}{indent} = ' ' x ( $self->{_dump}{nest} * 2 );
    }

    push @{ $self->{_dump}{rsrc} }, $rsrc;

    return;
}

sub __dump_end {
    my ( $self ) = @_;
    $self->{_dump}
	or return;
    # Not sure I like the below, as it gives me an extra 'new()' after
    # the 'ARGV' dump.
    # $self->_dump_title();	# The dump may be empty
    my $rsrc = pop @{ $self->{_dump}{rsrc} };
    if ( $rsrc->indent() ) {
	--$self->{_dump}{nest};
	$self->{_dump}{indent} = ' ' x ( $self->{_dump}{nest} * 2 );
    } else {
	$self->{_dump}{title} = 1;
    }
    return;
}

sub _format_opt {
    my ( undef, $attr_spec, $name, $value ) = @_;	# Invocant unused
    $name =~ tr/_/-/;
    my $leader = length( $name ) == 1 ? '-' : '--';
    if ( $attr_spec->{type} eq '' ) {
    } elsif ( $attr_spec->{type} eq '!' ) {
	$value
	    or $leader .= length( $name ) eq 1 ? 'no' : 'no-';
    } else {
	$name .= length( $name ) == 1 ? $value : "=$value";
    }
    return "$leader$name";
}

# FIXME this is a crock, but gives me a convenient hook for fiddling
# with this during testing.
sub __default_env {
    return 1;
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
		    or $self->__croak( "Unable to open $file: $!" );
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

    if ( m/ [.] ( [^.]* ) \z /smx ) {
	my $type;
	$type = $prop_spec->{ext}{ __fold_case( $1 ) }
	    and push @rslt, @{ $type };
    }

    if ( my $match = $prop_spec->{match} ) {
	foreach my $m ( @{ $match } ) {
	    $m->[1]->()
		and push @rslt, $m->[0];
	}
    }

    if (
	my $match = $prop_spec->{firstlinematch}
	    and not -B $path
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
	    $self->{_process_file}{type} ?
	    @{ $self->{_process_file}{type} } :
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

sub file_type_is {
    my ( $self, $path, $type ) = @_;
    return List::Util::first { $_ eq $type } $self->__file_type( $path );
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
    #         FLAG_DMP_NON_OPT - Dump as non-pption value. This is for
    #                 the use of the dump system; setting it on option
    #                 definitions is unsupported.
    #         FLAG_DMP_NOT - Do not dump this value.
    #         FLAG_IS_ATTR - The entry is an attribute
    #         FLAG_IS_OPT -- The entry is an option
    #         FLAG_FAC_NO_MATCH_PROC - No match processing.
    #         FLAG_FAC_SYNTAX - A symtax module must be instantiated.
    #         FLAG_FAC_TYPE - The file type needs to be computed.
    #         NOTE that if none of the FLAG_IS_* flags is provided,
    #         FLAG_IS_ATTR | FLAG_IS_OPT are set.
    my %attr_spec_hash = (
	1		=> {
	    type	=> '',
	},
	ack_mode	=> {
	    type	=> '!',
	},
	after_context	=> {
	    type	=> ':2',
	    alias	=> [ 'A' ],
	},
	argv	=> {
	    type	=> '=s@',
	    flags	=> FLAG_IS_ATTR | FLAG_DMP_NOT,
	    validate	=> '__validate_argv',
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
	    type	=> ':2',
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
	    type	=> ':2',
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
	define	=> {
	    type	=> '=s@',
	    validate	=> '__validate_define',
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
	    validate	=> '__validate_defer_boolean'
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
	no_encoding	=> {
	    type	=> '',
	    alias	=> [ 'noencoding' ],
	    flags	=> FLAG_IS_OPT,
	    validate	=> '__validate_fixed_value',
	    arg		=> [ encoding	=> '' ],
	},
	env	=> {
	    type	=> '!',
	    validate	=> '__validate_defer_boolean'
	},
	f	=> {
	    type	=> '!',
	    flags	=> FLAG_FAC_NO_MATCH_PROC,
	},
	g	=> {
	    type	=> '!',	# The expression comes from --match.
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
	    type	=> '',
	    alias	=> [ qw{ i } ],
	    flags	=> FLAG_IS_OPT,
	    validate	=> '__validate_fixed_value',
	    arg		=> [ match_case => RE_CASE_BLIND ],
	},
	I	=> {
	    type	=> '',
	    alias	=> [ qw{ noignore_case no_ignore_case
		nosmart_case no_smart_case } ],
	    flags	=> FLAG_IS_OPT,
	    validate	=> '__validate_fixed_value',
	    arg		=> [ match_case => RE_CASE_SENSITIVE ],
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
	    validate	=> '__validate_defer_boolean'
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
	match_case	=> {
	    type	=> '=i',
	    flags	=> FLAG_IS_ATTR,
	},
	smart_case	=> {
	    type	=> '',
	    alias	=> [ 'S' ],
	    flags	=> FLAG_IS_OPT,
	    validate	=> '__validate_fixed_value',
	    arg		=> [ match_case => RE_CASE_SMART ],
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
	no_ignore_directory	=> {
	    type	=> '=s@',
	    alias	=> [ 'noignore_directory' ],
	    validate	=> '__validate_ignore',
	    arg		=> 'ignore_directory',
	},
	no_ignore_file	=> {
	    type	=> '=s@',
	    alias	=> [ 'noignore_file' ],
	    validate	=> '__validate_ignore',
	    arg		=> 'ignore_file',
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
	pager	=> {
	    type	=> '=s',
	},
	no_pager	=> {
	    type	=> '',
	    alias	=> [ 'nopager' ],
	    flags	=> FLAG_IS_OPT,
	    validate	=> '__validate_fixed_value',
	    arg		=> [ pager	=> undef ],
	},
	passthru	=> {
	    type	=> '!',
	    alias	=> [ 'passthrough' ],
	},
	perldoc		=> {
	    type	=> ':s',
	    validate	=> '__validate_perldoc',
	    flags	=> FLAG_FAC_SYNTAX,
	},
	print0		=> {
	    type	=> '!',
	},
	P		=> {
	    type	=> '',
	    flags	=> FLAG_IS_OPT,
	    validate	=> '__validate_fixed_value',
	    arg		=> [ proximate	=> 0 ],
	},
	proximate	=> {
	    type	=> ':1',
	    alias	=> [ 'p' ],
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
	    alias	=> [ qw{ noremove no_remove noreplace } ],
	    validate	=> '__validate_fixed_value',
	    arg		=> [ 'replace' ],
	},
	s	=> {
	    type	=> '!',
	},
	samrc	=> {
	    type	=> '=s',
	    validate	=> '__validate_samrc',
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
	T	=> {
	    type	=> '=s@',
	    flags	=> FLAG_IS_OPT | FLAG_FAC_TYPE,
	    validate	=> '__validate_type',
	    arg		=> 1,
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
	my @alias;
	foreach ( $key, @{ $val->{alias} } ) {
	    my $aka;
	    ( $aka = $_ ) =~ tr/_/-/
		and push @alias, $aka;
	}
	@alias
	    and push @{ $val->{alias} }, @alias;

	defined $val->{flags}
	    or $val->{flags} = FLAG_DEFAULT;

	$val->{flags} & FLAG_IS
	    or $val->{flags} |= FLAG_IS_DEFAULT;

	if ( $val->{flags} & FLAG_FAC ) {
	    ( $val->{flags} & FLAG_FAC_SYNTAX )
		and $val->{flags} |= FLAG_FAC_TYPE;
	    $val->{validate} //= $val->{type} =~ m/ \A \@ \z /smx ?
		'__validate_accept_array' : '__validate_accept_scalar';
	}
    }

    Readonly::Hash %ATTR_SPEC => %attr_spec_hash;
}

sub __get_opt_specs {
    my ( $self ) = @_;
    my @opt_spec_list;
    foreach ( values %ATTR_SPEC ) {
	next unless $_->{flags} & FLAG_IS_OPT;
	push @opt_spec_list, join( '|', $_->{name}, @{ $_->{alias} || []
	    } ) . $_->{type}, $self->__get_validator( $_, 1 );
    }

    # Prevent autovivification
    if ( $self->{_type_def} ) {
	foreach ( keys %{ $self->{_type_def} } ) {
	    push @opt_spec_list, "$_!", sub {
		my ( $name, $value ) = @_;
		if ( $value ) {
		    $self->{type}{$name} = TYPE_WANTED;
		    $self->{_type_wanted} = 1;
		} else {
		    $self->{type}{$name} = TYPE_NOT_WANTED;
		}
		$self->__dump_data(
		    {
			name	=> $name,
			type	=> '!',
			flags	=> 0,
		    },
		    $name, $value,
		);
		return;
	    };
	}
    }

    # Prevent autovivification
    if ( $self->{define} ) {
	foreach my $attr_spec ( values %{ $self->{define} } ) {
	    push @opt_spec_list, $attr_spec->{name}, sub {
		my ( $name, $value ) = @_;	# $name unused
		my @def_arg = ( $value, split /,/, $value );
		my $tplt = App::Sam::Tplt->new(
		    die	=> $self->{die},
		    ofs	=> ',',
		);
		my @expansion;
		foreach my $expand ( @{ $attr_spec->{arg} } ) {
		    push @expansion, $tplt->execute_template(
			$expand,
			capt	=> \@def_arg,
		    );
		}

		$self->__dump_data( $attr_spec, $name, $value );

		$self->__get_attr_from_resource(
		    App::Sam::Resource->new(
			name	=> $self->_format_opt(
			    $attr_spec, $name, $value ),
			data	=> \@expansion,
			orts	=> $self->{argv},
		    ),
		);

		return;
	    };
	};
    }

    return @opt_spec_list;
}

sub __get_default_resource {
    my ( $invocant ) = @_;
    ref $invocant
	and $invocant->{ignore_sam_defaults}
	and return;
    return App::Sam::Resource->new(
	name	=> $invocant->__get_default_resource_name(),
	alias	=> 'Defaults',
    );
}

# NOTE the File::Share dodge is from David Farrell's
# https://www.perl.com/article/66/2014/2/7/3-ways-to-include-data-with-your-Perl-distribution/
sub __get_default_resource_name {
    return File::ShareDir::dist_file( 'App-Sam', 'default_samrc' );
}

sub __get_global_resource {
    my ( $invocant ) = @_;
    ref $invocant
	and not $invocant->{env}
	and return;
    return App::Sam::Resource->new(
	name	=> $invocant->__get_global_resource_name(),
    );
}

sub __get_global_resource_name {
    my ( $invocant ) = @_;
    IS_WINDOWS
	and $invocant->__todo( TODO_WIN_RSRC );
    return '/etc/samrc';
}

# NOTE that this MAY return a duplicate resource.
sub __get_project_resource {
    my ( $invocant ) = @_;
    ref $invocant
	and not $invocant->{env}
	and return;
    my $name = $invocant->__get_project_resource_name();
    my @dirs = File::Spec->splitdir( Cwd::getcwd() );
    while ( @dirs ) {
	my $path = File::Spec->catfile( @dirs, $name );
	-e $path
	    and return App::Sam::Resource->new(
	    name	=> $path,
	);
	pop @dirs;
    }
    return;
}

sub __get_project_resource_name {
    my ( $invocant ) = @_;
    IS_WINDOWS
	and $invocant->__todo( TODO_WIN_RSRC );
    # TODO ack's search semantics.
    return '.samrc';
}

sub __get_user_resource {
    my ( $invocant ) = @_;
    ref $invocant
	and not $invocant->{env}
	and return;
    return App::Sam::Resource->new(
	name	=> $invocant->__get_user_resource_name(),
    );
}

sub __get_user_resource_name {
    my ( $invocant ) = @_;
    defined $ENV{SAMRC}
	and $ENV{SAMRC} != ''
	and return $ENV{SAMRC};
    IS_WINDOWS
	and $invocant->__todo( TODO_WIN_RSRC );
    return '~/.samrc';
}

{
    my %resource_cache;

    # TODO __clear_resource_cache()

    sub __get_attr_from_resource {
	my ( $self, @arg_array ) = @_;

	local $self->{_already_loaded} = {};

	foreach my $arg ( @arg_array ) {

	    Scalar::Util::blessed( $arg )
		or $self->__confess( 'Not a resource' );

	    if ( ! $arg->data() && $self->{_already_loaded}{$arg->name()}++ ) {
		my $msg = "Resource @{[ $arg->name() ]} already loaded";
		defined $arg->from()
		    and $msg .= ' from ' . $arg->from();
		# In case we're called recursively via Getopt::Long
		local $SIG{__WARN__} = 'DEFAULT';
		$self->__carp( $msg );
		return;
	    }

	    my @data;

	    my $cache;
	    my $cached;
	    unless ( defined $arg->data() ) {
		if ( $cached = $resource_cache{$arg->name()} ) {
		    ref $cached
			or $self->__croak( $cached );
		    @data = @{ $cached };
		} else {
		    $cache = 1;
		}
	    }

	    if ( REF_ARRAY eq ref $arg->data() ) {
		@data = @{ $arg->data() };
	    } elsif ( ! $cached ) {
		my $fn = $arg->data() // $arg->name();
		open my $fh, '<' . $self->__get_encoding( $fn, 'utf-8' ), $fn	## no critic (RequireBriefOpen)
		    or do {
		    if ( $! == ENOENT && ! $arg->required() ) {
			$resource_cache{$fn} = [];
			next;
		    } else {
			$self->__croak( $resource_cache{$fn} =
			    "Unable to open $fn: $!" );
		    }
		};
		local $_ = undef;	# while (<>) does not localize
		while ( <$fh> ) {
		    m/ \A \s* (?: \# | \z ) /smx
			and next;
		    chomp;
		    push @data, $_;
		}
		close $fh;
		$cache
		    and $resource_cache{$arg->name()} = [ @data ];
	    }

	    if ( @data ) {

		local $self->{_rc_name} = $arg->name();

		$self->__dump_start( $arg );

		if ( $arg->getopt() ) {

		    my @warning;
		    local $SIG{__WARN__} = sub { push @warning, @_ };
		    $self->__get_option_parser()->getoptionsfromarray(
			\@data, $self, $self->__get_opt_specs() )
			or do {
			    chomp @warning;
			    my $msg = join '; ', @warning;
			    # $msg =~ s/ [?!.] \z //smx;
			    # $msg .= ' in ' . $arg->name();
			    $cache
				and $resource_cache{$arg->name()} = $msg;
			    $self->__croak( $msg );
		    };

		    if ( $arg->set_orts( @data ) ) {
			$self->__dump_data( {
				flags	=> FLAG_DMP_NON_OPT,
			    },
			    undef,	# $attr_name unused
			    \@data,
			);
		    } else {
			$self->__croak( 'Non-option arguments in ',
			    $arg->name() );
		    }
		} else {
		    for ( my $inx = 0; $inx < @data; $inx += 2 ) {
			$ATTR_SPEC{$data[$inx]}
			    or $self->__croak( "Invalid argument '$data[$inx]'" );
			$self->__validate_attr( $data[$inx], $data[$inx+1] )
			    or $self->__croak( "Invalid $data[$inx] value '$data[$inx+1]'" );
		    }
		}

		$self->__dump_end();
	    }

	}


	return $self;
    }

}

# Given an argument spec, return code to validate it.
sub __get_validator {
    my ( $self, $attr_spec, $die ) = @_;
    ref $attr_spec
	or $attr_spec = $ATTR_SPEC{$attr_spec}
	or $self->__confess( "Undefined attribute '$_[1]'" );
    if ( my $method = $attr_spec->{validate} ) {
	my $facility = $attr_spec->{flags} & FLAG_FAC;
	# NOTE we count on the attribute spec setup code to have
	# provided a validator if the facility was specified
	$die
	    or return sub {
		$self->__dump_data( $attr_spec, @_ );
		if ( $self->$method( $attr_spec, @_ ) ) {
		    $self->{flags} |= $facility;
		    return 1;
		}
		return 0;
	    };
	return sub {
	    $self->__dump_data( $attr_spec, @_ );
	    if ( $self->$method( $attr_spec, @_ ) ) {
		$self->{flags} |= $facility;
		return 1;
	    }
	    ( my $opt_name = $_[0] ) =~ tr/_/-/;
	    # FIXME This is a crock. The validators should raise
	    # exceptions.
	    $self->{ack_mode}
		or die "Invalid value --$opt_name=$_[1]\n";
	    $opt_name eq 'type'
		and die "Unknown $opt_name '$_[1]'\n";
	    die "Invalid value --$opt_name=$_[1]\n";
	};
    } elsif ( $self->{_dump} ) {
	return sub {
	    $self->__dump_data( $attr_spec, @_ );
	    return 1;
	};
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
	my $psr = Getopt::Long::Parser->new();
	$psr->configure( qw{
	    bundling no_ignore_case } );
	$pass_thru
	    and $psr->configure( qw{ pass_through } );
	$psr;
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
    defined $encoding
	and $encoding ne ''
	or return '';
    return ":encoding($encoding)";
}

# Manufacture all our resources. Optional argument $new_arg is an array
# reference to the arguments of new().
sub __get_resources {
    my ( $self, $new_arg ) = @_;
    my %uniq;
    my @rslt = grep { ! $uniq{ $_->name() }++ } (
	$self->__get_default_resource(),
	$self->__get_global_resource(),
	$self->__get_user_resource(),
	$self->__get_project_resource(),
    );
    $new_arg
	and push @rslt, App::Sam::Resource->new(
	data	=> $new_arg,
	getopt	=> 0,
	name	=> 'new()',
    );
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

Readonly::Array my @RE_CASE => do {
    my @re_case;
    $re_case[ RE_CASE_SENSITIVE ] = sub { '' };
    $re_case[ RE_CASE_BLIND ] = sub { 'i' };
    $re_case[ RE_CASE_SMART ] = sub { __smartcase( $_[0] ) ? 'i' : '' };
    @re_case;
};

sub _get_re_modifiers {
    my ( $self, $re ) = @_;
    $self->__confess( 'RE undefined' ) unless defined $re;
    return $RE_CASE[ $self->{match_case} // RE_CASE_SENSITIVE ]->( $re );
}

sub __make_munger {
    my ( $self ) = @_;

    defined( my $match = $self->{match} )
	or do {
	$self->{_munger} = sub {
	    $_[0]->__croak( 'No regular expression found' );
	};
	return;
    };

    my $modifier = $self->_get_re_modifiers( $match );

    $self->{literal}
	and $match = quotemeta $match;

    # OK, I give up. We do a trial here for the purpose of reporting the
    # error if any.

    {
	local $@ = undef;
	unless ( eval { qr/$match/ } ) {
	    my ( $error, $re ) = split / <-- HERE /, $@, 3;
	    $error =~ s/; marked by\z//;
	    my $leader = ' ' x ( 1 + length $re );
	    $self->__croak( <<"EOD" );
Invalid regex '$match'
Regex: $match
$leader^---HERE $error
EOD
	}
    }

    if ( $self->{word_regexp} ) {
	if ( $match =~ m/ \W /smx ) {
	    # NOTE that my perhaps not-so-humble opinion is that ack
	    # overvalidates here. But I reserve the option to change my
	    # mind.
	    not $self->{ack_mode}
		or _check_word_regexp( $match )
		or $self->__croak(
		'-w will not do the right thing if your regex does not begin and end with a word character.' );

	    $match = "\\b(?:$match)\\b";
	} else {
	    $match = "\\b$match\\b";
	}
    }

    my $str;
    $str = "m($match)$modifier";
    if ( $self->{flags} & FLAG_FAC_NO_MATCH_PROC ) {
	# Do nothing -- we just want to know if we have a match.
    } elsif ( defined $self->{output} ) {
	$self->{output} =~ s/ \n /\\n/smxg;
	$self->{output} =~ s/ (?<! \\n ) \z /\\n/smx;
	$modifier .= 'g';
	$str = "\$_[0]->_process_callback() while m($match)$modifier";
    } else {
	$modifier .= 'g';
	$str = "\$_[0]->_process_callback() while m($match)$modifier";
    }
    my $code;
    local $@;
    unless ( $code = eval "sub { $str }" ) {	## no critic (ProhibitStringyEval)
	$self->__croak( "Invalid regex m($match)$modifier: $@" );
    }

    $self->{_munger} = $code;
    return;
}

sub __ignore {
    ( my ( $self, $kind, $path ), local $_ ) = @_;
    my $prop_spec = $self->{"ignore_$kind"}
	or $self->__confess( "Invalid ignore kind '$kind'" );

    ( $path //= {
	    directory	=> $File::Next::dir,
	    file		=> $File::Next::name,
	}->{$kind}
    ) or $self->__confess( "Can not default path for '$kind'" );
    $_ //= ( File::Spec->splitpath( $path ) )[2];

    $prop_spec->{is}{$_}
	and return 1;
    # NOTE that the ack docs seem to me to say that this does not work.
    # But t/ack-ignore-dir.t explicitly tests for it.
    # FIXME Given ack --ignore-dir=another_subdir --noignore-dir=CVS,
    # ack lists files in .../another_subdir/CVS/.
    $prop_spec->{is}{$path}
	and return 1;
    m/ [.] ( [^.]* ) \z /smx
	and $prop_spec->{ext}{$1}
	and return 1;
    $prop_spec->{match}
	and $prop_spec->{match}->()
	and return 1;
    if ( $kind eq 'file' && $self->{type} ) {

	-B $_
	    and -s _
	    and return 1;

	# Encoding: undef = unspecified, 0 = accept, 1 = skip
	my $want_type;
	foreach my $type ( $self->__file_type( $path, $_ ) ) {
	    my $skip = $self->{type}{$type}
		and return 1;
	    $want_type //= $skip;
	}
	$self->{_type_wanted}
	    and return( ! defined $want_type );
    }
    return 0;
}

sub __perldoc_all {
    state $dirs = _perldoc_populate_dirs( qw{
	archlibexp
	privlibexp
	sitelibexp
	vendorlibexp
	} );
    return @{ $dirs };
}

sub __perldoc_core {
    state $dirs = _perldoc_populate_dirs( qw{
	archlibexp
	privlibexp
	} );
    return @{ $dirs };
}

*__perldoc_delta = \&__perldoc_core;	# sub __perldoc_delta()
*__perldoc_faq = \&__perldoc_core;	# sub __perldoc_faq()

sub __perldoc_files_from {
    my ( $self ) = @_;
    defined( my $attr_val = $self->{perldoc} )
	or return;
    my $method = "__perldoc_$attr_val";
    return $self->$method();
}

sub _perldoc_populate_dirs {
    my @key_list = @_;
    my @rslt;
    foreach my $cfg ( @key_list ) {
	my $key = $Config{$cfg};
	defined $key
	    and $key ne ''
	    or next;
	foreach my $dir ( qw{ pods pod } ) {
	    my $path = File::Spec->catfile( $key, $dir );
	    -d $path
		or next;
	    push @rslt, $path;
	    last;
	}
    }
    return \@rslt;
}

sub __print {
    # my ( $self ) = @_;	# Invocant unused
    my $line = join '', @_[ 1 .. $#_ ];
    print $line;
    return;
}

sub process {
    my ( $self, @files ) = @_;

    unless ( @files ) {
	push @files, $self->__perldoc_files_from();
	push @files, $self->files_from();
	if ( $self->{filter} ) {
	    @files
		or @files = ( \*STDIN );
	} else {
	    push @files, @{ $self->{argv} || [] };
	    @files
		or @files = ( File::Spec->curdir() );
	}
    }

    defined $self->{with_filename}
	or local $self->{with_filename} = (
	    @files == 1 && ! -d $files[0] ) ? 0 : 1;
    defined $self->{line}
	or local $self->{line} = $self->{ack_mode} ?
	    $self->{with_filename} : 1;
    my $t_stdout = -t STDOUT;
    defined $self->{color}
	or local $self->{color} = $self->{g} ? 0 : $t_stdout;
    defined $self->{heading}
	or local $self->{heading} = $self->{ack_mode} ? $t_stdout : 1;

    my $ors;
    $self->{print0}
	and $ors = "\0";
    my $tplt_prefix;
    my $tplt_match;
    my $tplt_finalize;

    # NOTE that this was moved here from __make_munger() because that
    # method no longer knows the final value of {with_filename}.
    if ( $self->{flags} & FLAG_FAC_NO_MATCH_PROC ) {
	# Do nothing -- we just want to know if we have a match.
    } elsif ( $self->{g} ) {
	$tplt_prefix = '';
	$ors = '';
    } else {
	my @prefix;
	$self->{with_filename}
	    and not $self->{heading}
	    and push @prefix, '$f$F';
	$self->{line}
	    and push @prefix, '$.$F';
	$self->{column}
	    and push @prefix, '$c$F';
	( $self->{syntax} || $self->{show_syntax} )
	    and push @prefix, '$s$F';
	$tplt_prefix = join '', @prefix;
	if ( defined $self->{output} ) {
	    $tplt_match = $tplt_prefix . $self->{output};
	    $tplt_prefix = $tplt_finalize = '';
	}
    }

    my %usual = (
	die		=> $self->{die},
	prefix_tplt	=> $tplt_prefix,
	match_tplt	=> $tplt_match,
	finalize_tplt	=> $tplt_finalize,
	ors		=> $ors,
    );

    if ( defined $self->{replace} ) {
	$usual{match_tplt} //= '$p$r';
	$usual{replace_tplt} = $self->{replace};
    }

    local $self->{_template} = {
	out	=> ( $self->{color} ? App::Sam::Tplt::Color->new(
		%usual,
		color_colno	=> $self->{color_colno},
		color_filename	=> $self->{color_filename},
		color_lineno	=> $self->{color_lineno},
		color_match	=> $self->{color_match},
		color_ors	=> $self->{ack_mode} ?
		    TERM_ANSI_RESET_COLOR . TERM_ANSI_CLR_EOL :
		    TERM_ANSI_CLR_EOL,
	    ) : App::Sam::Tplt->new( %usual ) ),
    };
    defined $self->{replace}
	and $self->{_template}{repl} = App::Sam::Tplt->new(
	%usual,
	match_tplt	=> '$p$r',
	prefix_tplt	=> '',
	finalize_tplt	=> TPLT_FLUSH,
    );
    defined $self->{underline}
	and $self->{_template}{under} = App::Sam::Tplt::Under->new( %usual );

    my $files_matched;

    # Thanks to David Farrell for the algorithm. Specifically:
    # https://www.perl.com/article/45/2013/10/27/How-to-redirect-and-restore-STDOUT/
    my $pager = -t *STDOUT ? $self->{pager} : undef;
    defined $pager
	and local *STDOUT;
    if ( defined $pager ) {
	my $encoding = $self->__get_encoding();
	open STDOUT, "|-$encoding", $pager
	    or $self->__croak( qq/Unable to pipe to pager "$pager": $!/ );
    }

    foreach my $file ( @files ) {

	my $rslt = ( ref( $file ) || ! -d $file ) ?
	    $self->_process_file( $file ) :
	    $self->_process_dir( $file );
	$files_matched += $rslt;
	$rslt eq STOP
	    and last;
	$self->{_max_files_wanted}
	    and $files_matched >= $self->{max_count}
	    and last;
    }

    $self->{count}
	and not $self->{with_filename}
	and $self->__say( $self->{_total_count} // 0 );

    return $files_matched;
}

# NOTE: Call this ONLY from inside process().
sub _process_dir {
    my ( $self, $file ) = @_;
    my $iterator = $self->__get_file_iterator( $file );
    my $files_matched = 0;
    while ( defined( my $fn = $iterator->() ) ) {
	my $rslt = ( ref( $fn ) || ! -d $fn ) ?
	    $self->_process_file( $fn ) :
	    $self->_process_dir( $fn );
	$files_matched += $rslt;
	$rslt eq STOP
	    and return $self->_process_result( $files_matched );
	# FIXME I think this is buggy. {max_count} should be compared to
	# the total number of files processed, not just the number
	# processed in this directory.
	$self->{_max_files_wanted}
	    and $files_matched >= $self->{max_count}
	    and return $self->_process_result( $files_matched );
    }
    return $files_matched;
}

# NOTE: Call this ONLY from inside process().
sub _process_file {
    my ( $self, $file ) = @_;

    local $self->{_process_file} = {
	filename	=> $file,
    };
    delete $self->{_process_file}{colored};


    $self->{_range}
	and $self->{_process_file}{in_range} = $self->{range_start} ? 0 : 1;

    -e $file
	or do {
	$self->{s}
	    or $self->__carp( "$file: $!" );
	return 0;
    };

    -B _
	and -s _
	and return 0;

    $self->{_process_file}{type} = [ $self->__file_type( $file ) ]
	if $self->{flags} & FLAG_FAC_TYPE;

    $self->{flush}
	and local $| = 1;

    my @show_types;
    # This rigamarole is just to duplicate the ack --show-types output
    # in the case where the file has no type.
    if ( $self->{show_types} ) {
	if ( @{ $self->{_process_file}{type} } ) {
	    @show_types = ( ' ' . join ',', @{ $self->{_process_file}{type} } );
	} else {
	    @show_types = ( '' );
	}
    }

    if ( $self->{flags} & FLAG_FAC_SYNTAX ) {
	if ( my ( $class ) = $self->__file_syntax( $file ) ) {
	    $self->{_process_file}{syntax_obj} =
		$self->{_syntax_obj}{$class} ||=
		"App::Sam::Syntax::$class"->new( die => $self->{die} );
	    $self->{_process_file}{syntax_obj}->init();
	}

	# If --syntax was specified and we did not find a syntax
	# object OR it does not produce the requested syntax, ignore
	# the file.
	if ( $self->{syntax} ) {
	    $self->{_process_file}{syntax_obj}
		or return 0;
	    List::Util::first( sub { $self->{syntax}{$_} },
		$self->{_process_file}{syntax_obj}->__classifications() )
		or return 0;
	}
    }

    $_->filename( $file ) for values %{ $self->{_template} };

    if ( $self->{f} || $self->{g} ) {
	if ( $self->{g} ) {
	    local $_ = $file;
	    $self->_process_unconditional_match()
		or return 0;
	    $file = $self->{_template}{out}->line();
	}
	$self->__say( join ' =>', $file, @show_types );
	return $self->_process_result( 1 );
    }

    my $encoding = $self->__get_encoding( $file );

    my $fh;
    if ( Scalar::Util::openhandle( $file ) ) {
	$fh = $file;
    } else {
	open $fh, "<$encoding", $file	## no critic (RequireBriefOpen)
	    or do {
	    $self->{s}
		or $self->__carp( "Unable to open $file: $!" );
	    return 0;
	};
    }

    my $accumulate = sub {};
    my $mod_fh;
    if ( defined $self->{replace} ) {
	if ( REF_SCALAR eq ref $self->{dry_run} ) {
	    $accumulate = sub {
		${ $self->{dry_run} } .= $_[0]->{_template}{repl}->line();
	    };
	} elsif ( $self->{dry_run} || ref $file ) {
	    # Do nothing
	} else {
	    $mod_fh = File::Temp->new(
		DIR	=> File::Basename::dirname( $file ),
	    );
	    $accumulate = sub {
		print { $mod_fh } $_[0]->{_template}{repl}->line();
	    };
	}
    }

    my $lines_matched = 0;
    local $_ = undef;	# while (<>) does not localize $_
    my @before_context;
    my $last_printed_line;
    my $want_context_break = $self->{before_context} ||
	$self->{after_context};

    while ( <$fh> ) {

	delete $self->{_process_file}{colored};

	$self->{_process_file}{syntax_obj}
	    and $self->{_process_file}{syntax} =
		$self->{_process_file}{syntax_obj}->__classify();

	if ( $self->{_process_file}{matched} = $self->_process_match() ) {
	    if ( $self->{files_with_matches} && ! $self->{count} ) {
		$self->__say( join ' => ',
		    $self->_process_get_filename_for_output(),
		    @show_types,
		);
		return $self->_process_result( 1 );
	    }
	    $lines_matched++;
	}

	$accumulate->( $self );

	if ( $self->_process_display_p() ) {

	    if ( ! $self->{_process_file}{header} ) {
		$self->{_process_file}{header} = 1;
		# NOTE that this will be set already if we are coloring
		# output, but the headings are independent lines.
		local $self->{_process_file}{colored} = 0;

		if ( $self->{_not_first_file} ) {
		    if ( $self->{break} || $self->{proximate} ) {
			$self->__say( '' );
		    } elsif ( ! $self->{heading} && (
			    $self->{after_context} ||
			    $self->{before_context} ) ) {
			$self->__say( '--' );
		    }
		}

		$self->{_not_first_file} = 1;
		$self->{heading}
		    and $self->{with_filename}
		    and $self->__say(
			join ' => ',
			$self->_process_get_filename_for_output(
			    $self->{ack_mode} ),
			@show_types,
		    );
	    }

	    $self->{proximate}
		and defined $self->{_process_file}{last_printed}
		and $. - @before_context - $self->{_process_file}{last_printed} >
		    $self->{proximate}
		and $self->__say( '' );

	    $want_context_break
		and defined $last_printed_line
		and $last_printed_line < $. - @before_context - 1
		and $self->__say( '--' );
	    $last_printed_line = $.;

	    $self->__print( $_ ) for @before_context;
	    $self->{_process_file}{last_printed} = $.;
	    @before_context = ();

	    foreach ( qw{ out under } ) {
		my $tplt = $self->{_template}{$_}
		    or next;
		$self->__print( $tplt->line() );
	    }

	} elsif ( $self->{before_context} ) {

	    push @before_context, $self->{_template}{out}->line();
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
    $mod_fh
	and close $mod_fh;

    if ( $self->{files_without_matches} && ! $lines_matched ) {
	$self->__say( join ' => ', $file, @show_types );
	return $self->_process_result( 1 );
    }

    if ( $self->{count} ) {
	if ( $self->{with_filename} ) {
	    ( $lines_matched || ! $self->{files_with_matches} )
		and $self->__say( join ' => ', sprintf(
		    '%s:%d',
		    $self->_process_get_filename_for_output(),
		    $lines_matched,
		),
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
		"Unable to rename $file to $backup: $!" );
	}

	$mod_fh->unlink_on_destroy( 0 );
	rename "$mod_fh", $file
	    or $self->__croak(
	    "Unable to rename $mod_fh to $file: $!" );
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

    if ( $self->{_process_file}{matched} ) {
	$self->{after_context}
	    and $self->{_process_file}{after_context} =
		$self->{after_context} + 1;
	return 1;
    }

    $self->{_process_file}{after_context}
	and --$self->{_process_file}{after_context}
	and return 1;

    $self->{passthru}
	and return 1;

    return 0;
}

sub _process_get_filename_for_output {
    my ( $self ) = @_;	# $ignore_coloring unused

    return $self->{_process_file}{filename_colored} //= do {
	$self->{_template}{out}->execute_template( '$f' );
    };
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
	and return ( $self->{_munger}->( $self ) xor $self->{invert_match} );

    return $self->_process_unconditional_match(
	$self->_process_match_p() );
}

sub _process_match_p {
    my ( $self ) = @_;

    if ( $self->{_range} ) {
	my $in_range = $self->{_process_file}{in_range};
	$in_range ||= $self->{_process_file}{in_range}
	    while $self->{_range}->( $self );
	$self->{_process_file}{in_range}
	    or $in_range
	    or return $self->{invert_match};
    }

    $self->{not}{match}
	and $self->{not}{match}->()
	and return $self->{invert_match};
    if ( $self->{syntax} && defined $self->{_process_file}{syntax} ) {
	$self->{syntax}{$self->{_process_file}{syntax}}
	    or return $self->{invert_match};
    }

    return undef;	## no critic (ProhibitExplicitReturnUndef)
}

sub _process_unconditional_match {
    my ( $self, $rslt ) = @_;

    # NOTE that suffix 'for()' can not be used here because it clobbers
    # the topic variable
    my $irs = __chomp( $_ );
    $self->{ack_mode}
	and $irs = "\n";
    foreach my $tplt ( values %{ $self->{_template} } ) {
	$tplt->syntax( $self->{_process_file}{syntax} );
	$tplt->irs( $irs );
	$tplt->init();
    }

    # NOTE that if the argument was provided and defined, it means that
    # for some reason no match was to be done.
    $rslt //= do {
	$self->{_munger}->( $self );
	( $self->{_template}{out}->matched() xor $self->{invert_match} );
    };

    # NOTE that suffix 'for()' can not be used here because it clobbers
    # the topic variable
    foreach my $tplt ( values %{ $self->{_template} } ) {
	$tplt->finalize();
    }

    return $rslt;
}

# NOTE that this is to be called only to process a match, including
# exactly once to process a failed match. In practice this means only in
# the subroutine built by __make_munger(), or immediately after this is
# called in _process_match().
sub _process_callback {
    my ( $self ) = @_;
    # NOTE that suffix 'for()' can not be used here because it clobbers
    # the topic variable
    foreach my $tplt ( values %{ $self->{_template} } ) {
	$tplt->match();
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

sub __get_file_iterator {
    my ( $self, @files ) = @_;
    my $descend_filter = $self->{recurse} ? sub {
	! $self->__ignore( directory => $File::Next::dir, $_ );
    } : sub { 0 };
    return File::Next::files( {
	    file_filter	=> sub {
		! $self->__ignore( file => $File::Next::name, $_ ) },
	    follow_symlinks	=> $self->{follow},
	    descend_filter	=> $descend_filter,
	    sort_files	=> $self->{sort_files},
	}, @files );
}

sub __say {
    push @_, $_[0]->{_eol};
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

# Returns true if case-blind and false if not.
# This implementation interprets the ack functionality to detect literal
# upper-case characters. If it has them, the entire match is
# case-sensitive. If it does not, the entire match is case-blind.
# This determination does NOT take into account whether the literals are
# in the scope of a (?i:...). It also does not count upper-case classes
# like [[:upper:]] or \p{Upper_case}.
#
# Interpolation is ignored; the
# contents of the interpolation can not be analyzed statically, but
# something like $FOO does not represent a literal upper-case letter,
# and nor does $foo{BAR}. But interpolation is probably not important in
# the current context, though I might want to consider looking for it
# anyway to prevent its use.
sub __smartcase {
    ( local $_ ) = @_;
    pos = 0;
    while ( pos $_ < length $_ ) {
	m/ \G \\ c . /smxgc		# Control character
	    and next;
	m/ \G \\ x \{ ( \s* [[:xdigit:]]+ ) \s* \} /smxgc	# Hex
	    and _smartcase_ordinal( hex $1 ) ? return RE_CASE_SENSITIVE : next;
	m/ \G \\ x ( [[:xdigit:]]{1,2} ) /smxgc		# Hex
	    and _smartcase_ordinal( hex $1 ) ? return RE_CASE_SENSITIVE : next;
	m/ \G \\ o \{ ( \s* [0-7]+ ) \s* \} /smxgc	# Octal
	    and _smartcase_ordinal( oct $1 ) ? return RE_CASE_SENSITIVE : next;
	m/ \G \\ o ( [0-7]{1,3} ) /smxgc		# Octal
	    and _smartcase_ordinal( oct $1 ) ? return RE_CASE_SENSITIVE : next;
	m/ \G \\ [gk] \{ [^$RCB]+ \} /smxgco	# Named backreference
	    and next;
	m/ \G \\ k < [^$GT]+ > /smxgco	# Named backreference
	    and next;
	m/ \G \\ k ' [^']+ ' /smxgc	# Named backreference
	    and next;
	m/ \G \\ [Bb] \{ [^$RCB]+ \} /smxgco	# Unicode boundary
	    and next;
	m/ \G \\ [Pp] \{ [^$RCB]+ \} /smxgco	# Unicode property
	    and next;
	m/ \G \\ [Pp] . /smxgc			# Unicode property
	    and next;
	m/ \G \\ N \{ ( [^$RCB]+ ) \} /smxgco	# Character by name
	    and _smartcase_named_char( $1 ) ? return RE_CASE_SENSITIVE : next;
	m/ \G \\ u [[:alpha:]] /smxgc	# Uppercase next char
	    and return RE_CASE_SENSITIVE;
	m/ \G \\ U /smxgc		# Uppercase until ...
	    and return RE_CASE_SENSITIVE;	# ... we assume
	m/ \G \\ . /smxgc	# Escaped character
	    and next;

	m/ \G [\$\@] \{ \w+ \} /smxgc	# Interpolation
	    and next;
	m/ \G [\$\@] \w+ /smxgc		# Interpolation
	    and next;
	# FIXME dereference (e.g. $foo{BAR})

	m/ \G \( \? < [^$GT]+ > /smxgco	# Named capture
	    and next;
	m/ \G \( \? ' [^']+ ' /smxgc	# Named capture
	    and next;
	m/ \G \( R [^$RP]+ \) /smxgco	# True if in recursion
	    and next;
	m/ \G \( < [^$GT]+ > /smxgco	# True if name matched
	    and next;
	m/ \G \( ' [^']+ ' /smxgc	# True if name matched
	    and next;

	m/ \G \( \*? [[:upper:]]+ \) /smxgc	# Backtrack control, misc
	    and next;

	m/ \G [^[:upper:]\\$LP]* /smxgc;	# Gobble
	m/ \G [[:upper:]] /smxgc
	    and return RE_CASE_SENSITIVE;
    }
    return RE_CASE_BLIND;
}

sub _smartcase_named_char {
    my ( $name ) = @_;
    $name =~ s/ \A \s+ //smx;
    $name =~ s/ \s+ \z //smx;
    return _smartcase_ordinal( charnames::vianame( $name ) );
}

sub _smartcase_ordinal {
    my ( $ord ) = @_;
    defined $ord
	or return;
    my $char = chr $ord;
    $char eq uc $char
	or return;
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
    my ( $self, $attr_spec, $attr_name ) = @_;	# $attr_val unused
    REF_ARRAY eq ref $attr_spec->{arg}
	or $self->__confess( "$attr_name arg must be an array ref" );
    if ( $attr_spec->{arg}[0] eq $attr_name ) {
	$self->{$attr_name} = $attr_spec->{arg}[1];
	return 1;
    } else {
	return $self->__set_attr( @{ $attr_spec->{arg} } );
    }
}

sub __validate_argv {
    my ( $self, undef, undef, $attr_val ) = @_;	# $attr_spec, $attr_name unused
    REF_ARRAY eq ref $attr_val
	or $attr_val = [ $attr_val ];
    $self->__get_attr_from_resource( App::Sam::Resource->new(
	    name	=> 'ARGV',
	    data	=> $attr_val,
	    from	=> $self->{_rc_name},
	    # getopt	=> 0,
	    indent	=> 0,
	    orts	=> $self->{argv},
	),
    );
    return 1;
}

sub __validate_color {
    my ( $self, undef, $attr_name, $attr_val ) = @_;	# $attr_spec unused
    Term::ANSIColor::colorvalid( $attr_val )
	or return 0;
    $self->{$attr_name} = $attr_val;
    return 1;
}

sub __validate_defer_boolean {
    my ( $self, undef, $attr_name, $attr_val ) = @_;	# $attr_spec unused

    if ( $self->{$attr_name} xor $attr_val ) {
	$self->{_defer}{$attr_name} = $attr_val;
    # NOTE that the double test is to avoid auto-vivifying
    # $self->{_defer}.
    } elsif ( exists $self->{_defer} && exists $self->{_defer}{$attr_name} ) {
	delete $self->{_defer}{$attr_name};
	keys %{ $self->{_defer} }
	    or delete $self->{_defer};
    }

    return 1;
}

sub __validate_define {
    my ( $self, undef, undef, $attr_val ) = @_;	# $attr_spec, $attr_name unused
    ref $attr_val
	or $attr_val = [ $attr_val ];
    REF_ARRAY eq ref $attr_val
	or return 0;
    foreach ( @{ $attr_val } ) {
	my ( $def_name, $def_val ) = split /:=/, $_, 2;
	( my $def_key = $def_name ) =~ s/ [|:=!] .* //smx;
	if ( defined $def_val ) {
	    my @expansion = Text::ParseWords::shellwords( $def_val );
	    my $type = $def_name =~ m/([:=!].*)/ ? $1 : '';
	    $self->{define}{$def_key} = {
		name	=> $def_name,
		arg	=> \@expansion,
		type	=> $type,
		flags	=> 0,
	    };
	} else {
	    delete $self->{define}{$def_name}
		or return 0;
	}
    }
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

	# Handle old-style ack file type definitions.
	unless( defined $kind ) {
	    ( $prop_val, $data ) = split /=\./, $_, 2;
	    $kind = 'ext';
	}

	$validate_prop_val->( $self, $prop_val )
	    or return 0;

	defined $data
	    or ( $kind, $data ) = ( is => $kind );

	state $validate_kind = {
	    ext	=> sub {
		my ( $self, $prop_name, $prop_val, $data ) = @_;
		my @item = split /,/, __fold_case( $data );
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

    push @{ $self->{$attr_name} }, ref $attr_val ? @{ $attr_val } : $attr_val;

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

# If arg is true, we assume delete of the named spec
sub __validate_ignore {
    my ( $self, $attr_spec, $attr_name, $attr_val ) = @_;
    foreach ( ref $attr_val ? @{ $attr_val } : $attr_val ) {
	my ( $kind, $data ) = split /:/, $_, 2;
	defined $data
	    or ( $kind, $data ) = ( is => $kind );
	state $validate_kind = {
	    ext	=> sub {
		my ( $self, $attr_spec, $attr_name, $data ) = @_;
		my @item = split /,/, $data;
		if ( my $name = $attr_spec->{arg} ) {
		    delete $self->{$name}{ext}{$_} for @item;
		} else {
		    @{ $self->{$attr_name}{ext} }{ @item } = ( ( 1 ) x @item );
		}
		return 1;
	    },
	    is	=> sub {
		my ( $self, $attr_spec, $attr_name, $data ) = @_;
		$attr_name eq 'ignore_directory'
		    and $data =~ s( [$DIR_SEP] \z )()smxo;
		if ( my $name = $attr_spec->{arg} ) {
		    delete $self->{$name}{is}{$data};
		    # NOTE the comment above in __ignore() about
		    # ignoring paths. I observe that in ack a
		    # --no-ignore-*=is:base_name also deletes entries
		    # for relative paths with that base name. Hence this
		    # loop.
		    foreach my $path ( keys %{ $self->{$name}{is} } ) {
			$data eq ( File::Spec->splitpath( $path ))[2]
			    and delete $self->{$name}{is}{$path};
		    }
		} else {
		    $self->{$attr_name}{is}{$data} = 1;
		}
		return 1;
	    },
	    match	=> sub {
		my ( $self, $attr_spec, $attr_name, $data ) = @_;
		if ( my $name = $attr_spec->{arg} ) {
		    @{ $self->{$name}{match} } =
			grep { $_ ne $data }
			@{ $self->{$name}{match} };
		} else {
		    local $@ = undef;
		    eval "qr $data"	## no critic (ProhibitStringyEval)
			or return 0;
		    push @{ $self->{$attr_name}{match} }, $data;
		}
		return 1;
	    },
	};
	my $code = $validate_kind->{$kind}
	    or return 0;
	$code->( $self, $attr_spec, $attr_name, $data )
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

sub __validate_perldoc {
    my ( $self, undef, undef, $attr_val ) = @_;	# $attr_spec, $attr_name unused
    $attr_val eq ''
	and $attr_val = 'all';
    state $expand = { Text::Abbrev::abbrev( qw{ all core delta faq } ) };
    defined( my $xv = $expand->{$attr_val} )
	or return 0;
    $self->{perldoc} = $xv;
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

sub __validate_samrc {
    my ( $self, undef, undef, $attr_val ) = @_;	# $attr_spec, $attr_name unused
    my @argz = ref $attr_val ? (
	name	=> 'samrc',
	data	=> $attr_val,
    ) : (
	name	=> $attr_val,
    );
    defined $self->{_rc_name}
	and push @argz, from => $self->{_rc_name};
    $self->__get_attr_from_resource( App::Sam::Resource->new(
	    @argz,
	    required	=> 1,
	) );
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
    my ( $self, $attr_spec, undef, $attr_val ) = @_;	# $attr_name unused
    foreach ( ref $attr_val ? @{ $attr_val } : $attr_val ) {
	my $type = $_;
	if ( $self->{_type_def}{$type} ) { 
	    $self->{type}{$type} = $attr_spec->{arg} ? TYPE_NOT_WANTED :
		TYPE_WANTED;
	} elsif ( $type =~ s/ \A no-? //smxi && (
		$self->{_type_def}{$type} ) ) {
	    $self->{type}{$type} = $attr_spec->{arg} ? TYPE_WANTED :
		TYPE_NOT_WANTED;
	} else {
	    return 0;
	}
	$self->{type}{$type} == TYPE_WANTED
	    and $self->{_type_wanted} = 1;
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

=item C<ack_mode>

See L<--ack-mode|sam/--ack-mode> in the L<sam|sam> documentation.

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

=item C<define>

See L<--define|sam/--define> in the L<sam|sam> documentation. You can
pass a definition as a scalar, or multiple definitions as an array
reference.

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

A value of C<''> or C<undef> specifies no encoding (i.e. use the system
encoding). This is equivalent to L<--no-encoding|sam/--no-encoding>.

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

=item C<filter>

See L<--filter|sam/--filter> in the L<sam|sam> documentation. The
default is true if F<STDIN> is a pipe; otherwise it is false.

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

=item C<match_case>

This enumerated value specifies how the L<match|/match> expression
handles case. Possible values are
L<RE_CASE_BLIND|App::Sam::Util/RE_CASE_BLIND>,
L<RE_CASE_SENSITIVE|App::Sam::Util/RE_CASE_SENSITIVE>, and
L<RE_CASE_SMART|App::Sam::Util/RE_CASE_SMART>, which are documented in
L<App::Sam::Util|App::Sam::Util>.

There is no option corresponding to this argument. Instead, these values
correspond to L<sam|sam> options
L<--ignore-case|sam/--ignore-case>,
L<--no-ignore-case|sam/--no-ignore-case>, and
L<--smart-case|sam/--smart-case> respectively.

=item C<max_count>

See L<--max-count|sam/--max-count> in the L<sam|sam> documentation.

=item C<no_ignore_directory>

See L<--no-ignore-directory|sam/--no-ignore-directory> in the L<sam|sam>
documentation.

=item C<no_ignore_file>

See L<--no-ignore-file|sam/--no-ignore-file> in the L<sam|sam>
documentation.

=item C<not>

See L<--not|sam/--not> in the L<sam|sam> documentation. The value is a
reference to an array.

=item C<output>

See L<--output|sam/--output> in the L<sam|sam> documentation. The value
is a template as described in that documentation.

=item C<pager>

See L<--pager|sam/--pager> in the L<sam|sam> documentation.

A value of C<undef> specifies no pager. This is equivalent to
L<--no-pager|sam/--no-pager>.

=item C<passthru>

See L<--passthru|sam/--passthru> in the L<sam|sam> documentation.

=item C<perldoc>

See L<--perldoc|sam/--perldoc> in the L<sam|sam> documentation.

=item C<print0>

See L<--print0|sam/--print0> in the L<sam|sam> documentation.

=item C<proximate>

See L<--proximate|sam/--proximate> in the L<sam|sam> documentation.

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

=head2 file_type_is

 if ( defined $sam->file_type_is( $path, 'perl' ) ) { ... }

This method takes as its arguments a path to a file, and a file type. If
the file is of the specified type it returns that type, otherwise it
returns C<undef>.

B<Note> that omitting the C<defined> in the above example will produce
incorrect behavior if you have defined (and actually ask for) file types
C<''> or C<'0'>.

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

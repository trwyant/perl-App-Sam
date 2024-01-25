package App::Sam;

use 5.010001;

use strict;
use warnings;

use utf8;

use App::Sam::Util qw{ :carp __syntax_types @CARP_NOT };
use File::Next ();
use File::Spec;
use Errno qw{ :POSIX };
use File::ShareDir;
use Getopt::Long ();
use List::Util ();
use Module::Load ();
use Readonly;
use Term::ANSIColor ();
use Text::Abbrev ();

our $VERSION = '0.000_001';

use constant CLR_EOL	=> "\e[K";

use constant IS_WINDOWS	=> {
    MSWin32	=> 1,
}->{$^O} || 0;

use constant REF_ARRAY	=> ref [];

use enum qw{ BITMASK:FLAG_ IS_ATTR IS_OPT PROCESS_EARLY
    PROCESS_NORMAL PROCESS_LATE };
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
	env		=> $priority_arg{env} // 1,
	recurse		=> 1,
	sort_files	=> 1,
    }, $class;

    if ( REF_ARRAY eq ref $argv ) {
	$self->__get_option_parser( 1 )->getoptionsfromarray( $argv,
	    $self, $self->__get_opt_specs( FLAG_PROCESS_EARLY ) );
    } elsif ( defined $argv ) {
	$self->__croak( 'Argument argv must be an ARRAY reference' );
    }

    @bad_arg
	and $self->__croak( "Unknown new() arguments @bad_arg" );

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
	$self->{$attr_name} = $attr_val;
    }

    $argv
	and $self->__get_attr_from_rc( $argv );

    $self->__incompat_arg( qw{ f match } );
    $self->__incompat_arg( qw{ f g replace } );
    $self->__incompat_arg( qw{ count passthru } );

    unless ( $self->{f} || defined $self->{match} ) {
	if ( $argv && @{ $argv } ) {
	    $self->{match} = shift @{ $argv };
	} else {
	    $self->__croak( 'No match string specified' );
	}
    }


    {
	no warnings qw{ once };
	$Carp::Verbose
	    and delete $self->{die};
    }

    defined $self->{replace}
	and delete $self->{color};

    defined $self->{backup}
	and $self->{backup} eq ''
	and delete $self->{backup};

    foreach my $name ( qw{ ignore_file ignore_directory not } ) {
	my $alias = "_$name";
	$self->{$alias}	# Prevent autovivification
	    and $self->{$alias}{match}
	    or next;
	my $str = join ' || ', map { "m $_" }
	    List::Util::uniqstr( @{ $self->{$alias}{match} } );
	my $code = eval "sub { $str }"	## no critic (ProhibitStringyEval)
	    or $self->__confess( "Failed to compile $name match spec" );
	$self->{$alias}{match} = $code;
    }

    foreach my $prop ( qw{ syntax type } ) {

	my $attr = "_${prop}_add";
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

    defined $self->{match}
	and $self->__make_munger();

    return $self;
}

sub create_samrc {
    my ( $self, $exit ) = @_;
    $exit //= caller eq __PACKAGE__;
    my $default_file = $self->__get_attr_default_file_name();
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
    } elsif ( $self->{_files_from} && @{ $self->{_files_from} } ) {
	return $self->files_from( @{ $self->{_files_from} || [] } );
    }
    return;
}

sub _file_property {
    ( my ( $self, $property, $path ), local $_ ) = @_;
    my $prop_spec = $self->{"_${property}_add"} || {};
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
    foreach my $type ( keys %{ $self->{_syntax_add}{type} } ) {
	$syntax eq $self->{_syntax_add}{type}{$type}
	    and delete $self->{_syntax_add}{type}{$type};
    }
    return;
}

sub __file_type {
    my ( $self, @arg ) = @_;
    return $self->_file_property( type => @arg );
}

sub __file_type_del {
    my ( $self, $type, $really ) = @_;
    my $def = $self->{_type_add};
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
	delete $self->{_syntax_add}{type}{$type};
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
    #         NOTE that the FLAG_PROCESS_* items only apply to
    #         attributes, and therefore imply FLAG_IS_ATTR. Optional. If
    #         not provided, the default is FLAG_IS_ATTR | FLAG_IS_OPT |
    #         FLAG_PROCESS_NORMAL.
    my %attr_spec_hash = (
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
	break	=> {
	    type	=> '!',
	},
	color	=> {
	    type	=> '!',
	    alias	=> [ qw{ colour } ],
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
	},
	g	=> {
	    type	=> '!',	# The expression comes from --match.
	},
	files_from	=> {
	    type	=> '=s@',
	    validate	=> '__validate_files_from',
	},
	filter_files_from	=> {
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
	},
	literal	=> {
	    type	=> '!',
	    alias	=> [ 'Q' ],
	},
	n		=> {
	    type	=> '!',
	    validate	=> '__validate_inverted_value',
	    arg		=> 'recurse',
	},
	not		=> {
	    type	=> '=s@',
	    validate	=> '__validate_not'
	},
	passthru	=> {
	    type	=> '!',
	    alias	=> [ 'passthrough' ],
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
	samrc	=> {
	    type	=> '=s',
	    flags	=> FLAG_IS_OPT | FLAG_PROCESS_LATE,
	},
	show_syntax	=> {
	    type	=> '!',
	},
	show_types	=> {
	    type	=> '!',
	},
	sort_files	=> {
	    type	=> '!',
	},
	syntax	=> {
	    type	=> '=s@',
	    validate	=> '__validate_syntax',
	},
	type	=> {
	    type	=> '=s@',
	    alias	=> [ 't' ],
	    validate	=> '__validate_type',
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
	help_types	=> {
	    type	=> '',
	    validate	=> 'help_types',
	},
	help_syntax	=> {
	    type	=> '',
	    validate	=> 'help_syntax',
	},
    );

    foreach my $key ( keys %attr_spec_hash ) {
	my $val = $attr_spec_hash{$key};
	$val->{name} = $key;
	if ( $key =~ m/ _ /smx ) {
	    ( my $alias = $key ) =~ s/ _ /-/smxg;
	    push @{ $val->{alias} }, $alias;
	}
	if ( $val->{flags} ) {
	    if ( $val->{flags} & ( FLAG_PROCESS_EARLY |
		    FLAG_PROCESS_NORMAL | FLAG_PROCESS_LATE ) ) {
		$val->{flags} |= FLAG_IS_ATTR;
	    }
	} elsif ( ! defined $val->{flags} ) {
	    $val->{flags} = FLAG_IS_ATTR | FLAG_IS_OPT | FLAG_PROCESS_NORMAL;
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
	unless ( REF_ARRAY eq ref $file ) {
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
		    push @{ $arg }, $_;
		}
		close $fh;
		$rc_cache{$file} = [ @{ $arg } ];
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
    my $method;
    defined( $method = $attr_spec->{validate} )
	or return;
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

# Validate an attribute given its name and value
sub __validate_attr {
    my ( $self, $name, $value ) = @_;
    my $attr_spec = $ATTR_SPEC{$name}
	or $self->__confess( "Unknown attribute '$name'" );
    if ( my $code = $self->__get_validator( $attr_spec ) ) {
	$code->( $name, $value )
	    or return 0;
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
    my @have = grep { exists $self->{$_} } @opt;
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
    my $modifier = 'g';
    $self->{ignore_case}
	and $modifier .= 'i';
    my $match = $self->{match};
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
    if ( defined( my $repl = $self->{replace} ) ) {
	$self->{literal}
	    and $repl = quotemeta $repl;
	$repl =~ s/ (?= [()] ) /\\/smxg;
	$str = "s($match)($repl)$modifier";
	$code = eval "sub { $str }"	## no critic (ProhibitStringyEval)
	    or $self->__croak( "Invalid replace '$repl': $@" );
    } elsif ( $self->{color} ) {
	$str = "s(($match))( \$_[0]->__color( match => \$1 ) )e$modifier";
	$code = eval "sub { $str }"	## no critic (ProhibitStringyEval)
	    or $self->__confess( "Generated bad coloring code: $@" );
    }
    $self->{munger} = $str;
    $self->{_munger} = $code;
    return;
}

sub __me {
    state $me = ( File::Spec->splitpath( $0 ) )[2];
    return $me;
}

sub __ignore {
    ( my ( $self, $kind, $path ), local $_ ) = @_;
    my $prop_spec = $self->{"_ignore_$kind"}
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
    if ( $kind eq 'file' && $self->{_type} ) {

	# Encoding: undef = unspecified, 0 = accept, 1 = skip
	my $want_type;
	foreach my $type ( $self->__file_type( $path, $_ ) ) {
	    my $skip = $self->{_type}{$type}
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
    # NOTE that ack uses "\e[0m\e[K" here. But "\e[K" suffices for me.
    $self->{_process}{colored}
	and $line =~ s/ (?= \n ) / CLR_EOL /smxge;
    print $line;
    return;
}

sub process {
    my ( $self, $file ) = @_;

    local $self->{_process} = {};

    if ( ref( $file ) || ! -d $file ) {

	-T $file
	    or return;

	$self->{_process}{type} = [ $self->__file_type( $file ) ]
	    if $self->{show_types} || $self->{known_types} ||
		$self->{_syntax} || $self->{show_syntax};

	$self->{known_types}
	    and not @{ $self->{_process}{type} }
	    and return;

	my @show_types;
	$self->{show_types}
	    and push @show_types, join ',', @{ $self->{_process}{type} };

	if ( $self->{_syntax} || $self->{show_syntax} ) {
	    if ( my ( $class ) = $self->__file_syntax( $file ) ) {
		$self->{_process}{syntax_obj} =
		    $self->{_syntax_obj}{$class} ||=
		    "App::Sam::Syntax::$class"->new( die => $self->{die} );
	    }

	    # If --syntax was specified and we did not find a syntax
	    # object OR it does not produce the requested syntax, ignore
	    # the file.
	    if ( $self->{_syntax} ) {
		$self->{_process}{syntax_obj}
		    or return;
		List::Util::first( sub { $self->{_syntax}{$_} },
		    $self->{_process}{syntax_obj}->__classifications() )
		    or return;
	    }
	}

	my $munger = $self->{_munger};

	if ( $self->{f} || $self->{g} ) {
	    if ( $self->{g} ) {
		local $_ = $file;
		$munger->( $self ) xor $self->{invert_match}
		    or return;
	    }
	    say join ' => ', $file, @show_types;
	    return;
	}

	my @mod;
	my $encoding = $self->__get_encoding( $file );
	open my $fh, "<$encoding", $file	## no critic (RequireBriefOpen)
	    or $self->__croak( "Failed to open $file for input: $!" );
	my $lines_matched = 0;
	local $_ = undef;	# while (<>) does not localize $_
	while ( <$fh> ) {

	    delete $self->{_process}{colored};

	    $self->{_process}{syntax_obj}
		and $self->{_process}{syntax} =
		    $self->{_process}{syntax_obj}->__classify();

	    $self->{_process}{matched} = $self->_process_match()
		and $lines_matched++;

	    if ( $self->_process_display_p() ) {
		if ( ! $self->{_process}{header} ) {
		    $self->{_process}{header} = 1;
		    $self->{break}
			and say '';
		    $self->{heading}
			and $self->__say(
			    join ' => ',
			    $self->__color( filename => $file ),
			    @show_types,
			);
		}

		my @line;
		$self->{heading}
		    or push @line, ( $self->{_process}{filename} //=
		    $self->__color( filename => $file ) );
		push @line, $self->__color( lineno => $. );
		$self->{show_syntax}
		    and push @line,
			substr $self->{_process}{syntax} // '', 0, 4;
		$self->__print( join ':', @line, $_ );
	    }

	    push @mod, $_;
	}
	close $fh;

	$self->{count}
	    and say join ' => ',
		sprintf( '%s:%d', $self->__color( filename => $file ),
		    $lines_matched ), @show_types;

	if ( defined( $self->{replace} ) && ! $self->{dry_run} &&
	    $lines_matched && ! ref $file
	) {
	    if ( defined $self->{backup} ) {
		my $backup = "$file$self->{backup}";
		rename $file, $backup
		    or $self->__croak(
		    "Unable to rename $file to $backup: $!" );
	    }
	    open my $fh, ">$encoding", $file
		or $self->__croak( "Failed to open $file for output: $!" );
	    print { $fh } @mod;
	    close $fh;
	}

	defined wantarray
	    and return join '', @mod;
    } else {
	my $iterator = $self->__get_file_iterator( $file );
	while ( defined( my $fn = $iterator->() ) ) {
	    $self->process( $fn );
	}
    }
    return;
}

# NOTE: Call this ONLY from inside process(). This is broken out because
# I expect it to get complicated if I implement match inversion,
# context, etc.
sub _process_display_p {
    my ( $self ) = @_;

    $self->{count}
	and return 0;

    $self->{passthru}
	and return 1;

    return $self->{_process}{matched} || 0;
}

# NOTE: Call this ONLY from inside process(). This is broken out because
# I expect it to get complicated if I implement ranges, syntax, etc.
# NOTE ALSO: the current line is in $_.
sub _process_match {
    my ( $self ) = @_;
    $self->{_not}{match}
	and $self->{_not}{match}->()
	and return $self->{invert_match};
    if ( $self->{_syntax} && defined $self->{_process}{syntax} ) {
	$self->{_syntax}{$self->{_process}{syntax}}
	    or return $self->{invert_match};
    }
    return( $self->{_munger}->( $self ) xor $self->{invert_match} );
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
		push @{ $self->{"_${prop_name}_add"}{ext}{$_} }, $prop_val
		    for @item;
		push @{ $self->{"_${prop_name}_def"}{$prop_val}{ext} },
		    map { ".$_" } @item;
		return 1;
	    },
	    is	=> sub {
		my ( $self, $prop_name, $prop_val, $data ) = @_;
		push @{ $self->{"_${prop_name}_add"}{is}{$data} }, $prop_val;
		push @{ $self->{"_${prop_name}_def"}{$prop_val}{is} }, $data;
		return 1;
	    },
	    match	=> sub {
		my ( $self, $prop_name, $prop_val, $data ) = @_;
		local $@ = undef;
		my $code = eval "sub { $data }"	## no critic (ProhibitStringyEval)
		    or return 0;
		push @{ $self->{"_${prop_name}_add"}{match} },
		    [ $prop_val, $code, "$prop_val:$data" ];
		push @{ $self->{"_${prop_name}_def"}{$prop_val}{match} }, $data;
		return 1;
	    },
	    firstlinematch	=> sub {
		my ( $self, $prop_name, $prop_val, $data ) = @_;
		local $@ = undef;
		my $code = eval "sub { $data }"	## no critic (ProhibitStringyEval)
		    or return 0;
		push @{ $self->{"_${prop_name}_add"}{firstlinematch} },
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
		    $self->{"_${prop_name}_add"}{type}{$_} = $prop_val;
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
	push @{ $self->{"_$attr_name"} }, $_;
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
		@{ $self->{"_$attr_name"}{ext} }{ @item } = ( ( 1 ) x @item );
		return 1;
	    },
	    is	=> sub {
		my ( $self, $attr_name, $data ) = @_;
		$self->{"_$attr_name"}{is}{$data} = 1;
		return 1;
	    },
	    match	=> sub {
		my ( $self, $attr_name, $data ) = @_;
		local $@ = undef;
		eval "qr $data"	## no critic (ProhibitStringyEval)
		    or return 0;
		push @{ $self->{"_$attr_name"}{match} }, $data;
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
	# {_not}, but the {match} means I can process this with the same
	# code that processes ignore_directory and ignore_file.
	push @{ $self->{"_$attr_name"}{match} }, "($_)";
    }
    return 1;
}

sub __validate_syntax {
    my ( $self, undef, undef, $attr_val ) = @_;	# $attr_spec, $attr_name unused
    foreach ( ref $attr_val ? @{ $attr_val } : $attr_val ) {
	state $valid = Text::Abbrev::abbrev( __syntax_types() );
	my $expansion = $valid->{$_}
	    or return 0;
	$self->{_syntax}{$expansion} = 1;
    }
    return 1;
}

sub __validate_type {
    my ( $self, undef, undef, $attr_val ) = @_;	# $attr_spec, $attr_name unused
    foreach ( ref $attr_val ? @{ $attr_val } : $attr_val ) {
	my $neg;
	if ( $self->{_type_def}{$_} ) { 
	    $self->{_type}{$_} = 0;
	} elsif ( ( $neg = $_ ) =~ s/ \A no-? //smxi && (
		$self->{_type_def}{$neg} ) ) {
	    $self->{_type}{$neg} = 1;
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

=item C<break>

See L<--break|sam/--break> in the L<sam|sam> documentation. The default
is false.

=item C<color>

See L<--color|sam/--color> in the L<sam|sam> documentation. The default
is false.

=item C<color_filename>

See L<--color-filename|sam/--color-filename> in the L<sam|sam> documentation.

=item C<color_lineno>

See L<--color-lineno|sam/--color-lineno> in the L<sam|sam> documentation.

=item C<color_match>

See L<--color-match|sam/--color-match> in the L<sam|sam> documentation.

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

=item C<encoding>

See L<--encoding|sam/--encoding> in the L<sam|sam> documentation.

=item C<env>

See L<--env|sam/--env> in the L<sam|sam> documentation.

=item C<f>

See L<-f|sam/-f> in the L<sam|sam> documentation.

=item C<files_from>

See L<--files-from|sam/--files-from> in the L<sam|sam> documentation.

B<Note> that the files are not actually read until
L<files_from()|/files_from> is called. The only validation before that
is that the C<-r> operator must report them as readable, though this is
not definitive in the presence of Access Control Lists.

=item C<filter_files_from>

See L<--filter-files-from|sam/--filter-files-from> in the L<sam|sam>
documentation.

=item C<follow>

See L<--follow|sam/--follow> in the L<sam|sam> documentation.

=item C<g>

See L<-g|sam/-g> in the L<sam|sam> documentation. B<Note> that as an
argument to C<new()>, C<g> is a Boolean flag. The match string is
specified in argument L<C<match>|/match>

=item C<heading>

See L<--heading|sam/--heading> in the L<sam|sam> documentation.

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

=item C<literal>

See L<--literal|sam/--literal> in the L<sam|sam> documentation.

=item C<match>

See L<--match|sam/--match> in the L<sam|sam> documentation. If legal but
not specified, the first non-option argument in C<argv> will be used.

=item C<not>

See L<--not|sam/--not> in the L<sam|sam> documentation. The value is a
reference to an array.

=item C<passthru>

See L<--passthru|sam/--passthru> in the L<sam|sam> documentation.

=item C<recurse>

See L<--recurse|sam/--recurse> in the L<sam|sam> documentation.

=item C<replace>

See L<--replace|sam/--replace> in the L<sam|sam> documentation.

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

=item C<word_regexp>

See L<--word-regexp|sam/--word-regexp> in the L<sam|sam> documentation.

=back

=head2 create_samrc

 $sam->create_samrc( $exit )

This method prints the default configuration to C<STDOUT>. If the
argument is true, it exits. Otherwise it returns. The default for
C<$exit> is true if called from the C<$sam> object.

=head2 files_from

Given the name of one or more files, this method reads them and returns
its contents, one line at a time, and C<chomp>-ed. These are assumed to
be file names, and will be filtered if C<filter_files_from> is true.

If called without arguments, reads the files specified by the
C<files_from> argument to L<new()|/new>, if any, and returns their
possibly-filtered contents.

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

 $sam->process( $file )

This method processes a single file or directory. Match output is
written to F<STDOUT>. If any files are modified, the modified file is
written.

The argument can be a scalar reference, but in this case modifications
are not written.

Binary files are ignored.

If the file is a directory, any files in the directory are processed
provided they are not ignored. Nothing is returned.

If the file is not a directory and is actually processed, its contents
(possibly modified) will be returned. Otherwise nothing is returned.

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

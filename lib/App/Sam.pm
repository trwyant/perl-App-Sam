package App::Sam;

use 5.010001;

use strict;
use warnings;

use utf8;

use App::Sam::Util qw{ :carp __syntax_types @CARP_NOT };
use File::Next ();
use File::Spec;
use Errno qw{ :POSIX };
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

sub new {
    my ( $class, %arg ) = @_;

    my $argv = delete $arg{argv};

    my $self = bless {
	ignore_sam_defaults	=> delete $arg{ignore_sam_defaults},
	env			=> delete $arg{env},
    }, $class;

    $argv
	and not REF_ARRAY eq ref $argv
	and $self->__croak( 'Argument argv must be an ARRAY reference' );

    $self->__get_attr_defaults();
    $self->{ignore_sam_defaults}	# Chicken-and-egg problem
	and %{ $self } = (
	    ignore_sam_defaults => $self->{ignore_sam_defaults}
	);

    foreach my $file ( $self->__get_rc_file_names() ) {
	$self->__get_attr_from_rc( $file );
    }

    if ( my $file = delete $arg{samrc} ) {
	$self->__get_attr_from_rc( $file, 1 );	# Required to exist
    }

    foreach my $name ( $self->__get_attr_names() ) {
	exists $arg{$name}
	    or next;
	$self->__validate_attr( $name, $arg{$name} )
	    or $self->__croak( "Invalid $name value '$arg{$name}'" );
	$self->{$name} = delete $arg{$name};
    }

    $argv
	and $self->__get_attr_from_rc( $argv );

    $self->__incompat_arg( qw{ f match } );
    $self->__incompat_arg( qw{ f replace } );
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

    keys %arg
	and $self->__croak( 'Invalid arguments to new()' );

    defined $self->{replace}
	and delete $self->{color};

    foreach my $name ( qw{ ignore_file ignore_directory } ) {
	my $alias = "_$name";
	$self->{$alias}{match}
	    or next;
	my $str = join ' || ', List::Util::uniqstr( @{ $self->{$alias}{match} } );
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
    $text eq ''
	and return $text;
    defined( my $color = $self->{"color_$kind"} )
	or $self->__confess( "Invalid color kind '$kind'" );
    return Term::ANSIColor::colored( $text, $color );
}

sub files_from {
    my ( $self, @file_list ) = @_;
    if ( @file_list ) {
	my @rslt;
	foreach my $file ( @file_list ) {
	    my $encoding = $self->__get_encoding( $file, 'utf-8' );
	    local $_ = undef;	# while (<>) does not localize $_
	    open my $fh, "<$encoding", $file	## no critic (RequireBriefOpen)
		or $self->__croak( "Failed to open $file: $!" );
	    while ( <$fh> ) {
		m/ \S /smx
		    or next;
		chomp;
		$self->{filter_files_from}
		    and $self->__ignore( file => $_ )
		    and next;
		push @rslt, $_;
	    }
	    close $fh;
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

our @ATTR_SPEC_LIST;
our %ATTR_SPEC_HASH;
{
    # The following keys are defined:
    # {name} - the name of the attribute, with underscores rather than
    #         dashes. This is required.
    # {type} - the type of the associated option, expressed as a
    #         GetOpt::Long suffix. Required.
    # {default} - The default value of the attribute. Optional.
    # {alias} - A reference to an array of aliases to the option. The
    #         variants with dashes rather than underscores need not be
    #         specified here as they will be generated. Optional.
    # {validate} - The name of the method used to validate the option.
    #         Optional.
    # {argument_only} - A true value means this is only an argument to
    #         new(), and no corresponding option will be generated.
    #         Optional.
    # {back_end} - The name of an attribute that corresponds to this
    #         option. If the {validate} key is present it represents the
    #         name of a method to transform the value before it is
    #         processed as the {back_end} attribute. It is the
    #         responsibility of this method to set the back-end
    #         attribute if it has no {validate} method. Optional.
    # {option_only} - A true value means this is only an option, and
    #         there is no corresponding attribute. It is up to the
    #         {validate} method to ensure that the value of this option
    #         is taken into account.
    no warnings qw{ qw };	## no critic (ProhibitNoWarnings)
    my @attr_spec_list = (
	{
	    name	=> 'backup',
	    type	=> '=s',
	    default	=> '',
	},
	{
	    name	=> 'break',
	    type	=> '!',
	},
	{
	    name	=> 'color',
	    type	=> '!',
	    alias	=> [ qw{ colour } ],
	},
	{
	    name	=> 'color_filename',
	    type	=> '=s',
	    default	=> 'bold green',
	    validate	=> '__validate_color',
	},
	{
	    name	=> 'color_lineno',
	    type	=> '=s',
	    default	=> 'bold yellow',
	    validate	=> '__validate_color',
	},
	{
	    name	=> 'color_match',
	    type	=> '=s',
	    default	=> 'black on_yellow',
	    validate	=> '__validate_color',
	},
	{
	    name	=> 'count',
	    type	=> '!',
	},
	{
	    name	=> 'die',
	    argument_only	=> 1,
	    type	=> '!',
	},
	{
	    name	=> 'dry_run',
	    type	=> '!',
	},
	{
	    name	=> 'encoding',
	    type	=> '=s',
	    default	=> 'utf-8',
	},
	{
	    name	=> 'f',
	    type	=> '!',
	},
	{
	    name	=> 'files_from',
	    type	=> '=s@',
	    validate	=> '__validate_files_from',
	},
	{
	    name	=> 'filter_files_from',
	    type	=> '!',
	},
	{
	    alias	=> [ qw{ i } ],
	    name	=> 'ignore_case',
	    type	=> '!',
	},
	{
	    name	=> 'I',
	    type	=> '|',
	    back_end	=> 'ignore_case',
	    validate	=> '__preprocess_logical_negation',
	},
	{
	    name	=> 'ignore_directory',
	    type	=> '=s@',
	    default	=> [ qw{ is:.bzr is:.cdv is:~.dep is:~.dot
		is:~.nib is:~.plst is:.git is:.hg is:.pc is:.svn is:_MTN
		is:CVS is:RCS is:SCCS is:_darcs is:_sgbak
		is:autom4te.cache is:blib is:_build is:cover_db
		is:node_modules is:CMakeFiles is:.metadata
		is:.cabal-sandbox is:__pycache__ is:.pytest_cache
		is:__MACOSX is:.vscode } ],
	    validate	=> '__validate_ignore',
	},
	{
	    name	=> 'ignore_file',
	    type	=> '=s@',
	    default	=> [ qw{ is:.git is:.DS_Store ext:bak match:/~$/
		match:/^#.+#$/ match:/[._].*[.]swp$/ match:/core[.]\d+$/
		match:/[.-]min[.]js$/ match:/[.]js[.]min$/
		match:/[.]min[.]css$/ match:/[.]css[.]min$/
		match:/[.]js[.]map$/ match:/[.]css[.]map$/ ext:pdf
		ext:gif,jpg,jpeg,png ext:gz,tar,tgz,zip ext:pyc,pyd,pyo
		ext:pkl,pickle ext:so ext:mo } ],
	    validate	=> '__validate_ignore',
	},
	{
	    name	=> 'invert_match',
	    type	=> '!',
	    alias	=> [ 'v' ],
	},
	{
	    name	=> 'known_types',
	    type	=> '!',
	    alias	=> [ 'k' ],
	},
	{
	    name	=> 'literal',
	    type	=> '!',
	    alias	=> [ 'Q' ],
	},
	{
	    name	=> 'passthru',
	    type	=> '!',
	    alias	=> [ 'passthrough' ],
	},
	{
	    name	=> 'type_add',	# NOTE: Must come before type
	    type	=> '=s@',
	    default	=> [ qw{ make:ext:mk make:ext:mak
		make:is:makefile make:is:Makefile make:is:Makefile.Debug
		make:is:Makefile.Release make:is:GNUmakefile
		rake:is:Rakefile cmake:is:CMakeLists.txt cmake:ext:cmake
		bazel:ext:bzl bazel:ext:bazelrc bazel:is:BUILD
		bazel:is:WORKSPACE actionscript:ext:as,mxml
		ada:ext:ada,adb,ads asp:ext:asp
		aspx:ext:master,ascx,asmx,aspx,svc asm:ext:asm,s
		batch:ext:bat,cmd cfmx:ext:cfc,cfm,cfml
		clojure:ext:clj,cljs,edn,cljc cc:ext:c,h,xs hh:ext:h
		coffeescript:ext:coffee
		cpp:ext:cpp,cc,cxx,m,hpp,hh,h,hxx hpp:ext:hpp,hh,h,hxx
		csharp:ext:cs crystal:ext:cr,ecr css:ext:css
		dart:ext:dart
		delphi:ext:pas,int,dfm,nfm,dof,dpk,dproj,groupproj,bdsgroup,bdsproj
		elixir:ext:ex,exs elm:ext:elm elisp:ext:el
		erlang:ext:erl,hrl
		fortran:ext:f,f77,f90,f95,f03,for,ftn,fpp go:ext:go
		groovy:ext:groovy,gtmpl,gpp,grunit,gradle gsp:ext:gsp
		haskell:ext:hs,lhs html:ext:htm,html,xhtml jade:ext:jade
		java:ext:java,properties js:ext:js
		jsp:ext:jsp,jspx,jspf,jhtm,jhtml json:ext:json
		kotlin:ext:kt,kts less:ext:less lisp:ext:lisp,lsp
		lua:ext:lua lua:firstlinematch:/^#!.*\blua(jit)?/
		markdown:ext:md,markdown matlab:ext:m objc:ext:m,h
		objcpp:ext:mm,h ocaml:ext:ml,mli,mll,mly
		perl:ext:pl,PL,pm,pod,t,psgi
		perl:firstlinematch:/^#!.*\bperl/ perltest:ext:t
		pod:ext:pod php:ext:php,phpt,php3,php4,php5,phtml
		php:firstlinematch:/^#!.*\bphp/
		plone:ext:pt,cpt,metadata,cpy,py powershell:ext:ps1,psm1
		purescript:ext:purs python:ext:py
		python:firstlinematch:/^#!.*\bpython/ rr:ext:R,Rmd
		raku:ext:raku,rakumod,rakudoc,rakutest,nqp,p6,pm6,pod6
		raku:firstlinematch:/^#!.*\braku/
		rakutest:ext:rakutest
		rst:ext:rst ruby:ext:rb,rhtml,rjs,rxml,erb,rake,spec
		ruby:is:Rakefile ruby:firstlinematch:/^#!.*\bruby/
		rust:ext:rs sass:ext:sass,scss scala:ext:scala,sbt
		scheme:ext:scm,ss
		shell:ext:sh,bash,csh,tcsh,ksh,zsh,fish
		shell:firstlinematch:/^#!.*\b(?:ba|t?c|k|z|fi)?sh\b/
		smalltalk:ext:st smarty:ext:tpl sql:ext:sql,ctl
		stylus:ext:styl svg:ext:svg swift:ext:swift
		swift:firstlinematch:/^#!.*\bswift/ tcl:ext:tcl,itcl,itk
		tex:ext:tex,cls,sty ttml:ext:tt,tt2,ttml toml:ext:toml
		ts:ext:ts,tsx vb:ext:bas,cls,frm,ctl,vb,resx
		verilog:ext:v,vh,sv vhdl:ext:vhd,vhdl vim:ext:vim
		xml:ext:xml,dtd,xsd,xsl,xslt,ent,wsdl
		xml:firstlinematch:/<[?]xml/ yaml:ext:yaml,yml } ],
	    validate	=> '__validate_file_property_add',
	},
	{
	    name	=> 'type_del',
	    type	=> '=s@',
	    option_only	=> 1,
	    validate	=> '__validate_file_property_add',
	},
	{
	    name	=> 'type_set',
	    type	=> '=s@',
	    option_only	=> 1,
	    validate	=> '__validate_file_property_add',
	},
	{	# Must come after type_add, type_del, and type_set
	    name	=> 'syntax_add',
	    type	=> '=s@',
	    default	=> [ qw{
		Cc:type:cc
		Cpp:type:cpp
		Fortran:type:fortran
		Java:ext:java
		Data:type:json
		Make:type:make,tcl
		Perl:type:perl,perltest,pod
		Properties:ext:properties
		Raku:type:raku,rakutest
		Shell:type:shell
		Vim:type:vim
		YAML:type:yaml
		} ],
	    validate	=> '__validate_file_property_add',
	},
	{
	    name	=> 'syntax_del',
	    type	=> '=s@',
	    option_only	=> 1,
	    validate	=> '__validate_file_property_add',
	},
	{
	    name	=> 'syntax_set',
	    type	=> '=s@',
	    option_only	=> 1,
	    validate	=> '__validate_file_property_add',
	},
	{
	    name	=> 'ignore_sam_defaults',
	    type	=> '!',
	},
	{
	    name	=> 'match',
	    type	=> '=s',
	},
	{
	    name	=> 'env',
	    type	=> '!',
	    default	=> 1,
	},
	{
	    name	=> 'replace',
	    type	=> '=s',
	},
	{
	    name	=> 'samrc',
	    type	=> '=s',
	},
	{
	    name	=> 'show_syntax',
	    type	=> '!',
	},
	{
	    name	=> 'show_types',
	    type	=> '!',
	},
	{
	    name	=> 'syntax',
	    type	=> '=s@',
	    validate	=> '__validate_syntax',
	},
	{
	    name	=> 'type',
	    type	=> '=s@',
	    validate	=> '__validate_type',
	},
	{
	    name	=> 'word_regexp',
	    type	=> '!',
	    alias	=> [ qw/ w / ],
	},
	{	# Must be after type_*
	    name	=> 'help_types',
	    type	=> '',
	    validate	=> 'help_types',
	},
	{	# Must be after syntax_*
	    name	=> 'help_syntax',
	    type	=> '',
	    validate	=> 'help_syntax',
	},
    );

    foreach ( @attr_spec_list ) {
	$_->{name} =~ m/ _ /smx
	    or next;
	( my $alias = $_->{name} ) =~ s/ _ /-/smxg;
	push @{ $_->{alias} }, $alias;
    }

    Readonly::Array @ATTR_SPEC_LIST => @attr_spec_list;

    Readonly::Hash %ATTR_SPEC_HASH => map { $_->{name} => $_ }
	@ATTR_SPEC_LIST;
}

sub __get_attr_names {
    state $attr = [
	map { $_->{name} }
	grep { ! $_->{option_only} && ! $_->{back_end} }
	@ATTR_SPEC_LIST,
    ];
    return @{ $attr };
}

sub __get_opt_specs {
    my ( $self ) = @_;
    my @opt_spec;
    foreach ( @ATTR_SPEC_LIST ) {
	next if $_->{argument_only};
	push @opt_spec, join( '|', $_->{name}, @{ $_->{alias} || []
	    } ) . $_->{type}, $self->__get_validator( $_, 1 );
    }
    return @opt_spec;
}

sub __get_attr_defaults {
    my ( $self ) = @_;
    $self ||= {};
    $self->{ignore_sam_defaults}
	and return $self;
    foreach my $attr_spec ( @ATTR_SPEC_LIST ) {
	exists $attr_spec->{default}
	    or next;

	if ( exists $attr_spec->{validate} ) {
	    $self->__validate_attr(
		$attr_spec->{name}, $attr_spec->{default} );
	} else {
	    $self->{$attr_spec->{name}} = $attr_spec->{default};
	}
    }
    return $self;
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
		$rc_cache{$file} = {};
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
		$arg, $self, $self->__get_opt_specs() )
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
	or $attr_spec = $ATTR_SPEC_HASH{$attr_spec}
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
    my $attr_spec = $ATTR_SPEC_HASH{$name}
	or $self->__confess( "Unknown attribute '$name'" );
    if ( my $code = $self->__get_validator( $attr_spec ) ) {
	$code->( $name, $value )
	    or return 0;
    }
    return 1;
}

sub __get_option_parser {
    state $opt_psr = do {
	my $p = Getopt::Long::Parser->new();
	$p->configure( qw{
	    bundling no_ignore_case } );
	$p;
    };
    return $opt_psr;
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
    $self->{env}
	or return;
    my @rslt;
    if ( IS_WINDOWS ) {
	$self->__croak( 'TODO - Windows resource files' );
    } else {
	push @rslt, '/etc/samrc', $ENV{SAMRC} // "$ENV{HOME}/.samrc";
	# TODO Ack semantics for project file
	push @rslt, '.samrc';
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
    # NOTE that the status of weird characters as delimiters is
    # extremely murky. The only documentation I am aware of is in
    # perl5290delta and the associated perldeprecation, which say that
    # that release drops support for combining characters and unassigned
    # characters. Noncharacters and out-of-range characters are
    # explicitly allowed. But Perl 5.12.5 and earlier seem to have a
    # problem with "\N{U+FFFF}", resulting in various errors depending
    # on the version. And there appears to have been a change in
    # semantics at Perl 5.20. Before that version, noncharacters were
    # treated as paired delimiters (paired with themselves), so the
    # replacement string of a substitution needed its own start
    # delimiter. At or after that version, it is a normal delimiter, so
    # in a substitution the end delimiter of the regular expression is
    # also the start delimiter of the replacement.
    state $delim = do {
	# no warnings qw{ utf8 }; needed before 5.14.
	no warnings qw{ utf8 };	## no critic (ProhibitNoWarnings)
	"\N{U+FFFE}";	# Noncharacter.
    };
    state $mid = "$]" < 5.020 ? "$delim $delim" : $delim;
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
    my $str = join '', 'm ', $delim, $match, $delim, $modifier;
    my $inv = $self->{invert_match} ? '! ' : '';
    my $code = eval "sub { $inv$str }"	## no critic (ProhibitStringyEval)
	or $self->__croak( "Invalid match '$match': $@" );
    if ( defined( my $repl = $self->{replace} ) ) {
	$self->{literal}
	    and $repl = quotemeta $repl;
	$str = join '', 's ', $delim, $match, $mid, $repl, $delim,
	    $modifier;
	$code = eval "sub { $inv$str }"	## no critic (ProhibitStringyEval)
	    or $self->__croak( "Invalid replace '$repl': $@" );
    } elsif ( $self->{color} ) {
	my ( $did_match, $did_not_match ) =
	    $self->{invert_match} ? ( 0, 1 ) : ( 1, 0 );
	$str = join '', 's ', $delim, "($match)", $mid,
	    ' $_[0]->__color( match => $1 ) ',
	    $delim, $modifier, 'e';
	# NOTE that ack uses "\e[0m\e[K" here. But "\e[K" suffices for
	# me.
	$code = eval <<"EOD"	## no critic (ProhibitStringyEval)
sub {
    if ( $str ) {
	s/ (?= \\n ) / CLR_EOL /smxge;
	return $did_match;
    } else {
	return $did_not_match;
    }
}
EOD
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

sub __preprocess_logical_negation {
    my ( $self, $attr_spec, $attr_name, $attr_val ) = @_;
    my $back_end = $attr_spec->{back_end}
	or $self->__confess(
	"Attribute '$attr_name' has no back_end specified" );
    if ( my $code = $self->__get_validator( $back_end ) ) {
	return $code->( $back_end, ! $attr_val );
    } else {
	$self->{$back_end} = ! $attr_val;
	return 1;
    }
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

	if ( $self->{f} ) {
	    say join ' => ', $file, @show_types;
	    return;
	}

	my $munger = $self->{_munger};
	my @mod;
	my $encoding = $self->__get_encoding( $file );
	open my $fh, "<$encoding", $file	## no critic (RequireBriefOpen)
	    or $self->__croak( "Failed to open $file for input: $!" );
	my $lines_matched = 0;
	local $_ = undef;	# while (<>) does not localize $_
	while ( <$fh> ) {

	    $self->{_process}{syntax_obj}
		and $self->{_process}{syntax} = $self->{_process}{syntax_obj}->__classify();

	    if ( $self->_process_match_p() ) {
		$self->{_process}{matched} = $munger->( $self )
		    and $lines_matched++;
	    } else {
		$self->{_process}{matched} = 0;
	    }

	    if ( $self->_process_display_p() ) {
		if ( ! $self->{_process}{header} ) {
		    $self->{_process}{header} = 1;
		    $self->{break}
			and say '';
		    say join ' => ',
			$self->__color( filename => $file ), @show_types;
		}

		my @syntax;
		$self->{show_syntax}
		    and push @syntax,
			substr $self->{_process}{syntax} // '', 0, 4;
		print join ':', $self->__color( lineno => $. ), @syntax, $_;
	    }

	    push @mod, $_;
	}
	close $fh;

	$self->{count}
	    and say join ' => ',
		sprintf( '%s:%d', $self->__color( filename => $file ),
		    $lines_matched ), @show_types;

	if ( $self->{replace} && ! $self->{dry_run} &&
	    $lines_matched && ! ref $file
	) {
	    if ( $self->{backup} ne '' ) {
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
sub _process_match_p {
    my ( $self ) = @_;
    # FIXME is this right? Or should I consider --syntax=foo to NOT
    # select lines with unknown syntax? The more I think, the more I
    # want the latter.
    if ( $self->{_syntax} && defined $self->{_process}{syntax} ) {
	$self->{_syntax}{$self->{_process}{syntax}}
	    or return 0;
    }
    return 1;
}

sub __get_file_iterator {
    my ( $self, $file ) = @_;
    return File::Next::files( {
	    file_filter	=> sub {
		! $self->__ignore( file => $File::Next::name, $_ ) },
	    descend_filter	=> sub {
		! $self->__ignore( directory => $File::Next::dir, $_ ) },
	    sort_files	=> 1,
	}, $file );
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
    my @valz = ref $attr_val ? @{ $attr_val } : $attr_val;
    foreach ( @valz ) {
	-r
	    or return 0;
	push @{ $self->{"_$attr_name"} }, $_;
    }
    return 1;
}

sub __validate_ignore {
    my ( $self, undef, $attr_name, $attr_val ) = @_;	# $attr_spec unused
    foreach ( @{ $attr_val } ) {
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
 my $sad = App::Sam->new(
   backup  => '.bak',
   match   => '\bfoo\b',
   replace => 'bar',
 );
 $sad->process( 'foo.txt' );

=head1 DESCRIPTION

This Perl object finds strings in files, possibly modifying them. It was
inspired by L<ack|ack>.

=head1 METHODS

This class supports the following public methods:

=head2 new

 my $sad = App::Sam->new();

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

See L<--backup|sam/--backup> in the L<sam|sam> documentation.

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

=item C<passthru>

See L<--passthru|sam/--passthru> in the L<sam|sam> documentation.

=item C<replace>

See L<--replace|sam/--replace> in the L<sam|sam> documentation.

=item C<samrc>

See L<--samrc|sam/--samrc> in the L<sam|sam> documentation.

=item C<show_syntax>

See L<--show-syntax|sam/--show-syntax> in the L<sam|sam> documentation.

=item C<show_types>

See L<--show-types|sam/--show-types> in the L<sam|sam> documentation.

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

=head2 files_from

Given the name of one or more files, this method reads them and returns
its contents, one line at a time, and C<chomp>-ed. These are assumed to
be file names, and will be filtered if C<filter_files_from> is true.

If called without arguments, reads the files specified by the
C<files_from> argument to L<new()|/new>, if any, and returns their
possibly-filtered contents.

=head2 help_syntax

 $sad->help_syntax( $exit )

This method prints help for the defined syntax types to F<STDOUT>. If
the argument is true, it exits; otherwise it returns. The default for
C<$exit> is true if called from the C<$sad> object (which happens if
argument C<help_types> is true or option C<--help-types> is asserted),
and false otherwise.

=head2 help_types

 $sad->help_types( $exit )

This method prints help for the defined file types to C<STDOUT>. If the
argument is true, it exits; otherwise it returns. The default for
C<$exit> is true if called from the C<$sad> object (which happens if
argument C<help_types> is true or option C<--help-types> is asserted),
and false otherwise.

The output is similar but not identical to L<ack|ack> C<--help-types>.

=head2 process

 $sad->process( $file )

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

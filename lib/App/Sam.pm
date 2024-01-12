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

    $self->__incompat_opt( qw{ f match } );

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

    foreach my $kind ( qw{ match firstlinematch } ) {
	my %uniq;
	@{ $self->{_type_add}{$kind} } =
	    map { pop @{ $_ }; $_ }
	    grep { ! $uniq{$_->[2]}++ }
	    @{ $self->{_type_add}{$kind} };
    }

    foreach my $attr ( qw{ _syntax_def _type_def } ) {

	foreach my $kind ( qw{ ext is } ) {
	    foreach my $spec ( values %{ $self->{_type_add}{$kind} || {} } ) {
		@{ $spec } = List::Util::uniqstr( @{ $spec } );
	    }
	}

	foreach my $thing ( values %{ $self->{$attr} } ) {
	    foreach my $spec ( values %{ $thing } ) {
		@{ $spec } = List::Util::uniqstr( @{ $spec } );
	    }
	}
    }

    defined $self->{match}
	and $self->__make_munger();

    return $self;
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
    my $spec = $self->{"_${property}_add"} || {};
    $_ //= ( File::Spec->splitpath( $path ) )[2];
    my @rslt;

    $spec->{is}{$_}
	and push @rslt, @{ $spec->{is}{$_} };

    m/ [.] ( [^.]* ) \z /smx
	and $spec->{ext}{$1}
	and push @rslt, @{ $spec->{ext}{$1} };

    if ( my $match = $spec->{match} ) {
	foreach my $m ( @{ $match } ) {
	    $m->[1]->()
		and push @rslt, $m->[0];
	}
    }

    if (
	my $match = $spec->{firstlinematch}
	    and open my $fh, '<' . $self->__get_encoding( $path ), $path
    ) {
	local $_ = <$fh>;
	close $fh;
	foreach my $m ( @{ $match } ) {
	    $m->[1]->()
		and push @rslt, $m->[0];
	}
    }

    if ( my $type_map = $spec->{type} ) {
	foreach my $type (
	    $self->{_process}{type} ?
	    @{ $self->{_process}{type} } :
	    $self->__type( $path, $_ )
	) {
	    $type_map->{$type}
		and push @rslt, $type_map->{$type};
	}
    }

    return List::Util::uniqstr( sort @rslt );
}

sub _get_spec_list {
    no warnings qw{ qw };	## no critic (ProhibitNoWarnings)
    my @spec_list = (
	{
	    name	=> 'backup',
	    type	=> '=s',
	    default	=> '',
	},
	{
	    name	=> 'break',
	    type	=> '|',
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
	    name	=> 'ignore_case',
	    type	=> '!',
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
	    validate	=> '__validate_type_add',
	},
	{
	    name	=> 'type_del',
	    type	=> '=s@',
	    option_only	=> 1,
	    validate	=> '__validate_type_add',
	},
	{
	    name	=> 'type_set',
	    type	=> '=s@',
	    option_only	=> 1,
	    validate	=> '__validate_type_add',
	},
	{	# Must come after type_add, type_del, and type_set
	    name	=> 'syntax_add',
	    type	=> '=s@',
	    default	=> [ qw{
		Cc:type:cc
		Cpp:type:cpp
		Java:ext:java
		Make:type:make,tcl
		Perl:type:perl,perltest,pod
		Raku:type:raku,rakutest
		} ],
	    validate	=> '__validate_syntax_add',
	},
	{
	    name	=> 'syntax_del',
	    type	=> '=s@',
	    option_only	=> 1,
	    validate	=> '__validate_syntax_add',
	},
	{
	    name	=> 'syntax_set',
	    type	=> '=s@',
	    option_only	=> 1,
	    validate	=> '__validate_syntax_add',
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
	}
    );

    foreach ( @spec_list ) {
	$_->{name} =~ m/ _ /smx
	    or next;
	( my $alias = $_->{name} ) =~ s/ _ /-/smxg;
	push @{ $_->{alias} }, $alias;
    }

    return @spec_list;
}

{
    Readonly::Array my @spec_list => _get_spec_list();

    Readonly::Hash my %spec_hash => map { $_->{name} => $_ } @spec_list;

    sub __get_attr_names {
	state $attr = [
	    map { $_->{name} }
	    grep { ! $_->{option_only} }
	    @spec_list,
	];
	return @{ $attr };
    }

    sub __get_opt_specs {
	my ( $self ) = @_;
	my @opt_spec;
	foreach ( @spec_list ) {
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
	foreach my $spec ( @spec_list ) {
	    exists $spec->{default}
		or next;

=begin comment

	    $self->{$spec->{name}} = $spec->{default};
	    $self->__validate_attr( $spec->{name},
		$self->{$spec->{name}} );

=end comment

=cut

	    if ( exists $spec->{validate} ) {
		$self->__validate_attr( $spec->{name}, $spec->{default} );
	    } else {
		$self->{$spec->{name}} = $spec->{default};
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
	my ( $self, $spec, $die ) = @_;
	my $method;
	defined( $method = $spec->{validate} )
	    or return;
	$die
	    and return sub {
	    $self->$method( @_ )
		or die "Invalid value --$_[0]=$_[1]\n";
	    return 1;
	};
	return sub {
	    return $self->$method( @_ );
	};
    }

    # Validate an attribute given its name and value
    sub __validate_attr {
	my ( $self, $name, $value ) = @_;
	my $spec = $spec_hash{$name}
	    or $self->__confess( "Unknown attribute '$name'" );
	if ( my $code = $self->__get_validator( $spec ) ) {
	    $code->( $name, $value )
		or return 0;
	}
	return 1;
    }
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

sub __incompat_opt {
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
    if ( $self->{word_regexp} ) {

	$match =~ s/ \A (?= \w ) /\\b/smx;
	$match =~ s/ (?<= \w ) \z /\\b/smx;
    }
    my $str = join '', 'm ', $delim, $match, $delim, $modifier;
    my $code = eval "sub { $str }"	## no critic (ProhibitStringyEval)
	or $self->__croak( "Invalid match '$match': $@" );
    if ( defined( my $repl = $self->{replace} ) ) {
	$str = join '', 's ', $delim, $match, $mid, $repl, $delim,
	    $modifier;
	$code = eval "sub { $str }"	## no critic (ProhibitStringyEval)
	    or $self->__croak( "Invalid replace '$repl': $@" );
    } elsif ( $self->{color} ) {
	$str = join '', 's ', $delim, "($match)", $mid,
	    ' $_[0]->__color( match => $1 ) ',
	    $delim, $modifier, 'e';
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
    my $spec = $self->{"_ignore_$kind"}
	or $self->__confess( "Invalid ignore kind '$kind'" );
    $_ //= ( File::Spec->splitpath( $path ) )[2];
    $spec->{is}{$_}
	and return 1;
    m/ [.] ( [^.]* ) \z /smx
	and $spec->{ext}{$1}
	and return 1;
    $spec->{match}
	and $spec->{match}->()
	and return 1;
    if ( $kind eq 'file' && $self->{_type} ) {

	# Encoding: undef = unspecified, 0 = accept, 1 = skip
	my $want_type;
	foreach my $type ( $self->__type( $path, $_ ) ) {
	    my $skip = $self->{_type}{$type}
		and return 1;
	    $want_type //= $skip;
	}
	return ! defined $want_type;
    }
    return 0;
}

sub process {
    my ( $self, $file ) = @_;

    local $self->{_process} = {};

    if ( ref( $file ) || ! -d $file ) {

	-T $file
	    or return;

	$self->{_process}{type} = [ $self->__type( $file ) ]
	    if $self->{show_types} || $self->{_syntax} ||
		$self->{show_syntax};

	my @show_types;
	$self->{show_types}
	    and push @show_types, join ',', @{ $self->{_process}{type} };

	if ( $self->{_syntax} || $self->{show_syntax} ) {
	    if ( my ( $class ) = $self->__syntax( $file ) ) {
		$self->{_process}{syntax_obj} =
		    $self->{_syntax_obj}{$class} ||=
		    "App::Sam::Syntax::$class"->new( die => $self->{die} );
	    }

	    # If --syntax was specified and we did not find a syntax
	    # object, ignore the file.
	    $self->{_syntax}
		and not $self->{_process}{syntax_obj}
		and return;
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
		and $self->{_process}{syntax} = $self->{_process}{syntax_obj}->__syntax();

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

sub __syntax_del {
    my ( $self, $syntax ) = @_;
    delete $self->{_syntax_def}{$syntax};
    foreach my $type ( keys %{ $self->{_syntax_add}{type} } ) {
	$syntax eq $self->{_syntax_add}{type}{$type}
	    and delete $self->{_syntax_add}{type}{$type};
    }
    return;
}

sub __syntax_type_del {
    my ( $self, $type ) = @_;
    foreach my $syntax ( keys %{ $self->{_syntax_def} } ) {
	@{ $self->{_syntax_def}{$syntax}{type} } = grep { $_ ne $type }
	    @{ $self->{_syntax_def}{$syntax}{type} }
	    or delete $self->{_syntax_def}{$syntax}{type};
	keys %{ $self->{_syntax_def}{$syntax} }
	    or delete $self->{_syntax_def}{$syntax};
    }
    delete $self->{_syntax_add}{type}{$type};
    return;
}

sub __syntax {
    my ( $self, @arg ) = @_;
    return $self->_file_property( syntax => @arg );
}

sub __type {
    my ( $self, @arg ) = @_;
    return $self->_file_property( type => @arg );
}

sub __type_del {
    my ( $self, $type ) = @_;
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
    return;
}

sub __validate_color {
    my ( $self, $name, $color ) = @_;
    Term::ANSIColor::colorvalid( $color )
	or return 0;
    $self->{$name} = $color;
    return 1;
}

sub __validate_files_from {
    my ( $self, $name, $value ) = @_;	# $self, $name unused
    not ref $value
	or REF_ARRAY eq ref $value
	or return 0;
    my @valz = ref $value ? @{ $value } : $value;
    foreach ( @valz ) {
	-r
	    or return 0;
	push @{ $self->{"_$name"} }, $_;
    }
    return 1;
}

sub __validate_ignore {
    my ( $self, $name, $spec ) = @_;
    foreach ( @{ $spec } ) {
	my ( $kind, $data ) = split /:/, $_, 2;
	defined $data
	    or ( $kind, $data ) = ( is => $kind );
	state $validate_kind = {
	    ext	=> sub {
		my ( $self, $name, $data ) = @_;
		my @item = split /,/, $data;
		@{ $self->{"_$name"}{ext} }{ @item } = ( ( 1 ) x @item );
		return 1;
	    },
	    is	=> sub {
		my ( $self, $name, $data ) = @_;
		$self->{"_$name"}{is}{$data} = 1;
		return 1;
	    },
	    match	=> sub {
		my ( $self, $name, $data ) = @_;
		local $@ = undef;
		eval "qr $data"	## no critic (ProhibitStringyEval)
		    or return 0;
		push @{ $self->{"_$name"}{match} }, $data;
		return 1;
	    },
	};
	my $code = $validate_kind->{$kind}
	    or return 0;
	$code->( $self, $name, $data )
	    or return 0;
    }
    return 1;
}

sub __validate_syntax {
    my ( $self, undef, $syntax_array ) = @_;	# $name unused
    foreach my $syntax ( ref $syntax_array ? @{ $syntax_array } : $syntax_array ) {
	state $valid = Text::Abbrev::abbrev( __syntax_types() );
	my $expansion = $valid->{$syntax}
	    or return 0;
	$self->{_syntax}{$expansion} = 1;
    }
    return 1;
}

sub __validate_syntax_add {
    my ( $self, $name, $spec ) = @_;
    foreach ( ref $spec ? @{ $spec } : $spec ) {
	my ( $syntax, $kind, $data ) = split /:/, $_, 3;
	{
	    local $@ = undef;
	    my $module = "App::Sam::Syntax::$syntax";
	    eval {
		Module::Load::load( $module );
		1;
	    } or return 0;
	}
	defined $data
	    or ( $kind, $data ) = ( type => $kind );
	state $validate_kind = {
	    ext	=> sub {
		my ( $self, $syntax, $data ) = @_;
		my @item = split /,/, $data;
		push @{ $self->{_syntax_add}{ext}{$_} }, $syntax for @item;
		push @{ $self->{_syntax_def}{$syntax}{ext} },
		    map { ".$_" } @item;
		return 1;
	    },
	    type	=> sub {
		my ( $self, $syntax, $data ) = @_;
		my @item = split /,/, $data;
		foreach my $type ( @item ) {
		    $self->{_type_def}{$type}
			or return 0;
		    $self->{_syntax_add}{type}{$type} = $syntax;
		    push @{ $self->{_syntax_def}{$syntax}{type} }, $type;
		}
		return 1;
	    },
	};
	my $code = $validate_kind->{$kind}
	    or return 0;
	state $handler = {
	    syntax_add	=> sub { 1 },
	    syntax_del	=> sub {
		my ( $self, $syntax ) = @_;
		$self->__syntax_del( $syntax );
		return 0;
	    },
	    syntax_set	=> sub {
		my ( $self, $syntax ) = @_;
		$self->__syntax_del( $syntax );
		return 1;
	    },
	};
	my $setup = $handler->{$name}
	    or $self->__confess( "Unknown syntax handler '$name'" );

	$setup->( $self, $syntax )
	    or next;

	$code->( $self, $syntax, $data )
	    or return 0;
    }
    return 1;
}

sub __validate_type {
    my ( $self, undef, $type_array ) = @_;	# $name unused
    foreach my $type ( ref $type_array ? @{ $type_array } : $type_array ) {
	my $neg;
	if ( $self->{_type_def}{$type} ) { 
	    $self->{_type}{$type} = 0;
	} elsif ( ( $neg = $type ) =~ s/ \A no-? //smxi && (
		$self->{_type_def}{$neg} ) ) {
	    $self->{_type}{$neg} = 1;
	} else {
	    return 0;
	}
    }
    return 1;
}

sub __validate_type_add {
    my ( $self, $name, $spec ) = @_;
    foreach ( ref $spec ? @{ $spec } : $spec ) {
	my ( $type, $kind, $data ) = split /:/, $_, 3;
	defined $data
	    or ( $kind, $data ) = ( is => $kind );
	state $validate_kind = {
	    ext	=> sub {
		my ( $self, $type, $data ) = @_;
		my @item = split /,/, $data;
		push @{ $self->{_type_add}{ext}{$_} }, $type for @item;
		push @{ $self->{_type_def}{$type}{ext} }, map { ".$_" } @item;
		return 1;
	    },
	    is	=> sub {
		my ( $self, $type, $data ) = @_;
		push @{ $self->{_type_add}{is}{$data} }, $type;
		push @{ $self->{_type_def}{$type}{is} }, $data;
		return 1;
	    },
	    match	=> sub {
		my ( $self, $type, $data ) = @_;
		local $@ = undef;
		my $code = eval "sub { $data }"	## no critic (ProhibitStringyEval)
		    or return 0;
		push @{ $self->{_type_add}{match} },
		    [ $type, $code, "$type:$data" ];
		push @{ $self->{_type_def}{$type}{match} }, $data;
		return 1;
	    },
	    firstlinematch	=> sub {
		my ( $self, $type, $data ) = @_;
		local $@ = undef;
		my $code = eval "sub { $data }"	## no critic (ProhibitStringyEval)
		    or return 0;
		push @{ $self->{_type_add}{firstlinematch} },
		    [ $type, $code, "$type:$data" ];
		push @{ $self->{_type_def}{$type}{firstlinematch} }, $data;
		return 1;
	    },
	};
	my $code = $validate_kind->{$kind}
	    or return 0;
	state $handler = {
	    type_add	=> sub { 1 },
	    type_set	=> sub {
		my ( $self, $type ) = @_;
		$self->__type_del( $type );
		return 1;
	    },
	    type_del	=> sub {
		my ( $self, $type ) = @_;
		$self->__type_del( $type );
		$self->__syntax_type_del( $type );
		return 0;
	    },
	};
	my $setup = $handler->{$name}
	    or $self->__confess( "Unknown type handler '$name'" );

	$setup->( $self, $type )
	    or next;

	$code->( $self, $type, $data )
	    or return 0;
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
modify them (things like C<type_add>, C<type_del>, and C<type_set>.
Unknown options result in an exception.

The argument must refer to an array that can be modified. After this
argument is processed, non-option arguments remain in the array.

=item C<backup>

This argument specifies that file modification renames the original file
before the modification is written. The value is the string to be
appended to the original file name. No rename is done unless the file
was actually modified. A value of C<''> specifies no rename.

=item C<break>

This Boolean argument specifies whether a break is printed between
output from different files. The default is false.

=item C<color>

This Boolean argument specifies whether output should be colored. The
default is false. Output will not be colored if C<replace> was
specified.

=item C<color_filename>

This argument specifies the L<Term::ANSIColor|Term::ANSIColor> coloring
to be applied to the file name.

=item C<color_lineno>

This argument specifies the L<Term::ANSIColor|Term::ANSIColor> coloring
to be applied to the line number.

=item C<color_match>

This argument specifies the L<Term::ANSIColor|Term::ANSIColor> coloring
to be applied to the match.

=item C<count>

If this Boolean option is true, only the number of matches is output.

=item C<die>

This Boolean argument specifies how warnings and errors are delivered. A
true value specifies C<warn()> or C<die()> respectively. A false value
specifies C<Carp::carp()> or C<Carp::croak()> respectively. The default
is false. A true value will be ignored if C<$Carp::verbose> is true.

=item C<dry_run>

If this Boolean argument is true, modified files are not rewritten, nor
are the originals backed up. The default is false.

=item C<encoding>

This argument specifies the encoding to use to read and write files. The
default is C<'utf-8'>.

=item C<f>

If this Boolean argument is true, no search is done, but the files that
would be searched are printed. You may not specify the C<match> argument
if this is true.

=item C<files_from>

This argument specifies the name of a file which contains the names of
files to search. It can also be a reference to an array of such files.
B<Note> that the files are not actually read until
L<files_from()|/files_from> is called. The only validation before that
is that the C<-r> operator must report them as readable, though this is
not definitive in the presence of Access Control Lists.

=item C<filter_files_from>

This Boolean argument specifies whether files obtained by calling
L<files_from()|/files_from> should be filtered. The default is false,
which is consistent with L<ack|ack>.

=item C<ignore_case>

If this Boolean argument is true, the match argument ignores case.

=item C<ignore_directory>

This argument is a reference to an array of
L<file selectors|/FILE SELECTORS>. Directory scans will ignore
directories that match any of the selectors.

Directories specified explicitly will not be ignored even if they match
one or more selectors.

=item C<ignore_file>

This argument is a reference to an array of
L<file selectors|/FILE SELECTORS>. Directory scans will ignore files
that match any of the selectors.

Files specified explicitly will not be ignored even if they match one or
more selectors.

=item C<ignore_sam_defaults>

If this Boolean argument is true, the built-in defaults are ignored.

=item C<match>

This argument specifies the regular expression to match. It can be given
as either a C<Regexp> object or a string.

=item C<env>

If this Boolean argument is true. all resource files are processed. The
default is true. Files explicitly specified by C<samrc> are exempt from
the effects of this argument.

=item C<replace>

If this argument is defined it represents a string to replace the
matched string. Capture variables may be used.

=item C<samrc>

This argument specifies the name of a resource file to read. This is
read after all the default resource files, and even if C<noenv> is true.
The file must exist.

=item C<show_syntax>

If this Boolean option is true, the syntax type of each line will be
displayed between the line number and the text of the line. This will be
empty if the file's type does not have syntax defined on it.

=item C<show_types>

If this Boolean option is true, file types are appended to the file name
when displayed.

=item C<syntax>

This argument is a reference to an array of syntax types to select. If a
file does not have syntax defined. it is ignored.

=item C<type>

This argument is a reference to an array of file types to select. The
type can be prefixed with C<'no'> or C<'no-'> to reject the type. In the
case of files with more than one type, rejection takes precedence over
selection.

=item C<type_add>

This argument is a reference to an array of file type definitions. These
are specified as C<type:file_selector> where the C<type> is the name
assigned to the type and C<file_selector> is a L<file selector|/FILE
SELECTORS>.

=item C<word_regexp>

If this Boolean argument is true, then if the beginning and/or end of
the match expression is a word character, a C<\b> assertion will be
prepended/appended. That is to say, C<foo> will become C<\bfoo\b>, but
C<(foo)> will remain C<(foo)>.

=back

=head2 files_from

Given the name of one or more files, this method reads them and returns
its contents, one line at a time, and C<chomp>-ed. These are assumed to
be file names, and will be filtered if C<filter_files_from> is true.

If called without arguments, reads the files specified by the
C<files_from> argument to L<new()|/new>, if any, and returns their
possibly-filtered contents.

=head2 help_types

 $sad->help_types( $exit )

This method prints help for the defined types. If the argument is true,
it exits; otherwise it returns. The default for C<$exit> is true if
called from the C<$sad> object (which happens if argument C<help_types>
is true or option C<--help-types> is asserted), and false otherwise.

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

=head1 FILE SELECTORS

Various functions of this package require selecting files or directories
for inclusion or exclusion. File selectors are specified as
C<'type:arg'>, where the C<type> is one of the known selector types
listed below, and the C<arg> is an argument specific to the selector
type.

=over

=item C<is>

The argument is the base name of the file to be selected. For example,
C<is:Makefile> selects all files named F<Makefile>, wherever they appear
in the directory hierarchy.

=item C<ext>

The argument is a comma-separated list of file name extensions/suffixes
to be selected. For example, C<ext:pl,t> selects all files whose names
end in F<.pl> or F<.t>.

B<Note> that unlike L<ack|ack>, this selector is case-sensitive:
C<ext:pl,t> does B<not> select F<Makefile.PL>; to do that, you must
include the C<PL> explicitly.

=item C<match>

The argument is a delimited regular expression that matches the base
name of the file to be selected. For example, C<match:/[._].*[.]swp$/>
selects C<vi*> swap files.

=item C<firstlinematch>

The argument is a delimited regular expression that matches the first
line of the file to be selected. For example, C<perl:firstlinematch:/^#!.*\bperl/> matches a Perl script.

This selector may not be used to select a directory.

=back

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

Copyright (C) 2023 by Thomas R. Wyant, III

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl 5.10.0. For more details, see the full text
of the licenses in the directory LICENSES.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=cut

# ex: set textwidth=72 :

package App::Sam;

use 5.010;

use strict;
use warnings;

use utf8;

use Carp ();
use File::Next ();
use File::Spec;
use Errno qw{ :POSIX };
use Getopt::Long ();
use Term::ANSIColor ();

our $VERSION = '0.000_001';

use constant IS_WINDOWS	=> {
    MSWin32	=> 1,
}->{$^O} || 0;

sub new {
    my ( $class, %arg ) = @_;

    my $self = bless {
	ignore_sad_defaults	=> delete $arg{ignore_sad_defaults},
	env			=> delete $arg{env},
    }, $class;

    $self->__get_attr_defaults();
    $self->{ignore_sad_defaults}	# Chicken-and-egg problem
	and %{ $self } = (
	    ignore_sad_defaults => $self->{ignore_sad_defaults}
	);

    foreach my $file ( $self->__get_rc_file_names() ) {
	$self->__get_attr_from_rc( $file );
    }

    if ( my $file = delete $arg{ackrc} ) {
	$self->__get_attr_from_rc( $file, 1 );	# Required to exist
    }

    foreach my $name ( $self->__get_attr_names() ) {
	exists $arg{$name}
	    or next;
	$self->__validate_attr( $name, $arg{$name} )
	    or $self->__croak( "Invalid $name value '$arg{name}'" );
	$self->{$name} = delete $arg{$name};
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
	my $str = join ' || ', @{ $self->{$alias}{match} };
	my $code = eval "sub { $str }"
	    or $self->__confess( "Failed to compile $name match spec" );
	$self->{$alias}{match} = $code;
    }

    defined $self->{match}
	and $self->__make_munger();

    return $self;
}

sub run {
    my ( $self, @arg ) = @_;

    my %opt;

    __PACKAGE__->get_option_parser()->getoptionsfromarray(
	\@arg, \%opt, __get_opt_specs() );

    $self = $self->new( %opt ) unless ref $self;

    unless ( defined $self->{match} ) {
	$self->{match} //= @arg ? shift @arg :
	    $self->__croak( 'No match specified' );
	$self->__make_munger();
    }

    # TODO

}

sub __carp {
    my ( $self, @arg ) = @_;
    @arg
	or @arg = ( 'Warning' );
    if ( $self->{die} ) {
	warn $self->__decorate_die_args( @arg );
    } else {
	Carp::carp( $self->__decorate_croak_args( @arg ) );
    }
    return;
}

sub __color {
    my ( $self, $kind, $text ) = @_;
    $self->{color}
	or return $text;
    defined( my $color = $self->{"color_$kind"} )
	or $self->__confess( "Invalid color kind '$kind'" );
    return Term::ANSIColor::colored( $text, $color );
}

sub __confess {
    my ( $self, @arg ) = @_;
    unshift @arg, @arg ? 'Bug - ' : 'Bug';
    if ( $self->{die} ) {
	state $me = sprintf '%s: ', $self->__me();
	unshift @arg, $me;
    }
    Carp::confess( $self->__decorate_croak_args( @arg ) );
}

sub __croak {
    my ( $self, @arg ) = @_;
    @arg
	or @arg = ( 'Died' );
    if ( $self->{die} ) {
	die $self->__decorate_die_args( @arg );
    } else {
	Carp::croak( $self->__decorate_croak_args( @arg ) );
    }
}

sub __decorate_croak_args {
    my ( $self, @arg ) = @_;
    chomp $arg[-1];
    $arg[-1] =~ s/ [.?!] //smx;
    return @arg;
}

sub __decorate_die_args {
    my ( $self, @arg ) = @_;
    chomp $arg[-1];
    $arg[-1] =~ s/ (?<! [.?!] ) \z /./smx;
    $arg[-1] .= $/;
    state $me = sprintf '%s: ', $self->__me();
    unshift @arg, $me;
    return @arg;
}

sub files_from {
    my ( $self, $file ) = @_;
    defined $file
	or return;
    my @rslt;
    local $_ = undef;	# while (<>) does not localize $_
    open my $fh, '<:encoding(utf-8)', $file
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
    return @rslt;
}

{
    no warnings qw{ qw };
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
	    name	=> 'type_add',
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
		perl:ext:pl,pm,pod,t,psgi
		perl:firstlinematch:/^#!.*\bperl/ perltest:ext:t
		pod:ext:pod php:ext:php,phpt,php3,php4,php5,phtml
		php:firstlinematch:/^#!.*\bphp/
		plone:ext:pt,cpt,metadata,cpy,py powershell:ext:ps1,psm1
		purescript:ext:purs python:ext:py
		python:firstlinematch:/^#!.*\bpython/ rr:ext:R,Rmd
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
	    validate	=> '__validate_type_set',
	},
	{
	    name	=> 'ignore_sad_defaults',
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
	    name	=> 'type',
	    type	=> '=s@',
	    validate	=> '__validate_type',
	},
	{
	    name	=> 'word_regexp',
	    type	=> '!',
	},
    );
    my %spec_hash = map { $_->{name} => $_ } @spec_list;

    foreach ( @spec_list ) {
	$_->{name} =~ m/ _ /smx
	    or next;
	( my $alias = $_->{name} ) =~ s/ _ /-/smxg;
	push @{ $_->{alias} }, $alias;
    }

    sub __get_attr_names {
	state $attr = [ map { $_->{name} } @spec_list ];
	return @{ $attr };
    }

    sub __get_opt_specs {
	state $opt_spec = [ map { join( '|', $_->{name}, @{ $_->{alias} ||
		[] } ) . $_->{type} } @spec_list ];
	return @{ $opt_spec };
    }

    sub __get_attr_defaults {
	my ( $self ) = @_;
	$self ||= {};
	$self->{ignore_sad_defaults}
	    and return $self;
	foreach my $spec ( @spec_list ) {
	    exists $spec->{default}
		or next;
	    $self->{$spec->{name}} = $spec->{default};
	    $self->__validate_attr( $spec->{name},
		$self->{$spec->{name}} );
	}
	return $self;
    }

    {
	my %rc_cache;

	# TODO __clear_rc_cache()

	sub __get_attr_from_rc {
	    my ( $self, $file, $required ) = @_;
	    if ( $rc_cache{$file} ) {
		ref $rc_cache{$file}
		    or $self->__croak( $rc_cache{$file} );
		@{ $self }{ keys %{ $rc_cache{$file} } } = values %{
		$rc_cache{$file} };
	    } elsif ( open my $fh, '<:encoding(utf-8)', $file ) {
		local $_ = undef;	# while (<>) does not localize $_
		my @arg;
		while ( <$fh> ) {
		    m/ \A \s* (?: \z | \# ) /smx
			and next;
		    chomp;
		    push @arg, $_;
		}
		close $fh;
		$self->__get_option_parser()->getoptionsfromarray(
		    \@arg, \( my %opt ), $self->__get_opt_specs() )
		    or $self->__croak( $rc_cache{$file} =
		    "Invalid option in $file" );
		@arg
		    and $self->__croak( $rc_cache{$file} =
		    "Non-option content in $file" );
		foreach my $name ( sort keys %opt ) {
		    $self->__validate_attr( $name, $opt{$name} )
			or $self->__croak( $rc_cache{$file} =
			"Invalid $name value '$opt{$name}' in $file" );
		}
		$rc_cache{$file} = \%opt;
		@{ $self }{ keys %opt } = values %opt;
	    } elsif ( $! == ENOENT && ! $required ) {
		$rc_cache{$file} = {};
	    } else {
		$self->__croak( $rc_cache{$file} =
		    "Failed to open resource file $file: $!" );
	    }

	    return;
	}

    }

    sub __validate_attr {
	my ( $self, $name, $value ) = @_;
	my $spec = $spec_hash{$name}
	    or $self->__confess( "Unknown attribute '$name'" );
	if ( defined( my $method = $spec->{validate} ) ) {
	    $self->$method( $name, $value )
		or return 0;
	}
	return 1;
    }

    # NOTE Not to be used except for testing.
    sub __set_attr_default {
	my ( $self, $name, $value ) = @_;
	my $spec = $spec_hash{$name}
	    or $self->__confess( "Unknown attribute '$name'" );
	$spec->{default} = $value;
	return;
    }
}

sub __get_option_parser {
    state $opt_psr = do {
	my $p = Getopt::Long::Parser->new();
	$p->configure( qw{
	    bundling no_ignore_case no_auto_abbrev pass_through } );
	$p;
    };
    return $opt_psr;
}

sub __get_encoding {
    my ( $self, $file ) = @_;
    if ( defined( $file ) && ! ref $file ) {
	# TODO file-specific
    }
    return $self->{encoding};
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
	no warnings qw{ utf8 };	# Needed before 5.14
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
    my $code = eval "sub { $str }"
	or $self->__croak( "Invalid match '$match': $@" );
    if ( defined( my $repl = $self->{replace} ) ) {
	$str = join '', 's ', $delim, $match, $mid, $repl, $delim,
	    $modifier;
	$code = eval "sub { $str }"
	    or $self->__croak( "Invalid replace '$repl': $@" );
    } elsif ( $self->{color} ) {
	$str = join '', 's ', $delim, "($match)", $mid,
	    ' $_[0]->__color( match => $1 ) ',
	    $delim, $modifier, 'e';
	$code = eval "sub { $str }"
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
	my $type = $self->__type( $path, $_ );
	defined $type
	    and return ! $self->{_type}{$type};
    }
    return 0;
}

sub process {
    my ( $self, $file ) = @_;
    delete $self->{_lines_matched};
    if ( ref( $file ) || ! -d $file ) {
	-T $file
	    or return;
	local $_ = undef;	# while (<>) does not localize $_
	my $munger = $self->{_munger};
	my @mod;
	my $encoding = $self->__get_encoding( $file );
	open my $fh, "<:encoding($encoding)", $file
	    or $self->__croak( "Failed to open $file for input: $!" );
	my $lines_matched = 0;
	while ( <$fh> ) {
	    if ( $munger->( $self ) ) {
		unless ( $lines_matched++ ) {
		    unless ( $self->{count} ) {	# TODO other conditions
			$self->{_file_count}++
			    and $self->{break}
			    and say '';
			say $self->__color( filename => $file );
		    }
		}
		$self->{count}
		    or printf '%s:%s', $self->__color( lineno => $. ), $_;
	    }
	    push @mod, $_;
	}
	close $fh;

	$self->{count}
	    and printf "%s:%d\n", $self->__color( filename => $file ), $lines_matched;

	$self->{_lines_matched} = $lines_matched;
	if ( $self->{replace} && ! $self->{dry_run} &&
	    $lines_matched && ! ref $file
	) {
	    if ( $self->{backup} ne '' ) {
		my $backup = "$file$self->{backup}";
		rename $file, $backup
		    or $self->__croak(
		    "Unable to rename $file to $backup: $!" );
	    }
	    open my $fh, ">:encoding($encoding)", $file
		or $self->__croak( "Failed to open $file for output: $!" );
	    print { $fh } @mod;
	    close $fh;
	}

	defined wantarray
	    and return join '', @mod;
    } else {
	my $iterator = File::Next::files( {
		file_filter	=> sub { ! $self->__ignore( file => $File::Next::name, $_ ) },
		descend_filter	=> sub { ! $self->__ignore( directory => $File::Next::dir, $_ ) },
		sort_files	=> 1,
	    }, $file );
	while ( defined( my $fn = $iterator->() ) ) {
	    $self->process( $fn );
	}
    }
    return;
}

sub __type {
    ( my ( $self, $path ), local $_ ) = @_;
    my $spec = $self->{_type_add} || {};
    $_ //= ( File::Spec->splitpath( $path ) )[2];
    $spec->{is}{$_}
	and return $spec->{is}{$_};
    m/ [.] ( [^.]* ) \z /smx
	and $spec->{ext}{$1}
	and return $spec->{ext}{$1};
    if ( my $match = $spec->{match} ) {
	foreach my $m ( @{ $match } ) {
	    $m->[0]->()
		and return $m->[1];
	}
    }
    if (
	my $match = $spec->{firstlinematch}
	    and open my $fh, "<:encoding($self->{encoding})", $path
    ) {
	local $_ = <$fh>;
	close $fh;
	foreach my $m ( @{ $match } ) {
	    $m->[0]->()
		and return $m->[1];
	}
    }
    return undef;
}

sub __type_del {
    my ( $self, $type ) = @_;
    my $def = $self->{_type_add};
    foreach my $kind ( qw{ is ext } ) {
	foreach my $key ( keys %{ $def->{$kind} } ) {
	    $def->{$kind}{$key} eq $type
		and delete $def->{$kind}{$key};
	}
    }
    foreach my $kind ( qw{ match firstlinematch } ) {
	@{ $def->{$kind} } = grep { $_->[1] ne $type } @{ $def->{$kind} };
    }
    delete $self->{_type_def}{$type};
    return;
}

sub __validate_color {
    my ( $self, $name, $color ) = @_;
    return Term::ANSIColor::colorvalid( $color );
}

sub __validate_ignore {
    my ( $self, $name, $spec ) = @_;
    foreach ( @{ $spec } ) {
	my ( $kind, $data ) = split /:/, $_, 2;
	defined $data
	    or ( $kind, $data ) = ( is => $kind );
	state $validate_kind = {
	    ext	=> sub {
		my ( $self, $name, $value ) = @_;
		my @item = split /,/, $value;
		@{ $self->{"_$name"}{ext} }{ @item } = ( ( 1 ) x @item );
		return 1;
	    },
	    is	=> sub {
		my ( $self, $name, $value ) = @_;
		my @item = split /,/, $value;
		@{ $self->{"_$name"}{is} }{ @item } = ( ( 1 ) x @item );
		return 1;
	    },
	    match	=> sub {
		my ( $self, $name, $value ) = @_;
		local $@ = undef;
		eval "qr $value"
		    or return 0;
		push @{ $self->{"_$name"}{match} }, $value;
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

sub __validate_type {
    my ( $self, $name, $type_array ) = @_;
    foreach my $type ( @{ $type_array } ) {
	$self->{_type_def}{$type}
	    or return 0;
	$self->{_type}{$type} = 1;
    }
    return 1;
}

sub __validate_type_set {
    my ( $self, $name, $spec ) = @_;
    foreach ( @{ $spec } ) {
	my ( $type, $kind, $data ) = split /:/, $_, 3;
	defined $data
	    or ( $kind, $data ) = ( is => $kind );
	state $validate_kind = {
	    ext	=> sub {
		my ( $self, $value, $type ) = @_;
		my @item = split /,/, $value;
		@{ $self->{_type_add}{ext} }{ @item } = ( ( $type ) x @item );
		return 1;
	    },
	    is	=> sub {
		my ( $self, $value, $type ) = @_;
		my @item = split /,/, $value;
		@{ $self->{_type_add}{is} }{ @item } = ( ( $type ) x @item );
		return 1;
	    },
	    match	=> sub {
		my ( $self, $value, $type ) = @_;
		local $@ = undef;
		my $code = eval "sub { $value }"
		    or return 0;
		push @{ $self->{_type_add}{match} }, [ $code, $type ];
		return 1;
	    },
	    firstlinematch	=> sub {
		my ( $self, $value, $type ) = @_;
		local $@ = undef;
		my $code = eval "sub { $value }"
		    or return 0;
		push @{ $self->{_type_add}{firstlinematch} }, [ $code, $type ];
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
		return 0;
	    },
	};
	my $setup = $handler->{$name}
	    or $self->__confess( "Unknown type handler '$name'" );

	$self->{_type_def}{$type} = 1;

	$setup->( $self, $type )
	    or return 1;

	$code->( $self, $data, $type )
	    or return 0;
    }
    return 1;
}

1;

__END__

=head1 NAME

App::Sam - Search for strings in files, and possibly modify them

=head1 SYNOPSIS

 use App::Sam;
 my $sad = App::Sam->new(
   backup  => '.bak',
   match   => '\bfoo\b',
   replace => 'bar',
 );
 $sad->process( 'foo.txt' );

=head1 DESCRIPTION

This Perl class finds strings in files, possibly modifying them. It was
inspired by L<ack|ack>.

=head1 METHODS

This class supports the following public methods:

=head2 new

 my $sad = App::Sam->new();

This static method instantiates an application object. It takes the
following named arguments:

=over

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
is false. A true value will be igored if C<$Carp::verbose> is true.

=item C<dry_run>

If this Boolean argument is true, modified files are not rewritten, nor
are the originals backed up. The default is false.

=item C<encoding>

This argument specifies the encoding to use to read and write files. The
default is C<'utf-8'>.

=item C<filter_files_from>

This Boolean argument specifies whether files obtained by calling
L<files_from|/files_from> should be filtered. The default is false,
which is consistent with L<ack|ack>.

=item C<ignore_case>

If this Boolean argument is true, the match argument ignores case.

=item C<ignore_sad_defaults>

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

=item C<word_regexp>

If this Boolean argument is true, then if the beginning and/or end of
the match expression is a word character, a C<\b> assertion will be
prepended/appended. That is to say, C<foo> will become C<\bfoo\b>, but
C<(foo)> will remain C<(foo)>.

=back

=head2 files_from

Given the name of a file, this method reads it and returns its contents,
one line at a time, and C<chomp>-ed. These are assumed to be file names,
and will be filtered if C<filter_files_from> is true.

=head2 process

 $sad->process( $file )

This method processes a single file or directory. Match output is
written to F<STDOUT>. If any files are modified, the modified file is
written.

The argument can be a scalar reference, but in this case modifications
are not written.

Binary files and directories are ignored.

If the file is a directory, any files in the direcory are processed
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

Copyright (C) 2023 by Thomas R. Wyant, III

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl 5.10.0. For more details, see the full text
of the licenses in the directory LICENSES.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=cut

# ex: set textwidth=72 :

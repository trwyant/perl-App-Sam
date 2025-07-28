package App::Sam::Util;

use 5.010001;

use strict;
use warnings;

use Carp ();
use Exporter qw{ import };
use File::Glob qw{ GLOB_ERR GLOB_TILDE };
use Term::ANSIColor ();

our $VERSION = '0.000_006';

our @EXPORT_OK = qw{
    __carp
    __confess
    __croak
    __expand_tilde
    __fold_case
    __match_shebang
    __me
    __syntax_types
    __todo
    RE_CASE_BLIND
    RE_CASE_SMART
    RE_CASE_SENSITIVE
    SYNTAX_CODE
    SYNTAX_COMMENT
    SYNTAX_DATA
    SYNTAX_DOCUMENTATION
    SYNTAX_METADATA
    SYNTAX_PREPROCESSOR
    SYNTAX_OTHER
    TERM_ANSI_CLR_EOL
    TERM_ANSI_RESET_COLOR
    @CARP_NOT
};

our %EXPORT_TAGS = (
    all		=> \@EXPORT_OK,
    carp	=> [ qw{ __carp __confess __croak __todo } ],
    case	=> [ qw{ __fold_case }, grep { m/ \A RE_CASE_ /smx }
	@EXPORT_OK ],
    syntax	=> [ grep { m/ \A SYNTAX_ /smx } @EXPORT_OK ],
    term_ansi	=> [ grep { m/ \A TERM_ANSI_ /smx } @EXPORT_OK ],
);

our @CARP_NOT = qw{
    App::Sam
    App::Sam::Resource
    App::Sam::Syntax
    App::Sam::Syntax::Ada
    App::Sam::Syntax::Batch
    App::Sam::Syntax::Cc
    App::Sam::Syntax::Cpp
    App::Sam::Syntax::Data
    App::Sam::Syntax::Fortran
    App::Sam::Syntax::Java
    App::Sam::Syntax::Lisp
    App::Sam::Syntax::Make
    App::Sam::Syntax::Pascal
    App::Sam::Syntax::Perl
    App::Sam::Syntax::Properties
    App::Sam::Syntax::Python
    App::Sam::Syntax::Raku
    App::Sam::Syntax::SQL
    App::Sam::Syntax::Shell
    App::Sam::Syntax::Swift
    App::Sam::Syntax::Vim
    App::Sam::Syntax::YAML
    App::Sam::Syntax::_cc_like
    App::Sam::Tplt
    App::Sam::Tplt::Color
    App::Sam::Tplt::Under
    App::Sam::Util
};

# NOTE that RE_CASE_SENSITIVE must be false, and the others must be
# true.
use enum qw{ ENUM:
    RE_CASE_SENSITIVE=0
    RE_CASE_BLIND
    RE_CASE_SMART
};

use constant SYNTAX_CODE		=> 'code';
use constant SYNTAX_COMMENT		=> 'comment';
use constant SYNTAX_DATA		=> 'data';
use constant SYNTAX_DOCUMENTATION	=> 'documentation';
use constant SYNTAX_METADATA		=> 'metadata';
use constant SYNTAX_OTHER		=> 'other';
use constant SYNTAX_PREPROCESSOR	=> 'preprocessor';

use constant TERM_ANSI_CLR_EOL		=> "\e[K";
use constant TERM_ANSI_RESET_COLOR	=> Term::ANSIColor::color( 'reset' );

sub __carp {
    my ( $self, @arg ) = @_;
    @arg
	or @arg = ( 'Warning' );
    if ( $self->{die} ) {
	warn _decorate_die_args( $self, @arg );
    } else {
	local $Carp::CarpLevel = $Carp::CarpLevel + 1;
	Carp::carp( _decorate_croak_args( $self, @arg ) );
    }
    return;
}

sub __confess {
    my ( $self, @arg ) = @_;
    unshift @arg, @arg ? 'Bug - ' : 'Bug';
    if ( $self->{die} ) {
	state $me = sprintf '%s: ', __me();
	unshift @arg, $me;
    }
    # local $! = 0;	# Force exit status.
    # local $@ = undef;	# Force exit status.
    local $Carp::CarpLevel = $Carp::CarpLevel + 1;
    Carp::confess( _decorate_croak_args( $self, @arg ) );
}

sub __croak {
    my ( $self, @arg ) = @_;
    @arg
	or @arg = ( 'Died' );
    # local $! = 0;	# Force exit status.
    # local $@ = undef;	# Force exit status.
    if ( $self->{die} ) {
	die _decorate_die_args( $self, @arg );
    } else {
	local $Carp::CarpLevel = $Carp::CarpLevel + 1;
	Carp::croak( _decorate_croak_args( $self, @arg ) );
    }
}

# NOTE that when this has been called, $! has already been set to 1 to
# force that as an exit status. So its value is useless, and it MUST
# NOT be changed.
sub _decorate_croak_args {
    my ( undef, @arg ) = @_;	# $self unused
    chomp $arg[-1];
    $arg[-1] =~ s/ [.?!] //smx;
    return @arg;
}

sub _decorate_die_args {
    my ( undef, @arg ) = @_;	# $self unused
    chomp $arg[-1];
    $arg[-1] =~ s/ (?<! [.?!] ) \z /./smx;
    $arg[-1] .= $/;
    state $me = sprintf '%s: ', __me();

    # NOTE that this guard is needed because the exception may get
    # caught and re-thrown multiple times. This is probably an argument
    # for an exception argument.
    @arg
	and index( $arg[0], $me ) == 0
	or unshift @arg, $me;
    return @arg;
}

sub __expand_tilde {
    my ( $path ) = @_;
    index( $path, '~' ) == 0
	or return $path;
    my $rslt;
    defined( $rslt = File::Glob::bsd_glob( $path, GLOB_TILDE ) )
	and return $rslt;
    my ( $first, $rest ) = split /\//, $path, 2;
    defined( $rslt = File::Glob::bsd_glob( $first, GLOB_TILDE ) )
	and return "$rslt/$rest";
    return $path;
}

# NOTE that I have to use this dodge under 5.10.1, because even though
# the 'CORE::fc' branch is not taken, the code gets compiled.
if ( "$]" >= 5.015008 ) {
    eval 'sub __fold_case { CORE::fc( $_[0] ) }'; ## no critic (ProhibitStringyEval, RequireCheckingReturnValueOfEval)
} else {
    eval 'sub __fold_case { lc( $_[0] ) }'; ## no critic (ProhibitStringyEval, RequireCheckingReturnValueOfEval)
}

sub __match_shebang {
    return ! index $_, '#!';
}

sub __me {
    state $me = ( File::Spec->splitpath( $0 ) )[2];
    return $me;
}

sub __syntax_types {
    state $types = [ map { __PACKAGE__->$_() } @{ $EXPORT_TAGS{syntax} } ];
    return @{ $types };
}

sub __todo {
    my ( $self, @arg ) = @_;
    unshift @arg, @arg ? 'Bug - ' : 'Bug';
    local $! = 0;	# Force exit status.
    local $@ = undef;	# Force exit status.
    if ( ref( $self ) && $self->{die} ) {
	die _decorate_die_args( $self, @arg );
    } else {
	local $Carp::CarpLevel = $Carp::CarpLevel + 1;
	Carp::croak( _decorate_croak_args( $self, @arg ) );
    }
}

1;

__END__

=head1 NAME

App::Sam::Util - Miscellaneous code for App-Sam.

=head1 SYNOPSIS

 use App::Sam::Util qw{ :carp };
 ...
 $self->__carp( 'Something may have gone wrong' );

=head1 DESCRIPTION

This Perl module is a catch-all for stuff that had no other obvious
place to live. It is B<private> to the C<App-Sam> package, and the user
does not interact with it directly.

This module may be changed or retracted without notice. Documentation is
for the convenience of the author.

=head1 SUBROUTINES

This module provides the following package-private subroutines:

=head2 __carp

 $self->__carp( 'Something may have gone wrong' );

This mixin displays the given message using either C<warn()> if
the invocant's C<die> attribute is true, or C<carp()> if not.

It can be imported by name or using the C<:carp> tag.

=head2 __confess

 $self->__confess( 'Something went horribly wrong' );

This mixin displays the given message using C<confess()>.

It can be imported by name or using the C<:carp> tag.

=head2 __croak

 $self->__croak( 'Something definitely went wrong' );

This mixin displays the given message using either C<die()> if
the invocant's C<die> attribute is true, or C<croak()> if not.

It can be imported by name or using the C<:carp> tag.

=head2 __expand_tilde

 say 'Home dir: ', __expand_tilde( '~' );

This subroutine expands a leading tilde in a POSIX file spec, if any.
The expansion is returned. If there was no leading tilde or if the
expansion failed, the original argument is returned.

=head2 __fold_case

This subroutine returns its argument case-folded. Under Perl 5.15.8 this
is done using the C<fc()> built-in. Under earlier Perls this was not
available, so C<lc()> is used instead.

=head2 __match_shebang

This is a generic shebang line matcher that can be imported into syntax
classifiers that need it. All it does is to return a true value if C<$_>
starts with C<'#!'>.

=head2 __me

This returns the base name of the currently-running script, as
determined from C<$0> at the time it is first called.

=head2 __syntax_types

This subroutine returns the names of all syntax types as defined by
C<SYNTAX_*> L<MANIFEST CONSTANTS|/MANIFEST CONSTANTS> (see below).

It can be imported by name.

=head2 __todo

 $self->__todo( 'This needs doing' );

This mixin displays the given message using either C<die()> if
the invocant's C<die> attribute is true, or C<croak()> if not. It can be
called as a static method, in which case it will call C<croak()>.

The message is prefaced with C<'TODO - '>.

It can be imported by name or using the C<:carp> tag.

=head1 ARRAYS

This subroutine provides the following package-private C<our> arrays

=head2 @CARP_NOT

This C<our> array contains the names of all modules in the package.
L<Carp|Carp> makes use of it to determine how far up the call stack to
go.

=head1 MANIFEST CONSTANTS

This module provides the following package-private manifest constants:

=head2 RE_CASE_BLIND

This enumerated value specifies that the match expression is to be
case-blind.

=head2 RE_CASE_SENSITIVE

This enumerated value specifies that the match expression is to be
case-sensitive.

=head2 RE_CASE_SMART

This enumerated value specifies that the match expression is to be
treated as case-sensitive if it contains any literal upper-case
characters, and case-blind if not.

=head2 SYNTAX_CODE

This syntax type represents code.

It can be imported by name or using the C<:syntax> tag.

=head2 SYNTAX_COMMENT

This syntax type represents comments.

It can be imported by name or using the C<:syntax> tag.

=head2 SYNTAX_DATA

This syntax type represents data.

It can be imported by name or using the C<:syntax> tag.

=head2 SYNTAX_DOCUMENTATION

This syntax type represents documentation.

It can be imported by name or using the C<:syntax> tag.

=head2 SYNTAX_METADATA

This syntax type represents metadata.

It can be imported by name or using the C<:syntax> tag.

=head2 SYNTAX_OTHER

This syntax type represents other syntax.

It can be imported by name or using the C<:syntax> tag.

=head2 SYNTAX_PREPROCESSOR

This syntax type represents preprocessor directives.

It can be imported by name or using the C<:syntax> tag.

=head2 TERM_ANSI_CLR_EOL

This manifest constant represents the ANSI escape sequence to clear from
the cursor to the end of the line.

It can be imported by name or using the C<:term_ansi> tag.

=head2 TERM_ANSI_RESET_COLOR

This manifest constant represents the ANSI escape sequence to clear
reset character and background color to the default.

It can be imported by name or using the C<:term_ansi> tag.

=head1 EXPORT TAGS

The following export tags are supported:

=head2 all

This imports everything.

=head2 carp

This imports __carp(), __confess(), __croak(), and __todo().

=head2 case

This imports __fold_case() and the C<RE_CASE_*> manifest constants.

=head2 syntax

This imports the C<SYNTAX_*> manifest constants.

=head2 term_ansi

This imports the C<TERM_ANSI_*> manifest constants.

=head1 SEE ALSO

L<App::Sam|App::Sam>.

=head1 SUPPORT

Support is by the author. Please file bug reports at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=App-Sam>,
L<https://github.com/trwyant/perl-App-Sam/issues/>, or in
electronic mail to the author.

=head1 AUTHOR

Thomas R. Wyant, III F<wyant at cpan dot org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2024 by Thomas R. Wyant, III

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl 5.10.0. For more details, see the full text
of the licenses in the directory LICENSES.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=cut

# ex: set textwidth=72 :

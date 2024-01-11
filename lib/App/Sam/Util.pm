package App::Sam::Util;

use 5.010;

use strict;
use warnings;

use Carp ();
use Exporter qw{ import };

our $VERSION = '0.000_001';

our @EXPORT_OK = qw{
    __carp
    __confess
    __croak
    __syntax_types
    SYNTAX_CODE
    SYNTAX_COMMENT
    SYNTAX_DATA
    SYNTAX_DOCUMENTATION
    SYNTAX_METADATA
    SYNTAX_PREPROCESSOR
    SYNTAX_OTHER
    @CARP_NOT
};

our %EXPORT_TAGS = (
    carp	=> [ qw{ __carp __confess __croak } ],
    syntax	=> [ grep { m/ \A SYNTAX_ /smx } @EXPORT_OK ],
);

our @CARP_NOT = qw{
    App::Sam
    App::Sam::Syntax
    App::Sam::Syntax::Cc
    App::Sam::Syntax::Cpp
    App::Sam::Syntax::Make
    App::Sam::Syntax::Perl
    App::Sam::Syntax::_cc_like
    App::Sam::Util
};

use constant SYNTAX_CODE		=> 'code';
use constant SYNTAX_COMMENT		=> 'comment';
use constant SYNTAX_DATA		=> 'data';
use constant SYNTAX_DOCUMENTATION	=> 'documentation';
use constant SYNTAX_METADATA		=> 'metadata';
use constant SYNTAX_OTHER		=> 'other';
use constant SYNTAX_PREPROCESSOR	=> 'preprocessor';

sub __carp {
    my ( $self, @arg ) = @_;
    @arg
	or @arg = ( 'Warning' );
    if ( $self->{die} ) {
	warn _decorate_die_args( $self, @arg );
    } else {
	Carp::carp( _decorate_croak_args( $self, @arg ) );
    }
    return;
}

sub __confess {
    my ( $self, @arg ) = @_;
    unshift @arg, @arg ? 'Bug - ' : 'Bug';
    if ( $self->{die} ) {
	state $me = sprintf '%s: ', $self->__me();
	unshift @arg, $me;
    }
    Carp::confess( _decorate_croak_args( $self, @arg ) );
}

sub __croak {
    my ( $self, @arg ) = @_;
    @arg
	or @arg = ( 'Died' );
    if ( $self->{die} ) {
	die _decorate_die_args( $self, @arg );
    } else {
	Carp::croak( _decorate_croak_args( $self, @arg ) );
    }
}

sub _decorate_croak_args {
    my ( undef, @arg ) = @_;	# $self unused
    chomp $arg[-1];
    $arg[-1] =~ s/ [.?!] //smx;
    return @arg;
}

sub _decorate_die_args {
    my ( $self, @arg ) = @_;
    chomp $arg[-1];
    $arg[-1] =~ s/ (?<! [.?!] ) \z /./smx;
    $arg[-1] .= $/;
    state $me = sprintf '%s: ', $self->__me();
    unshift @arg, $me;
    return @arg;
}

sub __syntax_types {
    state $types = [ map { __PACKAGE__->$_() } @{ $EXPORT_TAGS{syntax} } ];
    return @{ $types };
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

This mixin calls displays the given message using either C<warn()> if
the invocant's C<die> attribute is true, or C<carp()> if not.

It can be imported by name or using the C<:carp> tag.

=head2 __confess

 $self->__confess( 'Something went horribly wrong' );

This mixin calls displays the given message using C<confess()>.

It can be imported by name or using the C<:carp> tag.

=head2 __croak

 $self->__croak( 'Something definitely went wrong' );

This mixin calls displays the given message using either C<die()> if
the invocant's C<die> attribute is true, or C<croak()> if not.

It can be imported by name or using the C<:carp> tag.

=head2 __syntax_types

This subroutine returns the names of all syntax types as defined by
C<SYNTAX_*> L<MANIFEST CONSTANTS|/MANIFEST CONSTANTS> (see below).

It can be imported by name.

=head1 ARRAYS

This subroutine provides the following package-private C<our> arrays

=head2 @CARP_NOT

This C<our> array contains the names of all modules in the package.
L<Carp|Carp> makes use of it to determine how far up the call stack to
go.

=head1 MANIFEST CONSTANTS

This module provides the following package-private manifest constants:

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


=head1 SEE ALSO

L<App::Sam|App::Sam>.

=head1 SUPPORT

Support is by the author. Please file bug reports at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=App-Sad>,
L<https://github.com/trwyant/perl-App-Sad/issues/>, or in
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
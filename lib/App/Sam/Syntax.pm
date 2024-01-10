package App::Sam::Syntax;

use 5.010;

use strict;
use warnings;

use App::Sam::Util qw{ :carp :syntax };

our $VERSION = '0.000_001';

sub new {
    my ( $class, %arg ) = @_;
    my $self = bless {
	die	=> delete $arg{die},
    }, $class;
    $self->__init( \%arg );
    keys %arg
	and $self->__confess( 'Unsupported arguments to new()' );
    return $self;
}

sub __init {
    my ( $self ) = @_;
    $self->{in} = SYNTAX_CODE;
    return;
}

sub __syntax {
    my ( $self ) = @_;
    my $in = $self->{in};
    my $code = $self->can( "__syntax_$in" )
	or $self->__confess( "__syntax_$in() not implemented" );
    goto &$code;
}

1;

__END__

=head1 NAME

App::Sam::Syntax - Superclass for syntax classification hierarchy

=head1 SYNOPSIS

The user has no direct interaction with this module.

=head1 DESCRIPTION

This Perl class is the base of the syntax classification hierarchy. It
is B<private> to the C<App-Sam> package, and the user does not interact
with it directly.

This module may be changed or retracted without notice. Documentation is
for the convenience of the author.

L<App::Sam|App::Sam> syntax classification works on a per-line model,
which works well for line-oriented languages like Fortran, and less well
for stream-oriented languages like C.

Typically a line of code containing an end-of-line comment will be
classified as code. Multi-line C-style comments may not be recognized at
all unless they start on a line by themselves. This kind of thing
depends on how smart the syntax classifier involved is. Because the
author believes that code is likely to be of greater interest than the
other syntax types, the author recommends classifying a line as code if
in doubt.

Syntax classifiers are implemented as state machines.

=head1 METHODS

This class provides the following package-private methods:

=head2 new

This static method instantiates and returns a syntax classification
object. Arguments are specified as name-value pairs. The only argument
supported at this level of the hierarchy is C<die>, which is used by the
warning and error reporting system.

This method also calls C<< $self->__init( %arg ) >> to initialize the
object, passing it a reference to its argument hash.
C<__init()> is expected to remove any arguments it uses. If there are
any arguments left in the hash, a fatal error is declared, with stack
dump.

=head2 __init

This method initializes the state machine by setting C<< $self->{in} >>
to the initial syntax. It is called by L<new()|/new> and passed a
reference to its argument hash. It is expected to remove any arguments
it actually uses.

At this level of the hierarchy C<< $self->{in} >> is set to
C<SYNTAX_CODE>, and no arguments are removed.

Overrides to this method need not call C<< $self->SUPER::__init() >>
B<provided> they set C<< $self->{in} >> themselves.

=head2 __syntax

This method dispatches the handler for the current state, as described
below. It has no arguments other than its invocant. The line being
classified is in C<$_>.

The subclass is expected to implement methods to handle the current
state of the parse. These are allowed to examine (but not modify!)
C<$_>, and to change the value of C<< $self->{in} >>. They B<must>
return the syntax type of the current line, selected from

 SYNTAX_CODE
 SYNTAX_COMMENT
 SYNTAX_DATA
 SYNTAX_DOCUMENTATION
 SYNTAX_METADATA
 SYNTAX_OTHER
 SYNTAX_PREPROCESSOR

The expected methods are

 __syntax_code()
 __syntax_comment()
 __syntax_data()
 __syntax_documentation()
 __syntax_metadata()
 __syntax_other()
 __syntax_preprocessor()

The subclass need not (and probably should not) implement subroutines
corresponding to syntax types that can not occur.

The C<'other'> syntax type is provided as a catch-all, but the author's
strongly-held opinion that it should not be used.

=head1 SEE ALSO

C<App::Sam|App::Sam>.

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

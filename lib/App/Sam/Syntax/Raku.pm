package App::Sam::Syntax::Raku;

use 5.010001;

use strict;
use warnings;

use parent qw{ App::Sam::Syntax };

use App::Sam::Util qw{ :syntax __match_shebang @CARP_NOT };
use Readonly;

our $VERSION = '0.000_006';

Readonly::Scalar my $open_brkt => join '',
    "\N{U+0028}",	# Left parenthesis
    "\N{U+007B}",	# Left curly bracket
    "\N{U+005B}",	# Left square bracket
    "\N{U+00AB}";	# Left-pointing double angle quotation mark

sub __classifications {
    return ( SYNTAX_CODE, SYNTAX_COMMENT, SYNTAX_DOCUMENTATION,
	SYNTAX_METADATA );
}

sub __classify_code {
    my ( $self ) = @_;
    if ( m/ \A \s* \# /smxg ) {
	m/ \G ` ( ( [$open_brkt] ) \g{-1}* ) /smxgco and do {
	    my $close_brkt = _close_bracket( $1 );
	    index( $_, $close_brkt ) >= 0
		and return SYNTAX_COMMENT;
	    $self->{in} = SYNTAX_COMMENT;
	    $self->{Block_end} = $close_brkt;
	};
	m/ \G [|=] ( [$open_brkt] )? /smxgo and do {
	    $1
		or return SYNTAX_DOCUMENTATION;
	    $self->{Block_end} = _close_bracket( $1 );
	    $self->{in} = SYNTAX_DOCUMENTATION;
	    return SYNTAX_DOCUMENTATION;
	};
	return SYNTAX_COMMENT;
    }
    goto &__classify_data;
}

sub __classify_comment {
    my ( $self ) = @_;
    index( $_, $self->{Block_end} ) >= 0 and do {
	$self->{in} = SYNTAX_CODE;
	delete $self->{Block_end};
    };
    return SYNTAX_COMMENT;
}

# NOTE: MUST NOT be called if $self->{in} is 'documentation'
sub __classify_data {
    my ( $self ) = @_;

    m/ \A = begin \s+ pod \b /smx
	or return $self->{in};

    $self->{Cut} = $self->{in};
    $self->{in} = SYNTAX_DOCUMENTATION;
    return SYNTAX_DOCUMENTATION;
}

sub __classify_documentation {
    my ( $self ) = @_;
    if ( defined $self->{Block_end} &&
	index( $_, $self->{Block_end} ) >= 0
    ) {
	$self->{in} = delete( $self->{Cut} ) // SYNTAX_CODE;
	delete $self->{Block_end};
    } elsif ( m/ \A = end \s+ pod \b /smx ) {
	$self->{in} = delete( $self->{Cut} ) // SYNTAX_CODE;
    }
    return SYNTAX_DOCUMENTATION;
}

sub _close_bracket {
    my ( $brkt ) = @_;
    $brkt =~ tr/({[<\N{U+AB}/)}]>\N{U+BB}/;
    return $brkt;
}

1;

__END__

=head1 NAME

App::Sam::Syntax::Raku - Classify Raku syntax

=head1 SYNOPSIS

The user has no direct interaction with this module.

=head1 DESCRIPTION

This Perl class is a subclass of L<App::Sam::Syntax|App::Sam::Syntax>.
It is B<private> to the C<App-Sam> package, and the user does not
interact with it directly.

This module may be changed or retracted without notice. Documentation is
for the convenience of the author.

The syntax types produced by this module are

=over

=item * SYNTAX_CODE

Of course.

=item * SYNTAX_COMMENT

Any line whose first non-blank character is C<'#'>.

=item * SYNTAX_DOCUMENTATION

POD.

=item * SYNTAX_METADATA

The shebang line, C<__DATA__>, C<__END__>, and the C<#line> directive.

=back

This classifier can be used for Raku.

=head1 METHODS

This class does not provide any methods over and above those of its
superclass.

=head1 SEE ALSO

L<App::Sam|App::Sam>

L<App::Sam::Syntax|App::Sam::Syntax>

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

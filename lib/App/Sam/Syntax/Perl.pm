package App::Sam::Syntax::Perl;

use 5.010001;

use strict;
use warnings;

use parent qw{ App::Sam::Syntax };

use App::Sam::Util qw{ :syntax __match_shebang @CARP_NOT };

our $VERSION = '0.000_008';

sub __classifications {
    return ( SYNTAX_CODE, SYNTAX_COMMENT, SYNTAX_DATA,
	SYNTAX_DOCUMENTATION, SYNTAX_METADATA );
}

sub __classify_code {
    my ( $self ) = @_;
    if ( m/ \A \s* \# /smx ) {
	m/ \A \#line \s+ [0-9]+ /smx
	    and return SYNTAX_METADATA;
	return SYNTAX_COMMENT;
    }
    state $is_data = { map {; "__${_}__\n" => 1 } qw{ DATA END } };
    if ( $is_data->{$_} ) {
	$self->{in} = SYNTAX_DATA;
	return SYNTAX_METADATA;
    }
    goto &__classify_data;
}

# NOTE: MUST NOT be called if $self->{in} is 'documentation'
sub __classify_data {
    my ( $self ) = @_;
    if ( m/ \A = ( cut \b | [A-Za-z] ) /smx ) {
	'cut' eq $1
	    and return SYNTAX_DOCUMENTATION;
	$self->{Cut} = $self->{in};
	$self->{in} = SYNTAX_DOCUMENTATION;
    }
    return $self->{in};
}

sub __classify_documentation {
    my ( $self ) = @_;
    m/ \A = cut \b /smx
	and $self->{in} = delete $self->{Cut};
    return SYNTAX_DOCUMENTATION;
}

1;

__END__

=head1 NAME

App::Sam::Syntax::Perl - Classify Perl syntax

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

=item * SYNTAX_DATA

Anything after C<__DATA__> or C<__END__> except embedded POD.

=item * SYNTAX_DOCUMENTATION

POD.

=item * SYNTAX_METADATA

The shebang line, C<__DATA__>, C<__END__>, and the C<#line> directive.

=back

This classifier can be used for Perl, including F<.pod> files.

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

Copyright (C) 2024-2025 by Thomas R. Wyant, III

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl 5.10.0. For more details, see the full text
of the licenses in the files F<LICENSE-Artistic> and F<LICENSE-GNU>.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=cut

# ex: set textwidth=72 :

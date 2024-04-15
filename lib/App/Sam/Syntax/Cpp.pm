package App::Sam::Syntax::Cpp;

use 5.010001;

use strict;
use warnings;

use parent qw{ App::Sam::Syntax::_cc_like };

use App::Sam::Util qw{ :syntax @CARP_NOT };

our $VERSION = '0.000_006';

sub __classifications {
    return ( SYNTAX_CODE, SYNTAX_COMMENT, SYNTAX_DOCUMENTATION,
	SYNTAX_PREPROCESSOR );
}

sub __match_single_line_comment {
    return m| \A \s* // |smx;
}

sub __match_block_documentation_start {
    return m| \A \s* / [*] [*] |smx;
}

sub __match_block_documentation_end {
    return index( $_, '*/' ) >= 0;
}


1;

__END__

=head1 NAME

App::Sam::Syntax::Cpp - Classify C++ syntax

=head1 SYNOPSIS

The user has no direct interaction with this module.

=head1 DESCRIPTION

This Perl class is a subclass of
L<App::Sam::Syntax::_cc_like|App::Sam::Syntax::_cc_like>.
It is B<private> to the C<App-Sam> package, and the user does not
interact with it directly.

This module may be changed or retracted without notice. Documentation is
for the convenience of the author.

The syntax types produced by this module are

=over

=item * SYNTAX_CODE

Of course.

=item * SYNTAX_COMMENT

This is a C-style comment delimited by C</*> and C<*/>, or a C++-style
single-line comment introduced by C<//>. Comments will be recognized
only if there is only white space before the beginning of the comment.

=item * SYNTAX_DOCUMENTATION

This is C++-style documentation delimited by C</**> and C<*/>.
Documentation will be recognized only if there is only white space
before the beginning of the comment.

=item * SYNTAX_PREPROCESSOR

Preprocessor directives.

=back

This classifier can be used for C++.

=head1 METHODS

This class does not provide any methods over and above those of its
superclass.

=head1 SEE ALSO

L<App::Sam|App::Sam>

L<App::Sam::Syntax|App::Sam::Syntax>

L<App::Sam::Syntax::_cc_like|App::Sam::Syntax::_cc_like>

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

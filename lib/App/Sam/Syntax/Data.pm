package App::Sam::Syntax::Data;

use 5.010001;

use strict;
use warnings;

use parent qw{ App::Sam::Syntax };

use App::Sam::Util qw{ :syntax @CARP_NOT };

our $VERSION = '0.000_007';

sub __classifications {
    return ( SYNTAX_DATA );
}

sub __classify {
    return SYNTAX_DATA;
}

1;

__END__

=head1 NAME

App::Sam::Syntax::Data - Classify pure data files.

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

=item * SYNTAX_DATA

Of course.

=back

This classifier can be used for any file containing only data.

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

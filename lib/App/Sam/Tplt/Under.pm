package App::Sam::Tplt::Under;

use 5.010001;

use strict;
use warnings;

use parent qw{ App::Sam::Tplt };

use App::Sam::Util qw{ :carp @CARP_NOT };

our $VERSION = '0.000_003';

sub __default {
    my ( $self ) = @_;
    $self->SUPER::__default();
    $self->{underline} //= '^';
    return;
}

sub __extra_args {
    return qw{ underline };
}

sub __format_item {
    my ( $self, $item ) = @_;
    my $rslt = $self->SUPER::__format_item( $item );
    $rslt =~ tr/\0\a\e//d;
    $rslt eq ''
	and return $rslt;
    state $is_match = { map { $_ => 1 } qw{ $& $r } };
    if ( $is_match->{$item} ) {
	$rslt =~ s/ [[:^cntrl:]] /$self->{underline}/smxg;
    } else {
	$rslt =~ s/ [[:^cntrl:]] / /smxg;
    }
    return $rslt;
}

sub line {
    my ( $self ) = @_;
    $self->{line} =~ m/ \S /smx
	or return '';
    return $self->{line};
}

1;

__END__

=head1 NAME

App::Sam::Tplt::Under - Underline generator template for App::Sam

=head1 SYNOPSIS

No user-serviceable parts inside.

=head1 DESCRIPTION

This Perl class implements a template system for the benefit of
L<App::Sam|App::Sam>. This system is a superset of the L<ack|ack> system
used in its C<--output> processing. This class is a subclass of
L<App::Sam::Tplt|App::Sam::Tplt> that produces underlines.

This Perl module is B<private> to the C<App-Sam> package. It can be
changed or revoked at any time. All documentation is for the benefit of
the author.
<<< replace boilerplate >>>

=head1 METHODS

This class provides no new methods.

=head1 SEE ALSO

L<App::Sam|App::Sam>

L<App::Sam::Tplt|App::Sam::Tplt>

L<ack|ack>

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

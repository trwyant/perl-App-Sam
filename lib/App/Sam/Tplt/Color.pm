package App::Sam::Tplt::Color;

use 5.010001;

use strict;
use warnings;

use parent qw{ App::Sam::Tplt };

use App::Sam::Util qw{ :carp :term_ansi @CARP_NOT };
use Term::ANSIColor 4.03 ();	# for colorvalid

our $VERSION = '0.000_007';

sub __color {
    my ( $self, $kind, $text ) = @_;
    state $color_unconditionally = { map { $_ => 1 } qw{ filename lineno } };
    # FIXME {flags}
    # unless ( $self->{flags} & FLAG_FAC_NO_MATCH_PROC ||
    unless ( $color_unconditionally->{$kind} ) {
	$self->{matched}
	    or return $text;
    }
    $self->{no_color}{$kind}
	and return $text;
    state $uncolored = { map { $_ => 1 } '', "\n" };
    $uncolored->{$text}
	and return $text;
    defined( my $color = $self->{"color_$kind"} )
	or $self->__confess( "Invalid color kind '$kind'" );
    $self->{colored} = 1;
    return Term::ANSIColor::colored( $text, $color );
}

sub __default {
    my ( $self ) = @_;
    $self->SUPER::__default();
    $self->{color_colno}	//= 'bold yellow';
    $self->{color_filename}	//= 'bold green';
    $self->{color_lineno}	//= 'bold yellow';
    $self->{color_match}	//= 'black on_yellow';
    $self->{color_ors}		//= TERM_ANSI_CLR_EOL;
    return;
}

sub __extra_args {
    return qw{ color_colno color_filename color_lineno color_match
    color_ors };
}

sub __format_item_ctrl_n {
    my ( $self ) = @_;
    $self->{colored}
	or return $self->SUPER::__format_item_ctrl_n();
    $self->{colored} = 0;
    return $self->{color_ors} . $self->SUPER::__format_item_ctrl_n();
}

sub __init {
    my ( $self ) = @_;
    $self->{colored} = 0;
    return $self->SUPER::__init();
}

sub __format_item_dollar_r {
    my ( $self ) = @_;
    state $no_color = { map { $_ => 1 } qw{ match } };
    return $self->__color( match => do {
	    local $self->{no_color} = $no_color;
	    $self->execute_template( $self->{replace_tplt} );
	},
    );
}

1;

__END__

=head1 NAME

App::Sam::Tplt::Color - Colored template system for App::Sam

=head1 SYNOPSIS

No user-serviceable parts inside.

=head1 DESCRIPTION

This Perl class implements a template system for the benefit of
L<App::Sam|App::Sam>. This system is a superset of the L<ack|ack> system
used in its C<--output> processing. This class is a subclass of
L<App::Sam::Tplt|App::Sam::Tplt> that produces colored output.

This Perl module is B<private> to the C<App-Sam> package. It can be
changed or revoked at any time. All documentation is for the benefit of
the author.

=head1 METHODS

This class provides no new methods. However:

=head2 new

This static method adds the following arguments:

=over

=item color_column - the color for the C<$c> item

=item color_filename - the color for the C<$f> item

=item color_lineno - the color for the C<$.> item

=item color_match - the color for the C<$&> item

=item color_ors - the literal escape sequence to color a line break (default: "\e[K")

=back

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

Copyright (C) 2024-2025 by Thomas R. Wyant, III

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl 5.10.0. For more details, see the full text
of the licenses in the directory LICENSES.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=cut

# ex: set textwidth=72 :

package App::Sam::Tplt;

use 5.010001;

use strict;
use warnings;

use App::Sam::Util qw{ :carp @CARP_NOT };

our $VERSION = '0.000_001';

sub new {
    my ( $class, %arg ) = @_;
    my $self = bless {
	map { $_ => delete $arg{$_} } qw{
	    die filename finalize_tplt match_tplt ors prefix_tplt replace_tplt
	},
	$class->__extra_args()
    }, $class;
    $self->__default();
    return $self;
}

sub __color {
    my ( undef, undef, $text ) = @_;	# $self and $kind not used
    return $text;
}

sub __default {
    my ( $self ) = @_;
    $self->{die} //= 0;
    $self->{ors} //= "\n";
    defined $self->{replace_tplt}
	and $self->_validate_replace_tplt( $self->{replace_tplt} );
    $self->{match_tplt} = $self->_validate_match_tplt(
	$self->{match_tplt} // '$p$&' );
    $self->{prefix_tplt} = $self->_validate_prefix_tplt(
	$self->{prefix_tplt} // '' );
    $self->{finalize_tplt} = $self->_validate_finalize_tplt(
	$self->{finalize_tplt} // '$p\\n' );

    return;
}

sub execute_template {
    my ( $self, $tplt ) = @_;
    {
	$tplt =~ s( ( [\\\$] . ) )
	    ( $self->__format_item( $1 ) )smxge;
    }
    return $tplt;
}

sub __extra_args {
    return;
}

sub finalize {
    my ( $self ) = @_;
    $self->{capt} = [];
    $self->{match_start} = [ length ];
    $self->{match_end} = [ length ];
    $self->{paren_match} = '';
    $self->{last_pos} = $self->{curr_pos};
    $self->{curr_pos} = length;
    return $self->__format_line( $self->{finalize_tplt} );
}

sub __format_line {
    my ( $self, $tplt ) = @_;
    my $rslt;
    defined $self->{line}
	or $rslt .= $self->execute_template( $self->{prefix_tplt} );
    $rslt .= $self->execute_template( $tplt );
    $self->{line} .= $rslt;
    return $rslt;
}

sub __format_item {
    my ( $self, $item ) = @_;
    state $capt = sub {
	$_[0]->{capt}[$_[1]] // substr $_,
	$_[0]->{match_start}[$_[1]],
	$_[0]->{match_end}[$_[1]] - $_[0]->{match_start}[$_[1]]
    };
    # NOTE that the __format_item_* routines are represented in the
    # following by name rather than as code references so that they can
    # be overridden.
    state $hdlr = {
	'\\0'	=> sub { "\0" },
	'\\a'	=> sub { "\a" },
	'\\b'	=> sub { "\b" },
	'\\e'	=> sub { "\e" },
	'\\f'	=> sub { "\f" },
	'\\n'	=> '__format_item_ctrl_n',
	'\\r'	=> sub { "\r" },
	'\\t'	=> sub { "\t" },
	'$1'	=> sub { $capt->( $_[0], 1 ) },
	'$2'	=> sub { $capt->( $_[0], 2 ) },
	'$3'	=> sub { $capt->( $_[0], 3 ) },
	'$4'	=> sub { $capt->( $_[0], 4 ) },
	'$5'	=> sub { $capt->( $_[0], 5 ) },
	'$6'	=> sub { $capt->( $_[0], 6 ) },
	'$7'	=> sub { $capt->( $_[0], 7 ) },
	'$8'	=> sub { $capt->( $_[0], 8 ) },
	'$9'	=> sub { $capt->( $_[0], 9 ) },
	'$_'	=> sub { chomp( my $s = $_ ); $s },
	'$.'	=> sub { $_[0]->__color( lineno => $. ) },
	'$`'	=> sub { substr $_, 0, $_[0]->{match_start}[0] },
	'$&'	=> sub { $_[0]->__color( match => $capt->( $_[0], 0 ) ) },
	'$\''	=> sub {
	    my $s = substr $_, $_[0]->{match_end}[0];
	    chomp $s;
	    return $s;
	},
	'$+'	=> sub { $_[0]{paren_match} },
	'$c'	=> sub {
	    $_[0]{matched}
		or return '';
	    return $_[0]->__color( colno => $_[0]{match_start}[0] + 1 )
	},
	'$f'	=> sub {
	    return $_[0]->__color( filename => $_[0]{filename} );
	},
	'$F'	=> sub { length $_[0]{prev_field} ?
	    $_[0]{matched} ? ':' : '-' : '' },
	'$p'	=> sub {
	    my $s = substr $_, $_[0]{last_pos},
		$_[0]{match_start}[0] - $_[0]{last_pos};
	    chomp $s;
	    return $s; 
	},
	'$r'	=> '__format_item_dollar_r',
	'$s'	=> sub { substr $_[0]{syntax} // '', 0, 4 },
    };
    my $code = $hdlr->{$item}
	or return substr $item, 1;
    my $rslt = $self->$code();
    $self->{prev_field} = $rslt;
    return $rslt;
}

sub __format_item_ctrl_n {
    my ( $self ) = @_;
    return $self->{ors};
}

sub __format_item_dollar_r {
    my ( $self ) = @_;
    return $self->execute_template( $self->{replace_tplt} );
}

sub init {
    my ( $self ) = @_;
    $self->{last_pos} = $self->{curr_pos} = 0;
    $self->{line} = undef;
    $self->{matched} = 0;
    $self->{prev_field} = '';
    return $self;
}

sub line {
    my ( $self ) = @_;
    return $self->{line};
}

sub match {
    my ( $self ) = @_;
    defined pos
	or $self->__confess( 'match() called without a match' );
    $self->{capt} = [];
    $self->{last_pos} = $self->{curr_pos};
    $self->{curr_pos} = pos;
    $self->{matched} = 1;
    $self->{match_start} = [ @- ];
    $self->{match_end} = [ @+ ];
    $self->{paren_match} = $+ // '';
    return $self->__format_line( $self->{match_tplt} );
}

sub matched {
    my ( $self ) = @_;
    return $self->{matched};
}

sub _validate_replace_tplt {
    my ( $self, $tplt ) = @_;
    while ( $tplt =~ m( ( [\\\$] . ) )smxg ) {
	$1 eq '$r'
	    and $self->__croak( '$r not allowed in replace_tplt' );
    }
    return $tplt;
}

sub _validate_match_tplt {
    my ( $self, $tplt ) = @_;
    if ( defined $tplt ) {
	while ( $tplt =~ m( ( [\\\$] . ) )smxg ) {
	    $1 eq '$r'
		and not defined $self->{replace_tplt}
		and $self->__croak( '$r requires replace_tplt' );
	}
    }
    return $tplt;
}

BEGIN {
    # sub _validate_prefix_tplt()
    *_validate_prefix_tplt = \&_validate_match_tplt;
    # sub _validate_finalize_tplt()
    *_validate_finalize_tplt = \&_validate_match_tplt;
}

foreach my $attr ( qw{
    filename match_tplt prefix_tplt finalize_tplt replace_tplt syntax }
) {
    __PACKAGE__->can( $attr )
	and next;
    my $validate = __PACKAGE__->can( "_validate_$attr" ) || sub { $_[1] };
    no strict qw{ refs };
    *$attr = sub {
	my ( $self, @arg ) = @_;
	my $prev = $self->{$attr};
	@arg
	    and $self->{$attr} = $self->$validate( $arg[0] );
	return $prev;
    };
}

1;

__END__

=head1 NAME

App::Sam::Tplt - Template system for App::Sam

=head1 SYNOPSIS

No user-serviceable parts inside.

=head1 DESCRIPTION

This Perl class implements a template system for the benefit of
L<App::Sam|App::Sam>. This system is a superset of the L<ack|ack> system
used in its C<--output> processing.

This Perl module is B<private> to the C<App-Sam> package. It can be
changed or revoked at any time. All documentation is for the benefit of
the author.

The intended usage of this module is more or less the following:

 my $tplr = App::Sam::Tplt->new()
 ...
 local $_ = undef;
 $tplt->init();
 while ( m/\bfu(bar)\b/g ) {
   $tplt->match();
 }
 $tplt->finalize();
 print $tplt->line();

=head1 METHODS

This class supports the following package-private methods:

=head2 new

 my $tplt = App::Sam::Tplt->new();

This static method instantiates the object. Arguments are name/value
pairs, as follows:

=over

=item die - true to warn() or die() false to carp() or croak().

=item filename - the datum for the C<$f> item

=item finalize_tplt - finalization template for line (default C<'$p\n'>

=item match_tplt - match template for line (default C<'$p$&'>)

=item ors - line break character (default C<"\n">)

=item prefix_tplt - prefix template for line (default C<''>)

=item replace_tplt - executed to provide value for C<'$r'>. No default.

=item syntax - provides the value for C<'$s'>.

=back

=head2 execute_template

 say $tplt->execute_template( '$p$&' );

This low-level method processes the template and returns the result.

=head2 filename

 my $filename = $tplt->filename();
 $tplt->filename( 'fu.bar' );

This method acts as both accessor and mutator for the file name. If
called as a mutator, the previous file name is returned.

=head2 finalize

 my $rslt = $tplt->finalize();

This method formats its data according to the L<match_tplt|/match_tplt>.
The result will be appended to the current line, and returned.

This method B<should> only be called after the last successful match, or
if there were no successful match.

If C<match()> has not been called since the last call to
L<init()|/init>, the results of formatting template
L<prefix_tplt|/prefix_tplt> will be prepended to both the current line
and the returned string.

=head2 finalize_tplt

 my $finalize_tplt = $tplt->finalize_tplt();
 $tplt->finalize_tplt( 'fu.bar' );

This method acts as both accessor and mutator for the template used by
the L<finalize()|/finalize> method. If called as a mutator, the previous
template is returned.

=head2 init

This method B<must> be called after C<$_> has been modified, but before
L<match()|/match> or L<finalize()|/finalize> is called, to initialize
the object for processing the current line of input.

=head2 line

 say $tplt->line();

This method returns the line of text accumulated by L<matcg()|/match> or
L<finalize()|/finalize> calls since the most-recent L<init()|/init>
call.

The returned value will B<not> be terminated by C<"\n"> unless
L<finalize()|/finalize> has been called.

=head2 match

 my $rslt = $tplt->match();

This method formats its data according to the L<match_tplt|/match_tplt>.
The result will be appended to the current line, and returned.

This method B<must> only be called within the scope of a successful
match.

If C<match()> has not been called since the last call to
L<init()|/init>, the results of formatting template
L<prefix_tplt|/prefix_tplt> will be prepended to both the current line
and the returned string.

Optional arguments override the computed values of C<$&>, C<$1>, C<$2>,
and so on.

=head2 match_tplt

 my $match_tplt = $tplt->match_tplt();
 $tplt->match_tplt( 'fu.bar' );

This method acts as both accessor and mutator for the template used by
the L<match()|/match> method.. If called as a mutator, the previous
template is returned.

=head2 matched

This method returns a true value if L<match()|/match> has been called at
least once since the last call to L<init()|/init>. Otherwise it returns
a false value.

=head2 prefix_tplt

 my $prefix_tplt = $tplt->prefix_tplt();
 $tplt->prefix_tplt( 'fu.bar' );

This method acts as both accessor and mutator for the template used to
prefix the generated line by both the the L<match()|/match> and
L<finalize()|/finalize> methods. If called as a mutator, the previous
template is returned.

=head2 syntax

 my $syntax = $tplt->syntax();
 $tplt->syntax( 'code' );

This method acts as both accessor and mutator for the value of the
C<'$s'> template item. If called as a mutator, the previous value is
returned.

=head1 SEE ALSO

L<App::Sam|App::Sam>

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

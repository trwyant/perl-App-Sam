package App::Sam::Resource;

use 5.010001;

use strict;
use warnings;

use App::Sam::Util qw{ __expand_tilde @CARP_NOT };
#
# NOTE that we're using Carp directly because this code is buried so
# deeply that any error counts as a bug.

use Carp ();
use Cwd 3.08 ();
use Exporter qw{ import };
use Readonly;

our $VERSION = '0.000_006';

use enum qw{ ENUM:
    RC_ALIAS
    RC_DATA
    RC_FROM
    RC_GETOPT
    RC_INDENT
    RC_NAME
    RC_ORTS
    RC_REQUIRED
};

use constant REF_ARRAY	=> ref [];
use constant REF_SCALAR	=> ref \0;

Readonly::Array my @valid_attr => do {
    my @rslt;
    foreach ( keys %App::Sam::Resource:: ) {
	m/ \A RC_ ( \w+ ) \z /smx
	    or next;
	push @rslt, lc $1;
    }
    @rslt;
};

# NOTE that the exports are private to this package and can be changed
# or revoked without notice.
our @EXPORT_OK = (
    ( map { "RC_\U$_" } @valid_attr ),
);
our %EXPORT_TAGS = (
    rc	=> [ grep { m/ \A RC_ /smx } @EXPORT_OK ],
);

sub new {
    my ( $class, %arg ) = @_;
    my @self;
    defined $arg{name}
	or Carp::confess( "Bug - Attribute 'name' required" );
    state $valid_data = { map { $_ => 1 } REF_SCALAR, REF_ARRAY };
    not defined $arg{data}
	or $valid_data->{ ref $arg{data} }
	or Carp::confess( "Bug - Attribute 'data' must be undef, scalar ref, or array ref, not $arg{data}" );
    not defined $arg{orts}
	or REF_ARRAY eq ref $arg{orts}
	or Carp::confess( "Bug - Attribute 'orts' must be undef or array ref, not $arg{orts}" );
    $arg{getopt} //= 1;
    defined $arg{data}
	or $arg{name} = Cwd::abs_path( __expand_tilde( $arg{name} ) );
    $arg{alias} //= $arg{name};
    $arg{indent} //= 1;
    foreach my $attr_name ( keys %arg ) {
	my $code = $class->can( "RC_\U$attr_name" )
	    or Carp::confess( "Bug - bad attribute '$attr_name'" );
	$self[ $code->() ] = $arg{$attr_name};
    }
    return bless \@self, $class;
}

foreach my $attr_name ( @valid_attr ) {
    # NOTE that this is a stringy eval rather than a closure because I
    # didn't want to add Sub::Util as a dependency to set the sub name.
    my $sub = "sub $attr_name { return \$_[0][RC_\U$attr_name\E] }";
    eval "$sub 1"	## no critic (ProhibitStringyEval)
	or Carp::confess( "Bug - '$sub' failed to compile: $@ " );
}

sub dump_alias {
    my ( $self, $leader ) = @_;
    $leader //= '';
    my $alias = $self->alias();
    say $leader, $alias;
    say $leader, '=' x length $alias;
    return;
}

sub set_orts {
    my ( $self, @argv ) = @_;
    @argv
	or return 1;
    my $orts = $self->orts()
	or return 0;
    @{ $orts } = @argv;
    return 1;
}

1;

__END__

=head1 NAME

App::Sam::Resource - Represent resource files, et cetera.

=head1 SYNOPSIS

No user serviceable parts inside.

=head1 DESCRIPTION

This Perl class is B<private> to the C<App-Sam> package. It can be
modified or retracted at any time without notice. Documentation is
solely for the benefit of the author.

This Perl class represents a source of configuration data for
L<App::Sam|App::Sam>.

B<Note> that it is array-based. This is because the previous
implementation was based on an unblessed hash, and this was a convenient
way to ensure that I did not miss anything in the conversion. I may
convert to hash-based once the dust has settled.

=head1 METHODS

This class supports the following package-private methods:

=head2 new

 my $rsrc = App::Sam::Resource->new( name => 'fubar' );

This static method instantiates the resource. Arguments are passed as
name/value pairs. Attributes are as described below under their
accessors. The C<name> attribute is required. All others are optional.

=head2 alias

This accessor returns the value of the C<alias> argument, which is
provided for the benefit of the dump subsystem.

The default is the value of L<name|/name>.

=head2 data

This accessor returns the value of the C<data> argument. If specified,
this must be C<undef>, a scalar reference, or an array reference.

=head2 dump_alias

This method supports the dump subsystem. It takes an optional leading
string (defaulting to C<''>) and prints the alias and a double
underline, preceded by the leader.

=head2 from

This accessor returns the value of the C<from> argument. This is the
name of the resource that invoked this one.

=head2 getopt

If true, the data in the resource should be processed with
L<Getopt::Long|Getopt::Long>. If not, they are to be processed as
name/value pairs.

The default is true.

=head2 indent

This accessor returns the value of the C<indent> argument, which is
provided for the benefit of the dump subsystem.

The default is true.

=head2 name

This accessor returns the name of the resource. This should be
considered to be a file name unless L<data|/data> contains a true value.

=head2 orts

This accessor returns the value of the C<orts> argument. If defined, it
should be used to store any non-option arguments.

B<Note> that "ort" is a perfectly good English word, which a reasonably
good dictionary should have. It means "leftover" in the sense of food,
and is usually pluralized, as here. But I do not believe I have ever
seen it in the wild, other than in crossword puzzles.

=head2 required

This accessor returns the value of the C<required> argument. If this is
true B<and> the L<name|/name> is taken to be a file name, the file must
exist.

=head2 set_orts

This method takes as its arguments anything left over after processing
options.

This method returns a true value if there are no arguments or if the
L<orts()|/orts> accessor returns an array reference. In the latter case
the left overs are stored in the referenced array.

This method returns a false value if there are arguments but the
L<orts()|/orts> accessor returns a false value, meaning there is no
place to store them.

=head1 SEE ALSO

L<App::Sam|App::Sam>

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

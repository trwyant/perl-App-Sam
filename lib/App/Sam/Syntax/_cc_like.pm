package App::Sam::Syntax::_cc_like;

use 5.010001;

use strict;
use warnings;

use parent qw{ App::Sam::Syntax };

use App::Sam::Util qw{ :syntax @CARP_NOT };

our $VERSION = '0.000_008';

sub __classify_code {
    my ( $self ) = @_;
    $self->__match_single_line_documentation()
	and return SYNTAX_DOCUMENTATION;
    $self->__match_block_documentation_start() and do {
	$self->__match_block_documentation_end()
	    or $self->{in} = SYNTAX_DOCUMENTATION;
	return SYNTAX_DOCUMENTATION;
    };
    $self->__match_single_line_comment()
	and return SYNTAX_COMMENT;
    $self->__match_block_comment_start() and do {
	$self->{Comment_nest} = $self->__match_block_comment( 0 )
	    and $self->{in} = SYNTAX_COMMENT;
	return SYNTAX_COMMENT;
    };
    $self->__match_single_line_preprocessor() and do {
	$self->__match_preprocessor_continuation()
	    and $self->{in} = SYNTAX_PREPROCESSOR;
	return SYNTAX_PREPROCESSOR;
    };
    $self->__match_single_line_metadata()
	and return SYNTAX_METADATA;
    $self->__match_block_metadata_start() and do {
	$self->__match_block_metadata_end()
	    or $self->{in} = SYNTAX_METADATA;
	return SYNTAX_METADATA;
    };
    return SYNTAX_CODE;
}

sub __classify_documentation {
    my ( $self ) = @_;
    $self->__match_block_documentation_end()
	and $self->{in} = SYNTAX_CODE;
    return SYNTAX_DOCUMENTATION;
}

sub __classify_comment {
    my ( $self ) = @_;
    $self->{Comment_nest} = $self->__match_block_comment(
	$self->{Comment_nest} )
	or $self->{in} = SYNTAX_CODE;
    return SYNTAX_COMMENT;
}

sub __classify_metadata {
    my ( $self ) = @_;
    $self->__match_block_metadata_end()
	and $self->{in} = SYNTAX_CODE;
    return SYNTAX_METADATA;
}

sub __classify_preprocessor {
    my ( $self ) = @_;
    $self->__match_preprocessor_continuation()
	or $self->{in} = SYNTAX_CODE;
    return SYNTAX_PREPROCESSOR;
}

# Syntax implementation

# Comments

sub __match_block_comment {
    return ! m< [*] / >smx;
}

sub __match_block_comment_start {
    return m< \A \s* / [*] >smx;
}

sub __match_single_line_comment {
    # NOTE override to return 0 if single-line comments not supported.
    return m| \A \s* // |smx;
}

# Documentation

sub __match_block_documentation_end {
    return 0;
}

sub __match_block_documentation_start {
    return 0;
}

sub __match_single_line_documentation {
    return 0;
}

# Metadata

sub __match_block_metadata_end {
    return 0;
}

sub __match_block_metadata_start {
    return 0;
}

sub __match_single_line_metadata {
    return 0;
}

# Preprocessor

sub __match_single_line_preprocessor {
    return ! index $_, '#';
}

sub __match_preprocessor_continuation {
    return m/ \\ $ /smx;
}

1;

__END__

=head1 NAME

App::Sam::Syntax::_cc_like - Classify cc-like syntax

=head1 SYNOPSIS

The user has no direct interaction with this module.

=head1 DESCRIPTION

This Perl class is a subclass of L<App::Sam::Syntax|App::Sam::Syntax>.
It is B<private> to the C<App-Sam> package, and the user does not
interact with it directly.

This module may be changed or retracted without notice. Documentation is
for the convenience of the author.

This class abstracts syntax classification behaviour appropriate to
C-like syntaxes. Classification details and syntax types actually
produced are determined by the subclass.

The syntax types potentially produced by this module are

=over

=item * SYNTAX_CODE

Of course.

=item * SYNTAX_COMMENT

This may be either single-line comments or block comments, as configured
by the subclass.

=item * SYNTAX_DOCUMENTATION

If the subclass supports it.

=item * SYNTAX_METADATA

If the subclass supports it.

=item * SYNTAX_PREPROCESSOR

Preprocessor directives.

=back

=head1 METHODS

This class provides the following package-private methods, which may be
overridden by subclasses. The override B<must not> call C<SUPER::>.

The methods named C<__match_*> take the invocant as their only argument,
and expect the line being classified in C<$_>. They return a true value
if the line matches and a false value otherwise.

=head2 __match_block_comment_start

This method matches a line that consists only of the start of a block
comment. This implementation matches C<m|/*|>.

=head2 __match_block_comment_end

This method matches a line that contains the end of a block comment.
This implementation matches C<m|*/|>.

=head2 __match_block_documentation_start

This method matches a line that consists only of the start of block
documentation. This implementation always returns false.

=head2 __match_block_documentation_end

This method matches a line that contains the end of block documentation.
This implementation always returns false.

=head2 __match_shebang

This method will be called only for the first line of the file. It
matches a shebang line. This implementation always returns false.

=head2 __match_single_line_comment

This method matches a line that consists only of a single-line comment.
This implementation always returns false.

=head2 __match_single_line_documentation

This method matches a line that consists only of a single line of
documentation. This implementation always returns false.

=head2 __match_single_line_preprocessor

This method matches a single-line preprocessor directive. This method
matches C</\A#/>.

=head2 __match_preprocessor_continuation

This method matches a preprocessor line that is continued. This method
matches C</\$/>.

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

Copyright (C) 2024-2026 by Thomas R. Wyant, III

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl 5.10.0. For more details, see the full text
of the licenses in the files F<LICENSE-Artistic> and F<LICENSE-GNU>.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=cut

# ex: set textwidth=72 :

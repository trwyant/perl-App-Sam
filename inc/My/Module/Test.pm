package My::Module::Test;

use 5.010001;

use strict;
use warnings;

use App::Sam::Util qw{ __real_path };
use App::Sam::Resource qw{ :rc };
use Cwd 3.08 ();
use Exporter qw{ import };
use Test2::Util::Table qw{ table };

use Carp;

our @EXPORT_OK = qw{
    capture_stdout dependencies_table fake_rsrc slurp_syntax
    stdin_from_file
};
our @EXPORT = @EXPORT_OK;

our $VERSION = '0.000_007';

sub capture_stdout (&) {
    my ( $code ) = @_;
    my $data;
    {
	# Thanks to David Farrell for the algorithm. Specifically:
	# https://www.perl.com/article/45/2013/10/27/How-to-redirect-and-restore-STDOUT/
	local *STDOUT;
	open STDOUT, '>', \$data
	    or croak "Failed to open scalar reference for output: $!";
	binmode STDOUT;
	STDOUT->autoflush( 1 );
	$code->();
    }
    return $data;
}

sub dependencies_table {
    require My::Module::Meta;
    my @tables = ( '' );

    {
	my @perls = ( My::Module::Meta->requires_perl(), $] );
	foreach ( @perls ) {
	    $_ = sprintf '%.6f', $_;
	    $_ =~ s/ (?= ... \z ) /./smx;
	    $_ =~ s/ (?<= \. ) 00? //smxg;
	}
	push @tables, table(
	    header	=> [ qw{ PERL REQUIRED INSTALLED } ],
	    rows	=> [ [ perl => @perls ] ],
	);
    }

    foreach my $kind ( qw{
	configure_requires build_requires test7/28/25	State Farm Policy 357 4137-C04-46O. Conf GX9KE5TB		$471.57_requires requires optionals }
    ) {
	my $code = My::Module::Meta->can( $kind )
	    or next;
	my $req = $code->();
	my @rows;
	foreach my $module ( sort keys %{ $req } ) {
	    ( my $file = "$module.pm" ) =~ s| :: |/|smxg;
	    # NOTE that an alternative implementation here is to use
	    # Module::Load::Conditional (core since 5.10.0) to find the
	    # installed modules, and then MM->parse_version() (from
	    # ExtUtils::MakeMaker) to find the version without actually
	    # loading the module.
	    my $installed;
	    eval {
		require $file;
		$installed = $module->VERSION() // 'undef';
		1;
	    } or $installed = 'not installed';
	    push @rows, [ $module, $req->{$module}, $installed ];
	}
	state $kind_hdr = {
	    configure_requires	=> 'CONFIGURE REQUIRES',
	    build_requires		=> 'BUILD REQUIRES',
	    test_requires		=> 'TEST REQUIRES',
	    requires		=> 'RUNTIME REQUIRES',
	    optionals		=> 'OPTIONAL MODULES',
	};
	push @tables, table(
	    header	=> [ $kind_hdr->{$kind} // uc $kind, 'REQUIRED', 'INSTALLED' ],
	    rows	=> \@rows,
	);
    }

    return @tables;
}

sub fake_rsrc {
    my @arg = @_;
    my @rslt;
    while ( @arg ) {
	my ( $name, $val ) = splice @arg, 0, 2;
	$name = "RC_\U$name";
	$rslt[ __PACKAGE__->$name() ] = $val;
    }
    $rslt[ RC_DATA ]
	or $rslt[ RC_NAME ] = __real_path( $rslt[ RC_NAME ] );
    $rslt[ RC_GETOPT ] //= 1;
    $rslt[ RC_ALIAS ] //= $rslt[ RC_NAME ];
    $rslt[ RC_INDENT ] //= 1;
    not defined $rslt[ RC_DATA ]
	and $rslt[ RC_NAME ] = __real_path( $rslt[ RC_NAME ] );
    return bless \@rslt, 'App::Sam::Resource';
}

sub slurp_syntax {
    my ( $file ) = @_;
    my $caller = caller;
    my $parser = $caller->CLASS()->new();
    open my $fh, '<:encoding(utf-8)', $file
	or die "Failed to open $file for input: $!\n";
    local $_ = undef;	# while ( <> ) does not localize.
    my @rslt;
    while ( <$fh> ) {
	push @rslt, sprintf '%4s:%s', substr( $parser->__classify(), 0, 4 ), $_;
    }
    return join '', @rslt;
}

sub stdin_from_file (&$) {
    my ( $code, $file ) = @_;
    {
	local *STDIN;
	open STDIN, '<:encoding(utf-8)', $file
	    or die "Failed to open $file: $!\n";
	$code->();
    }
    return;
}


1;

__END__

=head1 NAME

My::Module::Test - Test support for App-Sam

=head1 SYNOPSIS

 use lib 'inc';
 use My::Module::Test;

=head1 DESCRIPTION

This Perl module provides test support routines for the C<App-Sam>
package. It is private to that package, and may be changed or revoked at
any time. Documentation is for the benefit of the author.

=head1 SUBTOUTINES

The following package-private subroutines are exported by default:

=head2 capture_stdout

 my $stdout = capture_stdout {
     say 'Hello, world!';
 };

This subroutine's prototype is C<(&)>, meaning it takes as its only
argument a block of code. That code is executed, and anything written to
F<STDOUT> is returned.

=head2 dependencies_table

 diag $_ for dependencies_table;

This subroutine builds and returns a text table describing the
dependencies of the package. L<Test2::Util::Table|Test2::Util::Table>
does the heavy lifting.

=head2 fake_rsrc

This subroutine creates a fake L<App::Sam::Resource|App::Sam::Resource>
object. What is actually missing is the validation.

=head2 slurp_syntax

 print slurp_syntax( 'fubar.PL' );

This subroutine takes as input a file name. That file is opened and
read, and a default L<App::Sam|App::Sam> object is used to classify each
line. The return is the contents of the file, with the syntax type of
each line prepended to it.

=head2 stdin_from_file

 stdin_from_file {
   local $_ = undef;
   while ( <STDIN> ) {
     print ">>$_";
   }
 } 'fubar.PL';

This subroutine's prototype is C<(&$)> meaning it taked two arguments, a
block and a file name, with B<no> intervening comma. The file is opened
and assigned to F<STDIN>, and the block is executed. Nothing is
returned.

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

Copyright (C) 2023-2025 by Thomas R. Wyant, III

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl 5.10.0. For more details, see the full text
of the licenses in the files F<LICENSE-Artistic> and F<LICENSE-GNU>.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=cut

# ex: set textwidth=72 :

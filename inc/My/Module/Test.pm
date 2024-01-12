package My::Module::Test;

use 5.010001;

use strict;
use warnings;

use Exporter qw{ import };
use Test2::Util::Table qw{ table };

use Carp;

our @EXPORT_OK = qw{ capture_stdout dependencies_table slurp_syntax };
our @EXPORT = @EXPORT_OK;

our $VERSION = '0.000_001';

sub capture_stdout (&) {
    my ( $code ) = @_;
    my $data;
    open my $stdout, '>', \$data	# Purposefully not encoded
	or croak "Failed to open scalar reference for output: $!";
    $stdout->autoflush( 1 );
    {
	local *STDOUT = $stdout;
	$code->();
    }
    close $stdout;
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
	configure_requires build_requires test_requires requires optionals }
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

sub slurp_syntax {
    my ( $file ) = @_;
    my $caller = caller;
    my $parser = $caller->CLASS()->new();
    open my $fh, '<:encoding(utf-8)', $file
	or die "Failed to open $file for input: $!\n";
    local $_ = undef;	# while ( <> ) does not localize.
    my @rslt;
    while ( <$fh> ) {
	push @rslt, sprintf '%4s:%s', substr( $parser->__syntax(), 0, 4 ), $_;
    }
    return join '', @rslt;
}


1;

__END__

=head1 NAME

My::Module::Test - <<< replace boilerplate >>>

=head1 SYNOPSIS

<<< replace boilerplate >>>

=head1 DESCRIPTION

<<< replace boilerplate >>>

=head1 METHODS

This class supports the following public methods:

=head1 ATTRIBUTES

This class has the following attributes:


=head1 SEE ALSO

<<< replace or remove boilerplate >>>

=head1 SUPPORT

Support is by the author. Please file bug reports at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=App-Sam>,
L<https://github.com/trwyant/perl-App-Sam/issues/>, or in
electronic mail to the author.

=head1 AUTHOR

Thomas R. Wyant, III F<wyant at cpan dot org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2023 by Thomas R. Wyant, III

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl 5.10.0. For more details, see the full text
of the licenses in the directory LICENSES.

This program is distributed in the hope that it will be useful, but
without any warranty; without even the implied warranty of
merchantability or fitness for a particular purpose.

=cut

# ex: set textwidth=72 :

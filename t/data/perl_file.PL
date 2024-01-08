#!/usr/bin/env perl

use strict;
use warnings;

# This is a comment

printf "Hello %s!\n", @ARGV ? $ARGV[0] : 'world';

__END__

This is data, kinda sorta.

=head1 TEST

This is documentation.

=cut

# ex: set textwidth=72 :

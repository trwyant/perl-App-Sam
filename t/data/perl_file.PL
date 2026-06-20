#!/usr/bin/env perl

use strict;
use warnings;

# This is a comment

printf "Hello %s!\n", @ARGV ? $ARGV[0] : 'world';

__END__

This is data, kinda sorta.

=head1 TEST

This is documentation.

=for comment But this is a comment.

This is also documentation.

=begin comment

But this entire block is a comment.

=cut

=pod

And we're still a comment.

=end comment

Documentation again.

=cut

# ex: set textwidth=72 :

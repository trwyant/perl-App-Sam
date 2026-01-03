package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Fortran';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/fortran_file.for';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
code:      character*64 my_name
code:      if ( iargc() .gt. 0 ) then
code:          call getarg( 1, my_name )
code:      else
code:          my_name = "world"
code:      end if
code:      print 1000, trim( my_name )
code:1000  format ( "Hello ", A, "!" )
code:      call exit()
code:      end
code:
comm:C Author: Thomas R. Wyant, III F<wyant at cpan dot org>
comm:C
comm:C Copyright (C) 2018-2026 by Thomas R. Wyant, III
comm:C
comm:C This program is distributed in the hope that it will be useful, but
comm:C without any warranty; without even the implied warranty of
comm:C merchantability or fitness for a particular purpose.
code:
comm:C ex: set textwidth=72 :
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

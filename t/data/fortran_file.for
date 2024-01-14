      character*64 my_name
      if ( iargc() .gt. 0 ) then
          call getarg( 1, my_name )
      else
          my_name = "world"
      end if
      print 1000, trim( my_name )
1000  format ( "Hello ", A, "!" )
      call exit()
      end

C Author: Thomas R. Wyant, III F<wyant at cpan dot org>
C
C Copyright (C) 2018-2023 by Thomas R. Wyant, III
C
C This program is distributed in the hope that it will be useful, but
C without any warranty; without even the implied warranty of
C merchantability or fitness for a particular purpose.

C ex: set textwidth=72 :

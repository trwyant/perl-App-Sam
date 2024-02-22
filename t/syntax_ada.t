package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Ada';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/ada_file.adb';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
code:with Ada.Text_IO;               use Ada.Text_IO;
code:with Ada.Command_Line;          use Ada.Command_Line;
code:with Ada.Strings.Unbounded;     use Ada.Strings.Unbounded;
code:
comm:-- This is a comment
comm:-- I have more, but ...
code:
code:procedure ada_file is
code:name : Unbounded_String := To_Unbounded_String( "world" );
code:begin
code:    if Argument_Count > 0
code:    then
code:        name := To_Unbounded_String( Argument( 1 ) );
code:    end if;
code:    Put_Line( "Hello " & To_String( name ) & "!" );
code:end ada_file;
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

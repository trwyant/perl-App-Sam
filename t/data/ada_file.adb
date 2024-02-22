with Ada.Text_IO;               use Ada.Text_IO;
with Ada.Command_Line;          use Ada.Command_Line;
with Ada.Strings.Unbounded;     use Ada.Strings.Unbounded;

-- This is a comment
-- I have more, but ...

procedure ada_file is
name : Unbounded_String := To_Unbounded_String( "world" );
begin
    if Argument_Count > 0
    then
        name := To_Unbounded_String( Argument( 1 ) );
    end if;
    Put_Line( "Hello " & To_String( name ) & "!" );
end ada_file;

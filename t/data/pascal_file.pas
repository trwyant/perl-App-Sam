(*
 * This is an old-style comment. The syntax is exactly the same as "C"
 * except for the use of matching parentheses rather than slashes.
 *)

{
   This is a Turbo Pascal comment. Again the syntax is like "C", except
   for the use of matching braces rather than '/* ... */'
}

// This is a Delphi comment, although Vims syntax highlighter appears
// not to know this, necessitating the elimination of the apostrophe
// in 'Vims'.

program Hello;
var
    name : String;
begin
    if ( ParamCount > 0 )
    then name := ParamStr( 1 )
    else name := 'world';
    writeln( 'Hello, ' + name + '!' );
end.

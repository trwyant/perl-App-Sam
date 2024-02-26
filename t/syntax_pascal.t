package main;

use 5.010001;

use strict;
use warnings;

use Test2::V0 -target => 'App::Sam::Syntax::Pascal';

use lib qw{ inc };

use My::Module::Test qw{ slurp_syntax };

use constant FILE	=> 't/data/pascal_file.pas';

is dies {
    is slurp_syntax( FILE ), <<'EOD', 'Got correct parse';
comm:(*
comm: * This is an old-style comment. The syntax is exactly the same as "C"
comm: * except for the use of matching parentheses rather than slashes.
comm: *)
code:
comm:{
comm:   This is a Turbo Pascal comment. Again the syntax is like "C", except
comm:   for the use of matching braces rather than '/* ... */'
comm:}
code:
comm:// This is a Delphi comment, although Vims syntax highlighter appears
comm:// not to know this, necessitating the elimination of the apostrophe
comm:// in 'Vims'.
code:
code:program Hello;
code:var
code:    name : String;
code:begin
code:    if ( ParamCount > 0 )
code:    then name := ParamStr( 1 )
code:    else name := 'world';
code:    writeln( 'Hello, ' + name + '!' );
code:end.
EOD
}, undef, 'Parse did not die';

done_testing;

1;

# ex: set textwidth=72 :

package main;

use strict;
use warnings;

use Test2::Tools::LoadModule;

load_module_or_skip_all 'Test::Spelling';

add_stopwords( <DATA> );

all_pod_files_spelling_ok();

1;
__DATA__
ack
argv
BEL
colno
del
env
ESC
Fortran
lexicographically
lineno
matcher
merchantability
NL
nobackup
NUL
passthrough
passthru
preprocessor
Raku
sam
samrc
superset
syntaxes
Wyant

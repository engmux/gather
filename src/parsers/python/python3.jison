/* Python Parser for Jison */
/* https://docs.python.org/3.4/reference/lexical_analysis.html */
/* https://docs.python.org/3.4/reference/grammar.html */

/* lexical gammar */
%{ 
    var indents = [0], 
        indent = 0, 
        dedents = 0

        // we don't need to implement a full stack here to ensure symmetry
        // because it's ensured by the grammar
        brackets_count = 0; 

    var keywords = [
        "continue", "nonlocal", "finally", "lambda", "return", "assert",
        "global", "import", "except", "raise", "break", "False", "class",
        "while", "yield", "None", "True", "from", "with", "elif", "else",
        "pass", "for", "try", "def", "and", "del", "not", "is", "as", "if",
        "or", "in"
    ]
%}

%lex

uppercase               [A-Z]
lowercase               [a-z]
digit                   [0-9]

// identifiers
identifier              ({xid_start})({xid_continue})*
xid_start               ("_")|({uppercase})|({lowercase})
xid_continue            {xid_start}|{digit}

// reserved
operators               ">>="|"<<="|"**="|"//="|"->"|"+="|"-="|"*="|"/="|"%="|
                        "&="|"|="|"^="|"**"|"//"|"<<"|">>"|"<="|">="|"=="|"!="|
                        "("|")"|"["|"]"|"{"|"}"|","|":"|"."|";"|"@"|"="|"+"|"-"|
                        "*"|"/"|"%"|"&"|"|"|"^"|"~"|"<"|">"|"""|"#"|"\"

// strings
longstring              {longstring_double}|{longstring_single}
longstring_double       '"""'{longstringitem}*'"""'
longstring_single       "'''"{longstringitem}*"'''"
longstringitem          {longstringchar}|{escapeseq}
longstringchar          [^\\]

shortstring             {shortstring_double}|{shortstring_single}
shortstring_double      '"'{shortstringitem_double}*'"'
shortstring_single      "'"{shortstringitem_single}*"'"
shortstringitem_double  {shortstringchar_double}|{escapeseq}
shortstringitem_single  {shortstringchar_single}|{escapeseq}
shortstringchar_single  [^\\\n\']
shortstringchar_double  [^\\\n\"]
escapeseq               \\.

// numbers
integer                 ({decinteger})|({hexinteger})|({octinteger})
decinteger              (([1-9]{digit}*)|"0")
hexinteger              "0"[x|X]{hexdigit}+
octinteger              "0"[o|O]{octdigit}+
bininteger              "0"[b|B]{bindigit}+
hexdigit                {digit}|[a-fA-F]
octdigit                [0-7]
bindigit                [0|1]

floatnumber             {exponentfloat}|{pointfloat}
exponentfloat           ({digit}+|{pointfloat}){exponent}
pointfloat              ({digit}*{fraction})|({digit}+".")
fraction                "."{digit}+
exponent                [e|E][\+|\-]({digit})+

%s INITIAL DEDENTS INLINE

%%

<INITIAL,INLINE><<EOF>> %{ 
                            // if the last statement in indented, need to force a dedent before EOF
                            if (indents.length > 1) { 
                               this.begin( 'DEDENTS' ); 
                               this.unput(' '); // make sure EOF is not triggered 
                               dedents = 1; 
                               indents.pop();
                            } else { 
                                return 'EOF'; 
                            } 
                        %}
<INITIAL>\              %{ indent += 1 %}
<INITIAL>\t             %{ indent = ( indent + 8 ) & -7 %}
<INITIAL>\n             %{ indent = 0 %} // blank line
<INITIAL>\#[^\n]*       /* skip comments */
<INITIAL>.              %{ 
                            this.unput( yytext )
                            var last = indents[ indents.length - 1 ]
                            if ( indent > last ) {
                                this.begin( 'INLINE' )
                                indents.push( indent )
                                return 'INDENT'
                            } else if ( indent < last ) {
                                this.begin( 'DEDENTS' )
                                dedents = 0 // how many dedents occured
                                while( indents.length ) {
                                    dedents += 1
                                    indents.pop()
                                    last = indents[ indents.length - 1 ]
                                    if ( last == indent ) break
                                }
                                if ( !indents.length ) {
                                    throw new Error( "TabError: Inconsistent" )
                                }
                            } else {
                                this.begin( 'INLINE' )
                            }
                        %}
<DEDENTS>.              %{
                            this.unput( yytext )
                            if ( dedents-- > 0 ) {
                                return 'DEDENT'
                            } else {
                                this.begin( 'INLINE' )
                            }
                        %}

<INLINE>\n              %{
                            // implicit line joining
                            if ( brackets_count <= 0 ) {
                                indent = 0; 
                                this.begin( 'INITIAL' )
                                return 'NEWLINE'
                            }
                        %}

<INLINE>\#[^\n]*        /* skip comments */
<INLINE>[\ \t\f]+       /* skip whitespace, separate tokens */
<INLINE>{operators}     %{
                            if ( yytext == '{' || yytext == '[' || yytext == '(' ) {
                                brackets_count += 1
                            } else if ( yytext == '}' || yytext == ']' || yytext == ')' ) {
                                brackets_count -= 1
                            }
                            return yytext 
                        %}
<INLINE>{floatnumber}   return 'NUMBER'
<INLINE>{bininteger}    %{  
                            var i = yytext.substr(2); // binary val
                            yytext = 'parseInt("'+i+'",2)'
                            return 'NUMBER'
                        %}
<INLINE>{integer}       return 'NUMBER'
<INLINE>{longstring}    %{
                            // escape string and convert to double quotes
                            // http://stackoverflow.com/questions/770523/escaping-strings-in-javascript
                            var str = yytext.substr(3, yytext.length-6)
                                .replace( /[\\"']/g, '\\$&' )
                                .replace(/\u0000/g, '\\0');
                            yytext = '"' + str + '"'
                            return 'STRING'
                        %}
<INLINE>{shortstring}   %{ return 'STRING' %}
<INLINE>{identifier}    %{
                            return ( keywords.indexOf( yytext ) == -1 )
                                ? 'NAME'
                                : yytext;
                        %}

/lex

%start expressions

%%


/** grammar **/
expressions
    : file_input        { return $1 }
    ;

// file_input: (NEWLINE | stmt)* ENDMARKER
file_input
    : EOF
    | file_input0 EOF    { $$ = { type: 'module', code: $1, location: @$ } }
    ;

file_input0
    : NEWLINE
    | stmt
    | NEWLINE file_input0
        { $$ = $2 }
    | stmt file_input0
        { $$ = [ $1 ].concat( $2 ) }
    ;

// decorator: '@' dotted_name [ '(' [arglist] ')' ] NEWLINE
decorator
    : '@' dotted_name NEWLINE
        { $$ = { type: 'decorator', decorator: $2, location: @$ } }
    | '@' dotted_name '(' ')' NEWLINE
        { $$ = { type: 'decorator', decorator: $2, args: '()', location: @$ } }
    | '@' dotted_name '(' arglist ')' NEWLINE
        { $$ = { type: 'decorator', decorator: $2, args: $4, location: @$ } }
    ;

// decorators: decorator+
decorators
    : decorator
        { $$ = [ $1 ] }
    | decorator decorators
        { $$ = [ $1 ].concat( $2 ) }
    ;

// decorated: decorators (classdef | funcdef)
decorated
    : decorators classdef
        { $$ = { type: 'decorate', decorators: $1, def: $2, location: @$ } }
    | decorators funcdef
        { $$ = { type: 'decorate', decorators: $1, def: $2, location: @$ } }
    ;

// funcdef: 'def' NAME parameters ['->' test] ':' suite
funcdef
    : 'def' NAME parameters ':' suite
        { $$ = { type: 'def', name: $2, params: $3, code: $5, location: @$ } }
    | 'def' NAME parameters '->' test ':' suite
        { $$ = { type: 'def', name: $2, params: $3, code: $7, annot: $5, location: @$ } }
    ;

// parameters: '(' [typedargslist] ')'
parameters
    : '(' ')'
        { $$ = [] }
    | '(' typedargslist ')'
        { $$ = $2 }
    ;

// typedargslist: (tfpdef ['=' test] (',' tfpdef ['=' test])* [','
//  ['*' [tfpdef] (',' tfpdef ['=' test])* [',' '**' tfpdef] | '**' tfpdef]]
//   |  '*' [tfpdef] (',' tfpdef ['=' test])* [',' '**' tfpdef] | '**' tfpdef)
// todo: *args and **kargs aren't currently implemented
typedargslist
    : tfpdef
        { $$ = [ $1 ] }
    | tfpdef ',' typedargslist_tail
        { $$ = [ $1 ].concat( $3 ) }
    | tfpdef typedargslist0
        { $$ = [ $1 ].concat( $2 ) }
    | tfpdef '=' test
        { $1.default = $3; $$ = [ $1 ] }
    | tfpdef '=' test typedargslist0
        { $1.default = $3; $$ = [ $1 ].concat( $4 ) }
    ;

typedargslist_tail
    : '*' tfpdef
        { $2.args = true; $$ = [ $2 ] }
    | '*' tfpdef typedargslist0
        { $2.args = true; $$ = [ $2 ].concat( $3 ) }
    //| '**' tfpdef // todo: implement
    //    { $2.kargs = true; $$ = [ $2 ] }
    //| '*' tfpdef ',' '**' tfpdef
    //| '*' tfpdef typedargslist0 ',' '**' tfpdef
    ;

typedargslist0
    : ',' tfpdef
        { $$ = [ $2 ] }
    | ',' tfpdef typedargslist0
        { $$ = [ $2 ].concat( $3 ) }
    | ',' tfpdef '=' test
        { $2.default = $4; $$ = [ $2 ] }
    | ',' tfpdef '=' test typedargslist0
        { $2.default = $4; $$ = [ $2 ].concat( $5 ) }
    ;

// tfpdef: NAME [':' test]
tfpdef
    : NAME
        { $$ = { name: $1 } }
    | NAME ':' test
        { $$ = { name: $1, anno: $3 } }
    ;

// varargslist: (vfpdef ['=' test] (',' vfpdef ['=' test])* [','
//   ['*' [vfpdef] (',' vfpdef ['=' test])* [',' '**' vfpdef] | '**' vfpdef]]
//   |  '*' [vfpdef] (',' vfpdef ['=' test])* [',' '**' vfpdef] | '**' vfpdef)
varargslist
    : vfpdef
        { $$ = [ $1 ] }
    | vfpdef ','
        { $$ = [ $1 ] }
    | vfpdef varargslist0
        { $$ = [ $1 ].concat( $2 ) }
    | vfpdef '=' test
        { $$ = [ $1 ] }
    | vfpdef '=' test ','
        { $$ = [ $1 ] }
    | vfpdef '=' test varargslist0
        { $$ = [ $1 ].concat( $4 ) }
    ;

varargslist0
    : ',' vfpdef
        { $$ = [ $2 ] }
    | ',' vfpdef ','
        { $$ = [ $2 ] }
    | ',' vfpdef varargslist0
        { $$ = [ $2 ].concat( $3 ) }
    | ',' vfpdef '=' test
        { $$ = [ $2 ] }
    | ',' vfpdef '=' test ','
        { $$ = [ $2 ] }
    | ',' vfpdef '=' test varargslist0
        { $$ = [ $2 ].concat( $5 ) }
    ;

// vfpdef: NAME
vfpdef: NAME;

// stmt: simple_stmt | compound_stmt
stmt: simple_stmt | compound_stmt;

// simple_stmt: small_stmt (';' small_stmt)* [';'] NEWLINE
simple_stmt
    : small_stmt NEWLINE
    | small_stmt ';' NEWLINE
    | small_stmt simple_stmt0 NEWLINE
        { $$ = [ $1 ].concat( $2 ) }
    ;

simple_stmt0
    : ';' small_stmt
        { $$ = [ $2 ] }
    | ';' small_stmt ';'
        { $$ = [ $2 ] }
    | ';' small_stmt simple_stmt0
        { $$ = [ $2 ].concat( $3 ) }
    ;

// small_stmt: (expr_stmt | del_stmt | pass_stmt | flow_stmt |
//              import_stmt | global_stmt | nonlocal_stmt | assert_stmt)
small_stmt: expr_stmt | del_stmt | pass_stmt | flow_stmt | import_stmt |
            global_stmt | nonlocal_stmt | assert_stmt;

// expr_stmt: testlist_star_expr (augassign (yield_expr|testlist) |
//  ('=' (yield_expr|testlist_star_expr))*)
expr_stmt
    : testlist_star_expr
        { $$ = $1.length == 1 ? $1[0] : { type: 'tuple', items: $1, location: @$ } }
    | testlist_star_expr assign
        { $$ = { type: 'assign', targets: $1.concat($2.targets), sources: $2.sources, location: @$ } }
    | testlist_star_expr augassign yield_expr
        { $$ = { type: 'assign', op: $2, targets: $1, sources: $3, location: @$ } }
    | testlist_star_expr augassign testlist
        { $$ = { type: 'assign', op: $2, targets: $1, sources: $3, location: @$ } }
    ;

assign
    : '=' yield_expr
    | '=' yield_expr assign
    | '=' testlist_star_expr
        { $$ = { targets: [], sources: $2 } }
    | '=' testlist_star_expr assign
        { $$ = { targets: $2.concat($3.targets), sources: $3.sources } }
    ;

// testlist_star_expr: (test|star_expr) (',' (test|star_expr))* [',']
testlist_star_expr
    : test
        { $$ = [ $1 ] }
    | test ','
        { $$ = [ $1 ] }
    | test testlist_star_expr0
        { $$ = [ $1 ].concat( $2 ) }
    | star_expr
        { $$ = [ $1 ] }
    | star_expr ','
        { $$ = [ $1 ] }
    | star_expr testlist_star_expr0
        { $$ = [ $1 ].concat( $2 ) }
    ;

testlist_star_expr0
    : ',' test
        { $$ = [ $2 ] }
    | ',' test ','
        { $$ = [ $2 ] }
    | ',' test testlist_star_expr0
        { $$ = [ $2 ].concat( $3 ) }
    | ',' star_expr
        { $$ = [ $2 ] }
    | ',' star_expr ','
        { $$ = [ $2 ] }
    | ',' star_expr testlist_star_expr0
        { $$ = [ $2 ].concat( $3 ) }
    ;

// augassign: ('+=' | '-=' | '*=' | '/=' | '%=' | '&=' | '|=' | '^=' |
//   '<<=' | '>>=' | '**=' | '//=')
augassign
    : '+='
    | '-='
    | '*='
    | '/='
    | '%='
    | '&='
    | '|='
    | '^='
    | '<<='
    | '>>='
    | '**='
    | '//='
    ;

// del_stmt: 'del' exprlist
del_stmt
    : 'del' NAME
        { $$ = {type:'del', name: $1, location: @$} }
    ;

// pass_stmt: 'pass'
pass_stmt
    : 'pass' 
        { $$ = {type:'pass', location: @$} }
    ;

// flow_stmt: break_stmt | continue_stmt | return_stmt | raise_stmt | yield_stmt
flow_stmt: break_stmt | continue_stmt | return_stmt | raise_stmt | yield_stmt;

// break_stmt: 'break'
break_stmt
    : 'break' 
        { $$ = {type:'break', location: @$} }
    ;

// continue_stmt: 'continue'
continue_stmt
    : 'continue'
        { $$ = {type:'continue', location: @$} }
    ;

// return_stmt: 'return' [testlist]
return_stmt
    : 'return'
        { $$ = {type:'return', location: @$} }
    | 'return' testlist
        { $$ = {type:'return', value:$2, location: @$} }
    ;

// yield_stmt: yield_expr
yield_stmt
    : yield_expr
    ;

// raise_stmt: 'raise' [test ['from' test]]
raise_stmt
    : 'raise'
        { $$ = {type: 'raise', location: @$} }
    | 'raise' test
        { $$ = {type: 'raise', err: $2, location: @$ } }
    | 'raise' test 'from' test
        { 
            $$ = { type: 'raise',  err: $2, location: @$  }
        }
    ;

// import_stmt: import_name | import_from
import_stmt
    : import_name | import_from ;

// import_name: 'import' dotted_as_names
import_name
    : 'import' dotted_as_names
        { $$ = {type: 'import', names: $2, location: @$ } }
    ;

// import_from: ('from' (('.' | '...')* dotted_name | ('.' | '...')+)
//  'import' ('*' | '(' import_as_names ')' | import_as_names))
import_from
    : 'from' dotted_name 'import' import_from_tail
        { $$ = { type: 'from',  base: $2, imports: $4, location: @$ } }
    | 'from' import_from0 dotted_name 'import' import_from_tail
        { $$ = { type: 'from',  base: $2 + $3, imports: $5, location: @$ } }
    | 'from' import_from0 'import' import_from_tail
    ;

// note below: the ('.' | '...') is necessary because '...' is tokenized as ELLIPSIS
import_from0
    : '.'
    | '.' import_from0
        { $$ = $1 + $2 }
    | '...'
    | '...' import_from0
        { $$ = $1 + $2 }
    ;

import_from_tail
    : '*' // todo: behavior not defined
    | '(' import_as_names ')'
        { $$ = $2 }
    | import_as_names
    ;

// import_as_name: NAME ['as' NAME]
import_as_name
    : NAME
        { $$ = { path: $1 } }
    | NAME 'as' NAME
        { $$ = { path: $1, name: $3 } }
    ;

// dotted_as_name: dotted_name ['as' NAME]
dotted_as_name
    : dotted_name
        { $$ = { path: $1 } }
    | dotted_name 'as' NAME
        { $$ = { path: $1, name: $3 } }
    ;

// import_as_names: import_as_name (',' import_as_name)* [',']
import_as_names
    : import_as_name
        { $$ = [ $1 ] }
    | import_as_name ','
        { $$ = [ $1 ] }
    | import_as_name import_as_names0
        { $$ = [ $1 ].concat( $2 ) }
    ;

import_as_names0
    : ',' import_as_name
        { $$ = [ $2 ] }
    | ',' import_as_name ','
        { $$ = [ $2 ] }
    | ',' import_as_name import_as_names0
        { $$ = [ $2 ].concat( $3 ) }
    ;

// dotted_as_names: dotted_as_name (',' dotted_as_name)*
dotted_as_names
    : dotted_as_name
        { $$ = [ $1 ] }
    | dotted_as_name dotted_as_names0
        { $$ = [ $1 ].concat( $2 ) }
    ;

dotted_as_names0
    : ',' dotted_as_name
        { $$ = [ $2 ] }
    | ',' dotted_as_name dotted_as_names0
        { $$ = [ $2 ].concat( $3 ) }
    ;

// dotted_name: NAME ('.' NAME)*
dotted_name
    : NAME
    | NAME dotted_name0
        { $$ = $1 + $2 }
    ;

dotted_name0
    : '.' NAME
        { $$ = $1 + $2 }
    | '.' NAME dotted_name0
        { $$ = $1 + $2 + $3 }
    ;

// global_stmt: 'global' NAME (',' NAME)*
// todo: behavior undefined (maybe use to avoid setting a 'assign' within the scope)
global_stmt
    : 'global' NAME
        { $$ = { type: 'global', names: [$2], location: @$ } }
    | 'global' NAME global_stmt0
        { $$ = { type: 'global', names: $2, location: @$ } }
    ;

global_stmt0
    : ',' NAME
        { $$ = [$2] }
    | ',' NAME global_stmt0
        { $$ = [$2].concat($3) }
    ;

// nonlocal_stmt: 'nonlocal' NAME (',' NAME)*
// todo: behavior undefined (maybe use to avoid setting a 'assign' within the scope)
nonlocal_stmt
    : 'nonlocal' NAME
        { $$ = { type: 'nonlocal', names: [$2], location: @$ } }
    | 'nonlocal' NAME nonlocal_stmt0
        { $$ = { type: 'nonlocal', names: $2, location: @$ } }
    ;

nonlocal_stmt0
    : ',' NAME
        { $$ = [$2] }
    | ',' NAME nonlocal_stmt0
        { $$ = [$2].concat($3) }
    ;

// assert_stmt: 'assert' test [',' test]
assert_stmt
    : 'assert' test
        { $$ = { type: 'assert',  cond: $2, location: @$ } }
    | 'assert' test ',' test
        { $$ = { type: 'assert',  cond: $2, err: $4, location: @$ } }
    ;

// compound_stmt: if_stmt | while_stmt | for_stmt | try_stmt | with_stmt |
//                funcdef | classdef | decorated
compound_stmt:  if_stmt | while_stmt | for_stmt | try_stmt | with_stmt | 
                funcdef | classdef | decorated;

// if_stmt: 'if' test ':' suite ('elif' test ':' suite)* ['else' ':' suite]
if_stmt
    : 'if' test ':' suite
        { $$ = { type: 'if',  cond: $2, code: $4, location: @$ } }
    | 'if' test ':' suite 'else' ':' suite
        { 
            $$ = { type: 'if', cond: $2, code: $4, else: $7, location: @$ }
        }
    | 'if' test ':' suite if_stmt0
        {
            $$ = { type: 'if', cond: $2, code: $4, elif: $5 }
        }
    | 'if' test ':' suite if_stmt0 'else' ':' suite
        {
            $$ = { type: 'if', cond: $2, code: $4, elif: $5, else: $8 }
        }
    ;

if_stmt0
    : 'elif' test ':' suite
        { $$ = [ { cond: $2, code: $4 } ] }
    | 'elif' test ':' suite if_stmt0
        { $$ = [ { cond: $2, code: $4 } ].concat( $5 ) }
    ;

// while_stmt: 'while' test ':' suite ['else' ':' suite]
while_stmt
    : 'while' test ':' suite
        { $$ = { type: 'while',  cond: $2, code: $4, location: @$ } }
    | 'while' test ':' suite 'else' ':' suite
        { $$ = { type: 'while',  cond: $2, code: $4, else: $7, location: @$ } }
    ;

// for_stmt: 'for' exprlist 'in' testlist ':' suite ['else' ':' suite]
for_stmt
    : 'for' exprlist 'in' testlist ':' suite
        { $$ = { type: 'for',  target: $2, iter: $4, code: $6, location: @$ } }
    | 'for' exprlist 'in' testlist ':' suite 'else' ':' suite
        { $$ = { type: 'for',  target: $2, iter: $4, code: $6, else: $9, location: @$ } }
    ;

// try_stmt: ('try' ':' suite
//   ((except_clause ':' suite)+
//    ['else' ':' suite]
//    ['finally' ':' suite] |
//     'finally' ':' suite))
try_stmt
    : 'try' ':' suite 'finally' ':' suite
        { $$ = { type: 'try',  code: $3, finally: $6, location: @$ } }
    | 'try' ':' suite try_excepts
        { $$ = { type: 'try',  code: $3, excepts: $4, location: @$ } }
    | 'try' ':' suite try_excepts 'finally' ':' suite
        { $$ = { type: 'try',  code: $3, excepts: $4, finally: $7, location: @$ } }
    | 'try' ':' suite try_excepts 'else' ':' suite
        { $$ = { type: 'try',  code: $3, excepts: $4, else: $7, location: @$ } }
    | 'try' ':' suite try_excepts 'else' ':' suite 'finally' ':' suite
        { $$ = { type: 'try',  code: $3, excepts: $4, else: $7, finally: $10, location: @$ } }
    ;

try_excepts
    : except_clause ':' suite
        { $1.code = $3; $$ = [ $1 ] }
    | except_clause ':' suite try_excepts
        { $1.code = $3; $$ = [ $1 ].concat( $4 ) }
    ;

// except_clause: 'except' [test ['as' NAME]]
// make sure that the default except clause is last
except_clause
    : 'except'
        { $$ = { cond: null} }
    | 'except' test
        { $$ = { cond: $2 } }
    | 'except' test 'as' NAME
        { $$ = { cond: $2, name: $4 } }
    ;

// with_stmt: 'with' with_item (',' with_item)*  ':' suite
with_stmt
    : 'with' with_item ':' suite
        { $$ = { type: 'with',  items: $2, code: $4, location: @$ } }
    | 'with' with_item with_stmt0 ':' suite
        { 
            $2 = [ $2 ].concat( $3 )
            $$ = { type: 'with', items: $2, code: $5, location: @$ }
        }
    ;

with_stmt0
    : ',' with_item
        { $$ = [ $2 ] }
    | ',' with_item with_stmt0
        { $$ = [ $2 ].concat( $3 ) }
    ;

// with_item: test ['as' expr]
with_item
    : test
        { $$ = { with: $1, as: $1 } }
    | test 'as' expr
        { $$ = { with: $1, as: $3 } }
    ;

// suite: simple_stmt | NEWLINE INDENT stmt+ DEDENT
suite
    : simple_stmt
    | NEWLINE INDENT suite0 DEDENT
        { $$ = $3 }
    ;

suite0
    : stmt
        { $$ = [ $1 ] }
    | stmt suite0
        { $$ = [ $1 ].concat( $2 ) }
    ;

// test: or_test ['if' or_test 'else' test] | lambdef
test
    : or_test
    | or_test 'if' or_test 'else' test
        { $$ = {type:'ifexpr', test: $1, then:$3, else: $5, location: @$ } }
    | lambdef
    ;

// test_nocond: or_test | lambdef_nocond
test_nocond: or_test | lambdef_nocond ;

// lambdef: 'lambda' [varargslist] ':' test
lambdef
    : 'lambda' ':' test
        { $$ = { type: 'lambda',  args: '', code: $3, location: @$ } }
    | 'lambda' varargslist ':' test
        { $$ = { type: 'lambda',  args: $2, code: $3, location: @$ } }
    ;

// lambdef_nocond: 'lambda' [varargslist] ':' test_nocond
lambdef_nocond
    : 'lambda' ':' test_nocond
    | 'lambda' varargslist ':' test_nocond
    ;

// or_test: and_test ('or' and_test)*
or_test
    : and_test
    | and_test or_test0
        { $$ = $2($1) }
    ;

or_test0
    : 'or' and_test
        { loc = @$; $$ = function (left) { return { type: 'binop', op: $1, left: left, right: $2, location: loc }; } }
    | 'or' and_test or_test0
        { loc = @$; $$ = function (left) { return $3({ type: 'binop', op: $1, left: left, right: $2, location: loc }); } }
    ;

// and_test: not_test ('and' not_test)*
and_test
    : not_test
    | not_test and_test0
        { $$ = $2($1) }
    ;

and_test0
    : 'and' not_test
        { loc = @$; $$ = function (left) { return { type: 'binop', op: $1, left: left, right: $2, location: loc }; } }
    | 'and' not_test and_test0
        { loc = @$; $$ = function (left) { return $3({ type: 'binop', op: $1, left: left, right: $2, location: loc }); } }
    ;

// not_test: 'not' not_test | comparison
not_test
    : 'not' not_test
        { $$ = { type: 'unop', op: $1, operand: $2, location: @$ } }
    | comparison
    ;

// comparison: expr (comp_op expr)*
comparison
    : expr
    | expr comparison0
        { $$ = $2($1) }
    ;

comparison0
    : comp_op expr
        { loc=@$; $$ = function (left) { return { type: 'binop', op: $1, left: left, right: $2, location: loc, foo:'hi' }; } }
    | comp_op expr comparison0
        { loc=@$; $$ = function (left) { return $3({ type: 'binop', op: $1, left: left, right: $2, location: loc, bar:'hi' }); } }
    ;

// comp_op: '<'|'>'|'=='|'>='|'<='|'<>'|'!='|'in'|'not' 'in'|'is'|'is' 'not'
// NOTE: '<>' is removed because we don't need to support __future__
comp_op: '<'|'>'|'=='|'>='|'<='|'!='
    |'in'
    |'not' 'in'
        { $$ = $1+$2 }
    |'is'
    |'is' 'not'
        { $$ = $1+$2 }
    ;

// star_expr: '*' expr
star_expr
    : '*' expr 
        { $$ = { type:'starred', value: $1, location: @$ } }
    ;

// expr: xor_expr ('|' xor_expr)*
expr
    : xor_expr
    | xor_expr expr0
        { $$ = $2($1) }
    ;

expr0
    : '|' xor_expr
        { loc = @$; $$ = function (left) { return {type:'binop', op:$1, left: left, right: $2, location: loc }; } }
    | '|' xor_expr expr0
        { loc = @$; $$ = function (left) { return $3({type:'binop', op:$1, left: left, right: $2, location: loc }); } }
    ;

// xor_expr: and_expr ('^' and_expr)*
xor_expr
    : and_expr
    | and_expr xor_expr0
        { $$ = $2($1) }
    ;

xor_expr0
    : '^' and_expr
        { loc = @$; $$ = function (left) { return {type:'binop', op:$1, left: left, right: $2, location: loc }; } }
    | '^' and_expr xor_expr0
        { loc = @$; $$ = function (left) { return $3({type:'binop', op:$1, left: left, right: $2, location: loc }); } }
    ;

// and_expr: shift_expr ('&' shift_expr)*
and_expr
    : shift_expr
    | shift_expr and_expr0
        { $$ = $2($1) }
    ;

and_expr0
    : '&' shift_expr
        { loc = @$; $$ = function (left) { return {type:'binop', op:$1, left: left, right: $2, location: loc }; } }
    | '&' shift_expr and_expr0
        { loc = @$; $$ = function (left) { return $3({type:'binop', op:$1, left: left, right: $2, location: loc }); } }
    ;

// shift_expr: arith_expr (('<<'|'>>') arith_expr)*
shift_expr
    : arith_expr
    | arith_expr shift_expr0
        { $$ = $2($1) }
    ;

shift_expr0
    : '<<' arith_expr
        { loc = @$; $$ = function (left) { return {type:'binop', op:$1, left: left, right: $2, location: loc }; } }
    | '<<' arith_expr shift_expr0
        { loc = @$; $$ = function (left) { return $3({type:'binop', op:$1, left: left, right: $2, location: loc }); } }
    | '>>' arith_expr
        { loc = @$; $$ = function (left) { return {type:'binop', op:$1, left: left, right: $2, location: loc }; } }
    | '>>' arith_expr shift_expr0
        { loc = @$; $$ = function (left) { return $3({type:'binop', op:$1, left: left, right: $2, location: loc }); } }
    ;

// arith_expr: term (('+'|'-') term)*
arith_expr
    : term
    | term arith_expr0
        { $$ = $2($1) }
    ;

arith_expr0
    : '+' term
        { loc = @$; $$ = function (left) { return {type:'binop', op:$1, left: left, right: $2, location: loc }; } }
    | '+' term arith_expr0
        { loc = @$; $$ = function (left) { return $3({type:'binop', op:$1, left: left, right: $2, location: loc }); } }
    | '-' term
        { loc = @$; $$ = function (left) { return {type:'binop', op:$1, left: left, right: $2, location: loc }; } }
    | '-' term arith_expr0
        { loc = @$; $$ = function (left) { return $3({type:'binop', op:$1, left: left, right: $2, location: loc }); } }
    ;

// term: factor (('*'|'/'|'%'|'//') factor)*
term
    : factor
    | factor term0
        { $$ = $2($1) }
    ;

term0
    : '*' factor
        { loc = @$; $$ = function (left) { return {type:'binop', op:$1, left: left, right: $2, location: loc }; } }
    | '*' factor term0
        { loc = @$; $$ = function (left) { return $3({type:'binop', op:$1, left: left, right: $2, location: loc }); } }
    | '/' factor
        { loc = @$; $$ = function (left) { return {type:'binop', op:$1, left: left, right: $2, location: loc }; } }
    | '/' factor term0
        { loc = @$; $$ = function (left) { return $3({type:'binop', op:$1, left: left, right: $2, location: loc }); } }
    | '%' factor
        { loc = @$; $$ = function (left) { return {type:'binop', op:$1, left: left, right: $2, location: loc }; } }
    | '%' factor term0
        { loc = @$; $$ = function (left) { return $3({type:'binop', op:$1, left: left, right: $2, location: loc }); } }
    | '//' factor
        { loc = @$; $$ = function (left) { return {type:'binop', op:$1, left: left, right: $2, location: loc }; } }
    | '//' factor term0
        { loc = @$; $$ = function (left) { return $3({type:'binop', op:$1, left: left, right: $2, location: loc }); } }
    ;

// factor: ('+'|'-'|'~') factor | power
factor
    : '+' factor
        { $$ = {type:'unop', op:$1, operand:$2, location: @$} }
    | '-' factor
        { $$ = {type:'unop', op:$1, operand:$2, location: @$} }
    | '~' factor
        { $$ = {type:'unop', op:$1, operand:$2, location: @$} }
    | power
    ;

// power: atom trailer* ['**' factor]
power
    : atom_expr
    | atom_expr '**' factor
        { $$ = {type: 'binop', op:$2, left: $1, right: $3, location: @$} }
    ;

trailer_list
    : trailer
    | trailer trailer_list
        { $$ = function (left) { return $2($1(left)) } }
    ;

atom_expr
    : atom
    | atom trailer_list
        { $$ = $2($1) }
    ;

// atom: ('(' [yield_expr|testlist_comp] ')' |
//        '[' [testlist_comp] ']' |
//        '{' [dictorsetmaker] '}' |
//        NAME | NUMBER | STRING+ | '...' | 'None' | 'True' | 'False')
atom
    : '(' ')'
        { $$ = { type: 'tuple', value: [], location: @$ } }
    | '(' yield_expr ')'
        { $$ = $2 }
    | '(' testlist_comp ')'
        { $$ = $2 }
    | '[' ']'
        { $$ = { type: 'list', items: [], location: @$ } }
    | '[' testlist_comp ']'
        { $$ = { type: 'list',  items: $2, location: @$ } }
    | '{' '}'
        { $$ = { type: 'dict',  pairs: [], location: @$ } }
    | '{' dictorsetmaker '}'
        {
            $$ = ( $2[ 0 ].k )
                ? { type: 'dict',  pairs: $2, location: @$ }
                : { type: 'set',  items: $2, location: @$ };
        }
    | NAME
        { $$ = { type: 'name', id: $1, location: @$ } }
    | NUMBER
        { $$ = { type: 'literal', value: $1 * 1, location: @$ } } // convert to number
    | STRING
        { $$ = { type: 'literal', value: $1, location: @$ } }
    | '...'
    | 'None'
        { $$ = { type: 'literal', value: 'None', location: @$ } }
    | 'True'
        { $$ = { type: 'literal', value: 'True', location: @$} }
    | 'False'
        { $$ = { type: 'literal', value: 'False', location: @$} }
    ;

// testlist_comp: (test|star_expr) ( comp_for | (',' (test|star_expr))* [','] )
testlist_comp
    : test
        { $$ = [ $1 ] }
    | test ','
        { $$ = [ $1 ] }
    | test testlist_comp_tail
        { $$ = [ $1 ].concat( $2 ) }
    | star_expr
        { $$ = [ $1 ] }
    | star_expr ','
        { $$ = [ $1 ] }
    | star_expr testlist_comp_tail
        { $$ = [ $1 ].concat( $2 ) }
    ;

testlist_comp_tail
    : comp_for
    | testlist_comp_tail0
    ;

testlist_comp_tail0
    : ',' test
        { $$ = [ $2 ] }
    | ',' test ','
        { $$ = [ $2 ] }
    | ',' test testlist_comp_tail0
        { $$ = [ $2 ].concat( $3 ) }
    | ',' star_expr
        { $$ = [ $2 ] }
    | ',' star_expr ','
        { $$ = [ $2 ] }
    | ',' star_expr testlist_comp_tail0
        { $$ = [ $2 ].concat( $3 ) }
    ;

// trailer: '(' [arglist] ')' | '[' subscriptlist ']' | '.' NAME
trailer
    : '(' ')'
        { loc = @$; $$ = function (left) { return {type: 'call', func: left, args: [], location: loc }; } }
    | '(' arglist ')'
        { loc = @$; $$ = function (left) { return {type: 'call', func: left, args: $2, location: loc }; } }
    | '[' ']'
        { loc = @$; $$ = function (left) { return {type: 'index', value: left, args: [], location: loc }; } }
    | '[' subscriptlist ']'
        { loc = @$; $$ = function (left) { return {type: 'index', value: left, args: $2, location: loc }; } }
    | '.' NAME
        { loc = @$; $$ = function (left) { return {type: 'dot', value: left, name: $2, location: loc }; } }
    ;

// subscriptlist: subscript (',' subscript)* [',']
subscriptlist
    : subscript
        { $$ = [ $1 ] }
    | subscript ','
        { $$ = [ $1 ] }
    | subscript subscriptlist0
        { $$ = [ $1 ].concat( $2 ) }
    ;

subscriptlist0
    : ',' subscript
        { $$ = [ $2 ] }
    | ',' subscript ','
        { $$ = [ $2 ] }
    | ',' subscript subscriptlist0
        { $$ = [ $2 ].concat( $3 ) }
    ;

// subscript: test | [test] ':' [test] [sliceop]
subscript
    : test
    | test ':' test sliceop
    | test ':' test
    | test ':' sliceop
    | test ':'
    | ':' test sliceop
    | ':' sliceop
    | ':'
    ;

// sliceop: ':' [test]
sliceop: ':' | ':' test;

// exprlist: (expr|star_expr) (',' (expr|star_expr))* [',']
exprlist
    : expr
        { $$ = [$1] }
    | expr ','
        { $$ = [$1] }
    | expr exprlist0
        { $$ = $1.concast($2) }
    | star_expr
        { $$ = [$1] }
    | star_expr ','
        { $$ = [$1] }
    | star_expr exprlist0
        { $$ = $1.concat($2) }
    ;

exprlist0
    : ',' expr
        { $$ = [$2] }
    | ',' expr ','
        { $$ = [$2] }
    | ',' expr exprlist0
        { $$ = $2.concast($3) }
    | ',' star_expr
        { $$ = [$2] }
    | ',' star_expr ','
        { $$ = [$2] }
    | ',' star_expr exprlist0
        { $$ = $2.concat($3) }
    ;

// testlist: test (',' test)* [',']
testlist
    : test
        { $$ = [ $1 ] }
    | test ','
        { $$ = [ $1 ] }
    | test testlist0
        { $$ = [ $1 ].concat( $2 ) }
    ;

testlist0
    : ',' test
        { $$ = [ $2 ] }
    | ',' test ','
        { $$ = [ $2 ] }
    | ',' test testlist0
        { $$ = [ $2 ].concat( $3 ) }
    ;

// dictorsetmaker: ( (test ':' test (comp_for | (',' test ':' test)* [','])) |
//   (test (comp_for | (',' test)* [','])) )
dictorsetmaker
    : test ':' test
        { $$ = [{ k: $1, v: $3 }] }
    | test ':' test ','
        { $$ = [{ k: $1, v: $3 }] }
    | test ':' test comp_for
        { $$ = [{ k: $1, v: $3 }].concat( $4 ) }
    | test ':' test dictmaker
        { $$ = [{ k: $1, v: $3 }].concat( $4 ) }
    | test
            { $$ = [ $1 ] }
    | test ','
        { $$ = [ $1 ] }
    | test comp_for
        { $$ = [ $1 ].concat( $2 ) }
    | test setmaker
        { $$ = [ $1 ].concat( $2 ) }
    ;

dictmaker
    : ',' test ':' test
        { $$ = [{ k: $2, v: $4 }] }
    | ',' test ':' test ','
        { $$ = [{ k: $2, v: $4 }] }
    | ',' test ':' test dictmaker
        { $$ = [{ k: $2, v: $4 }].concat( $5 ) }
    ;

setmaker
    : ',' test
        { $$ = [ $2 ] }
    | ',' test ','
        { $$ = [ $2 ] }
    | ',' test setmaker
        { $$ = [ $2 ].concat( $3 ) }
    ;

// classdef: 'class' NAME ['(' [arglist] ')'] ':' suite
classdef
    : 'class' NAME ':' suite
        { $$ = { type: 'class',  name: $2, code: $4, location: @$ } }
    | 'class' NAME '(' ')' ':' suite
        { $$ = { type: 'class',  name: $2, code: $6, location: @$ } }
    | 'class' NAME '(' arglist ')' ':' suite
        { $$ = { type: 'class',  name: $2, code: $7, extends: $4, location: @$ } }
    ;

// arglist: (argument ',')* (argument [',']
//  |'*' test (',' argument)* [',' '**' test] 
//  |'**' test)
arglist
    : argument
        { $$ = [ $1 ] }
    | argument ','
        { $$ = [ $1 ] }
    | argument arglist0
        { $$ = [ $1 ].concat( $2 ) }
    ;

arglist0
    : ',' argument
        { $$ = [ $2 ] }
    | ',' argument ','
        { $$ = [ $2 ] }
    | ',' argument arglist0
        { $$ = [ $2 ].concat( $3 ) }
    ;


// argument: test [comp_for] | test '=' test
argument
    : test
    | test comp_for
    | test '=' test
    ;

// comp_iter: comp_for | comp_if
comp_iter: comp_for | comp_if ;

// comp_for: 'for' exprlist 'in' or_test [comp_iter]
comp_for
    : 'for' exprlist 'in' or_test
        { $$ = [{ type: 'for', for: $2, in: $4, location: @$ }] }
    | 'for' exprlist 'in' or_test comp_iter
        { $$ = [{ type: 'for', for: $2, in: $4, location: @$ }].concat( $5 ) }
    ;

// comp_if: 'if' test_nocond [comp_iter]
comp_if
    : 'if' test_nocond
        { $$ = [{ type: 'if', test: $2, location: @$ }] }
    | 'if' test_nocond comp_iter
        { $$ = [{ type: 'if', test: $2, location: @$ }].concat( $3 )}
    ;

// yield_expr: 'yield' [yield_arg]
yield_expr
    : 'yield'
        { $$ = { type: 'yield', location: @$ } }
    | 'yield' yield_arg
        { $$ = { type: 'yield', value: $1, location: @$ } }
    ;

// yield_arg: 'from' test | testlist
yield_arg
    : 'from' test
    | testlist
    ;


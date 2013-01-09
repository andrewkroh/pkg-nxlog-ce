/*
 * This file is part of the nxlog log collector tool.
 * See the file LICENSE in the source root for licensing terms.
 * Website: http://nxlog.org
 * Author: Botond Botyanszki <botond.botyanszki@nxlog.org>
 */

%option prefix="nx_expr_parser_"
%option outfile="lex.yy.c"

%{
#include "expr.h"
#include "str.h"
#include "expr-grammar.h"
#include "expr-parser.h"
#include "error_debug.h"

#define NX_LOGMODULE NX_LOGMODULE_MODULE

#define PARSER yyget_extra(yyscanner)
#define YY_INPUT(buffer, res, max_size)             	    \
    do {                                                    \
        if (PARSER->pos >= PARSER->length)                  \
            res = YY_NULL;                                  \
        else                                                \
        {                                                   \
            res = PARSER->length - PARSER->pos;             \
            res > (int)max_size ? res = max_size : 0;       \
            memcpy(buffer, PARSER->buf + PARSER->pos, res); \
            PARSER->pos += res;                             \
        }                                                   \
    } while (0)

#define YY_USER_ACTION PARSER->linepos += yyleng;

%}

COMMENT		"#".*
NAME		[[:alpha:]_][[:alnum:]\._]*
SPACE		[ \t]*
FIELDNAME	"$"{NAME}
CAPTURED	"$"[0-9]|"$"[1-9][0-9]+
DATETIME        [1-9][0-9]{3}"-"[0-9]{2}"-"[0-9]{2}[ ][0-9]{2}":"[0-9]{2}":"[0-9]{2}
INTEGER		"-"?[0-9]+[KMG]?|"-"?"0X"[0-9A-Z]+[KMG]?

%x DOUBLEQUOTE
%x SINGLEQUOTE
%x REGEXPQUOTE
%x REGEXP

%option case-insensitive
%option reentrant bison-bridge
%option noyywrap
%option nounput

%%

"\""			{ yylval->string = NULL; BEGIN(DOUBLEQUOTE); }
"'"			{ yylval->string = NULL; BEGIN(SINGLEQUOTE);  }
"TRUE"			{ yylval->bool = TRUE; return ( TOKEN_BOOLEAN ); }
"FALSE"			{ yylval->bool = FALSE; return ( TOKEN_BOOLEAN ); }
{INTEGER}		{ yylval->string = yytext; return ( TOKEN_INTEGER ); }
{DATETIME}		{ yylval->string = yytext; return ( TOKEN_DATETIME ); }

"UNDEF"			{ yylval->string = "UNDEF"; return ( TOKEN_UNDEF ); }
"=~"			{ BEGIN(REGEXP); return ( TOKEN_REGMATCH ); }
"!~"			{ BEGIN(REGEXP); return ( TOKEN_NOTREGMATCH ); }

<SINGLEQUOTE>{
    [^']+		{ nx_expr_parser_append_string(&(yylval->string), yytext); }
    "'"			{
			  BEGIN(INITIAL);
			  return ( TOKEN_STRING );
                        }
}

<REGEXP>{
    [ \t]+		{  }
    [/]			{ log_debug("regexpquote start"); yylval->string = NULL; BEGIN(REGEXPQUOTE); }
}

<REGEXPQUOTE>{
    "\\/"		{ log_debug("regexp: append backslash"); nx_expr_parser_append_string(&(yylval->string), yytext); }
    [^/]+		{ log_debug("regexp: append"); nx_expr_parser_append_string(&(yylval->string), yytext); }
    "/"			{
			  log_debug("regexpquote end"); 
			  BEGIN(INITIAL);
			  return ( TOKEN_REGEXP );
                        }
}


<DOUBLEQUOTE>{
     [^\"]+          { nx_expr_parser_append_string(&(yylval->string), yytext); }
     "\\\""          { nx_expr_parser_append_string(&(yylval->string), yytext); }
     "\""              { 
			BEGIN(INITIAL); 
                        if ( yylval->string != NULL ) nx_string_unescape_c(yylval->string);
			return ( TOKEN_STRING );
		       }
}

"="	return ( TOKEN_ASSIGNMENT );
"not"	return ( TOKEN_NOT );
"defined" return ( TOKEN_DEFINED );
"and"	return ( TOKEN_AND );
"or"	return ( TOKEN_OR );
"xor"	return ( TOKEN_XOR );
"&"	return ( TOKEN_BINAND );
"|"	return ( TOKEN_BINOR );
"^"	return ( TOKEN_BINXOR );
"if"	return ( TOKEN_IF );
"else"	return ( TOKEN_ELSE );
"*"	return ( TOKEN_MUL );
"/"	return ( TOKEN_DIV );
"%"	return ( TOKEN_MOD );
"+"	return ( TOKEN_PLUS );
"-"	return ( TOKEN_MINUS );
"=="	return ( TOKEN_EQUAL );
"!="	return ( TOKEN_NOTEQUAL );
">="	return ( TOKEN_GE );
">"	return ( TOKEN_GREATER );
"<="	return ( TOKEN_LE );
"<"	return ( TOKEN_LESS );
"("	return ( TOKEN_LEFTBRACKET );
")"	return ( TOKEN_RIGHTBRACKET );
"{"	return ( TOKEN_LEFTBRACE );
"}"	return ( TOKEN_RIGHTBRACE );
";"	return ( TOKEN_SEMICOLON );
","	return ( TOKEN_COMMA );

{FIELDNAME}		{ yylval->string = nx_expr_parser_new_string(PARSER, yytext + 1); return ( TOKEN_FIELDNAME ); }
{NAME}"->"{NAME}	{ yylval->string = nx_expr_parser_new_string(PARSER, yytext); return ( TOKEN_FUNCPROC ); }
{NAME}			{ yylval->string = nx_expr_parser_new_string(PARSER, yytext); return ( TOKEN_FUNCPROC ); }
{CAPTURED}		{ yylval->string = nx_expr_parser_new_string(PARSER, yytext + 1); return ( TOKEN_CAPTURED ); }


[[:blank:]]+		/* ignore blanks */
{COMMENT}		/* ignore comment */
"\n"			PARSER->linepos = 0; (PARSER->linenum)++; /* reset column counter on new line */
.			nx_expr_parser_error(PARSER, yyscanner, "invalid character: '%c'", yytext[0]);

<*>.			nx_expr_parser_error(PARSER, yyscanner, "syntax error");

%%

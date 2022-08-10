#if defined __expression_parser_inc
	#endinput
#endif
#define __expression_parser_inc

#define EXPR_STR_MAX 512

typedef parser_variable_callback = function bool (any user_data, const char[] name, float &value);
typedef parser_function_callback = function bool (any user_data, const char[] name, int num_args, const float[] args, float &value);

native float parse_expression(const char[] str, parser_variable_callback variable_cb = INVALID_FUNCTION, parser_function_callback function_cb = INVALID_FUNCTION, any user_data = 0);

public SharedPlugin __pl_expression_parser =
{
	name = "expression_parser",
	file = "expression_parser.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_expression_parser_SetNTVOptional()
{
	MarkNativeAsOptional("parse_expression");
}
#endif
#include <sourcemod>
#include <expression_parser>

//https://github.com/jamesgregson/expression_parser

#define MAX_ERROR_STR 64

#define double float
#define fabs FloatAbs
#define atan2 ArcTangent2
#define atan ArcTangent
#define tan Tangent
#define acos ArcCosine
#define cos Cosine
#define asin ArcSine
#define sin Sine
#define sqrt SquareRoot
#define pow Pow
#define exp Exponential
#define log Logarithm

#define isalpha IsCharAlpha
#define isdigit IsCharNumeric
#define isspace IsCharSpace

float floor(float value)
{
	return float(RoundToFloor(value));
}

float round(float value)
{
	return float(RoundToNearest(value));
}

float abs(int value)
{
	return FloatAbs(float(value));
}

#if !defined PARSER_BOOLEAN_EQUALITY_THRESHOLD
#define PARSER_BOOLEAN_EQUALITY_THRESHOLD	(0.0000000001)
#endif

#if !defined PARSER_MAX_ARGUMENT_COUNT
#define PARSER_MAX_ARGUMENT_COUNT 10
#endif

#if !defined PARSER_MAX_TOKEN_SIZE
#define PARSER_MAX_TOKEN_SIZE 256
#endif

/**
 @brief main data structure for the parser, holds a pointer to the input string and the index of the current position of the parser in the input
*/
enum struct parser_data { 
	
	/** @brief input string to be parsed */
	char str[EXPR_STR_MAX]; 
	
	/** @brief length of input string */
	int        len;
	
	/** @brief current parser position in the input */
	int        pos;
	
	/** @brief error string to display, or query on failure */
	char error[MAX_ERROR_STR];
	
	/** @brief data pointer that is passed to the variable and function callback. Can be used to stored application state data necessary for performing variable and function lookup. Set to NULL if not used */
	any						user_data;
	
	/** @brief callback function used to lookup variable values, set to NULL if not used */
	Function	variable_cb;
	
	/** @brief callback function used to perform user-function evaluations, set to NULL if not used */
	Function	function_cb;

	Handle plugin;
}

double parser_parse( parser_data pd ){
	double result = 0.0;

#if !defined PARSER_EXCLUDE_BOOLEAN_OPS
	result = parser_read_boolean_or( pd );
#else
	result = parser_read_expr( pd );
#endif
	parser_eat_whitespace( pd );
	if( pd.pos < pd.len-1 ){
		parser_error( pd, "Failed to reach end of input expression, likely malformed input" );
		return sqrt( -1.0 );
	} else {
		return result;
	}
}

//#define DEBUG

#if defined DEBUG
static bool test_var_cb(any user_data, const char[] name, float &value)
{
	if(StrEqual(name, "lolvar")) {
		value = 42.0;
		return true;
	}
	return false;
}

static bool test_func_cb(any user_data, const char[] name, const int num_args, const float[] args, float &value)
{
	if(StrEqual(name, "lolfunc")) {
		if(num_args < 2) {
			return false;
		}
		value = args[0] + args[1];
		return true;
	}
	return false;
}

public void OnPluginStart()
{
	float result = parse_expression(
		"((1.0 + 1.0) * lolvar) + lolfunc(1.0, 8.0)"
	,test_var_cb, test_func_cb, 69);

	PrintToServer("result == %f", result);
}
#endif

int native_parse_expression(Handle plugin, int params)
{
	parser_data pd;
	pd.plugin = plugin;
	pd.variable_cb = GetNativeFunction(2);
	pd.function_cb = GetNativeFunction(3);
	pd.user_data = GetNativeCell(4);
	GetNativeString(1, pd.str, EXPR_STR_MAX);
	pd.pos = 0;
	pd.len = strlen(pd.str)+1;
	return view_as<int>(parser_parse(pd));
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("expression_parser");
	CreateNative("parse_expression", native_parse_expression);
	return APLRes_Success;
}

void parser_error( parser_data pd, const char[] err ){
	strcopy(pd.error, MAX_ERROR_STR, err);
	ThrowError("%s", err);
}

char parser_eat( parser_data pd ){
	if( pd.pos < pd.len ) {
		return pd.str[pd.pos++];
	}
	parser_error( pd, "Tried to read past end of string!" );
	return '\0';
}

char parser_peek( parser_data pd ){
	if( pd.pos < pd.len ) {
		return pd.str[pd.pos];
	}
	parser_error( pd, "Tried to read past end of string!" );
	return '\0';
}

void parser_eat_whitespace( parser_data pd ){
	while( isspace( parser_peek( pd ) ) ) {
		parser_eat( pd );
	}
}

char parser_peek_n( parser_data pd, int n ){
	if( pd.pos+n < pd.len ) {
		return pd.str[pd.pos+n];
	}
	parser_error( pd, "Tried to read past end of string!" );
	return '\0';
}

double parser_read_boolean_equality( parser_data pd ){
	char c;
	char oper[3];
	oper[0] = '\0';
	oper[1] = '\0';
	oper[2] = '\0';
	double v0, v1;
	
	// eat whitespace
	parser_eat_whitespace( pd );
	
	// read the first value
	v0 = parser_read_boolean_comparison( pd );
	
	// eat trailing whitespace
	parser_eat_whitespace( pd );
	
	// try to perform boolean equality operator
	c = parser_peek( pd );
	if( c == '=' || c == '!' ){
		if( c == '!' ){
			// try to match '!=' without advancing input to not clobber unary not
			if( parser_peek_n( pd, 1 ) == '=' ){
				oper[0] = parser_eat( pd );
				oper[1] = parser_eat( pd );
			} else {
				return v0;
			}
		} else {
			// try to match '=='
			oper[0] = parser_eat( pd );
			c = parser_peek( pd );
			if( c != '=' )
				parser_error( pd, "Expected a '=' for boolean '==' operator!" );
			oper[1] = parser_eat( pd );
		}
		// eat trailing whitespace
		parser_eat_whitespace( pd );
		
		// try to read the next term
		v1 = parser_read_boolean_comparison( pd );
		
		// perform the boolean operations
		if( strcmp( oper, "==" ) == 0 ){
			v0 = ( fabs(v0 - v1) < PARSER_BOOLEAN_EQUALITY_THRESHOLD ) ? 1.0 : 0.0;
		} else if( strcmp( oper, "!=" ) == 0 ){
			v0 = ( fabs(v0 - v1) > PARSER_BOOLEAN_EQUALITY_THRESHOLD ) ? 1.0 : 0.0;
		} else {
			parser_error( pd, "Unknown operation!" );
		}
		
		// read trailing whitespace
		parser_eat_whitespace( pd );
	}
	return v0;
}

double parser_read_argument( parser_data pd ){
	char c;
	double val;
	// eat leading whitespace
	parser_eat_whitespace( pd );
	
	// read the argument
	val = parser_read_expr( pd );
	
	// read trailing whitespace
	parser_eat_whitespace( pd );
	
	// check if there's a comma
	c = parser_peek( pd );
	if( c == ',' ) {
		parser_eat( pd );
	}
	
	// eat trailing whitespace
	parser_eat_whitespace( pd );
	
	// return result
	return val;
}

bool parser_read_argument_list( parser_data pd, int &num_args, double[] args ){
	char c;
	
	// set the initial number of arguments to zero
	num_args = 0;
	
	// eat any leading whitespace
	parser_eat_whitespace( pd );
	while( parser_peek( pd ) != ')' ){
		
		// check that we haven't read too many arguments
		if( num_args >= PARSER_MAX_ARGUMENT_COUNT ) {
			parser_error( pd, "Exceeded maximum argument count for function call, increase PARSER_MAX_ARGUMENT_COUNT and recompile!" );
		}
		
		// read the argument and add it to the list of arguments
		args[num_args] = parser_read_expr( pd );
		num_args = num_args+1;
		
		// eat any following whitespace
		parser_eat_whitespace( pd );
	
		// check the next character
		c = parser_peek( pd );
		if( c == ')' ){
			// closing parenthesis, end of argument list, return
			// and allow calling function to match the character
			break;
		} else if( c == ',' ){
			// comma, indicates another argument follows, match
			// the comma, eat any remaining whitespace and continue
			// parsing arguments
			parser_eat( pd );
			parser_eat_whitespace( pd );
		} else {
			// invalid character, print an error and return
			parser_error( pd, "Expected ')' or ',' in function argument list!" );
			return false;
		}
	}
	return true;
}

double parser_read_double( parser_data pd ){
	char c, token[PARSER_MAX_TOKEN_SIZE];
	int pos=0;
	double val=0.0;
	
	// read a leading sign
	c = parser_peek( pd );
	if( c == '+' || c == '-' ) {
		token[pos++] = parser_eat( pd );
	}
	
	// read optional digits leading the decimal point
	while( isdigit(parser_peek(pd)) ) {
		token[pos++] = parser_eat( pd );
	}
	
	// read the optional decimal point
	c = parser_peek( pd );
	if( c == '.' ) {
		token[pos++] = parser_eat( pd );
	}
	
	// read optional digits after the decimal point
	while( isdigit(parser_peek(pd)) ) {
		token[pos++] = parser_eat( pd );
	}
	
	// read the exponent delimiter
	c = parser_peek( pd );
	if( c == 'e' || c == 'E' ){
		token[pos++] = parser_eat( pd );
		
		// check if the expoentn has a sign,
		// if so, read it 
		c = parser_peek( pd );
		if( c == '+' || c == '-' ){
			token[pos++] = parser_eat( pd );
		}
	}
	
	// read the exponent delimiter
	while( isdigit(parser_peek(pd) ) ) {
		token[pos++] = parser_eat( pd );
	}
	
	// remove any trailing whitespace
	parser_eat_whitespace( pd );
	
	// null-terminate the string
	token[pos] = '\0';

	// check that a double-precision was read, otherwise throw an error
	if( pos == 0 ) {
		parser_error( pd, "Failed to read real number" );
	}

	val = StringToFloat(token);
	
	// return the parsed value
	return val;
}

double parser_read_builtin( parser_data pd ){
	double v0=0.0, v1=0.0, args[PARSER_MAX_ARGUMENT_COUNT];
	char c, token[PARSER_MAX_TOKEN_SIZE];
	int num_args, pos=0;
	
	c = parser_peek( pd );
	if( isalpha(c) || c == '_' ){
		// alphabetic character or underscore, indicates that either a function 
		// call or variable follows
		while( isalpha(c) || isdigit(c) || c == '_' ){
			token[pos++] = parser_eat( pd );
			c = parser_peek( pd );
		}
		token[pos] = '\0';
		
		// check for an opening bracket, which indicates a function call
		if( parser_peek(pd) == '(' ){
			// eat the bracket
			parser_eat(pd);
			
			// start handling the specific built-in functions
			if( strcmp( token, "pow" ) == 0 ){
				v0 = parser_read_argument( pd );
				v1 = parser_read_argument( pd );
				v0 = pow( v0, v1 );
			} else if( strcmp( token, "sqrt" ) == 0 ){
				v0 = parser_read_argument( pd );
				if( v0 < 0.0 ) {
					parser_error( pd, "sqrt(x) undefined for x < 0!" );
				}
				v0 = sqrt( v0 );
			} else if( strcmp( token, "log" ) == 0 ){
				v0 = parser_read_argument( pd );
				if( v0 <= 0 ) {
					parser_error( pd, "log(x) undefined for x <= 0!" );
				}
				v0 = log( v0 );
			} else if( strcmp( token, "exp" ) == 0 ){
				v0 = parser_read_argument( pd );
				v0 = exp( v0 );
			} else if( strcmp( token, "sin" ) == 0 ){
				v0 = parser_read_argument( pd );	
				v0 = sin( v0 );
			} else if( strcmp( token, "asin" ) == 0 ){
				v0 = parser_read_argument( pd );
				if( fabs(v0) > 1.0 ) {
					parser_error( pd, "asin(x) undefined for |x| > 1!" );
				}
				v0 = asin( v0 );
			} else if( strcmp( token, "cos" ) == 0 ){
				v0 = parser_read_argument( pd );
				v0 = cos( v0 );
			} else if( strcmp( token, "acos" ) == 0 ){
				v0 = parser_read_argument( pd );
				if( fabs(v0 ) > 1.0 ) {
					parser_error( pd, "acos(x) undefined for |x| > 1!" );
				}
				v0 = acos( v0 );
			} else if( strcmp( token, "tan" ) == 0 ){
				v0 = parser_read_argument( pd );	
				v0 = tan( v0 );
			} else if( strcmp( token, "atan" ) == 0 ){
				v0 = parser_read_argument( pd );
				v0 = atan( v0 );
			} else if( strcmp( token, "atan2" ) == 0 ){
				v0 = parser_read_argument( pd );
				v1 = parser_read_argument( pd );
				v0 = atan2( v0, v1 );
			} else if( strcmp( token, "abs" ) == 0 ){
				v0 = parser_read_argument( pd );
				v0 = abs( RoundToFloor(v0) );
			} else if( strcmp( token, "fabs" ) == 0 ){
				v0 = parser_read_argument( pd );
				v0 = fabs( v0 );
			} else if( strcmp( token, "floor" ) == 0 ){
				v0 = parser_read_argument( pd );
				v0 = floor( v0 );
			} else if( strcmp( token, "ceil" ) == 0 ){
				v0 = parser_read_argument( pd );
				v0 = floor( v0 );
			} else if( strcmp( token, "round" ) == 0 ){
				v0 = parser_read_argument( pd );
				// This is a C99 compiler - use the built-in round function.
				v0 = round( v0 );
			} else {
				parser_read_argument_list( pd, num_args, args );
				bool result = false;

				if( pd.function_cb != INVALID_FUNCTION ){
					Call_StartFunction(pd.plugin, pd.function_cb);
					Call_PushCell(pd.user_data);
					Call_PushString(token);
					Call_PushCell(num_args);
					Call_PushArray(args, sizeof(args));
					Call_PushFloatRef(v1);
					Call_Finish(result);

					v0 = v1;
				}

				if(!result) {
					parser_error( pd, "Tried to call unknown built-in function!" );
				}
			}
		
			// eat closing bracket of function call
			if( parser_eat( pd ) != ')' ) {
				parser_error( pd, "Expected ')' in built-in call!" );
			}
		} else {
			bool result = false;

			// no opening bracket, indicates a variable lookup
			if( pd.variable_cb != INVALID_FUNCTION ){
				Call_StartFunction(pd.plugin, pd.variable_cb);
				Call_PushCell(pd.user_data);
				Call_PushString(token);
				Call_PushFloatRef(v1);
				Call_Finish(result);

				v0 = v1;
			}

			if(!result) {
				parser_error( pd, "Could not look up value for variable!" );
			}
		}
	} else {
		// not a built-in function call, just read a literal double
		v0 = parser_read_double( pd );
	}
	
	// consume whitespace
	parser_eat_whitespace( pd );
	
	// return the value
	return v0;
}

double parser_read_paren( parser_data pd ){
	double val;
	
	// check if the expression has a parenthesis
	if( parser_peek( pd ) == '(' ){
		// eat the character
		parser_eat( pd );
		
		// eat remaining whitespace
		parser_eat_whitespace( pd );
		
		// if there is a parenthesis, read it 
		// and then read an expression, then
		// match the closing brace
		val = parser_read_boolean_or( pd );
		
		// consume remaining whitespace
		parser_eat_whitespace( pd );
		
		// match the closing brace
		if( parser_peek(pd) != ')' ) {
			parser_error( pd, "Expected ')'!" );		
		}
		parser_eat(pd);
	} else {
		// otherwise just read a literal value
		val = parser_read_builtin( pd );
	}
	// eat following whitespace
	parser_eat_whitespace( pd );
	
	// return the result
	return val;
}

double parser_read_unary( parser_data pd ){
	char c;
	double v0;
	c = parser_peek( pd );
	if( c == '!' ){
		// if the first character is a '!', perform a boolean not operation
#if !defined PARSER_EXCLUDE_BOOLEAN_OPS
		parser_eat(pd);
		parser_eat_whitespace(pd);
		v0 = parser_read_paren(pd);
		v0 = fabs(v0) >= PARSER_BOOLEAN_EQUALITY_THRESHOLD ? 0.0 : 1.0;
#else
		parser_error( pd, "Expected '+' or '-' for unary expression, got '!'" );
#endif
	} else if( c == '-' ){
		// perform unary negation
		parser_eat(pd);
		parser_eat_whitespace(pd);
		v0 = -parser_read_paren(pd);
	} else if( c == '+' ){
		// consume extra '+' sign and continue reading
		parser_eat( pd );
		parser_eat_whitespace(pd);
		v0 = parser_read_paren(pd);
	} else {
		v0 = parser_read_paren(pd);
	}
	parser_eat_whitespace(pd);
	return v0;
}

double parser_read_power( parser_data pd ){
	double v0, v1=1.0, s=1.0;
	
	// read the first operand
	v0 = parser_read_unary( pd );
	
	// eat remaining whitespace
	parser_eat_whitespace( pd );
	
	// attempt to read the exponentiation operator
	while( parser_peek(pd) == '^' ){
		parser_eat(pd );
		
		// eat remaining whitespace
		parser_eat_whitespace( pd );
		
		// handles case of a negative immediately 
		// following exponentiation but leading
		// the parenthetical exponent
		if( parser_peek( pd ) == '-' ){
			parser_eat( pd );
			s = -1.0;
			parser_eat_whitespace( pd );
		}
		
		// read the second operand
		v1 = s*parser_read_power( pd );
		
		// perform the exponentiation
		v0 = pow( v0, v1 );
		
		// eat remaining whitespace
		parser_eat_whitespace( pd );
	}
	
	// return the result
	return v0;
}

double parser_read_term( parser_data pd ){
	double v0;
	char c;
	
	// read the first operand
	v0 = parser_read_power( pd );
	
	// eat remaining whitespace
	parser_eat_whitespace( pd );
	
	// check to see if the next character is a
	// multiplication or division operand
	c = parser_peek( pd );
	while( c == '*' || c == '/' ){
		// eat the character
		parser_eat( pd );
		
		// eat remaining whitespace
		parser_eat_whitespace( pd );
		
		// perform the appropriate operation
		if( c == '*' ){
			v0 *= parser_read_power( pd );
		} else if( c == '/' ){
			v0 /= parser_read_power( pd );
		}
		
		// eat remaining whitespace
		parser_eat_whitespace( pd );
		
		// update the character
		c = parser_peek( pd );
	}
	return v0;
}

double parser_read_expr( parser_data pd ){
	double v0 = 0.0;
	char c;
	
	// handle unary minus
	c = parser_peek( pd );
	if( c == '+' || c == '-' ){
		parser_eat( pd );
		parser_eat_whitespace( pd );
		if( c == '+' ) {
			v0 += parser_read_term( pd );
		}
		else if( c == '-' ) {
			v0 -= parser_read_term( pd );
		}
	} else {
		v0 = parser_read_term( pd );
	}
	parser_eat_whitespace( pd );
	
	// check if there is an addition or
	// subtraction operation following
	c = parser_peek( pd );
	while( c == '+' || c == '-' ){
		// advance the input
		parser_eat( pd );
		
		// eat any extra whitespace
		parser_eat_whitespace( pd );
		
		// perform the operation
		if( c == '+' ){		
			v0 += parser_read_term( pd );
		} else if( c == '-' ){
			v0 -= parser_read_term( pd );
		}
		
		// eat whitespace
		parser_eat_whitespace( pd );
		
		// update the character being tested in the while loop
		c = parser_peek( pd );
	}
	
	// return expression result
	return v0;
}

double parser_read_boolean_comparison( parser_data pd ){
	char c;
	char oper[3];
	oper[0] = '\0';
	oper[1] = '\0';
	oper[2] = '\0';
	double v0, v1;
	
	// eat whitespace
	parser_eat_whitespace( pd );
	
	// read the first value
	v0 = parser_read_expr( pd );
	
	// eat trailing whitespace
	parser_eat_whitespace( pd );
	
	// try to perform boolean comparison operator. Unlike the other operators
	// like the arithmetic operations and the boolean and/or operations, we
	// only allow one operation to be performed. This is done since cascading
	// operations would have unintended results: 2.0 < 3.0 < 1.5 would
	// evaluate to true, since (2.0 < 3.0) == 1.0, which is less than 1.5, even
	// though the 3.0 < 1.5 does not hold.
	c = parser_peek( pd );
	if( c == '>' || c == '<' ){
		// read the operation
		oper[0] = parser_eat( pd );
		c = parser_peek( pd );
		if( c == '=' ) {
			oper[1] = parser_eat( pd );
		}
		
		// eat trailing whitespace
		parser_eat_whitespace( pd );
		
		// try to read the next term
		v1 = parser_read_expr( pd );
		
		// perform the boolean operations
		if( strcmp( oper, "<" ) == 0 ){
			v0 = (v0 < v1) ? 1.0 : 0.0;
		} else if( strcmp( oper, ">" ) == 0 ){
			v0 = (v0 > v1) ? 1.0 : 0.0;
		} else if( strcmp( oper, "<=" ) == 0 ){
			v0 = (v0 <= v1) ? 1.0 : 0.0;
		} else if( strcmp( oper, ">=" ) == 0 ){
			v0 = (v0 >= v1) ? 1.0 : 0.0;
		} else {
			parser_error( pd, "Unknown operation!" );
		}
		
		// read trailing whitespace
		parser_eat_whitespace( pd );
	}
	return v0;
}

double parser_read_boolean_and( parser_data pd ){
	char c;
	double v0, v1;
	
	// tries to read a boolean comparison operator ( <, >, <=, >= ) 
	// as the first operand of the expression
	v0 = parser_read_boolean_equality( pd );
	
	// consume any whitespace befor the operator
	parser_eat_whitespace( pd );
	
	// grab the next character and check if it matches an 'and'
	// operation. If so, match and perform and operations until
	// there are no more to perform
	c = parser_peek( pd );
	while( c == '&' ){
		// eat the first '&'
		parser_eat( pd );
		
		// check for and eat the second '&'
		c = parser_peek( pd );
		if( c != '&' ) {
			parser_error( pd, "Expected '&' to follow '&' in logical and operation!" );
		}
		parser_eat( pd );
		
		// eat any remaining whitespace
		parser_eat_whitespace( pd );

		// read the second operand of the
		v1 = parser_read_boolean_equality( pd );
		
		// perform the operation, returning 1.0 for TRUE and 0.0 for FALSE
		v0 = ( fabs(v0) >= PARSER_BOOLEAN_EQUALITY_THRESHOLD && fabs(v1) >= PARSER_BOOLEAN_EQUALITY_THRESHOLD ) ? 1.0 : 0.0;
	
		// eat any following whitespace
		parser_eat_whitespace( pd );
		
		// grab the next character to continue trying to perform 'and' operations
		c = parser_peek( pd );
	}
	
	return v0;
}

double parser_read_boolean_or( parser_data pd ){
	char c;
	double v0, v1;
	
	// read the first term
	v0 = parser_read_boolean_and( pd );
	
	// eat whitespace
	parser_eat_whitespace( pd );

	// grab the next character and check if it matches an 'or'
	// operation. If so, match and perform and operations until
	// there are no more to perform
	c = parser_peek( pd );
	while( c == '|' ){
		// match the first '|' character
		parser_eat( pd );
		
		// check for and match the second '|' character
		c = parser_peek( pd );
		if( c != '|' ) {
			parser_error( pd, "Expected '|' to follow '|' in logical or operation!" );
		}
		parser_eat( pd );
		
		// eat any following whitespace
		parser_eat_whitespace( pd );
		
		// read the second operand
		v1 = parser_read_boolean_and( pd );
	
		// perform the 'or' operation
		v0 = ( fabs(v0) >= PARSER_BOOLEAN_EQUALITY_THRESHOLD || fabs(v1) >= PARSER_BOOLEAN_EQUALITY_THRESHOLD ) ? 1.0 : 0.0;
		
		// eat any following whitespace
		parser_eat_whitespace( pd );
		
		// grab the next character to continue trying to match
		// 'or' operations
		c = parser_peek( pd );
	}
	
	// return the resulting value
	return v0;
}
#include <sourcemod>
#include <popspawner>
#include <expression_parser>

public void OnPluginStart()
{
	
}

static bool expr_pop_var(any user_data, const char[] name, float &value)
{
	return false;
}

static bool expr_pop_fnc(any user_data, const char[] name, int num_args, const float[] args, float &value)
{
	return false;
}

public Action wavespawn_parse(CWaveSpawnPopulator populator, KeyValues data, bool &result)
{
	char value_str[EXPR_STR_MAX];

	if(data.JumpToKey("TotalCount")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);

		float value = parse_expression(value_str, expr_pop_var, expr_pop_fnc, 0);

		populator.TotalCount = RoundToFloor(value);

		data.GoBack();
	}

	return Plugin_Continue;
}
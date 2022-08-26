#include <sourcemod>
#include <popspawner>
#include <expression_parser>

public void OnPluginStart()
{
	
}

enum current_parsing_t
{
	current_parsing_none,
	current_parsing_wavespawn,
	current_parsing_wave
};

static current_parsing_t current_parsing;

static bool expr_pop_var(any user_data, const char[] name, float &value)
{
	switch(current_parsing) {
		case current_parsing_wavespawn: {
			CWaveSpawnPopulator populator = view_as<CWaveSpawnPopulator>(user_data);

			if(StrEqual(name, "TotalCount")) {
				value = float(populator.TotalCount);
				return true;
			} else if(StrEqual(name, "MaxActive")) {
				value = float(populator.MaxActive);
				return true;
			} else if(StrEqual(name, "SpawnCount")) {
				value = float(populator.SpawnCount);
				return true;
			} else if(StrEqual(name, "WaitBeforeStarting")) {
				value = populator.WaitBeforeStarting;
				return true;
			} else if(StrEqual(name, "WaitBetweenSpawns")) {
				value = populator.WaitBetweenSpawns;
				return true;
			} else if(StrEqual(name, "WaitBetweenSpawnsAfterDeath")) {
				value = populator.WaitBetweenSpawnsAfterDeath;
				return true;
			} else if(StrEqual(name, "RandomSpawn")) {
				value = populator.RandomSpawn ? 1.0 : 0.0;
				return true;
			} else if(StrEqual(name, "TotalCurrency")) {
				value = float(populator.TotalCurrency);
				return true;
			}
		}
		case current_parsing_wave: {
			CWave populator = view_as<CWave>(user_data);

			if(StrEqual(name, "WaitWhenDone")) {
				value = populator.WaitWhenDone;
				return true;
			}
		}
	}

	return false;
}

static bool expr_pop_fnc(any user_data, const char[] name, int num_args, const float[] args, float &value)
{
	return false;
}

public Action wave_parse(CWave populator, KeyValues data, bool &result)
{
	current_parsing = current_parsing_wave;

	char value_str[EXPR_STR_MAX];

	if(data.JumpToKey("WaitWhenDone")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_var, expr_pop_fnc, populator);
		populator.WaitWhenDone = value;
		data.GoBack();
	}

	current_parsing = current_parsing_none;

	return Plugin_Continue;
}

public Action wavespawn_parse(CWaveSpawnPopulator populator, KeyValues data, bool &result)
{
	current_parsing = current_parsing_wavespawn;

	char value_str[EXPR_STR_MAX];

	if(data.JumpToKey("TotalCount")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_var, expr_pop_fnc, populator);
		populator.TotalCount = RoundToFloor(value);
		data.GoBack();
	}

	if(data.JumpToKey("MaxActive")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_var, expr_pop_fnc, populator);
		populator.MaxActive = RoundToFloor(value);
		data.GoBack();
	}

	if(data.JumpToKey("SpawnCount")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_var, expr_pop_fnc, populator);
		populator.SpawnCount = RoundToFloor(value);
		data.GoBack();
	}

	if(data.JumpToKey("WaitBeforeStarting")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_var, expr_pop_fnc, populator);
		populator.WaitBeforeStarting = value;
		data.GoBack();
	}

	if(data.JumpToKey("WaitBetweenSpawns")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_var, expr_pop_fnc, populator);
		populator.WaitBetweenSpawns = value;
		data.GoBack();
	}

	if(data.JumpToKey("WaitBetweenSpawnsAfterDeath")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_var, expr_pop_fnc, populator);
		populator.WaitBetweenSpawnsAfterDeath = value;
		data.GoBack();
	}

	if(data.JumpToKey("RandomSpawn")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_var, expr_pop_fnc, populator);
		populator.RandomSpawn = (RoundToFloor(value) != 0);
		data.GoBack();
	}

	if(data.JumpToKey("TotalCurrency")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_var, expr_pop_fnc, populator);
		populator.TotalCurrency = RoundToFloor(value);
		data.GoBack();
	}

	current_parsing = current_parsing_none;

	return Plugin_Continue;
}
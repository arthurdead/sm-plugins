#include <sourcemod>
#include <popspawner>
#include <expression_parser>
#include <stocksoup/tf/monster_resource>
#include <datamaps>

static TFMonsterResource monster_resource;

static ConVar tf_mvm_miniboss_scale;

public void OnPluginStart()
{
	tf_mvm_miniboss_scale = FindConVar("tf_mvm_miniboss_scale");
}

public void OnMapStart()
{
	monster_resource = TFMonsterResource.GetEntity(true);
	monster_resource.Hide();
}

//TODO!!!! hook takedmg and *= damage to pop_damage_multiplier

static bool expr_pop_spawner_var(any user_data, const char[] name, float &value)
{
	return false;
}

static int native_expr_pop_parse(Handle plugin, int params)
{
	CustomPopulationSpawner spawner = GetNativeCell(1);
	KeyValues data = GetNativeCell(2);

	char value_str[EXPR_STR_MAX];

	if(data.JumpToKey("Health")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_spawner_var, INVALID_FUNCTION, 0);
		if(value < 1.0) {
			data.GoBack();
			return 0;
		}
		spawner.set_data("health", RoundToFloor(value));
		data.GoBack();
	}

	if(data.JumpToKey("ModelScale")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_spawner_var, INVALID_FUNCTION, 0);
		if(value <= 0.0) {
			data.GoBack();
			return 0;
		}
		spawner.set_data("model_scale", value);
		data.GoBack();
	}

	if(data.JumpToKey("BossHealthBar")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_spawner_var, INVALID_FUNCTION, 0);
		spawner.set_data("bosshealthbar", RoundToFloor(value) != 0);
		data.GoBack();
	}

	return 1;
}

static Action bosshealthbar_think(int entity, const char[] context)
{
	monster_resource.LinkHealth(entity);
	SetEntityNextThink(entity, GetGameTime() + 0.1, context);
	return Plugin_Continue;
}

static int native_expr_pop_spawn(Handle plugin, int params)
{
	ArrayList result = GetNativeCell(3);
	if(!result) {
		return 1;
	}

	CustomPopulationSpawner spawner = GetNativeCell(1);

	float pos[3];
	GetNativeArray(2, pos, 3);

	int health = 0;
	if(spawner.has_data("health")) {
		health = spawner.get_data("health");
	}

	bool tank = spawner.IsMiniBoss();

	float health_mult = pop_health_multiplier(tank);

	int health_scaled = 0;
	if(health > 0) {
		health_scaled = RoundToFloor(float(health) * health_mult);
		if(health_scaled <= 0) {
			return 0;
		}
	}

	float model_scale = 0.0;
	if(spawner.has_data("model_scale")) {
		model_scale = spawner.get_data("model_scale");
	}

	bool bosshealthbar = false;
	if(spawner.has_data("bosshealthbar")) {
		bosshealthbar = spawner.get_data("bosshealthbar");
	}

	int len = result.Length;
	for(int i = 0; i < len; ++i) {
		int entity = result.Get(i);
		if(!IsValidEntity(entity)) {
			return 0;
		}

		if(health_scaled > 0) {
			SetEntProp(entity, Prop_Data, "m_iHealth", health_scaled);
			SetEntProp(entity, Prop_Data, "m_iMaxHealth", health_scaled);
		} else {
			int newhealth = RoundToFloor(float(GetEntProp(entity, Prop_Data, "m_iMaxHealth")) * health_mult);
			if(newhealth <= 0) {
				return 0;
			}
			SetEntProp(entity, Prop_Data, "m_iHealth", newhealth);
			SetEntProp(entity, Prop_Data, "m_iMaxHealth", newhealth);
		}

		if(model_scale > 0.0) {
			SetEntPropFloat(entity, Prop_Send, "m_flModelScale", model_scale);
		} else if(spawner.IsMiniBoss(i)) {
			SetEntPropFloat(entity, Prop_Send, "m_flModelScale", tf_mvm_miniboss_scale.FloatValue);
		}

		if(bosshealthbar) {
			HookEntityContextThink(entity, bosshealthbar_think, "ThinkBossHealthbar");
			SetEntityNextThink(entity, GetGameTime() + 0.1, "ThinkBossHealthbar");
		}
	}

	return 1;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("expr_pop");
	CreateNative("expr_pop_parse", native_expr_pop_parse);
	CreateNative("expr_pop_spawn", native_expr_pop_spawn);
	return APLRes_Success;
}

static bool expr_pop_wavespawn_var(any user_data, const char[] name, float &value)
{
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

	return false;
}

static bool expr_pop_wave_var(any user_data, const char[] name, float &value)
{
	CWave populator = view_as<CWave>(user_data);

	if(StrEqual(name, "WaitWhenDone")) {
		value = populator.WaitWhenDone;
		return true;
	}

	return false;
}

public Action wave_parse(CWave populator, KeyValues data, bool &result)
{
	char value_str[EXPR_STR_MAX];

	if(data.JumpToKey("WaitWhenDone")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wave_var, INVALID_FUNCTION, populator);
		populator.WaitWhenDone = value;
		data.GoBack();
	}

	return Plugin_Continue;
}

public Action wavespawn_parse(CWaveSpawnPopulator populator, KeyValues data, bool &result)
{
	char value_str[EXPR_STR_MAX];

	if(data.JumpToKey("TotalCount")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, INVALID_FUNCTION, populator);
		populator.TotalCount = RoundToFloor(value);
		data.GoBack();
	}

	if(data.JumpToKey("MaxActive")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, INVALID_FUNCTION, populator);
		populator.MaxActive = RoundToFloor(value);
		data.GoBack();
	}

	if(data.JumpToKey("SpawnCount")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, INVALID_FUNCTION, populator);
		populator.SpawnCount = RoundToFloor(value);
		data.GoBack();
	}

	if(data.JumpToKey("WaitBeforeStarting")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, INVALID_FUNCTION, populator);
		populator.WaitBeforeStarting = value;
		data.GoBack();
	}

	if(data.JumpToKey("WaitBetweenSpawns")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, INVALID_FUNCTION, populator);
		populator.WaitBetweenSpawns = value;
		data.GoBack();
	}

	if(data.JumpToKey("WaitBetweenSpawnsAfterDeath")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, INVALID_FUNCTION, populator);
		populator.WaitBetweenSpawnsAfterDeath = value;
		data.GoBack();
	}

	if(data.JumpToKey("RandomSpawn")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, INVALID_FUNCTION, populator);
		populator.RandomSpawn = (RoundToFloor(value) != 0);
		data.GoBack();
	}

	if(data.JumpToKey("TotalCurrency")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, INVALID_FUNCTION, populator);
		populator.TotalCurrency = RoundToFloor(value);
		data.GoBack();
	}

	return Plugin_Continue;
}
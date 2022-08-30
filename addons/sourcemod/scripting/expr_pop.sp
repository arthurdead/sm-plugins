#include <sourcemod>
#include <popspawner>
#include <expression_parser>
#include <stocksoup/tf/monster_resource>
#include <datamaps>
#include <nextbot>
#include <expr_pop>

#define TEAM_SPECTATOR 1
#define TF_TEAM_PVE_DEFENDERS 2

#define LIFE_ALIVE 2
#define EFL_KILLME (1 << 0)

static TFMonsterResource monster_resource;

static ConVar tf_mvm_miniboss_scale;

static ArrayList ambush_spawn_locations;

static ArrayList last_ambush_areas;
static float next_ambush_calc;
static ArrayList entity_seen_time;
static ArrayList ambush_entities;

static float next_teleport_calc;

static ConVar tf_populator_active_buffer_range;

static ConVar ambush_unseen_time;
static ConVar ambush_teleport_time;
static ConVar ambush_collect_time;

public void OnPluginStart()
{
	tf_mvm_miniboss_scale = FindConVar("tf_mvm_miniboss_scale");

	tf_populator_active_buffer_range = FindConVar("tf_populator_active_buffer_range");

	ambush_unseen_time = CreateConVar("ambush_unseen_time", "5.0");
	ambush_teleport_time = CreateConVar("ambush_teleport_time", "0.5");
	ambush_collect_time = CreateConVar("ambush_collect_time", "1.0");

	ambush_spawn_locations = new ArrayList();

	ambush_entities = new ArrayList();

	last_ambush_areas = new ArrayList();
	entity_seen_time = new ArrayList(3);

	HookEvent("teamplay_round_start", teamplay_round_start);
}

//TODO!!!! hook takedmg and *= damage to pop_damage_multiplier

public void OnMapStart()
{
	monster_resource = TFMonsterResource.GetEntity(true);
	monster_resource.Hide();

	next_ambush_calc = 0.0;
}

static void teamplay_round_start(Event event, const char[] name, bool dontBroadcast)
{
	collect_ambush_areas();
}

static void collect_ambush_areas()
{
	last_ambush_areas.Clear();

	ArrayList tmp_ambush_areas = new ArrayList();

	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			IsClientSourceTV(i) ||
			IsClientReplay(i)) {
			continue;
		}

		if(!IsPlayerAlive(i) ||
			GetClientTeam(i) != TF_TEAM_PVE_DEFENDERS) {
			continue;
		}

		CNavArea start_area = GetEntityLastKnownArea(i);
		if(start_area == CNavArea_Null) {
			continue;
		}

		CollectSurroundingAreas(tmp_ambush_areas, start_area, tf_populator_active_buffer_range.FloatValue, STEP_HEIGHT, 200.0);

		int len = tmp_ambush_areas.Length;
		for(int j = 0; j < len; ++j) {
			CTFNavArea area = tmp_ambush_areas.Get(j);

			if(!area.ValidForWanderingPopulation) {
				continue;
			}

			if(area.IsPotentiallyVisibleToTeam(TF_TEAM_PVE_DEFENDERS)) {
				continue;
			}

			if(last_ambush_areas.FindValue(area) == -1) {
				last_ambush_areas.Push(area);
			}
		}
	}

	delete tmp_ambush_areas;

	next_ambush_calc = GetGameTime() + ambush_collect_time.FloatValue;
}

static bool get_random_ambush(float pos[3])
{
	int len = last_ambush_areas.Length;
	if(len == 0) {
		return false;
	}

	for(int i = 0; i < 5; ++i) {
		int idx = GetRandomInt(0, len-1);
		CNavArea area = last_ambush_areas.Get(idx);

		for(int j = 0; j < 3; ++j) {
			area.GetRandomPoint(pos);

			if(IsSpaceToSpawnHere(pos)) {
				return true;
			}
		}
	}

	return false;
}

public void pop_entity_spawned(IPopulator populator, IPopulationSpawner spawner, SpawnLocation location, int entity)
{
	if(ambush_spawn_locations.FindValue(location) != -1) {
		ambush_entities.Push(EntIndexToEntRef(entity));
	}
}

public void OnGameFrame()
{
	if(next_ambush_calc < GetGameTime()) {
		collect_ambush_areas();
	}

	if(next_teleport_calc < GetGameTime()) {
		int len = ambush_entities.Length;
		for(int i = 0; i < len;) {
			int ref = ambush_entities.Get(i);

			int seen_idx = entity_seen_time.FindValue(ref);

			int entity = EntRefToEntIndex(ref);
			if(entity == -1) {
				ambush_entities.Erase(i);
				if(seen_idx != -1) {
					entity_seen_time.Erase(seen_idx);
				}
				continue;
			}

			if(GetEntProp(entity, Prop_Data, "m_lifeState") != LIFE_ALIVE ||
				GetEntProp(entity, Prop_Data, "m_iEFlags") & EFL_KILLME) {
				ambush_entities.Erase(i);
				if(seen_idx != -1) {
					entity_seen_time.Erase(seen_idx);
				}
				continue;
			}

			if(GetEntProp(entity, Prop_Send, "m_iTeamNum") == TF_TEAM_PVE_DEFENDERS ||
				GetEntProp(entity, Prop_Send, "m_iTeamNum") == TEAM_SPECTATOR) {
				ambush_entities.Erase(i);
				if(seen_idx != -1) {
					entity_seen_time.Erase(seen_idx);
				}
				continue;
			}

			if(seen_idx == -1) {
				seen_idx = entity_seen_time.Push(ref);
				entity_seen_time.Set(seen_idx, 0.0, 1);
			}

			INextBot bot = INextBot(entity);
			IVision vision = bot.VisionInterface;

			for(int j = 1; j <= MaxClients; ++j) {
				if(!IsClientInGame(j) ||
					IsClientSourceTV(j) ||
					IsClientReplay(j)) {
					continue;
				}

				if(GetClientTeam(j) != TF_TEAM_PVE_DEFENDERS) {
					continue;
				}

				if(CombatCharacterIsAbleToSeeEnt(j, entity, USE_FOV) ||
					vision.IsAbleToSeeEntity(j, DISREGARD_FOV)) {
					entity_seen_time.Set(seen_idx, GetGameTime(), 1);
					break;
				}
			}

			float last_seen = entity_seen_time.Get(seen_idx, 1);

			if((GetGameTime() - last_seen) > ambush_unseen_time.FloatValue) {
				float pos[3];
				if(get_random_ambush(pos)) {
					TeleportEntity(entity, pos);
				}
			}

			++i;
		}

		next_teleport_calc = GetGameTime() + ambush_teleport_time.FloatValue;
	}
}

public Action find_spawn_location(IPopulator populator, SpawnLocation location, float pos[3])
{
	if(ambush_spawn_locations.FindValue(location) != -1) {
		if(get_random_ambush(pos)) {
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

public Action spawnlocation_parse(IPopulator populator, SpawnLocation location, KeyValues data, bool &result)
{
	if(data.JumpToKey("Where")) {
		char value_str[32];
		data.GetString(NULL_STRING, value_str, sizeof(value_str));
		if(StrEqual(value_str, "Ambush")) {
			location.Relative = ANYWHERE;
			location.ClosestPointOnNav = true;
			ambush_spawn_locations.Push(location);
		}
		data.GoBack();
	}

	return Plugin_Continue;
}

public void OnMapEnd()
{
	ambush_spawn_locations.Clear();
	ambush_entities.Clear();
}

public void OnEntityDestroyed(int entity)
{
	if(entity == -1) {
		return;
	}

	if(entity & (1 << 31)) {
		entity = EntRefToEntIndex(entity);
	}

	int ref = EntIndexToEntRef(entity);

	int idx = entity_seen_time.FindValue(ref);
	if(idx != -1) {
		entity_seen_time.Erase(idx);
	}

	idx = ambush_entities.FindValue(ref);
	if(idx != -1) {
		ambush_entities.Erase(idx);
	}

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	if(StrEqual(classname, "info_populator")) {
		ambush_spawn_locations.Clear();
		ambush_entities.Clear();
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "info_populator")) {
		ambush_spawn_locations.Clear();
		ambush_entities.Clear();
	}
}

public Action pop_parse(KeyValues data, bool &result)
{
	ambush_spawn_locations.Clear();
	ambush_entities.Clear();
	return Plugin_Continue;
}

static bool base_expr_pop_var(const char[] name, float &value)
{
	if(StrEqual(name, "DamageMultiplier")) {
		value = pop_damage_multiplier();
		return true;
	}

	if(StrEqual(name, "HealthMultiplier")) {
		value = pop_health_multiplier(false);
		return true;
	}

	if(StrEqual(name, "TankHealthMultiplier")) {
		value = pop_health_multiplier(true);
		return true;
	}

	if(StrEqual(name, "CurrentWaveIndex")) {
		value = float(current_wave_index());
		return true;
	}

	if(StrEqual(name, "CurrentWave")) {
		CWave wave = current_wave();
		if(wave != CWave_Null) {
			value = float(wave.Index);
		} else {
			value = 0.0;
		}
		return true;
	}

	ConVar cvar = FindConVar(name);
	if(cvar) {
		value = cvar.FloatValue;
		return true;
	}

	return false;
}

static bool base_expr_pop_func(const char[] name, int num_args, const float[] args, float &value)
{
	if(StrEqual(name, "HealthMultiplier")) {
		if(num_args != 1) {
			return false;
		}

		value = pop_health_multiplier(RoundToFloor(args[0]) != 0);
		return true;
	}

	return false;
}

static bool expr_pop_spawner_func(any user_data, const char[] name, int num_args, const float[] args, float &value)
{
	CustomPopulationSpawner spawner = view_as<CustomPopulationSpawner>(user_data);

	return base_expr_pop_func(name, num_args, args, value);
}

static bool expr_pop_spawner_var(any user_data, const char[] name, float &value)
{
	CustomPopulationSpawner spawner = view_as<CustomPopulationSpawner>(user_data);

	if(StrEqual(name, "MiniBoss")) {
		value = spawner.IsMiniBoss() ? 1.0 : 0.0;
		return true;
	}

	if(StrEqual(name, "Health")) {
		value = float(spawner.GetHealth());
		return true;
	}

	if(StrEqual(name, "Class")) {
		value = float(view_as<int>(spawner.GetClass()));
		return true;
	}

	return base_expr_pop_var(name, value);
}

static int native_expr_pop_parse(Handle plugin, int params)
{
	CustomPopulationSpawner spawner = GetNativeCell(1);
	KeyValues data = GetNativeCell(2);

	char value_str[EXPR_STR_MAX];

	if(data.JumpToKey("Health")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_spawner_var, expr_pop_spawner_func, spawner);
		if(value < 1.0) {
			data.GoBack();
			return 0;
		}
		spawner.set_data("health", RoundToFloor(value));
		data.GoBack();
	}

	if(data.JumpToKey("ModelScale")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_spawner_var, expr_pop_spawner_func, spawner);
		if(value <= 0.0) {
			data.GoBack();
			return 0;
		}
		spawner.set_data("model_scale", value);
		data.GoBack();
	}

	if(data.JumpToKey("HealthBar")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		if(StrEqual(value_str, "None")) {
			spawner.set_data("healthbar", entity_healthbar_none);
		} else if(StrEqual(value_str, "Boss")) {
			spawner.set_data("healthbar", entity_healthbar_boss);
		}
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

	entity_healthbar_t healthbar = entity_healthbar_none;
	if(spawner.has_data("healthbar")) {
		healthbar = spawner.get_data("healthbar");
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

		switch(healthbar) {
			case entity_healthbar_boss: {
				HookEntityContextThink(entity, bosshealthbar_think, "ThinkBossHealthbar");
				SetEntityNextThink(entity, GetGameTime() + 0.1, "ThinkBossHealthbar");
			}
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

static bool expr_pop_wavespawn_func(any user_data, const char[] name, int num_args, const float[] args, float &value)
{
	return base_expr_pop_func(name, num_args, args, value);
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

	return base_expr_pop_var(name, value);
}

static bool expr_pop_wave_func(any user_data, const char[] name, int num_args, const float[] args, float &value)
{
	return base_expr_pop_func(name, num_args, args, value);
}

static bool expr_pop_wave_var(any user_data, const char[] name, float &value)
{
	CWave populator = view_as<CWave>(user_data);

	if(StrEqual(name, "WaitWhenDone")) {
		value = populator.WaitWhenDone;
		return true;
	}

	return base_expr_pop_var(name, value);
}

public Action wave_parse(CWave populator, KeyValues data, bool &result)
{
	char value_str[EXPR_STR_MAX];

	if(data.JumpToKey("WaitWhenDone")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wave_var, expr_pop_wave_func, populator);
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
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, populator);
		populator.TotalCount = RoundToFloor(value);
		data.GoBack();
	}

	if(data.JumpToKey("MaxActive")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, populator);
		populator.MaxActive = RoundToFloor(value);
		data.GoBack();
	}

	if(data.JumpToKey("SpawnCount")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, populator);
		populator.SpawnCount = RoundToFloor(value);
		data.GoBack();
	}

	if(data.JumpToKey("WaitBeforeStarting")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, populator);
		populator.WaitBeforeStarting = value;
		data.GoBack();
	}

	if(data.JumpToKey("WaitBetweenSpawns")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, populator);
		populator.WaitBetweenSpawns = value;
		data.GoBack();
	}

	if(data.JumpToKey("WaitBetweenSpawnsAfterDeath")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, populator);
		populator.WaitBetweenSpawnsAfterDeath = value;
		data.GoBack();
	}

	if(data.JumpToKey("RandomSpawn")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, populator);
		populator.RandomSpawn = (RoundToFloor(value) != 0);
		data.GoBack();
	}

	if(data.JumpToKey("TotalCurrency")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, populator);
		populator.TotalCurrency = RoundToFloor(value);
		data.GoBack();
	}

	return Plugin_Continue;
}
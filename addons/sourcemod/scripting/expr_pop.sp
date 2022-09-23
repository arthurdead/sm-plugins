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

enum mod_type_t
{
	mod_merge,
	mod_merge_parent,
	mod_merge_root,
};

enum struct ModInfo
{
	KeyValues data;
	mod_type_t type;
}

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

static ArrayList manager_mods;
static ArrayList wave_mods;
static ArrayList wavespawn_mods;

public void OnPluginStart()
{
	tf_mvm_miniboss_scale = FindConVar("tf_mvm_miniboss_scale");

	tf_populator_active_buffer_range = FindConVar("tf_populator_active_buffer_range");

	ambush_unseen_time = CreateConVar("ambush_unseen_time", "5.0");
	ambush_teleport_time = CreateConVar("ambush_teleport_time", "0.5");
	ambush_collect_time = CreateConVar("ambush_collect_time", "0.5");

	ambush_spawn_locations = new ArrayList();

	ambush_entities = new ArrayList();

	last_ambush_areas = new ArrayList();
	entity_seen_time = new ArrayList(3);

	HookEvent("teamplay_round_start", teamplay_round_start);

	manager_mods = new ArrayList(sizeof(ModInfo));
	wave_mods = new ArrayList(sizeof(ModInfo));
	wavespawn_mods = new ArrayList(sizeof(ModInfo));
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
		int idx = GetURandomInt() % len;
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
				--len;
				if(seen_idx != -1) {
					entity_seen_time.Erase(seen_idx);
				}
				continue;
			}

			if(GetEntProp(entity, Prop_Data, "m_lifeState") != LIFE_ALIVE ||
				GetEntProp(entity, Prop_Data, "m_iEFlags") & EFL_KILLME) {
				ambush_entities.Erase(i);
				--len;
				if(seen_idx != -1) {
					entity_seen_time.Erase(seen_idx);
				}
				continue;
			}

			if(GetEntProp(entity, Prop_Send, "m_iTeamNum") == TF_TEAM_PVE_DEFENDERS ||
				GetEntProp(entity, Prop_Send, "m_iTeamNum") == TEAM_SPECTATOR) {
				ambush_entities.Erase(i);
				--len;
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
	char name[20];
	data.GetSectionName(name, sizeof(name));

	if(!StrEqual(name, "PluginSpawnLocation")) {
		return Plugin_Continue;
	}

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

	data.GoBack();

	return Plugin_Continue;
}

public void OnMapEnd()
{
	ambush_spawn_locations.Clear();
	ambush_entities.Clear();
	entity_seen_time.Clear();
	last_ambush_areas.Clear();
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
}

public void OnEntityCreated(int entity, const char[] classname)
{
	
}

static void parse_mod(const char[] path, ArrayList arr)
{
	mod_type_t type = mod_merge;

	int idx = StrContains(path, ".parent");
	if(idx != -1) {
		type = mod_merge_parent;
	} else {
		idx = StrContains(path, ".root");
		if(idx != -1) {
			type = mod_merge_root;
		}
	}

	KeyValues kv = new KeyValues("Population");
	if(kv.ImportFromFile(path)) {
		if(kv.GotoFirstSubKey()) {
			ModInfo mod;

			do {
				mod.data = view_as<KeyValues>(CloneHandle(kv));

				mod.type = type;

				arr.PushArray(mod, sizeof(ModInfo));
			} while(kv.GotoNextKey());
			kv.GoBack();
		}
	}
	delete kv;
}

static void loop_mod_folder(const char[] type, ArrayList arr, char[] mod_dir_path, char[] mod_file_path)
{
	BuildPath(Path_SM, mod_dir_path, PLATFORM_MAX_PATH, "configs/pop_mods/%s", type);
	DirectoryListing dir_it = OpenDirectory(mod_dir_path, true);
	if(dir_it != null) {
		FileType filetype;
		while(dir_it.GetNext(mod_file_path, PLATFORM_MAX_PATH, filetype)) {
			if(filetype != FileType_File) {
				continue;
			}

			int mod = StrContains(mod_file_path, ".mod");
			if(mod == -1) {
				continue;
			}

			if((strlen(mod_file_path)-mod) != 4) {
				continue;
			}

			Format(mod_file_path, PLATFORM_MAX_PATH, "%s/%s", mod_dir_path, mod_file_path);

			parse_mod(mod_file_path, arr);
		}
	}
	delete dir_it;
}

static void free_mods(ArrayList arr, ModInfo mod)
{
	int num_mods = arr.Length;
	for(int j = 0; j < num_mods; ++j) {
		arr.GetArray(j, mod, sizeof(ModInfo));
		delete mod.data;
	}

	arr.Clear();
}

enum expand_type_t
{
	expand_manager,
	expand_wave,
	expand_wavespawn,
};

static float tmp_wave_percent = -1.0;
static float tmp_wavespawn_percent = -1.0;

static bool expr_pop_mod_func(any user_data, const char[] name, int num_args, const float[] args, float &value)
{
	DataPack pack = view_as<DataPack>(user_data);

	pack.Reset();

	CWave wave = pack.ReadCell();
	CWaveSpawnPopulator wavespawn = pack.ReadCell();

	if(wavespawn != CWaveSpawnPopulator_Null) {
		if(expr_pop_wavespawn_func_impl(wavespawn, name, num_args, args, value)) {
			return true;
		}
	}

	if(wave != CWave_Null) {
		if(expr_pop_wave_func_impl(wave, name, num_args, args, value)) {
			return true;
		}
	}

	if(base_expr_pop_func(name, num_args, args, value)) {
		return true;
	}

	return false;
}

static bool expr_pop_mod_var(any user_data, const char[] name, float &value)
{
	DataPack pack = view_as<DataPack>(user_data);

	pack.Reset();

	CWave wave = pack.ReadCell();
	CWaveSpawnPopulator wavespawn = pack.ReadCell();

	if(wavespawn != CWaveSpawnPopulator_Null) {
		if(expr_pop_wavespawn_var_impl(wavespawn, name, value)) {
			return true;
		}
	}

	if(wave != CWave_Null) {
		if(expr_pop_wave_var_impl(wave, name, value)) {
			return true;
		}
	}

	if(StrEqual(name, "WavePercent")) {
		value = tmp_wave_percent;
		return true;
	}

	if(StrEqual(name, "WaveSpawnPercent")) {
		value = tmp_wavespawn_percent;
		return true;
	}

	if(base_expr_pop_var(name, value)) {
		return true;
	}

	return false;
}

static void expand_mod_ifs(KeyValues data, KeyValues expanded, expand_type_t type, DataPack objs)
{
	if(data.GotoFirstSubKey(false)) {
		char tmp_sec_name[EXPR_STR_MAX];
		char tmp_value[64];

		do {
			data.GetSectionName(tmp_sec_name, sizeof(tmp_sec_name));

			bool is_if = (strncmp(tmp_sec_name, "If", 2) == 0);

			float value = 0.0;
			if(is_if) {
				value = parse_expression(tmp_sec_name[3], expr_pop_mod_var, expr_pop_mod_func, objs);
			} else {
				value = 1.0;
			}

			if(RoundToFloor(value) == 0) {
				continue;
			}

			if(is_if) {
				expand_mod_ifs(data, expanded, type, objs);
			} else {
				if(expanded.JumpToKey(tmp_sec_name, true)) {
					data.GetString(NULL_STRING, tmp_value, sizeof(tmp_value));
					expanded.SetString(NULL_STRING, tmp_value);
					expand_mod_ifs(data, expanded, type, objs);
					expanded.GoBack();
				}
			}
		} while(data.GotoNextKey(false));
		data.GoBack();
	}
}

public Action pop_parse(KeyValues data, bool &result)
{
	ambush_spawn_locations.Clear();
	ambush_entities.Clear();

	ModInfo mod;

	free_mods(manager_mods, mod);
	free_mods(wave_mods, mod);
	free_mods(wavespawn_mods, mod);

	char mod_file_path[PLATFORM_MAX_PATH];
	char mod_dir_path[PLATFORM_MAX_PATH];

	loop_mod_folder("wave", wave_mods, mod_dir_path, mod_file_path);
	loop_mod_folder("wavespawn", wavespawn_mods, mod_dir_path, mod_file_path);
	loop_mod_folder("manager", manager_mods, mod_dir_path, mod_file_path);

	int num_manager_mods = manager_mods.Length;

	char tmp_sec_name[EXPR_STR_MAX];

	tmp_wave_percent = -1.0;
	tmp_wavespawn_percent = -1.0;

	for(int i = 0; i < num_manager_mods; ++i) {
		manager_mods.GetArray(i, mod, sizeof(ModInfo));

		KeyValues mod_data_expanded = new KeyValues("Population");

		DataPack objs = new DataPack();
		objs.WriteCell(CWave_Null);
		objs.WriteCell(CWaveSpawnPopulator_Null);
		expand_mod_ifs(mod.data, mod_data_expanded, expand_manager, objs);
		delete objs;

		if(!merge_pop(mod_data_expanded)) {
			delete mod_data_expanded;
			result = false;
			return Plugin_Stop;
		}

		delete mod_data_expanded;
	}

	int num_wave_mods = wave_mods.Length;
	int num_wavespawn_mods = wavespawn_mods.Length;

	int num_waves = wave_count();
	for(int i = 0; i < num_waves; ++i) {
		CWave wave = get_wave(i);

		tmp_wave_percent = (float(i+1) / float(num_waves));

		for(int j = 0; j < num_wave_mods; ++j) {
			wave_mods.GetArray(j, mod, sizeof(ModInfo));

			KeyValues mod_data_expanded = new KeyValues("Population");

			DataPack objs = new DataPack();
			objs.WriteCell(wave);
			objs.WriteCell(CWaveSpawnPopulator_Null);
			expand_mod_ifs(mod.data, mod_data_expanded, expand_wave, objs);
			delete objs;

			switch(mod.type) {
				case mod_merge: {
					if(!wave.ParseAdditive(mod_data_expanded)) {
						result = false;
						return Plugin_Stop;
					}
				}
				case mod_merge_parent, mod_merge_root: {
					if(!merge_pop(mod_data_expanded)) {
						result = false;
						return Plugin_Stop;
					}
				}
			}

			delete mod_data_expanded;
		}

		int num_wavespawns = wave.WaveSpawnCount;
		for(int k = 0; k < num_wavespawns; ++k) {
			CWaveSpawnPopulator wavespawn = wave.GetWaveSpawn(k);

			tmp_wavespawn_percent = (float(k+1) / float(num_wavespawns));

			for(int j = 0; j < num_wavespawn_mods; ++j) {
				wavespawn_mods.GetArray(j, mod, sizeof(ModInfo));

				KeyValues mod_data_expanded = new KeyValues("Population");

				DataPack objs = new DataPack();
				objs.WriteCell(wave);
				objs.WriteCell(wavespawn);
				expand_mod_ifs(mod.data, mod_data_expanded, expand_wavespawn, objs);
				delete objs;

				if(mod.type == mod_merge_parent) {
					if(mod_data_expanded.GotoFirstSubKey()) {
						do {
							mod_data_expanded.GetSectionName(tmp_sec_name, sizeof(tmp_sec_name));

							if(StrEqual(tmp_sec_name, "WaveSpawn")) {
								if(!mod_data_expanded.JumpToKey("WaitForAllSpawned")) {
									wavespawn.GetWaitForAllSpawned(tmp_sec_name, sizeof(tmp_sec_name));
									mod_data_expanded.SetString("WaitForAllSpawned", tmp_sec_name);
								} else {
									mod_data_expanded.GoBack();
								}

								if(!mod_data_expanded.JumpToKey("WaitForAllDead")) {
									wavespawn.GetWaitForAllSpawned(tmp_sec_name, sizeof(tmp_sec_name));
									mod_data_expanded.SetString("WaitForAllDead", tmp_sec_name);
								} else {
									mod_data_expanded.GoBack();
								}

								if(!mod_data_expanded.JumpToKey("WaitBeforeStarting")) {
									mod_data_expanded.SetFloat("WaitBeforeStarting", wavespawn.WaitBeforeStarting);
								} else {
									mod_data_expanded.GoBack();
								}
							}
						} while(mod_data_expanded.GotoNextKey());
						mod_data_expanded.GoBack();
					}
				}

				switch(mod.type) {
					case mod_merge: {
						if(!wavespawn.ParseAdditive(mod_data_expanded)) {
							delete mod_data_expanded;
							result = false;
							return Plugin_Stop;
						}
					}
					case mod_merge_parent: {
						if(!wave.ParseAdditive(mod_data_expanded)) {
							delete mod_data_expanded;
							result = false;
							return Plugin_Stop;
						}
					}
					case mod_merge_root: {
						if(!merge_pop(mod_data_expanded)) {
							delete mod_data_expanded;
							result = false;
							return Plugin_Stop;
						}
					}
				}

				delete mod_data_expanded;
			}
		}
	}

	return Plugin_Continue;
}

static bool base_expr_pop_var(const char[] name, float &value)
{
	if(StrEqual(name, "DamageMultiplier")) {
		value = pop_damage_multiplier();
		return true;
	} else if(StrEqual(name, "HealthMultiplier")) {
		value = pop_health_multiplier(false);
		return true;
	} else if(StrEqual(name, "TankHealthMultiplier")) {
		value = pop_health_multiplier(true);
		return true;
	} else {
		ConVar cvar = FindConVar(name);
		if(cvar) {
			value = cvar.FloatValue;
			return true;
		}
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
	} else if(StrEqual(name, "Health")) {
		value = float(spawner.GetHealth());
		return true;
	} else if(StrEqual(name, "Class")) {
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

static bool expr_pop_wavespawn_func_impl(any user_data, const char[] name, int num_args, const float[] args, float &value)
{
	return false;
}

static bool expr_pop_wavespawn_func(any user_data, const char[] name, int num_args, const float[] args, float &value)
{
	DataPack pack = view_as<DataPack>(user_data);

	pack.Reset();

	CWave wave = pack.ReadCell();
	CWaveSpawnPopulator wavespawn = pack.ReadCell();

	if(expr_pop_wavespawn_func_impl(wavespawn, name, num_args, args, value)) {
		return true;
	}

	if(wave != CWave_Null) {
		if(expr_pop_wave_func_impl(wave, name, num_args, args, value)) {
			return true;
		}
	}

	return base_expr_pop_func(name, num_args, args, value);
}

static bool expr_pop_wavespawn_var_impl(any user_data, const char[] name, float &value)
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

static bool expr_pop_wavespawn_var(any user_data, const char[] name, float &value)
{
	DataPack pack = view_as<DataPack>(user_data);

	pack.Reset();

	CWave wave = pack.ReadCell();
	CWaveSpawnPopulator wavespawn = pack.ReadCell();

	if(expr_pop_wavespawn_var_impl(wavespawn, name, value)) {
		return true;
	}

	if(wave != CWave_Null) {
		if(expr_pop_wave_var_impl(wave, name, value)) {
			return true;
		}
	}

	return base_expr_pop_var(name, value);
}

static bool expr_pop_wave_func_impl(any user_data, const char[] name, int num_args, const float[] args, float &value)
{
	return false;
}

static bool expr_pop_wave_func(any user_data, const char[] name, int num_args, const float[] args, float &value)
{
	if(expr_pop_wave_func_impl(user_data, name, num_args, args, value)) {
		return true;
	}

	return base_expr_pop_func(name, num_args, args, value);
}

static bool expr_pop_wave_var_impl(any user_data, const char[] name, float &value)
{
	CWave populator = view_as<CWave>(user_data);

	if(StrEqual(name, "WaitWhenDone")) {
		value = populator.WaitWhenDone;
		return true;
	} else if(StrEqual(name, "WaveIndex")) {
		value = float(populator.Index);
		return true;
	}

	return false;
}

static bool expr_pop_wave_var(any user_data, const char[] name, float &value)
{
	if(expr_pop_wave_var_impl(user_data, name, value)) {
		return true;
	}

	return base_expr_pop_var(name, value);
}

public Action wave_parse(CWave populator, KeyValues data, bool &result)
{
	if(!data.JumpToKey("Plugin")) {
		return Plugin_Continue;
	}

	char value_str[EXPR_STR_MAX];

	if(data.JumpToKey("WaitWhenDone")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wave_var, expr_pop_wave_func, populator);
		populator.WaitWhenDone = value;
		data.GoBack();
	}

	data.GoBack();

	return Plugin_Continue;
}

public Action wavespawn_parse(CWave wave, CWaveSpawnPopulator populator, KeyValues data, bool &result)
{
	if(!data.JumpToKey("Plugin")) {
		return Plugin_Continue;
	}

	char value_str[EXPR_STR_MAX];

	DataPack objs = new DataPack();
	objs.WriteCell(wave);
	objs.WriteCell(populator);

	if(data.JumpToKey("TotalCount")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, objs);
		populator.TotalCount = RoundToFloor(value);
		data.GoBack();
	}

	if(data.JumpToKey("MaxActive")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, objs);
		populator.MaxActive = RoundToFloor(value);
		data.GoBack();
	}

	if(data.JumpToKey("SpawnCount")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, objs);
		populator.SpawnCount = RoundToFloor(value);
		data.GoBack();
	}

	if(data.JumpToKey("WaitBeforeStarting")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, objs);
		populator.WaitBeforeStarting = value;
		data.GoBack();
	}

	if(data.JumpToKey("WaitBetweenSpawns")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, objs);
		populator.WaitBetweenSpawns = value;
		data.GoBack();
	}

	if(data.JumpToKey("WaitBetweenSpawnsAfterDeath")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, objs);
		populator.WaitBetweenSpawnsAfterDeath = value;
		data.GoBack();
	}

	if(data.JumpToKey("RandomSpawn")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, objs);
		populator.RandomSpawn = (RoundToFloor(value) != 0);
		data.GoBack();
	}

	if(data.JumpToKey("TotalCurrency")) {
		data.GetString(NULL_STRING, value_str, EXPR_STR_MAX);
		float value = parse_expression(value_str, expr_pop_wavespawn_var, expr_pop_wavespawn_func, objs);
		populator.TotalCurrency = RoundToFloor(value);
		data.GoBack();
	}

	data.GoBack();

	delete objs;

	return Plugin_Continue;
}
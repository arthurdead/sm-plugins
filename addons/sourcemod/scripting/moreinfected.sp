#include <sourcemod>
#include <keyvalues>
#include <sdkhooks>
#include <moreinfected>
#include <dhooks>

#undef REQUIRE_EXTENSIONS
#tryinclude <datamaps>
#tryinclude <nextbot>
#tryinclude <animhelpers>

KeyValues kvInfected = null;

enum struct InfectedInfo
{
	Handle hPlugin;
	char name[MI_MAX_NAME_LEN];
	char alias[MI_MAX_NAME_LEN];
	char plname[MI_MAX_PLUGIN_LEN];
	char place[MI_MAX_PLACE_LEN];
	float weight;
	KeyValues data;
	infected_directive_flags directive_flags;
	infected_class_flags class_flags;
}

enum
{
	class_common,
	class_tank,
	class_smoker,
	class_charger,
	class_boomer,
	class_hunter,
	class_jockey,
	class_spitter,
	class_witch,
	class_witch_bride,
	infected_class_count,
};

enum
{
	directive_wanderer,
	directive_ambient,
	directive_attack,
	directive_special,
	infected_directive_count,
};

enum func_name
{
	func_precache,
	func_common,
	func_special
};

enum struct HopscotchPair
{
	ArrayList weights;
	ArrayList accum;
}

ArrayList arInfectedInfos = null;
StringMap infectedMap[2][infected_directive_count];

bool g_bLateLoaded = false;

#if defined datamaps_included
bool g_bDatamaps = false;
#endif
#if defined nextbot_included
bool g_bNextBot = false;
#endif
#if defined animhelpers_included
bool g_bAnimhelpers = false;
#endif

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int length)
{
	g_bLateLoaded = late;
	RegPluginLibrary("moreinfected");

#if defined nextbot_included
	if(LibraryExists("nextbot")) {
		g_bNextBot = true;
	} else if(GetExtensionFileStatus("nextbot.ext") == 1) {
		g_bNextBot = true;
	}
#endif
#if defined datamaps_included
	if(LibraryExists("datamaps")) {
		g_bDatamaps = true;
	} else if(GetExtensionFileStatus("datamaps.ext") == 1) {
		g_bDatamaps = true;
	}
#endif
#if defined animhelpers_included
	if(LibraryExists("animhelpers")) {
		g_bAnimhelpers = true;
	} else if(GetExtensionFileStatus("animhelpers.ext") == 1) {
		g_bAnimhelpers = true;
	}
#endif

	return APLRes_Success;
}

public void OnLibraryAdded(const char[] name)
{
#if defined nextbot_included
	if(StrEqual(name, "nextbot")) {
		g_bNextBot = true;
	}
#endif
#if defined datamaps_included
	if(StrEqual(name, "datamaps")) {
		g_bDatamaps = true;
	}
#endif
#if defined animhelpers_included
	if(StrEqual(name, "animhelpers")) {
		g_bAnimhelpers = true;
	}
#endif
}

public void OnLibraryRemoved(const char[] name)
{
#if defined nextbot_included
	if(StrEqual(name, "nextbot")) {
		g_bNextBot = false;
	}
#endif
#if defined datamaps_included
	if(StrEqual(name, "datamaps")) {
		g_bDatamaps = false;
	}
#endif
#if defined animhelpers_included
	if(StrEqual(name, "animhelpers")) {
		g_bAnimhelpers = false;
	}
#endif
}

void PrepareHopscotchRandom(ArrayList weights, ArrayList &accum)
{
	SortADTArray(weights, Sort_Descending, Sort_Float);

	int len = weights.Length;
	accum = new ArrayList();
	for(int i = 0; i < len; ++i) {
		float value = weights.Get(i);
		if(i > 0) {
			float last_value = accum.Get(i-1);
			value += last_value;
		}
		accum.Push(value);
	}
}

int HopscotchRandom(ArrayList weights, ArrayList accum)
{
	int len = accum.Length;
	float value = accum.Get(len-1);
	float target_dist = GetRandomFloat(0.0, 1.0) * value;
	int idx = 0;
	while(true) {
		if(idx >= len) {
			break;
		}
		value = accum.Get(idx);
		if(value > target_dist) {
			return idx;
		}
		float hop_distance = target_dist - value;
		value = weights.Get(idx);
		int hop_idx = 1 + RoundToFloor(hop_distance / value);
		idx += hop_idx;
	}

	return -1;
}

ArrayList tmparrclasses[infected_class_count] = {null, ...};

bool classflags_has_special(infected_class_flags flags)
{
	return (!(flags & class_flags_common) ||
			flags & class_flags_tank ||
			flags & class_flags_smoker ||
			flags & class_flags_charger ||
			flags & class_flags_boomer ||
			flags & class_flags_hunter ||
			flags & class_flags_jockey ||
			flags & class_flags_spitter ||
			flags & class_flags_witch ||
			flags & class_flags_witch_bride);
}

void LoadKVFile()
{
	char infectedfile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, infectedfile, sizeof(infectedfile), "data/moreinfected.txt");

	if(FileExists(infectedfile, true)) {
		kvInfected = new KeyValues("moreinfected");
		kvInfected.ImportFromFile(infectedfile);

		if(kvInfected.GotoFirstSubKey()) {
			arInfectedInfos = new ArrayList(sizeof(InfectedInfo));

			for(int j = 0; j < 2; ++j) {
				for(int i = 0; i < infected_directive_count; ++i) {
					infectedMap[j][i] = new StringMap();
				}
			}

			char name[MI_MAX_NAME_LEN];
			char place[MI_MAX_PLACE_LEN];
			char classstr[MI_MAX_CLASS_LEN];
			char directivestr[MI_MAX_DIRECTIVE_LEN];
			InfectedInfo info;
			char datastr[MI_MAX_DATA_LEN];
			char hookstr[5];

			do {
				kvInfected.GetSectionName(name, sizeof(name));

				float weight = kvInfected.GetFloat("weight");
				if(weight == 0.0) {
					PrintToServer("[MOREINFECTED] %s: ignoring due to weight being 0", name);
					continue;
				}

				kvInfected.GetString("class_flags", classstr, sizeof(classstr), "common");
				infected_class_flags classflags = ClassStrToFlags(classstr);
				if(classflags == class_flags_invalid) {
					PrintToServer("[MOREINFECTED] %s: invalid class flags: %s", name, classstr);
					continue;
				}

				infected_directive_flags directiveflags = directive_flags_attack;

				if(classflags & class_flags_common) {
					kvInfected.GetString("directive_flags", directivestr, sizeof(directivestr), "any");
					directiveflags = DirectiveStrToFlags(directivestr);
					if(directiveflags == directive_flags_invalid) {
						PrintToServer("[MOREINFECTED] %s: invalid directive flags: %s", name, directivestr);
						continue;
					}
				}

				bool post = true;

				kvInfected.GetString("hook", hookstr, sizeof(hookstr), "post");

				if(StrEqual(hookstr, "post")) {
					post = true;
				} else if(StrEqual(hookstr, "pre")) {
					post = false;
				} else {
					PrintToServer("[MOREINFECTED] %s: invalid hook str: %s", name, hookstr);
					continue;
				}

				kvInfected.GetString("place", place, sizeof(place), "default");

				if(classflags & class_flags_common) {
					if(directiveflags & directive_flags_wanderer)
					{ SetupClassesMap(infectedMap[post ? 0 : 1][directive_wanderer], classflags, arInfectedInfos.Length, place); }
					if(directiveflags & directive_flags_ambient)
					{ SetupClassesMap(infectedMap[post ? 0 : 1][directive_ambient], classflags, arInfectedInfos.Length, place); }
					if(directiveflags & directive_flags_attack)
					{ SetupClassesMap(infectedMap[post ? 0 : 1][directive_attack], classflags, arInfectedInfos.Length, place); }
				}

				if(classflags_has_special(classflags)) {
					SetupClassesMap(infectedMap[post ? 0 : 1][directive_special], classflags, arInfectedInfos.Length, place);
				}

				info.weight = weight;
				info.class_flags = classflags;
				info.directive_flags = directiveflags;
				strcopy(info.name, sizeof(info.name), name);
				strcopy(info.place, sizeof(info.place), place);

				kvInfected.GetString("plugin", info.plname, sizeof(info.plname));
				kvInfected.GetString("alias", info.alias, sizeof(info.alias));

				if(kvInfected.JumpToKey("data")) {
					kvInfected.ExportToString(datastr, sizeof(datastr));
					kvInfected.GoBack();

					info.data = new KeyValues("data");
					info.data.ImportFromString(datastr);
				}

				arInfectedInfos.PushArray(info, sizeof(info));
			} while(kvInfected.GotoNextKey());

			for(int n = 0; n < 2; ++n) {
				for(int j = 0; j < infected_directive_count; ++j) {
					StringMapSnapshot snapshot = infectedMap[n][j].Snapshot();
					int len = snapshot.Length;
					for(int i = 0; i < len; ++i) {
						snapshot.GetKey(i, place, sizeof(place));
						if(infectedMap[n][j].GetArray(place, tmparrclasses, sizeof(tmparrclasses))) {
							for(int k = 0; k < infected_class_count; ++k) {
								ArrayList tmparr = tmparrclasses[k];
								if(tmparr == null || tmparr.Length == 0) {
									continue;
								}
								int arrlen = tmparr.Length;
								ArrayList weights = new ArrayList();
								for(int l = 0; l < arrlen; ++l) {
									int idx = tmparr.Get(l);
									arInfectedInfos.GetArray(idx, info, sizeof(info));
									weights.Push(info.weight);
								}
								ArrayList accum = null;
								PrepareHopscotchRandom(weights, accum);
								tmparr.Push(weights);
								tmparr.Push(accum);
							}
						}
					}
					delete snapshot;
				}
			}

			kvInfected.GoBack();
		}
		kvInfected.GoBack();
	}
}

public void OnPluginStart()
{
	GameData gamedata = new GameData("moreinfected");

	DynamicDetour dSpawnCommonZombie =
	DynamicDetour.FromConf(gamedata, "ZombieManager::SpawnCommonZombie");

	DynamicDetour dSpawnSpecialNav =
	DynamicDetour.FromConf(gamedata, "ZombieManager::SpawnSpecial<TerrorNavArea>");

	DynamicDetour dSpawnSpecialVec =
	DynamicDetour.FromConf(gamedata, "ZombieManager::SpawnSpecial<Vector>");

	DynamicDetour dSpawnTankNav =
	DynamicDetour.FromConf(gamedata, "ZombieManager::SpawnTank<TerrorNavArea>");

	DynamicDetour dSpawnTankVec =
	DynamicDetour.FromConf(gamedata, "ZombieManager::SpawnTank<Vector>");

	DynamicDetour dSpawnWitchNav =
	DynamicDetour.FromConf(gamedata, "ZombieManager::SpawnWitch<TerrorNavArea>");

	DynamicDetour dSpawnWitchVec =
	DynamicDetour.FromConf(gamedata, "ZombieManager::SpawnWitch<Vector>");

	DynamicDetour dSpawnWitchBride =
	DynamicDetour.FromConf(gamedata, "ZombieManager::SpawnWitchBride");

	delete gamedata;

	dSpawnCommonZombie.Enable(Hook_Pre, SpawnCommonZombiePre);
	dSpawnCommonZombie.Enable(Hook_Post, SpawnCommonZombiePost);

	dSpawnSpecialNav.Enable(Hook_Post, SpawnSpecialNavPre);
	dSpawnSpecialVec.Enable(Hook_Pre, SpawnSpecialVecPre);
	dSpawnSpecialVec.Enable(Hook_Post, SpawnSpecialVecPost);

	dSpawnTankNav.Enable(Hook_Post, SpawnTankNavPre);
	dSpawnTankVec.Enable(Hook_Pre, SpawnTankVecPre);
	dSpawnTankVec.Enable(Hook_Post, SpawnTankVecPost);

	dSpawnWitchNav.Enable(Hook_Post, SpawnWitchNavPre);
	dSpawnWitchVec.Enable(Hook_Pre, SpawnWitchVecPre);
	dSpawnWitchVec.Enable(Hook_Post, SpawnWitchVecPost);

	dSpawnWitchBride.Enable(Hook_Pre, SpawnWitchBrideVecPre);
	dSpawnWitchBride.Enable(Hook_Post, SpawnWitchBrideVecPost);

	HookEvent("player_death", player_death, EventHookMode_Pre);

#if defined datamaps_included
	if(g_bDatamaps) {
		CustomEntityFactory factory = EntityFactoryDictionary.register_based_name("infected_server", "infected");
		CustomSendtable table = CustomSendtable.from_factory(factory, "NextBotCombatCharacter");
		table.set_name("DT_InfectedServer");
		table.set_network_name("InfectedServer");
	}
#endif

	LoadKVFile();

	RegAdminCmd("sm_mi_reload", sm_mi_reload, ADMFLAG_ROOT);
}

void UnloadKVFile()
{
	char place[MI_MAX_PLACE_LEN];

	for(int n = 0; n < 2; ++n) {
		for(int j = 0; j < infected_directive_count; ++j) {
			StringMapSnapshot snapshot = infectedMap[n][j].Snapshot();
			int len = snapshot.Length;
			for(int i = 0; i < len; ++i) {
				snapshot.GetKey(i, place, sizeof(place));
				if(infectedMap[n][j].GetArray(place, tmparrclasses, sizeof(tmparrclasses))) {
					for(int k = 0; k < infected_class_count; ++k) {
						ArrayList tmparr = tmparrclasses[k];
						if(tmparr == null) {
							continue;
						}

						int arrlen = tmparr.Length;
						if(arrlen > 0) {
							ArrayList weights = tmparr.Get(arrlen-3);
							ArrayList accum = tmparr.Get(arrlen-2);

							delete weights;
							delete accum;
						}

						delete tmparr;
					}
				}
			}
			delete snapshot;
			delete infectedMap[n][j];
		}
	}

	delete arInfectedInfos;
	delete kvInfected;
}

Action sm_mi_reload(int client, int args)
{
	UnloadKVFile();
	LoadKVFile();

	return Plugin_Handled;
}

void SetupClassesMap(StringMap map, infected_class_flags classflags, int idx, const char[] place)
{
	if(!map.GetArray(place, tmparrclasses, sizeof(tmparrclasses))) {
		for(int i = 0; i < infected_class_count; ++i) {
			tmparrclasses[i] = new ArrayList();
		}
		map.SetArray(place, tmparrclasses, sizeof(tmparrclasses));
	}

	if(classflags & class_flags_common)
	{ tmparrclasses[class_common].Push(idx);}
	if(classflags & class_flags_tank)
	{ tmparrclasses[class_tank].Push(idx); }
	if(classflags & class_flags_smoker)
	{ tmparrclasses[class_smoker].Push(idx); }
	if(classflags & class_flags_charger)
	{ tmparrclasses[class_charger].Push(idx); }
	if(classflags & class_flags_boomer)
	{ tmparrclasses[class_boomer].Push(idx); }
	if(classflags & class_flags_hunter)
	{ tmparrclasses[class_hunter].Push(idx); }
	if(classflags & class_flags_jockey)
	{ tmparrclasses[class_jockey].Push(idx); }
	if(classflags & class_flags_spitter)
	{ tmparrclasses[class_spitter].Push(idx); }
	if(classflags & class_flags_witch)
	{ tmparrclasses[class_witch].Push(idx); }
	if(classflags & class_flags_witch_bride)
	{ tmparrclasses[class_witch_bride].Push(idx); }
}

char tmpdireflagstrs[3][MI_MAX_DIRECTIVE_LEN];
infected_directive_flags DirectiveStrToFlags(const char[] str)
{
	int num = ExplodeString(str, "|", tmpdireflagstrs, 3, MI_MAX_DIRECTIVE_LEN);

	infected_directive_flags flags = directive_flags_invalid;

	for(int i = 0; i < num; ++i) {
		if(StrEqual(tmpdireflagstrs[i], "wanderer")) {
			flags |= directive_flags_wanderer;
		} else if(StrEqual(tmpdireflagstrs[i], "ambient")) {
			flags |= directive_flags_ambient;
		} else if(StrEqual(tmpdireflagstrs[i], "attack")) {
			flags |= directive_flags_attack;
		} else if(StrEqual(tmpdireflagstrs[i], "any_background")) {
			flags |= directive_flags_wanderer;
			flags |= directive_flags_ambient;
		} else if(StrEqual(tmpdireflagstrs[i], "any")) {
			flags |= directive_flags_wanderer;
			flags |= directive_flags_ambient;
			flags |= directive_flags_attack;
		}
	}

	return flags;
}

char tmpclassflagstrs[infected_class_count][MI_MAX_CLASS_LEN];
infected_class_flags ClassStrToFlags(const char[] str)
{
	int num = ExplodeString(str, "|", tmpclassflagstrs, infected_class_count, MI_MAX_CLASS_LEN);

	infected_class_flags flags = class_flags_invalid;

	for(int i = 0; i < num; ++i) {
		if(StrEqual(tmpclassflagstrs[i], "common")) {
			flags |= class_flags_common;
		} else if(StrEqual(tmpclassflagstrs[i], "tank")) {
			flags |= class_flags_tank;
		} else if(StrEqual(tmpclassflagstrs[i], "smoker")) {
			flags |= class_flags_smoker;
		} else if(StrEqual(tmpclassflagstrs[i], "charger")) {
			flags |= class_flags_charger;
		} else if(StrEqual(tmpclassflagstrs[i], "boomer")) {
			flags |= class_flags_boomer;
		} else if(StrEqual(tmpclassflagstrs[i], "hunter")) {
			flags |= class_flags_hunter;
		} else if(StrEqual(tmpclassflagstrs[i], "jockey")) {
			flags |= class_flags_jockey;
		} else if(StrEqual(tmpclassflagstrs[i], "spitter")) {
			flags |= class_flags_spitter;
		} else if(StrEqual(tmpclassflagstrs[i], "witch")) {
			flags |= class_flags_witch;
		} else if(StrEqual(tmpclassflagstrs[i], "witch_bride")) {
			flags |= class_flags_witch_bride;
		} else if(StrEqual(tmpclassflagstrs[i], "any_boss")) {
			flags |= class_flags_tank;
			flags |= class_flags_witch;
			flags |= class_flags_witch_bride;
		} else if(StrEqual(tmpclassflagstrs[i], "any_special")) {
			flags |= class_flags_smoker;
			flags |= class_flags_charger;
			flags |= class_flags_boomer;
			flags |= class_flags_hunter;
			flags |= class_flags_jockey;
			flags |= class_flags_spitter;
		} else if(StrEqual(tmpclassflagstrs[i], "any")) {
			flags |= class_flags_common;
			flags |= class_flags_smoker;
			flags |= class_flags_charger;
			flags |= class_flags_boomer;
			flags |= class_flags_hunter;
			flags |= class_flags_jockey;
			flags |= class_flags_spitter;
			flags |= class_flags_tank;
			flags |= class_flags_witch;
			flags |= class_flags_witch_bride;
		}
	}

	return flags;
}

public void OnAllPluginsLoaded()
{
	if(arInfectedInfos != null) {
		ArrayList infolist = new ArrayList();

		for(int i = 0; i < arInfectedInfos.Length; ++i) {
			infolist.Push(i);
		}

		bool done = false;

		char file[MI_MAX_PLUGIN_LEN];
		InfectedInfo info;

		Handle iter = GetPluginIterator();
		while(MorePlugins(iter)) {
			Handle pl = ReadPlugin(iter);

			GetPluginFilename(pl, file, sizeof(file));

			for(int i = 0; i < infolist.Length; ++i) {
				int idx = infolist.Get(i);

				arInfectedInfos.GetArray(idx, info, sizeof(info));

				if(StrEqual(info.plname, file)) {
					infolist.Erase(i);
					--i;

					info.hPlugin = pl;

					arInfectedInfos.SetArray(idx, info, sizeof(info));

					if(infolist.Length == 0) {
						done = true;
						break;
					}
				}
			}

			if(done) {
				break;
			}
		}
		delete iter;

		if(!done) {
			for(int i = 0; i < infolist.Length; ++i) {
				int idx = infolist.Get(i);

				arInfectedInfos.GetArray(idx, info, sizeof(info));

				PrintToServer("[MOREINFECTED] %s: plugin not found", info.name);
			}
		}
	}
}

bool CheckPluginHandle(Handle hPlugin)
{
	return !(hPlugin == null || !IsValidHandle(hPlugin));
}

bool IsPluginLoaded(InfectedInfo info, const char[] func)
{
	if(CheckPluginHandle(info.hPlugin)) {
		info.hPlugin = FindPluginByFile(info.plname);
		if(CheckPluginHandle(info.hPlugin)) {
			PrintToServer("[MOREINFECTED] %s: %s failed: plugin not found", func, info.name);
			return false;
		}
	}

	if(GetPluginStatus(info.hPlugin) != Plugin_Running) {
		PrintToServer("[MOREINFECTED] %s: %s failed: plugin not running", func, info.name);
		return false;
	}

	return true;
}

void MakeFuncName(InfectedInfo info, char[] funcname, int length, func_name func)
{
	if(info.alias[0] != '\0') {
		strcopy(funcname, length, info.alias);
	} else {
		strcopy(funcname, length, info.name);
	}

	switch(func) {
		case func_precache:
		{ StrCat(funcname, length, "_precache"); }
		case func_common:
		{ StrCat(funcname, length, "_spawn_common"); }
		case func_special:
		{ StrCat(funcname, length, "_spawn_special"); }
	}
}

Function GetFunc(InfectedInfo info, func_name name)
{
	char funcname[MI_MAX_FUNC_LEN];
	MakeFuncName(info, funcname, sizeof(funcname), name);

	return GetFunctionByName(info.hPlugin, funcname);
}

public void OnMapStart()
{
	if(arInfectedInfos != null) {
		char funcname[MI_MAX_FUNC_LEN];
		InfectedInfo info;
		moreinfected_data data;

		for(int i = 0; i < arInfectedInfos.Length; ++i) {
			arInfectedInfos.GetArray(i, info, sizeof(info));

			if(!IsPluginLoaded(info, "precache")) {
				continue;
			}

			MakeFuncName(info, funcname, sizeof(funcname), func_precache);

			Function precache = GetFunctionByName(info.hPlugin, funcname);
			if(precache == INVALID_FUNCTION) {
				PrintToServer("[MOREINFECTED] %s: precache failed: function not provided", info.name);
				continue;
			}

			Call_StartFunction(info.hPlugin, precache);
			strcopy(data.name, MI_MAX_NAME_LEN, info.name);
			data.class_flags = info.class_flags;
			data.directive_flags = info.directive_flags;
			data.data = info.data;
			Call_PushArray(data, sizeof(data));
			Call_Finish();
		}
	}
}

void GetPlaceFromNav(Address area, float pos[3], char[] place, int length)
{
#if defined nextbot_included
	if(g_bNextBot) {
		if(area == Address_Null) {
			int id = CNavMesh.GetPlace(pos);
			if(id != UNDEFINED_PLACE) {
				CNavMesh.PlaceToName(id, place, length);
				return;
			}
		} else {
			int id = view_as<CNavArea>(area).Place;
			if(id != UNDEFINED_PLACE) {
				CNavMesh.PlaceToName(id, place, length);
				return;
			}
		}
	}
#endif

	strcopy(place, length, "default");
}

bool GetInfectedByChance(InfectedInfo info, ArrayList arr, const char[] func)
{
	int len = arr.Length;
	ArrayList weights = arr.Get(len-3);
	ArrayList accum = arr.Get(len-2);

	int idx = HopscotchRandom(weights, accum);

	arInfectedInfos.GetArray(idx, info, sizeof(info));

	if(!IsPluginLoaded(info, func)) {
		return false;
	}

	return true;
}

MRESReturn SpawnCommonHelper(DHookReturn hReturn, DHookParam hParams, bool post)
{
	if(arInfectedInfos == null) {
		return MRES_Ignored;
	}

	InfectedSpawnDirective directive = hParams.Get(3);

	StringMap placemap = null;
	switch(directive) {
		case SpawnDirective_Wanderer:
		{ placemap = infectedMap[post ? 0 : 1][directive_wanderer]; }
		case SpawnDirective_Ambient:
		{ placemap = infectedMap[post ? 0 : 1][directive_ambient]; }
		case SpawnDirective_Attack:
		{ placemap = infectedMap[post ? 0 : 1][directive_attack]; }
	}

	Address area = hParams.Get(1);

	float pos[3];
	hParams.GetVector(2, pos);

	char place[MI_MAX_PLACE_LEN];
	GetPlaceFromNav(area, pos, place, sizeof(place));

	if(!placemap.GetArray(place, tmparrclasses, sizeof(tmparrclasses))) {
		return MRES_Ignored;
	}

	ArrayList arr = tmparrclasses[class_common];
	if(arr == null || arr.Length == 0) {
		return MRES_Ignored;
	}

	InfectedInfo info;
	if(!GetInfectedByChance(info, arr, "spawn")) {
		return MRES_Ignored;
	}

	Function spawn = GetFunc(info, func_common);
	if(spawn == INVALID_FUNCTION) {
		PrintToServer("[MOREINFECTED] %s: spawn failed: function not provided", info.name);
		return MRES_Ignored;
	}

	int entity = -1;

	if(post) {
		entity = hReturn.Value;
		if(entity == -1) {
			return MRES_Ignored;
		}
	}

	Call_StartFunction(info.hPlugin, spawn);
	Call_PushCell(entity);
	Call_PushCell(area);
	Call_PushArray(pos, sizeof(pos));
	Call_PushCell(directive);
	moreinfected_data data;
	strcopy(data.name, MI_MAX_NAME_LEN, info.name);
	data.class_flags = info.class_flags;
	data.directive_flags = info.directive_flags;
	data.data = info.data;
	Call_PushArray(data, sizeof(data));
	Call_Finish(entity);

	if(post) {
		hReturn.Value = entity;
		return MRES_Override;
	} else {
		if(entity != -1) {
			hReturn.Value = entity;
			return MRES_Supercede;
		} else {
			return MRES_Ignored;
		}
	}
}

MRESReturn SpawnCommonZombiePre(Address pThis, DHookReturn hReturn, DHookParam hParams)
{ return SpawnCommonHelper(hReturn, hParams, false); }
MRESReturn SpawnCommonZombiePost(Address pThis, DHookReturn hReturn, DHookParam hParams)
{ return SpawnCommonHelper(hReturn, hParams, true); }

Address g_LastArea = Address_Null;

MRESReturn SpawnSpecialNavPre(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	g_LastArea = hParams.Get(2);
	return MRES_Ignored;
}

MRESReturn SpawnTankNavPre(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	g_LastArea = hParams.Get(1);
	return MRES_Ignored;
}

MRESReturn SpawnWitchNavPre(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	g_LastArea = hParams.Get(1);
	return MRES_Ignored;
}

MRESReturn SpawnSpecialHelper(DHookReturn hReturn, float pos[3], float ang[3], ZombieClassType type, bool post, bool bride = false)
{
	if(arInfectedInfos == null) {
		g_LastArea = Address_Null;
		return MRES_Ignored;
	}

	StringMap placemap = infectedMap[post ? 0 : 1][directive_special];

	char place[MI_MAX_PLACE_LEN];
	GetPlaceFromNav(g_LastArea, pos, place, sizeof(place));

	if(!placemap.GetArray(place, tmparrclasses, sizeof(tmparrclasses))) {
		g_LastArea = Address_Null;
		return MRES_Ignored;
	}

	ArrayList arr = null;

	switch(type) {
		case ZombieClass_Common:
		{ arr = tmparrclasses[class_common]; }
		case ZombieClass_Smoker:
		{ arr = tmparrclasses[class_smoker]; }
		case ZombieClass_Boomer:
		{ arr = tmparrclasses[class_boomer]; }
		case ZombieClass_Hunter:
		{ arr = tmparrclasses[class_hunter]; }
		case ZombieClass_Spitter:
		{ arr = tmparrclasses[class_spitter]; }
		case ZombieClass_Jockey:
		{ arr = tmparrclasses[class_jockey]; }
		case ZombieClass_Charger:
		{ arr = tmparrclasses[class_charger]; }
		case ZombieClass_Witch:
		{ arr = tmparrclasses[bride ? class_witch_bride : class_witch]; }
		case ZombieClass_Tank:
		{ arr = tmparrclasses[class_tank]; }
	}

	if(arr == null || arr.Length == 0) {
		g_LastArea = Address_Null;
		return MRES_Ignored;
	}

	InfectedInfo info;
	if(!GetInfectedByChance(info, arr, "spawn")) {
		g_LastArea = Address_Null;
		return MRES_Ignored;
	}

	Function spawn = GetFunc(info, func_special);
	if(spawn == INVALID_FUNCTION) {
		PrintToServer("[MOREINFECTED] %s: spawn failed: function not provided", info.name);
		g_LastArea = Address_Null;
		return MRES_Ignored;
	}

	int entity = -1;

	if(post) {
		entity = hReturn.Value;
		if(entity == -1) {
			g_LastArea = Address_Null;
			return MRES_Ignored;
		}
	}

	Call_StartFunction(info.hPlugin, spawn);
	Call_PushCell(entity);
	Call_PushCell(g_LastArea);
	Call_PushArray(pos, sizeof(pos));
	Call_PushArray(ang, sizeof(ang));
	Call_PushCell(type);
	moreinfected_data data;
	strcopy(data.name, MI_MAX_NAME_LEN, info.name);
	data.class_flags = info.class_flags;
	data.directive_flags = info.directive_flags;
	data.data = info.data;
	Call_PushArray(data, sizeof(data));
	Call_Finish(entity);

	g_LastArea = Address_Null;
	if(post) {
		hReturn.Value = entity;
		return MRES_Override;
	} else {
		if(entity != -1) {
			hReturn.Value = entity;
			return MRES_Supercede;
		} else {
			return MRES_Ignored;
		}
	}
}

MRESReturn CallSpawnSpecialBossVec(DHookReturn hReturn, DHookParam hParams, ZombieClassType type, bool post, bool bride = false)
{
	float pos[3];
	hParams.GetVector(1, pos);

	float ang[3];
	hParams.GetVector(2, ang);

	return SpawnSpecialHelper(hReturn, pos, ang, type, post, bride);
}

MRESReturn CallSpawnSpecialVec(DHookReturn hReturn, DHookParam hParams, bool post, bool bride = false)
{
	ZombieClassType type = hParams.Get(1);

	float pos[3];
	hParams.GetVector(2, pos);

	float ang[3];
	hParams.GetVector(3, ang);

	return SpawnSpecialHelper(hReturn, pos, ang, type, post, bride);
}

MRESReturn SpawnSpecialVecPre(Address pThis, DHookReturn hReturn, DHookParam hParams)
{ return CallSpawnSpecialVec(hReturn, hParams, false); }
MRESReturn SpawnSpecialVecPost(Address pThis, DHookReturn hReturn, DHookParam hParams)
{ return CallSpawnSpecialVec(hReturn, hParams, true); }

MRESReturn SpawnWitchVecPre(Address pThis, DHookReturn hReturn, DHookParam hParams)
{ return CallSpawnSpecialBossVec(hReturn, hParams, ZombieClass_Witch, false); }
MRESReturn SpawnWitchVecPost(Address pThis, DHookReturn hReturn, DHookParam hParams)
{ return CallSpawnSpecialBossVec(hReturn, hParams, ZombieClass_Witch, true); }

MRESReturn SpawnWitchBrideVecPre(Address pThis, DHookReturn hReturn, DHookParam hParams)
{ return CallSpawnSpecialBossVec(hReturn, hParams, ZombieClass_Witch, false, true); }
MRESReturn SpawnWitchBrideVecPost(Address pThis, DHookReturn hReturn, DHookParam hParams)
{ return CallSpawnSpecialBossVec(hReturn, hParams, ZombieClass_Witch, true, true); }

MRESReturn SpawnTankVecPre(Address pThis, DHookReturn hReturn, DHookParam hParams)
{ return CallSpawnSpecialBossVec(hReturn, hParams, ZombieClass_Tank, false); }
MRESReturn SpawnTankVecPost(Address pThis, DHookReturn hReturn, DHookParam hParams)
{ return CallSpawnSpecialBossVec(hReturn, hParams, ZombieClass_Tank, true); }

static char tmpmodelbuff[MI_MAX_MODEL_LEN];
HopscotchPair VariationsHopscotch;
ArrayList VariantionsIDs = null;

public void infected_precache(moreinfected_data data)
{
	KeyValues kv = data.data;

	if(kv.JumpToKey("model")) {
		kv.GetString(NULL_STRING, tmpmodelbuff, sizeof(tmpmodelbuff));
		PrecacheModel(tmpmodelbuff);
		kv.GoBack();
	}

	if(kv.JumpToKey("variations")) {
		if(kv.GotoFirstSubKey()) {
			VariationsHopscotch.weights = new ArrayList();
			VariantionsIDs = new ArrayList();

			char name[MI_MAX_NAME_LEN];

			do {
				kv.GetString("model", tmpmodelbuff, sizeof(tmpmodelbuff));
				if(tmpmodelbuff[0] != '\0') {
					PrecacheModel(tmpmodelbuff);
				}

				float weight = kv.GetFloat("weight", 0.0);
				if(weight == 0.0) {
					kv.GetSectionName(name, sizeof(name));
					PrintToServer("[MOREINFECTED] %s: variation %s: ignoring due to weight being 0", data.name, name);
					continue;
				}

				int id = 0;
				if(kv.GetSectionSymbol(id)) {
					VariationsHopscotch.weights.Push(weight);
					VariantionsIDs.Push(id);
				}
			} while(kv.GotoNextKey());

			PrepareHopscotchRandom(VariationsHopscotch.weights, VariationsHopscotch.accum);

			kv.GoBack();
		}
		kv.GoBack();
	}
}

#define EF_BONEMERGE 0x001
#define EF_BONEMERGE_FASTCULL 0x080
#define EF_PARENT_ANIMATES 0x200

#define	LIFE_ALIVE 0
#define LIFE_DYING 1
#define LIFE_DEAD 2
#define LIFE_RESPAWNABLE 3
#define LIFE_DISCARDBODY 4

Action player_death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client == 0) {
		return Plugin_Continue;
	}

	int m_iHammerID = GetEntProp(client, Prop_Data, "m_iHammerID");
	if(m_iHammerID == 0) {
		return Plugin_Continue;
	}

	int effect = EntRefToEntIndex(m_iHammerID);
	if(effect != -1) {
		InfectedDied(client);
	}

	return Plugin_Continue;
}

public void OnEntityDestroyed(int entity)
{
	if(entity < MaxClients) {
		return;
	}

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));

	if(StrEqual(classname, "infected") ||
		StrEqual(classname, "infected_server"))
	{
		int m_iHammerID = GetEntProp(entity, Prop_Data, "m_iHammerID");
		if(m_iHammerID == 0) {
			return;
		}

		int effect = EntRefToEntIndex(m_iHammerID);
		if(effect != -1) {
			InfectedDied(entity);
		}
	}
}

void InfectedDied(int entity)
{
	SetEntityRenderMode(entity, RENDER_NORMAL);
	SetEntityRenderColor(entity, 255, 255, 255, 255);

	int m_iHammerID = GetEntProp(entity, Prop_Data, "m_iHammerID");
	if(m_iHammerID == 0) {
		return;
	}

	char model[MI_MAX_MODEL_LEN];

	int effect = EntRefToEntIndex(m_iHammerID);
	if(effect != -1) {
		int effects = GetEntProp(effect, Prop_Send, "m_fEffects");
		effects &= ~EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES|EF_BONEMERGE;
		SetEntProp(effect, Prop_Send, "m_fEffects", effects);

		AcceptEntityInput(effect, "ClearParent");
		SetEntPropEnt(effect, Prop_Data, "m_hOwnerEntity", -1);

		float pos[3];
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
		float ang[3];
		GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", ang);
		float vel[3];
		GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vel);

		TeleportEntity(effect, pos, ang, vel);

	/*#if defined animhelpers_included
		if(g_bAnimhelpers) {
			BaseAnimating anim = BaseAnimating(effect);
			int seq = anim.SelectWeightedSequence(ACT_DIERAGDOLL);
			anim.ResetSequence(seq);
		}
	#endif*/

		int flags = GetEntityFlags(effect);
		flags |= FL_TRANSRAGDOLL;
		SetEntityFlags(effect, flags);

		SetEntityRenderFx(effect, RENDERFX_RAGDOLL);

		GetEntPropString(effect, Prop_Data, "m_ModelName", model, sizeof(model));

		RemoveEntity(effect);
	}

	SetEntProp(entity, Prop_Data, "m_iHammerID", 0);

	if(model[0] != '\0') {
		SetEntityModel(entity, model);
	}
}

void InfectedThink(int entity)
{
	int state = GetEntProp(entity, Prop_Data, "m_lifeState");
	if(state == LIFE_ALIVE) {
		return;
	}

	/*bool deathanim = true;

#if defined animhelpers_included
	BaseAnimating anim = BaseAnimating(entity);

	if(g_bAnimhelpers) {
		int seq = GetEntProp(entity, Prop_Send, "m_nSequence");

		Activity act = anim.GetSequenceActivity(seq);
		if(!(act >= ACT_TERROR_DIE_FROM_STAND &&
			act <= ACT_TERROR_DIE_RIGHTWARD_FROM_SHOTGUN)) {
			deathanim = false;
		}
	}
#endif

	if(!deathanim) {
	#if defined animhelpers_included
		if(g_bAnimhelpers) {
			int seq = anim.SelectWeightedSequence(ACT_TERROR_DIE_FROM_STAND);
			anim.ResetSequence(seq);
		}
	#endif
	}*/

	if(!GetEntProp(entity, Prop_Data, "m_bSequenceFinished")) {
		return;
	}

	SDKUnhook(entity, SDKHook_Think, InfectedThink);

	InfectedDied(entity);
}

enum struct kvblock_info
{
	bool bonemerge;
	bool server;
	int health;
	int gender;
}

enum
{
	gender_neutral,
	gender_male,
	gender_female,
	gender_bill,
	gender_zoey,
	gender_francis,
	gender_louis,
	gender_nick,
	gender_rochelle,
	gender_coach,
	gender_ellis,
	gender_ceda,
	gender_mudman,
	gender_workman,
	gender_fallen,
	gender_riotcop,
	gender_clown,
	gender_jimmygibbs,
	gender_hospitalpatient,
};

int GenderStrToNum(const char[] genderstr)
{
	if(StrEqual(genderstr, "male"))
	{ return gender_male; }
	else if(StrEqual(genderstr, "female"))
	{ return gender_female; }
	else if(StrEqual(genderstr, "bill"))
	{ return gender_bill; }
	else if(StrEqual(genderstr, "zoey"))
	{ return gender_zoey; }
	else if(StrEqual(genderstr, "francis"))
	{ return gender_francis; }
	else if(StrEqual(genderstr, "louis"))
	{ return gender_louis; }
	else if(StrEqual(genderstr, "nick"))
	{ return gender_nick; }
	else if(StrEqual(genderstr, "rochelle"))
	{ return gender_rochelle; }
	else if(StrEqual(genderstr, "coach"))
	{ return gender_coach; }
	else if(StrEqual(genderstr, "ellis"))
	{ return gender_ellis; }
	else if(StrEqual(genderstr, "ceda"))
	{ return gender_ceda; }
	else if(StrEqual(genderstr, "mudman"))
	{ return gender_mudman; }
	else if(StrEqual(genderstr, "workman"))
	{ return gender_workman; }
	else if(StrEqual(genderstr, "fallen"))
	{ return gender_fallen; }
	else if(StrEqual(genderstr, "riotcop"))
	{ return gender_riotcop; }
	else if(StrEqual(genderstr, "clown"))
	{ return gender_clown; }
	else if(StrEqual(genderstr, "jimmygibbs"))
	{ return gender_jimmygibbs; }
	else if(StrEqual(genderstr, "hospitalpatient"))
	{ return gender_hospitalpatient; }
	else
	{ return -1; }
}

static char tmpgenderstr[MI_MAX_GENDER_LEN];
void ParseKVBlock(KeyValues kv, kvblock_info info)
{
	kv.GetString("model", tmpmodelbuff, sizeof(tmpmodelbuff), tmpmodelbuff);
	info.bonemerge = view_as<bool>(kv.GetNum("bonemerge", info.bonemerge));
	info.server = view_as<bool>(kv.GetNum("server", info.server));
	info.health = kv.GetNum("health", info.health);
	info.gender = kv.GetNum("gender", info.gender);

	kv.GetString("gender", tmpgenderstr, sizeof(tmpgenderstr));
	if(tmpgenderstr[0] != '\0') {
		int gendernum = GenderStrToNum(tmpgenderstr);
		if(gendernum == -1) {
			ThrowError("invalid gender str: %s", tmpgenderstr);
		} else {
			info.gender = gendernum;
		}
	}
}

int infected_spawn_shared(int entity, KeyValues kv, float pos[3], bool common)
{
	tmpmodelbuff[0] = '\0';
	kvblock_info info;
	info.bonemerge = false;
	info.server = false;
	info.health = -1;
	info.gender = -1;

	ParseKVBlock(kv, info);

	if(kv.JumpToKey("variations")) {
		int idx = HopscotchRandom(VariationsHopscotch.weights, VariationsHopscotch.accum);
		int id = VariantionsIDs.Get(idx);

		if(kv.JumpToKeySymbol(id)) {
			ParseKVBlock(kv, info);
			kv.GoBack();
		}

		kv.GoBack();
	}

#if defined datamaps_included
	if(common && g_bDatamaps && info.server) {
		if(entity != -1) {
			RemoveEntity(entity);
		}
		entity = CreateEntityByName("infected_server");
		DispatchSpawn(entity);
		TeleportEntity(entity, pos);
	}
#endif

	if(entity == -1) {
		entity = CreateEntityByName("infected");
		DispatchSpawn(entity);
		TeleportEntity(entity, pos);
	}

	if(info.health != -1) {
		SetEntProp(entity, Prop_Data, "m_iHealth", info.health);
		SetEntProp(entity, Prop_Data, "m_iMaxHealth", info.health);
	}

	if(info.gender != -1) {
		SetEntProp(entity, Prop_Send, "m_Gender", info.gender);
	}

	if(tmpmodelbuff[0] != '\0') {
		if(!info.bonemerge) {
			SetEntityModel(entity, tmpmodelbuff);
		} else {
			int prop = CreateEntityByName("commentary_dummy");
			DispatchKeyValue(prop, "model", tmpmodelbuff);
			DispatchSpawn(prop);

			TeleportEntity(prop, pos);

			SetVariantString("!activator");
			AcceptEntityInput(prop, "SetParent", entity);

			int effects = GetEntProp(prop, Prop_Send, "m_fEffects");
			effects |= EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES|EF_BONEMERGE;
			SetEntProp(prop, Prop_Send, "m_fEffects", effects);

			SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
			SetEntityRenderColor(entity, 255, 255, 255, 0);

			SetEntPropEnt(prop, Prop_Data, "m_hOwnerEntity", entity);
			SetEntProp(entity, Prop_Data, "m_iHammerID", EntIndexToEntRef(prop));
		}
	}

	if(info.bonemerge) {
		if(entity > MaxClients) {
			SDKHook(entity, SDKHook_Think, InfectedThink);
		}
	}

	return entity;
}

public int infected_spawn_common(int entity, Address area, float pos[3], InfectedSpawnDirective directive, moreinfected_data data)
{
	KeyValues kv = data.data;
	return infected_spawn_shared(entity, kv, pos, true);
}

public int infected_spawn_special(int entity, Address area, float pos[3], float ang[3], ZombieClassType type, moreinfected_data data)
{
	KeyValues kv = data.data;
	return infected_spawn_shared(entity, kv, pos, false);
}
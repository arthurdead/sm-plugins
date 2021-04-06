#include <sourcemod>
#include <dhooks>
#include <keyvalues>
#include <moreinfected>

KeyValues kvInfected = null;

enum struct InfectedInfo
{
	Handle hPlugin;
	char name[64];
	char alias[64];
	char plname[64];
	char data[MAX_DATA_LENGTH];
	float chance;
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
}

ArrayList arInfectedInfos = null;
ArrayList arClasses[infected_class_count] = {null, ...};

bool g_bLateLoaded = false;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int length)
{
	g_bLateLoaded = late;
	RegPluginLibrary("moreinfected");
	return APLRes_Success;
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

	dSpawnCommonZombie.Enable(Hook_Post, SpawnCommonZombiePost);

	dSpawnSpecialNav.Enable(Hook_Post, SpawnSpecialNavPre);
	dSpawnSpecialVec.Enable(Hook_Post, SpawnSpecialVecPost);

	dSpawnTankNav.Enable(Hook_Post, SpawnTankNavPre);
	dSpawnTankVec.Enable(Hook_Post, SpawnTankVecPost);

	dSpawnWitchNav.Enable(Hook_Post, SpawnWitchNavPre);
	dSpawnWitchVec.Enable(Hook_Post, SpawnWitchVecPost);

	dSpawnWitchBride.Enable(Hook_Post, SpawnWitchBrideVecPost);

	char infectedfile[64];
	BuildPath(Path_SM, infectedfile, sizeof(infectedfile), "data/moreinfected.txt");

	if(FileExists(infectedfile, true)) {
		kvInfected = new KeyValues("moreinfected");
		kvInfected.ImportFromFile(infectedfile);

		if(kvInfected.GotoFirstSubKey()) {
			arInfectedInfos = new ArrayList(sizeof(InfectedInfo));

			for(int i = 0; i < infected_class_count; ++i) {
				arClasses[i] = new ArrayList();
			}

			do {
				char name[64];
				kvInfected.GetSectionName(name, sizeof(name));

				float chance = kvInfected.GetFloat("chance");
				if(chance == 0.0) {
					PrintToServer("[MOREINFECTED] %s: ignoring due to chance being 0", name);
					continue;
				}

				char classstr[64];
				kvInfected.GetString("class_flags", classstr, sizeof(classstr));
				infected_class_flags classflags = ClassStrToFlags(classstr);
				if(classflags == class_flags_invalid) {
					PrintToServer("[MOREINFECTED] %s: invalid class flags %s", name, classstr);
					continue;
				}

				if(classflags & class_flags_common) {
					arClasses[class_common].Push(arInfectedInfos.Length);
				}
				if(classflags & class_flags_tank) {
					arClasses[class_tank].Push(arInfectedInfos.Length);
				}
				if(classflags & class_flags_smoker) {
					arClasses[class_smoker].Push(arInfectedInfos.Length);
				}
				if(classflags & class_flags_charger) {
					arClasses[class_charger].Push(arInfectedInfos.Length);
				}
				if(classflags & class_flags_boomer) {
					arClasses[class_boomer].Push(arInfectedInfos.Length);
				}
				if(classflags & class_flags_hunter) {
					arClasses[class_hunter].Push(arInfectedInfos.Length);
				}
				if(classflags & class_flags_jockey) {
					arClasses[class_jockey].Push(arInfectedInfos.Length);
				}
				if(classflags & class_flags_spitter) {
					arClasses[class_spitter].Push(arInfectedInfos.Length);
				}
				if(classflags & class_flags_witch) {
					arClasses[class_witch].Push(arInfectedInfos.Length);
				}
				if(classflags & class_flags_witch_bride) {
					arClasses[class_witch_bride].Push(arInfectedInfos.Length);
				}

				InfectedInfo info;
				info.chance = chance * 0.01;
				info.class_flags = classflags;
				strcopy(info.name, sizeof(info.name), name);

				kvInfected.GetString("plugin", info.plname, sizeof(info.plname));
				kvInfected.GetString("alias", info.alias, sizeof(info.alias));
				kvInfected.GetString("data", info.data, sizeof(info.data));

				arInfectedInfos.PushArray(info, sizeof(InfectedInfo));
			} while(kvInfected.GotoNextKey());
			kvInfected.GoBack();
		}
		kvInfected.GoBack();
	}
}

infected_class_flags ClassStrToFlags(const char[] str)
{
	char flagstrs[infected_class_count][64];
	int num = ExplodeString(str, "|", flagstrs, infected_class_count, 64);

	infected_class_flags flags = class_flags_invalid;

	for(int i = 0; i < num; ++i) {
		if(StrEqual(flagstrs[i], "common")) {
			flags |= class_flags_common;
		} else if(StrEqual(flagstrs[i], "tank")) {
			flags |= class_flags_tank;
		} else if(StrEqual(flagstrs[i], "smoker")) {
			flags |= class_flags_smoker;
		} else if(StrEqual(flagstrs[i], "charger")) {
			flags |= class_flags_charger;
		} else if(StrEqual(flagstrs[i], "boomer")) {
			flags |= class_flags_boomer;
		} else if(StrEqual(flagstrs[i], "hunter")) {
			flags |= class_flags_hunter;
		} else if(StrEqual(flagstrs[i], "jockey")) {
			flags |= class_flags_jockey;
		} else if(StrEqual(flagstrs[i], "spitter")) {
			flags |= class_flags_spitter;
		} else if(StrEqual(flagstrs[i], "witch")) {
			flags |= class_flags_witch;
		} else if(StrEqual(flagstrs[i], "witch_bride")) {
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

		Handle iter = GetPluginIterator();
		while(MorePlugins(iter)) {
			Handle pl = ReadPlugin(iter);

			char file[64];
			GetPluginFilename(pl, file, sizeof(file));

			for(int i = 0; i < infolist.Length; ++i) {
				int idx = infolist.Get(i);

				InfectedInfo info;
				arInfectedInfos.GetArray(idx, info, sizeof(InfectedInfo));

				if(StrEqual(info.plname, file)) {
					infolist.Erase(i);
					--i;

					info.hPlugin = pl;

					arInfectedInfos.SetArray(idx, info, sizeof(InfectedInfo));

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

				InfectedInfo info;
				arInfectedInfos.GetArray(idx, info, sizeof(InfectedInfo));

				PrintToServer("[MOREINFECTED] %s: plugin not found", info.name);
			}
		}
	}
}

public void OnMapStart()
{
	if(arInfectedInfos != null) {
		for(int i = 0; i < arInfectedInfos.Length; ++i) {
			InfectedInfo info;
			arInfectedInfos.GetArray(i, info, sizeof(InfectedInfo));

			if(info.hPlugin == null || !IsValidHandle(info.hPlugin)) {
				info.hPlugin = FindPluginByFile(info.plname);
				if(info.hPlugin == null || !IsValidHandle(info.hPlugin)) {
					PrintToServer("[MOREINFECTED] %s: precache failed: plugin not found", info.name);
					continue;
				}
			}

			if(GetPluginStatus(info.hPlugin) != Plugin_Running) {
				PrintToServer("[MOREINFECTED] %s: precache failed: plugin not running", info.name);
				continue;
			}

			char funcname[64];
			if(!StrEqual(info.alias, "")) {
				strcopy(funcname, sizeof(funcname), info.alias);
			} else {
				strcopy(funcname, sizeof(funcname), info.name);
			}
			StrCat(funcname, sizeof(funcname), "_precache");

			Function precache = GetFunctionByName(info.hPlugin, funcname);
			if(precache == INVALID_FUNCTION) {
				PrintToServer("[MOREINFECTED] %s: precache failed: function not provided", info.name);
				continue;
			}

			Call_StartFunction(info.hPlugin, precache);
			moreinfected_data data;
			data.class_flags = info.class_flags;
			strcopy(data.data, MAX_DATA_LENGTH, info.data);
			Call_PushArray(data, sizeof(moreinfected_data));
			Call_Finish();
		}
	}
}

MRESReturn SpawnCommonZombiePost(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	if(arInfectedInfos == null) {
		return MRES_Ignored;
	}

	ArrayList arr = arClasses[class_common];

	int idx = GetRandomInt(0, arr.Length-1);

	idx = arr.Get(idx);

	InfectedInfo info;
	arInfectedInfos.GetArray(idx, info, sizeof(InfectedInfo));

	float value = GetRandomFloat(0.0, 1.0);
	if(value > info.chance) {
		return MRES_Ignored;
	}

	if(info.hPlugin == null || !IsValidHandle(info.hPlugin)) {
		info.hPlugin = FindPluginByFile(info.plname);
		if(info.hPlugin == null || !IsValidHandle(info.hPlugin)) {
			PrintToServer("[MOREINFECTED] %s: spawn failed: plugin not found", info.name);
			return MRES_Ignored;
		}
	}

	if(GetPluginStatus(info.hPlugin) != Plugin_Running) {
		PrintToServer("[MOREINFECTED] %s: spawn failed: plugin not running", info.name);
		return MRES_Ignored;
	}

	char funcname[64];
	if(!StrEqual(info.alias, "")) {
		strcopy(funcname, sizeof(funcname), info.alias);
	} else {
		strcopy(funcname, sizeof(funcname), info.name);
	}
	StrCat(funcname, sizeof(funcname), "_spawn_common");

	Function spawn = GetFunctionByName(info.hPlugin, funcname);
	if(spawn == INVALID_FUNCTION) {
		PrintToServer("[MOREINFECTED] %s: spawn failed: function not provided", info.name);
		return MRES_Ignored;
	}

	int entity = hReturn.Value;
	if(entity == -1) {
		return MRES_Ignored;
	}

	float pos[3];
	hParams.GetVector(2, pos);

	Call_StartFunction(info.hPlugin, spawn);
	Call_PushCell(entity);
	Call_PushCell(hParams.Get(1));
	Call_PushArray(pos, sizeof(pos));
	Call_PushCell(hParams.Get(3));
	moreinfected_data data;
	data.class_flags = info.class_flags;
	strcopy(data.data, MAX_DATA_LENGTH, info.data);
	Call_PushArray(data, sizeof(moreinfected_data));
	Call_Finish(entity);

	hReturn.Value = entity;

	return MRES_Override;
}

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

MRESReturn SpawnSpecialHelper(DHookReturn hReturn, float pos[3], float ang[3], ZombieClassType type, bool bride = false)
{
	if(arInfectedInfos == null) {
		g_LastArea = Address_Null;
		return MRES_Ignored;
	}

	ArrayList arr = null;

	switch(type) {
		case ZombieClassType_Smoker: {
			arr = arClasses[class_smoker];
		}
		case ZombieClassType_Boomer: {
			arr = arClasses[class_boomer];
		}
		case ZombieClassType_Hunter: {
			arr = arClasses[class_hunter];
		}
		case ZombieClassType_Spitter: {
			arr = arClasses[class_spitter];
		}
		case ZombieClassType_Jockey: {
			arr = arClasses[class_jockey];
		}
		case ZombieClassType_Charger: {
			arr = arClasses[class_charger];
		}
		case ZombieClassType_Witch: {
			arr = arClasses[bride ? class_witch_bride : class_witch];
		}
		case ZombieClassType_Tank: {
			arr = arClasses[class_tank];
		}
	}

	if(arr == null) {
		g_LastArea = Address_Null;
		return MRES_Ignored;
	}

	int idx = GetRandomInt(0, arr.Length-1);

	idx = arr.Get(idx);

	InfectedInfo info;
	arInfectedInfos.GetArray(idx, info, sizeof(InfectedInfo));

	float value = GetRandomFloat(0.0, 1.0);
	if(value > info.chance) {
		g_LastArea = Address_Null;
		return MRES_Ignored;
	}

	if(info.hPlugin == null || !IsValidHandle(info.hPlugin)) {
		info.hPlugin = FindPluginByFile(info.plname);
		if(info.hPlugin == null || !IsValidHandle(info.hPlugin)) {
			PrintToServer("[MOREINFECTED] %s: spawn failed: plugin not found", info.name);
			g_LastArea = Address_Null;
			return MRES_Ignored;
		}
	}

	if(GetPluginStatus(info.hPlugin) != Plugin_Running) {
		PrintToServer("[MOREINFECTED] %s: spawn failed: plugin not running", info.name);
		g_LastArea = Address_Null;
		return MRES_Ignored;
	}

	char funcname[64];
	if(!StrEqual(info.alias, "")) {
		strcopy(funcname, sizeof(funcname), info.alias);
	} else {
		strcopy(funcname, sizeof(funcname), info.name);
	}
	StrCat(funcname, sizeof(funcname), "_spawn_special");

	Function spawn = GetFunctionByName(info.hPlugin, funcname);
	if(spawn == INVALID_FUNCTION) {
		PrintToServer("[MOREINFECTED] %s: spawn failed: function not provided", info.name);
		g_LastArea = Address_Null;
		return MRES_Ignored;
	}

	int entity = hReturn.Value;
	if(entity == -1) {
		g_LastArea = Address_Null;
		return MRES_Ignored;
	}

	Call_StartFunction(info.hPlugin, spawn);
	Call_PushCell(entity);
	Call_PushCell(g_LastArea);
	Call_PushArray(pos, sizeof(pos));
	Call_PushArray(ang, sizeof(ang));
	Call_PushCell(type);
	moreinfected_data data;
	data.class_flags = info.class_flags;
	strcopy(data.data, MAX_DATA_LENGTH, info.data);
	Call_PushArray(data, sizeof(moreinfected_data));
	Call_Finish(entity);

	hReturn.Value = entity;

	g_LastArea = Address_Null;
	return MRES_Override;
}

MRESReturn SpawnSpecialVecPost(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	ZombieClassType type = hParams.Get(1);

	float pos[3];
	hParams.GetVector(2, pos);

	float ang[3];
	hParams.GetVector(3, ang);

	return SpawnSpecialHelper(hReturn, pos, ang, type);
}

MRESReturn SpawnWitchVecPost(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	float pos[3];
	hParams.GetVector(1, pos);

	float ang[3];
	hParams.GetVector(2, ang);

	return SpawnSpecialHelper(hReturn, pos, ang, ZombieClassType_Witch);
}

MRESReturn SpawnWitchBrideVecPost(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	float pos[3];
	hParams.GetVector(1, pos);

	float ang[3];
	hParams.GetVector(2, ang);

	return SpawnSpecialHelper(hReturn, pos, ang, ZombieClassType_Witch, true);
}

MRESReturn SpawnTankVecPost(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	float pos[3];
	hParams.GetVector(1, pos);

	float ang[3];
	hParams.GetVector(2, ang);

	return SpawnSpecialHelper(hReturn, pos, ang, ZombieClassType_Tank);
}
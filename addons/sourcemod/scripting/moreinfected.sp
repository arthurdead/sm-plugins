#include <sourcemod>
#include <dhooks>
#include <keyvalues>
#include <moreinfected>

#undef REQUIRE_EXTENSIONS
#tryinclude <nextbot>

KeyValues kvInfected = null;

enum struct InfectedInfo
{
	Handle hPlugin;
	char name[64];
	char alias[64];
	char plname[64];
	char place[64];
	char data[MAX_DATA_LENGTH];
	float chance;
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
}

enum
{
	directive_wanderer,
	directive_ambient,
	directive_attack,
	directive_special,
	infected_directive_count,
};

ArrayList arInfectedInfos = null;
StringMap infectedMap[infected_directive_count] = {null, ...};

bool g_bLateLoaded = false;

#if defined nextbot_included
bool g_bNextBot = false;
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

	return APLRes_Success;
}

#if defined nextbot_included
public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "nextbot")) {
		g_bNextBot = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "nextbot")) {
		g_bNextBot = false;
	}
}
#endif

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

			for(int i = 0; i < infected_directive_count; ++i) {
				infectedMap[i] = new StringMap();
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
				kvInfected.GetString("class_flags", classstr, sizeof(classstr), "common");
				infected_class_flags classflags = ClassStrToFlags(classstr);
				if(classflags == class_flags_invalid) {
					PrintToServer("[MOREINFECTED] %s: invalid class flags: %s", name, classstr);
					continue;
				}

				if((classflags & class_flags_common) &&
					(classflags & (class_flags_tank|
					class_flags_smoker|
					class_flags_charger|
					class_flags_boomer|
					class_flags_hunter|
					class_flags_jockey|
					class_flags_spitter|
					class_flags_witch|
					class_flags_witch_bride))) {
					PrintToServer("[MOREINFECTED] %s: cant be both common and special: %s", name, classstr);
					continue;
				}

				infected_directive_flags directiveflags = directive_flags_attack;

				if(classflags & class_flags_common) {
					kvInfected.GetString("directive_flags", classstr, sizeof(classstr), "any");
					directiveflags = DirectiveStrToFlags(classstr);
					if(directiveflags == directive_flags_invalid) {
						PrintToServer("[MOREINFECTED] %s: invalid directive flags: %s", name, classstr);
						continue;
					}
				}

				char place[64];
				kvInfected.GetString("place", place, sizeof(place), "default");

				if(classflags & class_flags_common) {
					if(directiveflags & directive_flags_wanderer) {
						SetupClassesMap(infectedMap[directive_wanderer], classflags, arInfectedInfos.Length, place);
					}
					if(directiveflags & directive_flags_ambient) {
						SetupClassesMap(infectedMap[directive_ambient], classflags, arInfectedInfos.Length, place);
					}
					if(directiveflags & directive_flags_attack) {
						SetupClassesMap(infectedMap[directive_attack], classflags, arInfectedInfos.Length, place);
					}
				} else {
					SetupClassesMap(infectedMap[directive_special], classflags, arInfectedInfos.Length, place);
				}

				InfectedInfo info;
				info.chance = chance * 0.01;
				info.class_flags = classflags;
				info.directive_flags = directiveflags;
				strcopy(info.name, sizeof(info.name), name);
				strcopy(info.place, sizeof(info.place), place);

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

void SetupClassesMap(StringMap map, infected_class_flags classflags, int idx, const char[] place)
{
	ArrayList arClasses[infected_class_count] = {null, ...};
	if(!map.GetArray(place, arClasses, sizeof(arClasses))) {
		for(int i = 0; i < infected_class_count; ++i) {
			arClasses[i] = new ArrayList();
		}
		map.SetArray(place, arClasses, sizeof(arClasses));
	}

	if(classflags & class_flags_common) {
		arClasses[class_common].Push(idx);
	}
	if(classflags & class_flags_tank) {
		arClasses[class_tank].Push(idx);
	}
	if(classflags & class_flags_smoker) {
		arClasses[class_smoker].Push(idx);
	}
	if(classflags & class_flags_charger) {
		arClasses[class_charger].Push(idx);
	}
	if(classflags & class_flags_boomer) {
		arClasses[class_boomer].Push(idx);
	}
	if(classflags & class_flags_hunter) {
		arClasses[class_hunter].Push(idx);
	}
	if(classflags & class_flags_jockey) {
		arClasses[class_jockey].Push(idx);
	}
	if(classflags & class_flags_spitter) {
		arClasses[class_spitter].Push(idx);
	}
	if(classflags & class_flags_witch) {
		arClasses[class_witch].Push(idx);
	}
	if(classflags & class_flags_witch_bride) {
		arClasses[class_witch_bride].Push(idx);
	}
}

infected_directive_flags DirectiveStrToFlags(const char[] str)
{
	char flagstrs[3][64];
	int num = ExplodeString(str, "|", flagstrs, 3, 64);

	infected_directive_flags flags = directive_flags_invalid;

	for(int i = 0; i < num; ++i) {
		if(StrEqual(flagstrs[i], "wanderer")) {
			flags |= directive_flags_wanderer;
		} else if(StrEqual(flagstrs[i], "ambient")) {
			flags |= directive_flags_ambient;
		} else if(StrEqual(flagstrs[i], "attack")) {
			flags |= directive_flags_attack;
		} else if(StrEqual(flagstrs[i], "any_background")) {
			flags |= directive_flags_wanderer;
			flags |= directive_flags_ambient;
		} else if(StrEqual(flagstrs[i], "any")) {
			flags |= directive_flags_wanderer;
			flags |= directive_flags_ambient;
			flags |= directive_flags_attack;
		}
	}

	return flags;
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
		} else if(StrEqual(flagstrs[i], "any_boss")) {
			flags |= class_flags_tank;
			flags |= class_flags_witch;
			flags |= class_flags_witch_bride;
		} else if(StrEqual(flagstrs[i], "any_special")) {
			flags |= class_flags_smoker;
			flags |= class_flags_charger;
			flags |= class_flags_boomer;
			flags |= class_flags_hunter;
			flags |= class_flags_jockey;
			flags |= class_flags_spitter;
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
			data.directive_flags = info.directive_flags;
			strcopy(data.data, MAX_DATA_LENGTH, info.data);
			Call_PushArray(data, sizeof(moreinfected_data));
			Call_Finish();
		}
	}
}

void GetPlaceFromNav(Address area, float pos[3], char[] place, int length)
{
#if 0 && defined nextbot_included
	if(g_bNextBot) {
		if(area == Address_Null) {
			int id = CNavMesh.GetPlace(pos);
			CNavMesh.PlaceToName(id, place, length);
			return;
		} else {
			int id = view_as<CNavArea>(area).Place;
			CNavMesh.PlaceToName(id, place, length);
			return;
		}
	}
#endif

	strcopy(place, length, "default");
}

MRESReturn SpawnCommonZombiePost(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	if(arInfectedInfos == null) {
		return MRES_Ignored;
	}

	CommonInfectedSpawnDirective directive = hParams.Get(3);

	StringMap placemap = null;
	switch(directive) {
		case SpawnDirective_Wanderer:
		{ placemap = infectedMap[directive_wanderer]; }
		case SpawnDirective_Ambient:
		{ placemap = infectedMap[directive_ambient]; }
		case SpawnDirective_Attack:
		{ placemap = infectedMap[directive_attack]; }
	}

	Address area = hParams.Get(1);

	float pos[3];
	hParams.GetVector(2, pos);

	char place[64];
	GetPlaceFromNav(area, pos, place, sizeof(place));

	ArrayList arClasses[infected_class_count] = {null, ...};
	if(!placemap.GetArray(place, arClasses, sizeof(arClasses))) {
		return MRES_Ignored;
	}

	ArrayList arr = arClasses[class_common];

	if(arr == null || arr.Length == 0) {
		return MRES_Ignored;
	}

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

	Call_StartFunction(info.hPlugin, spawn);
	Call_PushCell(entity);
	Call_PushCell(area);
	Call_PushArray(pos, sizeof(pos));
	Call_PushCell(directive);
	moreinfected_data data;
	data.class_flags = info.class_flags;
	data.directive_flags = info.directive_flags;
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

	StringMap placemap = infectedMap[directive_special];

	char place[64];
	GetPlaceFromNav(g_LastArea, pos, place, sizeof(place));

	ArrayList arClasses[infected_class_count] = {null, ...};
	if(!placemap.GetArray(place, arClasses, sizeof(arClasses))) {
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

	if(arr == null || arr.Length == 0) {
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
	data.directive_flags = info.directive_flags;
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
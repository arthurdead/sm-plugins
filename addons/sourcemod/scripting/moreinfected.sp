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
	infected_class class;
}

ArrayList arInfectedInfos = null;
ArrayList arCommons = null;

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

	delete gamedata;

	dSpawnCommonZombie.Enable(Hook_Pre, SpawnCommonZombiePre);
	dSpawnCommonZombie.Enable(Hook_Post, SpawnCommonZombiePost);

	char infectedfile[64];
	BuildPath(Path_SM, infectedfile, sizeof(infectedfile), "data/moreinfected.txt");

	if(FileExists(infectedfile, true)) {
		kvInfected = new KeyValues("moreinfected");
		kvInfected.ImportFromFile(infectedfile);

		if(kvInfected.GotoFirstSubKey()) {
			arInfectedInfos = new ArrayList(sizeof(InfectedInfo));

			arCommons = new ArrayList();

			do {
				char name[64];
				kvInfected.GetSectionName(name, sizeof(name));

				float chance = kvInfected.GetFloat("chance");
				if(chance == 0.0) {
					PrintToServer("[MOREINFECTED] %s: ignoring due to chance being 0", name);
					continue;
				}

				char classstr[64];
				kvInfected.GetString("class", classstr, sizeof(classstr));
				infected_class classnum = ClassStrToNum(classstr);
				if(classnum == class_invalid) {
					PrintToServer("[MOREINFECTED] %s: unknown class %s", name, classstr);
					continue;
				}

				switch(classnum) {
					case class_common:
					{ arCommons.Push(arInfectedInfos.Length); }
				}

				InfectedInfo info;
				info.chance = chance * 0.01;
				info.class = classnum;
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

infected_class ClassStrToNum(const char[] str)
{
	if(StrEqual(str, "common")) {
		return class_common;
	}

	return class_invalid;
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

					info.hPlugin = pl;

					arInfectedInfos.SetArray(idx, info, sizeof(InfectedInfo));

					if(infolist.Length == 0) {
						done = true;
					}

					break;
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
			Call_PushCell(info.class);
			Call_PushString(info.data);
			Call_Finish();
		}
	}
}

public void OnMapEnd()
{
	
}

MRESReturn SpawnCommonZombiePre(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	return MRES_Ignored;
}

MRESReturn SpawnCommonZombiePost(Address pThis, DHookReturn hReturn, DHookParam hParams)
{
	if(arInfectedInfos == null) {
		return MRES_Ignored;
	}

	int idx = GetRandomInt(0, arCommons.Length-1);

	idx = arCommons.Get(idx);

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
	StrCat(funcname, sizeof(funcname), "_spawn");

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
	Call_PushCell(info.class);
	Call_PushString(info.data);
	Call_Finish(entity);

	hReturn.Value = entity;

	return MRES_Override;
}
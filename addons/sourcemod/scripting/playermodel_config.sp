#include <sourcemod>
#include <sdkhooks>
#include <clientprefs>
#include <tf2>
#include <tf2_stocks>
#include <animhelpers>
#include <playermodel>
#include <playermodel_config>
#include <tf2attributes>

#undef REQUIRE_PLUGIN
#define NO_SHAPESHIFT_NATIVES
#tryinclude <shapeshift_funcs>
#tryinclude <tauntmanager>

ArrayList arrModelInfos = null;
ArrayList arrAnimInfos = null;
StringMap mapGroup = null;
StringMap mapModelInfoIds = null;
StringMap mapAnimInfoIds = null;
StringMap mapGestures = null;
StringMap mapTaunts = null;

#define MODEL_NAME_MAX 64
#define OVERRIDE_MAX 64
#define STEAMID_MAX 64

#define M_PI 3.14159265358979323846
#define IN_ANYMOVEMENTKEY (IN_FORWARD|IN_BACK|IN_MOVELEFT|IN_MOVERIGHT)

#define TFClass_Any (view_as<TFClassType>(-1))

enum AnimCodeType
{
	animcode_default,
	animcode_simple,
};

enum LegType
{
	leg_8yaw,
	leg_9way,
	leg_ignore,
};

#define PLAYERMODEL_TRANSMIT_BUGGED

#define FLAG_NOWEAPONS (1 << 0)
#define FLAG_NODMG (1 << 2)
#define FLAG_ALWAYSBONEMERGE (1 << 4)
#if defined PLAYERMODEL_TRANSMIT_BUGGED
#define FLAG_HACKTHIRDPERSON (1 << 5)
#endif

enum struct AnimSetInfo
{
	char name[MODEL_NAME_MAX];
	AnimCodeType animcode;
	LegType legtype;
	StringMap animnames;
	StringMap seq_cache;
	StringMap pose_cache;
}

enum struct ConfigModelInfo
{
	char name[MODEL_NAME_MAX];
	char model[PLATFORM_MAX_PATH];
	char anim[PLATFORM_MAX_PATH];
	char override[OVERRIDE_MAX];
	char steamid[STEAMID_MAX];
	StringMap gestures;
	StringMap taunts;
	TFClassType orig_class;
	TFClassType class;
	int flags;
	PlayerModelType type;
	int bodygroup;
	int skin;
	int animsetid;
}

#define ModelInfo ConfigModelInfo

enum struct GroupInfo
{
	char override[OVERRIDE_MAX];
	char steamid[STEAMID_MAX];
	ArrayList classarr[10];
}

enum struct AnimInfo
{
	int m_hOldGroundEntity;
	bool m_bDidJustJump;
	bool m_bDidJustLand;
	bool m_bWillHardLand;
	bool m_bWasDucked;
	bool m_bCanAnimate;
	int m_nOldButtons;

	void Init()
	{
		this.m_hOldGroundEntity = -1;
		this.m_bCanAnimate = true;
	}

	void Clear()
	{
		this.m_hOldGroundEntity = -1;
		this.m_bDidJustJump = false;
		this.m_bDidJustLand = false;
		this.m_bWillHardLand = false;
		this.m_bWasDucked = false;
		this.m_bCanAnimate = true;
		this.m_nOldButtons = 0;
	}
}

enum struct PlayerInfo
{
	int flags;
	int modelid;
	int animid;
	TFClassType orig_class;
	AnimCodeType animcode;
	StringMap seq_cache;
	StringMap pose_cache;
	StringMap animnames;
	LegType legtype;
	StringMap gestures;
	StringMap taunts;

	void Init()
	{
		this.Clear();
	}

	void Clear()
	{
		this.flags = 0;
		this.modelid = -1;
		this.animid = -1;
		this.orig_class = TFClass_Unknown;
		this.animcode = animcode_default;
		this.seq_cache = null;
		this.pose_cache = null;
		this.animnames = null;
		this.legtype = leg_ignore;
		this.gestures = null;
		this.taunts = null;
	}
}

AnimInfo playeranim[34];
PlayerInfo playerinfo[34];

#include "playermodel/animcode_simple.sp"

ModelInfo tmpmodelinfo;
GroupInfo tmpgroupinfo;
AnimSetInfo tmpanimsetinfo;
char tmpstr1[64];
char tmpstr2[PLATFORM_MAX_PATH];

char tmpflagstrs[7][13];
int FlagStrToFlags(const char[] str)
{
	int num = ExplodeString(str, "|", tmpflagstrs, 7, 13);

	int flags = 0;

	for(int i = 0; i < num; ++i) {
		if(StrEqual(tmpflagstrs[i], "hidehats")) {
			flags |= playermodel_hidehats;
		} else if(StrEqual(tmpflagstrs[i], "noweapons")) {
			flags |= FLAG_NOWEAPONS;
		} else if(StrEqual(tmpflagstrs[i], "nodmg")) {
			flags |= FLAG_NODMG;
		} else if(StrEqual(tmpflagstrs[i], "hideweapons")) {
			flags |= playermodel_hideweapons;
		} else if(StrEqual(tmpflagstrs[i], "alwaysmerge")) {
			flags |= FLAG_ALWAYSBONEMERGE;
		} else if(StrEqual(tmpflagstrs[i], "customanims")) {
			flags |= playermodel_customanims;
		}
	}

	return flags;
}

Cookie ClassCookies[10] = {null, ...};

stock void ClassToClassname(TFClassType type, char[] name, int length)
{
	switch(type)
	{
		case TFClass_Unknown: { strcopy(name, length, "unknown"); }
		case TFClass_Scout: { strcopy(name, length, "scout"); }
		case TFClass_Soldier: { strcopy(name, length, "soldier"); }
		case TFClass_Sniper: { strcopy(name, length, "sniper"); }
		case TFClass_Spy: { strcopy(name, length, "spy"); }
		case TFClass_Medic: { strcopy(name, length, "medic"); }
		case TFClass_DemoMan: { strcopy(name, length, "demoman"); }
		case TFClass_Pyro: { strcopy(name, length, "pyro"); }
		case TFClass_Engineer: { strcopy(name, length, "engineer"); }
		case TFClass_Heavy: { strcopy(name, length, "heavy"); }
	}
}

void FrameInventoryRemoveWeapon(int client)
{
	TF2_RemoveAllWeapons(client);
}

void FrameInventoryHideWeapon(int client)
{
	TF2_HideAllWeapons(client, true);
}

void FrameInventoryHats(int client)
{
	TF2_HideAllWearables(client, true);
}

void OnSpawnEndTouch(int entity, int other)
{
	if(other < 1 || other > MaxClients) {
		return;
	}

	if(playerinfo[other].flags & playermodel_hideweapons) {
		RequestFrame(FrameInventoryHideWeapon, other);
	}

	if(playerinfo[other].flags & playermodel_hidehats) {
		RequestFrame(FrameInventoryHats, other);
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "func_respawnroom"))
	{
		SDKHook(entity, SDKHook_EndTouch, OnSpawnEndTouch);
	}
}

void post_inventory_application(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(playerinfo[client].flags & FLAG_NOWEAPONS) {
		RequestFrame(FrameInventoryRemoveWeapon, client);
	} else if(playerinfo[client].flags & playermodel_hideweapons) {
		RequestFrame(FrameInventoryHideWeapon, client);
	}

	if(playerinfo[client].flags & playermodel_hidehats) {
		RequestFrame(FrameInventoryHats, client);
	}
}

public Action OnShapeShift(int client, int currentClass, int &targetClass)
{
	LoadCookies(client, view_as<TFClassType>(targetClass));
	return Plugin_Continue;
}

void player_changeclass(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	int class = event.GetInt("class");

	LoadCookies(client, view_as<TFClassType>(class));
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("playermodel_config");
	CreateNative("Playermodel_GetFlags", Native_GetFlags);
#if defined GAME_TF2
	CreateNative("Playermodel_GetOriginalClass", Native_GetOrigClass);
#endif
	return APLRes_Success;
}

#if defined GAME_TF2
int Native_GetOrigClass(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	return view_as<int>(playerinfo[client].orig_class);
}
#endif

int Native_GetFlags(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	return playerinfo[client].flags;
}

void GetGroupString(KeyValues kvGroups, const char[] group, const char[] name, char[] str, int len, const char[] def, bool seek)
{
	if(seek) {
		if(kvGroups.JumpToKey(group)) {
			kvGroups.GetString(name, str, len, def);
			kvGroups.GoBack();
		} else {
			strcopy(str, len, def);
		}
	} else {
		kvGroups.GetString(name, str, len, def);
	}
}

void ParseModelsKV(KeyValues kvGroups, const char[] path, const char[] group, bool inside)
{
	KeyValues kvModels = new KeyValues("Playermodels");
	kvModels.ImportFromFile(path);

	if(kvModels.GotoFirstSubKey()) {
		char tmpgroup[64];
		strcopy(tmpgroup, sizeof(tmpgroup), group);

		do {
			kvModels.GetSectionName(tmpmodelinfo.name, MODEL_NAME_MAX);

			kvModels.GetString("group", tmpgroup, sizeof(tmpgroup), tmpgroup);

			kvModels.GetString("class", tmpstr1, sizeof(tmpstr1), "__unset");
			if(StrEqual(tmpstr1, "__unset")) {
				GetGroupString(kvGroups, tmpgroup, "class", tmpstr1, sizeof(tmpstr1), "all", !inside);
			}

			if(StrEqual(tmpstr1, "all")) {
				tmpmodelinfo.class = TFClass_Any;
			} else {
				tmpmodelinfo.class = TF2_GetClass(tmpstr1);
				if(tmpmodelinfo.class == TFClass_Unknown) {
					PrintToServer("%s: model %s has unknown class: %s", tmpgroup, tmpmodelinfo.name, tmpstr1);
					continue;
				}
			}

			kvModels.GetString("animset", tmpstr1, sizeof(tmpstr1), "__unset");
			if(StrEqual(tmpstr1, "__unset")) {
				GetGroupString(kvGroups, tmpgroup, "animset", tmpstr1, sizeof(tmpstr1), "default", !inside);
			}

			int animid = -1;
			if(!StrEqual(tmpstr1, "default")) {
				if(!mapAnimInfoIds.GetValue(tmpstr1, animid)) {
					PrintToServer("%s: model %s has unknown animset: %s", tmpgroup, tmpmodelinfo.name, tmpstr1);
					continue;
				}
			}
			tmpmodelinfo.animsetid = animid;

			kvModels.GetString("gestures", tmpstr1, sizeof(tmpstr1), "__unset");
			if(StrEqual(tmpstr1, "__unset")) {
				GetGroupString(kvGroups, tmpgroup, "gestures", tmpstr1, sizeof(tmpstr1), "none", !inside);
			}

			StringMap animmap = null;
			if(tmpstr1[0] != '\0' && !StrEqual(tmpstr1, "none")) {
				if(!mapGestures.GetValue(tmpstr1, animmap)) {
					PrintToServer("%s: model %s has unknown gestures: %s", tmpgroup, tmpmodelinfo.name, tmpstr1);
					continue;
				}
			}
			tmpmodelinfo.gestures = animmap;

			kvModels.GetString("taunts", tmpstr1, sizeof(tmpstr1), "__unset");
			if(StrEqual(tmpstr1, "__unset")) {
				GetGroupString(kvGroups, tmpgroup, "gestures", tmpstr1, sizeof(tmpstr1), "none", !inside);
			}

			animmap = null;
			if(tmpstr1[0] != '\0' && !StrEqual(tmpstr1, "none")) {
				if(!mapTaunts.GetValue(tmpstr1, animmap)) {
					PrintToServer("%s: model %s has unknown taunts: %s", tmpgroup, tmpmodelinfo.name, tmpstr1);
					continue;
				}
			}
			tmpmodelinfo.taunts = animmap;

			kvModels.GetString("type", tmpstr1, sizeof(tmpstr1), "__unset");
			if(StrEqual(tmpstr1, "__unset")) {
				GetGroupString(kvGroups, tmpgroup, "type", tmpstr1, sizeof(tmpstr1), "custom_model", !inside);
			}

			if(StrEqual(tmpstr1, "bonemerge")) {
				tmpmodelinfo.type = PlayerModelBonemerge;
			} else if(StrEqual(tmpstr1, "prop")) {
				tmpmodelinfo.type = PlayerModelProp;
			} else if(StrEqual(tmpstr1, "custom_model")) {
				tmpmodelinfo.type = PlayerModelCustomModel;
			} else {
				PrintToServer("%s: model %s has unknown type: %s", tmpgroup, tmpmodelinfo.name, tmpstr1);
				continue;
			}

			kvModels.GetString("model", tmpmodelinfo.model, PLATFORM_MAX_PATH);
			kvModels.GetString("animation", tmpmodelinfo.anim, PLATFORM_MAX_PATH);

			kvModels.GetString("override", tmpstr1, sizeof(tmpstr1));
			if(StrEqual(tmpstr1, "__unset")) {
				GetGroupString(kvGroups, tmpgroup, "override", tmpstr1, sizeof(tmpstr1), "", !inside);
			}

			strcopy(tmpmodelinfo.override, OVERRIDE_MAX, tmpstr1);

			kvModels.GetString("steamid", tmpstr1, sizeof(tmpstr1));
			if(StrEqual(tmpstr1, "__unset")) {
				GetGroupString(kvGroups, tmpgroup, "steamid", tmpstr1, sizeof(tmpstr1), "", !inside);
			}

			strcopy(tmpmodelinfo.steamid, STEAMID_MAX, tmpstr1);

			kvModels.GetString("flags", tmpstr1, sizeof(tmpstr1), "__unset");
			if(StrEqual(tmpstr1, "__unset")) {
				GetGroupString(kvGroups, tmpgroup, "flags", tmpstr1, sizeof(tmpstr1), "nodmg", !inside);
			}

			tmpmodelinfo.flags = FlagStrToFlags(tmpstr1);

			if(animid != -1) {
				tmpmodelinfo.type = PlayerModelProp;
			}

			if(tmpmodelinfo.type == PlayerModelProp ||
				animid != -1) {
				tmpmodelinfo.flags |= playermodel_hidehats|FLAG_NOWEAPONS;
			}

		#if defined PLAYERMODEL_TRANSMIT_BUGGED
			if(tmpmodelinfo.type == PlayerModelProp) {
				tmpmodelinfo.flags |= FLAG_HACKTHIRDPERSON;
			}
		#endif

			kvModels.GetString("bodygroup", tmpstr1, sizeof(tmpstr1), "__unset");
			if(StrEqual(tmpstr1, "__unset")) {
				GetGroupString(kvGroups, tmpgroup, "bodygroup", tmpstr1, sizeof(tmpstr1), "0", !inside);
			}

			tmpmodelinfo.bodygroup = StringToInt(tmpstr1);

			kvModels.GetString("skin", tmpstr1, sizeof(tmpstr1), "__unset");
			if(StrEqual(tmpstr1, "__unset")) {
				GetGroupString(kvGroups, tmpgroup, "skin", tmpstr1, sizeof(tmpstr1), "-1", !inside);
			}

			tmpmodelinfo.skin = StringToInt(tmpstr1);

			kvModels.GetString("original_class", tmpstr1, sizeof(tmpstr1), "unknown");
			tmpmodelinfo.orig_class = TF2_GetClass(tmpstr1);

			int idx = arrModelInfos.Length;

			arrModelInfos.PushArray(tmpmodelinfo, sizeof(tmpmodelinfo));

			mapModelInfoIds.SetValue(tmpmodelinfo.name, idx);

			if(!mapGroup.GetArray(tmpgroup, tmpgroupinfo, sizeof(tmpgroupinfo))) {
				for(int i = 1; i <= 9; ++i) {
					tmpgroupinfo.classarr[i] = new ArrayList();
				}
				mapGroup.SetArray(tmpgroup, tmpgroupinfo, sizeof(tmpgroupinfo));
			}

			if(tmpmodelinfo.class == TFClass_Any) {
				for(int i = 1; i <= 9; ++i) {
					tmpgroupinfo.classarr[i].Push(idx);
				}
			} else {
				tmpgroupinfo.classarr[tmpmodelinfo.class].Push(idx);
			}
		} while(kvModels.GotoNextKey());

		kvModels.GoBack();
	}

	delete kvModels;
}

public void OnPluginStart()
{
	RegAdminCmd("sm_pm", ConCommand_PM, ADMFLAG_GENERIC);
	RegAdminCmd("sm_gt", ConCommand_GT, ADMFLAG_GENERIC);
	RegAdminCmd("sm_pt", ConCommand_PT, ADMFLAG_GENERIC);

	HookEvent("post_inventory_application", post_inventory_application);

	HookEvent("player_changeclass", player_changeclass);

	mapModelInfoIds = new StringMap();
	mapGroup = new StringMap();
	mapGestures = new StringMap();
	mapTaunts = new StringMap();
	mapAnimInfoIds = new StringMap();

	arrModelInfos = new ArrayList(sizeof(ModelInfo));
	arrAnimInfos = new ArrayList(sizeof(AnimSetInfo));

	char tmpclass[64];
	for(int i = 1; i <= 9; ++i) {
		ClassToClassname(view_as<TFClassType>(i), tmpclass, sizeof(tmpclass));
		Format(tmpstr1, sizeof(tmpstr1), "playermodel_v3_%s", tmpclass);
		ClassCookies[i] = new Cookie(tmpstr1, "", CookieAccess_Private);
	}

	BuildPath(Path_SM, tmpstr2, sizeof(tmpstr2), "configs/playermodels/gestures.txt");
	KeyValues KvTemp = new KeyValues("Playermodels_gestures");
	if(FileExists(tmpstr2)) {
		KvTemp.ImportFromFile(tmpstr2);

		if(KvTemp.GotoFirstSubKey()) {
			char tmpstr3[64];

			do {
				KvTemp.GetSectionName(tmpstr1, sizeof(tmpstr1));

				StringMap animmap = new StringMap();
				mapGestures.SetValue(tmpstr1, animmap);

				if(KvTemp.GotoFirstSubKey(false)) {
					do {
						KvTemp.GetSectionName(tmpstr1, sizeof(tmpstr1));
						KvTemp.GetString(NULL_STRING, tmpstr3, sizeof(tmpstr3));

						animmap.SetString(tmpstr1, tmpstr3);
					} while(KvTemp.GotoNextKey(false));

					KvTemp.GoBack();
				}
			} while(KvTemp.GotoNextKey());

			KvTemp.GoBack();
		}
	}
	delete KvTemp;

	BuildPath(Path_SM, tmpstr2, sizeof(tmpstr2), "configs/playermodels/taunts.txt");
	KvTemp = new KeyValues("Playermodels_taunts");
	if(FileExists(tmpstr2)) {
		KvTemp.ImportFromFile(tmpstr2);

		if(KvTemp.GotoFirstSubKey()) {
			char tmpstr3[64];

			do {
				KvTemp.GetSectionName(tmpstr1, sizeof(tmpstr1));

				StringMap animmap = new StringMap();
				mapTaunts.SetValue(tmpstr1, animmap);

				if(KvTemp.GotoFirstSubKey(false)) {
					do {
						KvTemp.GetSectionName(tmpstr1, sizeof(tmpstr1));
						KvTemp.GetString(NULL_STRING, tmpstr3, sizeof(tmpstr3));

						animmap.SetString(tmpstr1, tmpstr3);
					} while(KvTemp.GotoNextKey(false));

					KvTemp.GoBack();
				}
			} while(KvTemp.GotoNextKey());

			KvTemp.GoBack();
		}
	}
	delete KvTemp;

	BuildPath(Path_SM, tmpstr2, sizeof(tmpstr2), "configs/playermodels/animsets.txt");
	KvTemp = new KeyValues("Playermodels_animsets");
	if(FileExists(tmpstr2)) {
		KvTemp.ImportFromFile(tmpstr2);

		if(KvTemp.GotoFirstSubKey()) {
			char tmpstr3[64];

			do {
				KvTemp.GetSectionName(tmpanimsetinfo.name, sizeof(tmpanimsetinfo.name));

				if(KvTemp.JumpToKey("animations")) {
					if(KvTemp.GotoFirstSubKey(false)) {
						tmpanimsetinfo.animnames = new StringMap();

						do {
							KvTemp.GetSectionName(tmpstr1, sizeof(tmpstr1));
							KvTemp.GetString(NULL_STRING, tmpstr3, sizeof(tmpstr3));

							tmpanimsetinfo.animnames.SetString(tmpstr1, tmpstr3);
						} while(KvTemp.GotoNextKey(false));

						KvTemp.GoBack();
					}

					KvTemp.GoBack();
				}

				if(tmpanimsetinfo.animnames == null) {
					PrintToServer("%s animset missing animation names", tmpanimsetinfo.name);
					continue;
				}

				KvTemp.GetString("leg_type", tmpstr1, sizeof(tmpstr1), "9way");
				if(StrEqual(tmpstr1, "9way")) {
					tmpanimsetinfo.legtype = leg_9way;
				} else if(StrEqual(tmpstr1, "8way")) {
					tmpanimsetinfo.legtype = leg_8yaw;
				} else if(StrEqual(tmpstr1, "ignore")) {
					tmpanimsetinfo.legtype = leg_ignore;
				} else {
					PrintToServer("%s unknown leg type %s", tmpanimsetinfo.name, tmpstr1);
					continue;
				}

				KvTemp.GetString("code_path", tmpstr1, sizeof(tmpstr1), "simple");
				if(StrEqual(tmpstr1, "simple")) {
					tmpanimsetinfo.animcode = animcode_simple;
				} else {
					PrintToServer("%s unknown code path %s", tmpanimsetinfo.name, tmpstr1);
					continue;
				}

				tmpanimsetinfo.seq_cache = new StringMap();
				tmpanimsetinfo.pose_cache = new StringMap();

				int idx = arrAnimInfos.Length;

				arrAnimInfos.PushArray(tmpanimsetinfo, sizeof(tmpanimsetinfo));

				mapAnimInfoIds.SetValue(tmpanimsetinfo.name, idx);
			} while(KvTemp.GotoNextKey());

			KvTemp.GoBack();
		}
	}
	delete KvTemp;

	BuildPath(Path_SM, tmpstr2, sizeof(tmpstr2), "configs/playermodels/groups.txt");
	KeyValues kvGroups = new KeyValues("Playermodels_groups");
	if(FileExists(tmpstr2)) {
		kvGroups.ImportFromFile(tmpstr2);

		if(kvGroups.GotoFirstSubKey()) {
			do {
				kvGroups.GetSectionName(tmpstr1, sizeof(tmpstr1));

				kvGroups.GetString("override", tmpgroupinfo.override, OVERRIDE_MAX);
				kvGroups.GetString("steamid", tmpgroupinfo.steamid, STEAMID_MAX);

				for(int i = 1; i <= 9; ++i) {
					tmpgroupinfo.classarr[i] = new ArrayList();
				}

				mapGroup.SetArray(tmpstr1, tmpgroupinfo, sizeof(tmpgroupinfo));

				BuildPath(Path_SM, tmpstr2, sizeof(tmpstr2), "configs/playermodels/%s.txt", tmpstr1);
				if(FileExists(tmpstr2)) {
					ParseModelsKV(kvGroups, tmpstr2, tmpstr1, true);
				}
			} while(kvGroups.GotoNextKey());

			kvGroups.GoBack();
		}
	}

	BuildPath(Path_SM, tmpstr2, sizeof(tmpstr2), "configs/playermodels/models.txt");
	if(FileExists(tmpstr2)) {
		ParseModelsKV(kvGroups, tmpstr2, "all", false);
	}

	delete kvGroups;

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
		if(AreClientCookiesCached(i)) {
			OnClientCookiesCached(i);
		}
	}
}

void LoadCookies(int client, TFClassType class)
{
	ClassCookies[class].Get(client, tmpstr1, sizeof(tmpstr1));

	if(tmpstr1[0] == '\0' || StrEqual(tmpstr1, "none")) {
		ClearPlayerModel(client);
	} else {
		int idx = -1;

		bool valid = true;

		if(mapModelInfoIds.GetValue(tmpstr1, idx)) {
			arrModelInfos.GetArray(idx, tmpmodelinfo, sizeof(tmpmodelinfo));

			if(tmpmodelinfo.override[0] != '\0') {
				if(!CheckCommandAccess(client, tmpmodelinfo.override, ADMFLAG_GENERIC)) {
					valid = false;
				}
			}

			char tmpauth[STEAMID_MAX];
			if(tmpmodelinfo.steamid[0] != '\0') {
				if(GetClientAuthId(client, AuthId_SteamID64, tmpauth, sizeof(tmpauth))) {
					if(!StrEqual(tmpauth, tmpmodelinfo.steamid)) {
						valid = false;
					}
				} else {
					valid = false;
				}
			}

			if(valid) {
				SetPlayerModel(client, class, tmpmodelinfo, idx);
				PrintToChat(client, "[SM] The model \"%s\" was applied on you", tmpstr1);
			}
		}

		if(!valid) {
			ClearPlayerModel(client);

			ClassCookies[class].Set(client, "none");
		}
	}
}

public void OnClientCookiesCached(int client)
{
	if(IsClientInGame(client)) {
		TFClassType class = TF2_GetPlayerClass(client);

		if(class != TFClass_Unknown) {
			LoadCookies(client, class);
		}
	}
}

void CleanString(char[] str)
{
	int len = strlen(str);
	for(int i = 0; i < len; ++i) {
		switch(str[i]) {
			case '\r': { str[i] = ' '; }
			case '\n': { str[i] = ' '; }
			case '\t': { str[i] = ' '; }
		}
	}

	TrimString(str);
}

public void OnMapStart()
{
	for(int i = 0, len = arrModelInfos.Length; i < len; ++i) {
		arrModelInfos.GetArray(i, tmpmodelinfo, sizeof(tmpmodelinfo));

		PrecacheModel(tmpmodelinfo.model);

		if(tmpmodelinfo.anim[0] != '\0') {
			PrecacheModel(tmpmodelinfo.anim);
		}

		Format(tmpstr2, sizeof(tmpstr2), "%s.dep", tmpmodelinfo.model);
		if(FileExists(tmpstr2, true)) {
			File dlfile = OpenFile(tmpstr2, "r", true);

			while(!dlfile.EndOfFile()) {
				dlfile.ReadLine(tmpstr2, sizeof(tmpstr2));

				CleanString(tmpstr2);

				AddFileToDownloadsTable(tmpstr2);
			}

			delete dlfile;
		}
	}
}

public void OnClientPutInServer(int client)
{
	playeranim[client].Init();
	playerinfo[client].Init();
	SDKHook(client, SDKHook_PostThink, OnPlayerPostThink);
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnPlayerTakeDamageAlive);
}

Action OnPlayerTakeDamageAlive(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if(victim != attacker && attacker >= 1 && attacker <= MaxClients) {
		if(playerinfo[attacker].flags & FLAG_NODMG) {
			damage = 0.0;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

public void OnClientDisconnect(int client)
{
	playeranim[client].Clear();
	playerinfo[client].Clear();
}

float GetVectorLength2D(float vec[3])
{
	float tmp[3];
	tmp[0] = vec[0];
	tmp[1] = vec[1];
	return GetVectorLength(tmp);
}

int LookupSequenceCached(StringMap map, int entity, const char[] name, StringMap remap = null)
{
	if(remap != null) {
		remap.GetString(name, tmpstr1, sizeof(tmpstr1));
	} else {
		strcopy(tmpstr1, sizeof(tmpstr1), name);
	}
	int sequence = -1;
	if(map.GetValue(tmpstr1, sequence)) {
		return sequence;
	} else {
		sequence = view_as<BaseAnimating>(entity).LookupSequence(tmpstr1);
		map.SetValue(tmpstr1, sequence, true);
	}
	return sequence;
}

int LookupPoseParameterCached(StringMap map, int entity, const char[] name)
{
	int sequence = -1;
	if(map.GetValue(name, sequence)) {
		return sequence;
	} else {
		sequence = view_as<BaseAnimating>(entity).LookupPoseParameter(name);
		map.SetValue(name, sequence, true);
	}
	return sequence;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	AnimCodeType animcode = playerinfo[client].animcode;
	if(animcode != animcode_default) {
		if(!playeranim[client].m_bCanAnimate) {
			buttons &= ~IN_ANYMOVEMENTKEY;
			buttons &= ~IN_JUMP;
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}

void OnPlayerPostThink(int client)
{
	if(playerinfo[client].flags & playermodel_hideweapons) {
		TF2_HideAllWeapons(client, true);
	}

	if(playerinfo[client].flags & playermodel_hidehats) {
		TF2_HideAllWearables(client, true);
	}

	AnimCodeType animcode = playerinfo[client].animcode;
	if(animcode == animcode_default) {
		return;
	}

	int ref = Playermodel_GetAnimEnt(client);
	int entity = EntRefToEntIndex(ref);
	if(!IsValidEntity(entity)) {
		return;
	}

#if defined PLAYERMODEL_TRANSMIT_BUGGED
	if(playerinfo[client].flags & FLAG_HACKTHIRDPERSON) {
		SetEntProp(client, Prop_Send, "m_nForceTauntCam", 1);
	}
#endif

	switch(animcode) {
		case animcode_simple: {
			do_simpleanimcode(
				client, entity,
				playeranim[client],
				playerinfo[client].seq_cache, playerinfo[client].pose_cache,
				playerinfo[client].legtype, playerinfo[client].animnames
			);
		}
	}

	bool m_bDucked = view_as<bool>(GetEntProp(client, Prop_Send, "m_bDucked"));

#if defined GAME_TF2
	float playback = GetEntPropFloat(entity, Prop_Send, "m_flPlaybackRate");
	playback = TF2Attrib_HookValueFloat(1.0, "mult_gesture_time", client);
	SetEntPropFloat(entity, Prop_Send, "m_flPlaybackRate", playback);
#endif

	float speed = 0.1;
	if(playeranim[client].m_bCanAnimate) {
		speed = GetEntPropFloat(entity, Prop_Data, "m_flGroundSpeed");
		if(m_bDucked) {
			speed *= 3.00000003;
		}
	#if defined GAME_TF2
		speed = TF2Attrib_HookValueFloat(speed, "mult_gesture_time", client);
	#endif
	}
	if(speed == 0.0) {
		speed = 4.0;
	}
	SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", speed);

	SetEntProp(entity, Prop_Data, "m_bSequenceLoops", 1);
}

#if defined GAME_TF2
public void TF2_OnConditionAdded(int client, TFCond condition)
{
	if(playerinfo[client].animcode != animcode_default) {
		if(condition == TFCond_Taunting) {
			playeranim[client].m_bCanAnimate = false;
		}
	}
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	if(playerinfo[client].animcode != animcode_default) {
		if(condition == TFCond_Taunting) {
			playeranim[client].m_bCanAnimate = true;
		}
	}
}
#endif

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			ClearPlayerModel(i);
		}
	}
}

void TF2_HideWeaponSlot(int client, int slot, bool hide)
{
	int entity = GetPlayerWeaponSlot(client, slot);
	if(entity != -1) {
		SetEntityRenderMode(entity, hide ? RENDER_TRANSCOLOR : RENDER_NORMAL);
		SetEntityRenderColor(entity, 255, 255, 255, hide ? 0 : 255);
	}
}

void TF2_HideAllWeapons(int client, bool hide)
{
	for(int i = 0; i <= 5; i++)
	{
		TF2_HideWeaponSlot(client, i, hide);
	}
}

void TF2_HideAllWearables(int client, bool hide)
{
	int entity = -1;
	while((entity = FindEntityByClassname(entity, "tf_wearable*")) != -1)
	{
		int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		if(owner == client) {
			SetEntityRenderMode(entity, hide ? RENDER_TRANSCOLOR : RENDER_NORMAL);
			SetEntityRenderColor(entity, 255, 255, 255, hide ? 0 : 255);
		}
	}
}

public void Playermodel_OnApplied(int client)
{
	if(playerinfo[client].flags & FLAG_NOWEAPONS) {
		TF2_RemoveAllWeapons(client);
		SetEntProp(client, Prop_Data, "m_bDrawViewmodel", 0);
	} else if(playerinfo[client].flags & playermodel_hideweapons) {
		TF2_HideAllWeapons(client, true);
	}

	if(playerinfo[client].flags & playermodel_hidehats) {
		TF2_HideAllWearables(client, true);
	}

#if defined PLAYERMODEL_TRANSMIT_BUGGED
	if(playerinfo[client].flags & FLAG_HACKTHIRDPERSON) {
		SetEntProp(client, Prop_Send, "m_nForceTauntCam", 1);
	}
#endif
}

void ClearPlayerModel(int client)
{
	bool hadnoweapons = !!(playerinfo[client].flags & FLAG_NOWEAPONS);
	bool hadhideweapons = !!(playerinfo[client].flags & playermodel_hideweapons);
	bool hadhidehats = !!(playerinfo[client].flags & playermodel_hidehats);

#if defined PLAYERMODEL_TRANSMIT_BUGGED
	if(playerinfo[client].flags & FLAG_HACKTHIRDPERSON) {
		//SetEntProp(client, Prop_Send, "m_nForceTauntCam", 0);
	}
#endif

	OnClientDisconnect(client);

	Playermodel_Clear(client);
	Playermodel_Clear(client, true);

	if(hadnoweapons) {
		TF2_RespawnPlayer(client);
		SetEntProp(client, Prop_Data, "m_bDrawViewmodel", 1);
	} else if(hadhideweapons) {
		TF2_HideAllWeapons(client, false);
	}

	if(hadhidehats) {
		TF2_HideAllWearables(client, false);
	}
}

void SetPlayerModel(int client, TFClassType class, ModelInfo info, int id)
{
	bool hadnoweapons = !!(playerinfo[client].flags & FLAG_NOWEAPONS);
	bool hadhideweapons = !!(playerinfo[client].flags & playermodel_hideweapons);
	bool hadhidehats = !!(playerinfo[client].flags & playermodel_hidehats);

#if defined PLAYERMODEL_TRANSMIT_BUGGED
	if(playerinfo[client].flags & FLAG_HACKTHIRDPERSON) {
		//SetEntProp(client, Prop_Send, "m_nForceTauntCam", 0);
	}
#endif

	playerinfo[client].flags = info.flags;

	if(CheckCommandAccess(client, "playermodel_dmgoverride", ADMFLAG_GENERIC)) {
		playerinfo[client].flags &= ~FLAG_NODMG;
	}

	playerinfo[client].modelid = id;
	playerinfo[client].animid = info.animsetid;
	playerinfo[client].orig_class = info.orig_class;
	playerinfo[client].gestures = info.gestures;
	playerinfo[client].taunts = info.taunts;

	if(info.animsetid != -1) {
		arrAnimInfos.GetArray(info.animsetid, tmpanimsetinfo, sizeof(tmpanimsetinfo));

		playerinfo[client].animcode = tmpanimsetinfo.animcode;
		playerinfo[client].seq_cache = tmpanimsetinfo.seq_cache;
		playerinfo[client].pose_cache = tmpanimsetinfo.pose_cache;
		playerinfo[client].animnames = tmpanimsetinfo.animnames;
		playerinfo[client].legtype = tmpanimsetinfo.legtype;
	} else {
		playerinfo[client].animcode = animcode_default;
		playerinfo[client].seq_cache = null;
		playerinfo[client].pose_cache = null;
		playerinfo[client].animnames = null;
		playerinfo[client].legtype = leg_ignore;
	}

	if(!(info.flags & FLAG_NOWEAPONS) && hadnoweapons) {
		TF2_RespawnPlayer(client);
		SetEntProp(client, Prop_Data, "m_bDrawViewmodel", 1);
	} else if(!(info.flags & playermodel_hideweapons) && hadhideweapons) {
		TF2_HideAllWeapons(client, false);
	}

	if(!(info.flags & playermodel_hidehats) && hadhidehats) {
		TF2_HideAllWearables(client, false);
	}

	PlayerModelType type = info.type;
	if(!(info.flags & FLAG_ALWAYSBONEMERGE)) {
		if(type == PlayerModelBonemerge && class == info.orig_class) {
			type = PlayerModelCustomModel;
		}
	}

	PlayerModel_SetType(client, info.model, type, true);
	Playermodel_SetSkin(client, info.skin, true);
	Playermodel_SetBodygroup(client, info.bodygroup, true);

	if(info.anim[0] != '\0') {
		Playermodel_SetAnimation(client, info.anim, true);
	}

	Playermodel_Clear(client, false, true);
}

int MenuHandler_PlayerModel(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		if(!TF2_IsPlayerInCondition(param1, TFCond_Taunting)) {
			menu.GetItem(param2, tmpstr1, sizeof(tmpstr1));

			int idx = StringToInt(tmpstr1);

			TFClassType class = TF2_GetPlayerClass(param1);
			if(class != TFClass_Unknown) {
				arrModelInfos.GetArray(idx, tmpmodelinfo, sizeof(tmpmodelinfo));

				SetPlayerModel(param1, class, tmpmodelinfo, idx);

				if(!CheckCommandAccess(param1, "playermodel_dmgoverride", ADMFLAG_GENERIC) &&
					tmpmodelinfo.flags & FLAG_NODMG) {
					PrintToChat(param1, "[SM] You cannot do damage with the \"%s\" model", tmpmodelinfo.name);
				}

				ClassCookies[class].Set(param1, tmpmodelinfo.name);

				menu.GetTitle(tmpstr1, sizeof(tmpstr1));

				if(mapGroup.GetArray(tmpstr1, tmpgroupinfo, sizeof(tmpgroupinfo))) {
					DisplayModelMenu(tmpstr1, tmpgroupinfo.classarr[class], class, param1, menu.Selection);
				}
			}
		} else {
			PrintToChat(param1, "[SM] can't change model mid taunt");
		}
	} else if(action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			DisplayGroupMenu(param1);
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

int MenuHandler_ModelGroup(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		if(param2 == 0) {
			if(!TF2_IsPlayerInCondition(param1, TFCond_Taunting)) {
				ClearPlayerModel(param1);

				TFClassType class = TF2_GetPlayerClass(param1);
				if(class != TFClass_Unknown) {
					ClassCookies[class].Set(param1, "none");
				}
			} else {
				PrintToChat(param1, "[SM] can't change model mid taunt");
			}

			DisplayGroupMenu(param1);
		} else {
			menu.GetItem(param2, tmpstr1, sizeof(tmpstr1));

			if(mapGroup.GetArray(tmpstr1, tmpgroupinfo, sizeof(tmpgroupinfo))) {
				TFClassType class = TF2_GetPlayerClass(param1);
				if(class != TFClass_Unknown) {
					DisplayModelMenu(tmpstr1, tmpgroupinfo.classarr[class], class, param1);
				}
			} else {
				DisplayGroupMenu(param1);
			}
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

void DisplayModelMenu(const char[] group, ArrayList arr, TFClassType class, int client, int item = -1)
{
	Handle style = GetMenuStyleHandle(MenuStyle_Default);

	Menu menu = CreateMenuEx(style, MenuHandler_PlayerModel, MENU_ACTIONS_DEFAULT);
	menu.SetTitle(group);

	int drawstyle = ITEMDRAW_DEFAULT;
	if(playerinfo[client].modelid == -1) {
		drawstyle = ITEMDRAW_DISABLED;
	}

	menu.ExitBackButton = true;

	GetModelForClass(class, tmpstr2, sizeof(tmpstr2));

	char tmpauth[STEAMID_MAX];

	for(int i, len = arr.Length; i < len; ++i) {
		int idx = arr.Get(i);

		arrModelInfos.GetArray(idx, tmpmodelinfo, sizeof(tmpmodelinfo));

		if(tmpmodelinfo.override[0] != '\0') {
			if(!CheckCommandAccess(client, tmpmodelinfo.override, ADMFLAG_GENERIC)) {
				continue;
			}
		}

		if(tmpmodelinfo.steamid[0] != '\0') {
			if(GetClientAuthId(client, AuthId_SteamID64, tmpauth, sizeof(tmpauth))) {
				if(!StrEqual(tmpauth, tmpmodelinfo.steamid)) {
					continue;
				}
			}
		}

		if(tmpmodelinfo.orig_class == class) {
			if(StrEqual(tmpstr2, tmpmodelinfo.model)) {
				continue;
			}
		}

		IntToString(idx, tmpstr1, sizeof(tmpstr1));

		drawstyle = ITEMDRAW_DEFAULT;
		if(playerinfo[client].modelid == idx) {
			drawstyle = ITEMDRAW_DISABLED;
		}

		menu.AddItem(tmpstr1, tmpmodelinfo.name, drawstyle);
	}

	if(item == -1) {
		menu.Display(client, MENU_TIME_FOREVER);
	} else {
		menu.DisplayAt(client, item, MENU_TIME_FOREVER);
	}
}

void DisplayGroupMenu(int client, int item = -1)
{
	TFClassType class = TF2_GetPlayerClass(client);
	if(class == TFClass_Unknown) {
		return;
	}

	Handle style = GetMenuStyleHandle(MenuStyle_Default);

	Menu menu = CreateMenuEx(style, MenuHandler_ModelGroup, MENU_ACTIONS_DEFAULT);
	menu.SetTitle("Playermodel");

	menu.AddItem("-1", "none");

	StringMapSnapshot snapshot = mapGroup.Snapshot();

	char tmpauth[STEAMID_MAX];

	for(int i = 0, len = snapshot.Length; i < len; ++i) {
		snapshot.GetKey(i, tmpstr1, sizeof(tmpstr1));

		mapGroup.GetArray(tmpstr1, tmpgroupinfo, sizeof(tmpgroupinfo));

		if(tmpgroupinfo.override[0] != '\0') {
			if(!CheckCommandAccess(client, tmpgroupinfo.override, ADMFLAG_GENERIC)) {
				continue;
			}
		}

		if(tmpgroupinfo.steamid[0] != '\0') {
			if(GetClientAuthId(client, AuthId_SteamID64, tmpauth, sizeof(tmpauth))) {
				if(!StrEqual(tmpauth, tmpgroupinfo.steamid)) {
					continue;
				}
			}
		}

		menu.AddItem(tmpstr1, tmpstr1);
	}

	delete snapshot;

	if(item == -1) {
		menu.Display(client, MENU_TIME_FOREVER);
	} else {
		menu.DisplayAt(client, item, MENU_TIME_FOREVER);
	}
}

int MenuHandler_PropModelGestures(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		int ref = Playermodel_GetEntity(param1);
		int entity = EntRefToEntIndex(ref);

		menu.GetItem(param2, tmpstr1, sizeof(tmpstr1));
		
		if(IsValidEntity(entity)) {
			int sequence = LookupSequenceCached(playerinfo[param1].seq_cache, entity, tmpstr1);
			if(sequence != -1) {
				view_as<BaseAnimatingOverlay>(entity).AddGestureSequence1(sequence);
			}
		}

		DiplayPropGesturesMenu(param1, menu.Selection);
	} else if(action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

void DiplayPropGesturesMenu(int client, int item = -1)
{
	StringMap gestures = playerinfo[client].gestures;

	Handle style = GetMenuStyleHandle(MenuStyle_Default);

	Menu menu = CreateMenuEx(style, MenuHandler_PropModelGestures, MENU_ACTIONS_DEFAULT);
	menu.SetTitle("Gestures");

	StringMapSnapshot snapshot = gestures.Snapshot();

	char tmpstr3[64];

	for(int i = 0, len = snapshot.Length; i < len; ++i) {
		snapshot.GetKey(i, tmpstr1, sizeof(tmpstr1));

		gestures.GetString(tmpstr1, tmpstr3, sizeof(tmpstr3));

		menu.AddItem(tmpstr1, tmpstr3);
	}

	delete snapshot;

	if(item == -1) {
		menu.Display(client, MENU_TIME_FOREVER);
	} else {
		menu.DisplayAt(client, item, MENU_TIME_FOREVER);
	}
}

int MenuHandler_ModelGestures(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		menu.GetItem(param2, tmpstr1, sizeof(tmpstr1));
		
		

		DiplayGesturesMenu(param1, menu.Selection);
	} else if(action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

void DiplayGesturesMenu(int client, int item = -1)
{
	/*Handle style = GetMenuStyleHandle(MenuStyle_Default);

	Menu menu = CreateMenuEx(style, MenuHandler_ModelGestures, MENU_ACTIONS_DEFAULT);
	menu.SetTitle("Gestures");

	TFClassType class = TF2_GetPlayerClass(client);
	switch(class) {
		case TFClass_Scout: {

		}
	}

	menu.AddItem("0", "Thumbs Up");

	if(item == -1) {
		menu.Display(client, MENU_TIME_FOREVER);
	} else {
		menu.DisplayAt(client, item, MENU_TIME_FOREVER);
	}*/
}

Action ConCommand_GT(int client, int args)
{
	if(playerinfo[client].animcode == animcode_default) {
		if(args < 1) {
			DiplayGesturesMenu(client);
			return Plugin_Handled;
		}

		char name[64];
		GetCmdArg(1, name, sizeof(name));


	} else {
		StringMap gestures = playerinfo[client].gestures;
		if(gestures == null) {
			ReplyToCommand(client, "[SM] This model has no gestures configured");
			return Plugin_Handled;
		}

		if(args < 1) {
			//DiplayPropGesturesMenu(client);
			return Plugin_Handled;
		}

		char name[64];
		GetCmdArg(1, name, sizeof(name));


	}

	return Plugin_Handled;
}

int MenuHandler_ModelTaunt(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		int ref = Playermodel_GetAnimEnt(param1);
		int entity = EntRefToEntIndex(ref);

		menu.GetItem(param2, tmpstr1, sizeof(tmpstr1));
		
		if(IsValidEntity(entity)) {
			int sequence = LookupSequenceCached(playerinfo[param1].seq_cache, entity, tmpstr1);
			if(sequence != -1) {
				if(TauntManager_DoTauntAnim(param1, entity, sequence, true, false)) {
					playeranim[param1].m_bCanAnimate = false;
				}
			}
		}

		DiplayTauntMenu(param1, menu.Selection);
	} else if(action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

void DiplayTauntMenu(int client, int item = -1)
{
	StringMap taunts = playerinfo[client].taunts;

	Handle style = GetMenuStyleHandle(MenuStyle_Default);

	Menu menu = CreateMenuEx(style, MenuHandler_ModelTaunt, MENU_ACTIONS_DEFAULT);
	menu.SetTitle("Taunt");

	StringMapSnapshot snapshot = taunts.Snapshot();

	char tmpstr3[64];

	for(int i = 0, len = snapshot.Length; i < len; ++i) {
		snapshot.GetKey(i, tmpstr1, sizeof(tmpstr1));

		taunts.GetString(tmpstr1, tmpstr3, sizeof(tmpstr3));

		menu.AddItem(tmpstr1, tmpstr3);
	}

	delete snapshot;

	if(item == -1) {
		menu.Display(client, MENU_TIME_FOREVER);
	} else {
		menu.DisplayAt(client, item, MENU_TIME_FOREVER);
	}
}

Action ConCommand_PT(int client, int args)
{
	StringMap taunts = playerinfo[client].taunts;
	if(taunts == null) {
		ReplyToCommand(client, "[SM] This model has no taunts configured");
		return Plugin_Handled;
	}

	DiplayTauntMenu(client);
	
	return Plugin_Handled;
}

Action ConCommand_PM(int client, int args)
{
	DisplayGroupMenu(client);

	return Plugin_Handled;
}
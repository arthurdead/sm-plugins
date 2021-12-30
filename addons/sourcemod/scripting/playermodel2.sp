#include <sourcemod>
#include <sdkhooks>
#include <dhooks>
#include <morecolors>
#if defined GAME_TF2
	#include <tf2items>
	#include <tf_econ_data>
#endif
#include <playermodel2>
#tryinclude <tauntmanager>
#tryinclude <sendproxy>
#include <teammanager_gameplay>

//#define DEBUG

#define INT_STR_MAX 4
#define MODEL_NAME_MAX 64
#define OVERRIDE_MAX 64
#define STEAMID_MAX 64

#define PM2_CON_PREFIX "[PM2] "
#define PM2_CHAT_PREFIX "{dodgerblue}[GMM]{default} "

#if defined GAME_TF2
	#define CLASS_NAME_MAX 10
	#define TF_CLASS_COUNT_ALL 10

	#define BIT_FOR_CLASS(%1) (1 << (view_as<int>(%1)-1))
#endif

#if defined GAME_TF2
	#define OBS_MODE_IN_EYE 4
#else
	#error
#endif

#define EF_BONEMERGE 0x001
#define EF_BONEMERGE_FASTCULL 0x080
#define EF_PARENT_ANIMATES 0x200
#define EF_NODRAW 0x020
#define EF_NOSHADOW 0x010
#define EF_NORECEIVESHADOW 0x040

#define playermodelslot_hack_all view_as<playermodelslot>(-1)

enum struct ConfigGroupInfo
{
	char name[MODEL_NAME_MAX];
	char override[OVERRIDE_MAX];
	char steamid[STEAMID_MAX];
	ArrayList models;
}

enum struct ConfigVariationInfo
{
	char name[MODEL_NAME_MAX];
	int skin;
	playermodelflags flags;
}

enum struct ConfigModelInfo
{
	char name[MODEL_NAME_MAX];
	char model[PLATFORM_MAX_PATH];
#if defined GAME_TF2
	TFClassType orig_class;
	int classes;
#endif
	playermodelflags flags;
	int bodygroup;
	int skin;
	ArrayList variations;
}

enum handledatafrom
{
	handledatafrom_unknown,
	handledatafrom_taunt_start,
	handledatafrom_taunt_end,
	handledatafrom_weaponswitch,
	handledatafrom_disguise_end,
	handledatafrom_spawn,
	handledatafrom_inventory,
	handledatafrom_equip,
};

enum cleardatafrom
{
	cleardatafrom_death,
	cleardatafrom_disconnect,
	cleardatafrom_remove,
	cleardatafrom_disguise_start,
	cleardatafrom_reapply,
};

#if defined GAME_TF2
static Handle dummy_item_view;
static Handle EquipWearable;
static Handle RecalculatePlayerBodygroups;
static int m_Shared_offset = -1;
static int m_flInvisibility_offset = -1;
static int m_iAttributeDefinitionIndex_offset = -1;
static ArrayList class_cache = null;
static TFClassType tempclass;
static TFClassType tmpplayerclass[MAXPLAYERS+1];
static bool taunting[MAXPLAYERS+1];
#endif

static int modelgameplay = -1;

static ArrayList modelinfos;
static StringMap modelinfoidmap;

static ArrayList groupinfos;

static char animation_override[PLATFORM_MAX_PATH];

static char player_model[MAXPLAYERS+1][PLATFORM_MAX_PATH];
static int player_skin[MAXPLAYERS+1] = {-1, ...};
static int player_bodygroup[MAXPLAYERS+1] = {-1, ...};
static int player_modelentity[MAXPLAYERS+1] = {INVALID_ENT_REFERENCE, ...};
static playermodelflags player_flags[MAXPLAYERS+1];
static TFClassType player_modelclass[MAXPLAYERS+1];

#if defined GAME_TF2
static void GetModelForPlayerClass(int client, char[] model, int length)
{
	TFClassType class = TF2_GetPlayerClass(client);
	GetModelForClass(class, model, length);
}

static void GetModelForClass(TFClassType class, char[] model, int length)
{
	switch(class)
	{
		case TFClass_Unknown: { strcopy(model, length, "models/error.mdl"); }
		case TFClass_Engineer: { strcopy(model, length, "models/player/engineer.mdl"); }
		case TFClass_Scout: { strcopy(model, length, "models/player/scout.mdl"); }
		case TFClass_Medic: { strcopy(model, length, "models/player/medic.mdl"); }
		case TFClass_Soldier: { strcopy(model, length, "models/player/soldier.mdl"); }
		case TFClass_Heavy: { strcopy(model, length, "models/player/heavy.mdl"); }
		case TFClass_DemoMan: { strcopy(model, length, "models/player/demo.mdl"); }
		case TFClass_Spy: { strcopy(model, length, "models/player/spy.mdl"); }
		case TFClass_Sniper: { strcopy(model, length, "models/player/sniper.mdl"); }
		case TFClass_Pyro: { strcopy(model, length, "models/player/pyro.mdl"); }
	}
}

static void GetArmModelForClass(TFClassType class, char[] model, int length)
{
	switch(class)
	{
		case TFClass_Unknown: { strcopy(model, length, "models/error.mdl"); }
		case TFClass_Engineer: { strcopy(model, length, "models/weapons/c_models/c_engineer_arms.mdl"); }
		case TFClass_Scout: { strcopy(model, length, "models/weapons/c_models/c_scout_arms.mdl"); }
		case TFClass_Medic: { strcopy(model, length, "models/weapons/c_models/c_medic_arms.mdl"); }
		case TFClass_Soldier: { strcopy(model, length, "models/weapons/c_models/c_soldier_arms.mdl"); }
		case TFClass_Heavy: { strcopy(model, length, "models/weapons/c_models/c_heavy_arms.mdl"); }
		case TFClass_DemoMan: { strcopy(model, length, "models/weapons/c_models/c_demo_arms.mdl"); }
		case TFClass_Spy: { strcopy(model, length, "models/weapons/c_models/c_spy_arms.mdl"); }
		case TFClass_Sniper: { strcopy(model, length, "models/weapons/c_models/c_sniper_arms.mdl"); }
		case TFClass_Pyro: { strcopy(model, length, "models/weapons/c_models/c_pyro_arms.mdl"); }
	}
}
#endif

int native_pm2_getflags(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	return player_flags[client];
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("playermodel2");
	CreateNative("pm2_getflags", native_pm2_getflags);
	return APLRes_Success;
}

static void unload_models()
{
	OnPluginEnd();

	ConfigGroupInfo groupinfo;

	int len = groupinfos.Length;
	for(int i = 0; i < len; ++i) {
		groupinfos.GetArray(i, groupinfo, sizeof(ConfigGroupInfo));

		delete groupinfo.models;
	}

	delete modelinfoidmap;

	ConfigModelInfo modelinfo;

	len = modelinfos.Length;
	for(int i = 0; i < len; ++i) {
		modelinfos.GetArray(i, modelinfo, sizeof(ConfigModelInfo));

		delete modelinfo.variations;
	}

	delete modelinfos;
}

#if defined GAME_TF2
static bool parse_classes_str(int &classes, const char[] str, const char[] modelname)
{
	if(StrEqual(str, "all") || StrEqual(str, "any")) {
		classes = 0;
		return true;
	}

	char classnames[TF_CLASS_COUNT_ALL][CLASS_NAME_MAX];

	int num = ExplodeString(str, "|", classnames, TF_CLASS_COUNT_ALL, CLASS_NAME_MAX);
	for(int i = 0; i < num; ++i) {
		if(StrEqual(classnames[i], "scout")) {
			classes |= BIT_FOR_CLASS(TFClass_Scout);
		} else if(StrEqual(classnames[i], "sniper")) {
			classes |= BIT_FOR_CLASS(TFClass_Sniper);
		} else if(StrEqual(classnames[i], "soldier")) {
			classes |= BIT_FOR_CLASS(TFClass_Soldier);
		} else if(StrEqual(classnames[i], "demoman")) {
			classes |= BIT_FOR_CLASS(TFClass_DemoMan);
		} else if(StrEqual(classnames[i], "medic")) {
			classes |= BIT_FOR_CLASS(TFClass_Medic);
		} else if(StrEqual(classnames[i], "heavy")) {
			classes |= BIT_FOR_CLASS(TFClass_Heavy);
		} else if(StrEqual(classnames[i], "pyro")) {
			classes |= BIT_FOR_CLASS(TFClass_Pyro);
		} else if(StrEqual(classnames[i], "spy")) {
			classes |= BIT_FOR_CLASS(TFClass_Spy);
		} else if(StrEqual(classnames[i], "engineer")) {
			classes |= BIT_FOR_CLASS(TFClass_Engineer);
		} else {
			LogError(PM2_CON_PREFIX ... "model %s has unknown class %s", modelname, classnames[i]);
			return false;
		}
	}
	return true;
}
#endif

#define FLAGS_NUM 7
#define FLAGS_MAX 13

#define REMOVE_OR_ADD_FLAG(%1,%2) \
	if(remove) { \
		%1 &= ~(%2); \
	} else { \
		%1 |= (%2); \
	}

static playermodelflags flagsstr_to_flags(const char[] str, playermodelflags def = playermodel_noflags)
{
	char flagstrs[FLAGS_NUM][FLAGS_MAX];
	int num = ExplodeString(str, "|", flagstrs, FLAGS_NUM, FLAGS_MAX);

	playermodelflags flags = def;

	for(int i = 0; i < num; ++i) {
		bool remove = (flagstrs[i][0] == '~');
		int start = (remove ? 1 : 0);

		if(StrEqual(flagstrs[i][start], "hidehats")) {
			REMOVE_OR_ADD_FLAG(flags, playermodel_hidehats)
		} else if(StrEqual(flagstrs[i][start], "nogameplay")) {
			REMOVE_OR_ADD_FLAG(flags, playermodel_nogameplay)
		} else if(StrEqual(flagstrs[i][start], "noweapons")) {
			if(remove) {
				flags &= ~(playermodel_noweapons);
			} else {
				flags |= playermodel_noweapons|playermodel_nogameplay;
			}
		} else if(StrEqual(flagstrs[i][start], "hideweapons")) {
			REMOVE_OR_ADD_FLAG(flags, playermodel_hideweapons)
		} else if(StrEqual(flagstrs[i][start], "alwaysmerge")) {
			REMOVE_OR_ADD_FLAG(flags, playermodel_alwaysmerge)
		} else if(StrEqual(flagstrs[i][start], "nevermerge")) {
			REMOVE_OR_ADD_FLAG(flags, playermodel_nevermerge)
		}
	}

	return flags;
}

#if defined GAME_TF2
	#define BODYGROUP_MAX 16
	#define BODYGROUP_NUM 23

	#define BODYGROUP_SCOUT_HAT (1 << 0)
	#define BODYGROUP_SCOUT_HEADPHONES (1 << 1)
	#define BODYGROUP_SCOUT_SHOESSOCKS (1 << 2)
	#define BODYGROUP_SCOUT_DOGTAGS (1 << 3)
	#define BODYGROUP_SOLDIER_ROCKET (1 << 0)
	#define BODYGROUP_SOLDIER_HELMET (1 << 1)
	#define BODYGROUP_SOLDIER_MEDAL (1 << 2)
	#define BODYGROUP_SOLDIER_GRENADES (1 << 3)
	#define BODYGROUP_PYRO_HEAD (1 << 0)
	#define BODYGROUP_PYRO_GRENADES (1 << 1)
	#define BODYGROUP_DEMO_SMILE (1 << 0)
	#define BODYGROUP_DEMO_SHOES (1 << 1)
	#define BODYGROUP_HEAVY_HANDS (1 << 0)
	#define BODYGROUP_ENGINEER_HELMET (1 << 0)
	#define BODYGROUP_ENGINEER_ARM (1 << 1)
	#define BODYGROUP_MEDIC_BACKPACK (1 << 0)
	#define BODYGROUP_SNIPER_ARROWS (1 << 0)
	#define BODYGROUP_SNIPER_HAT (1 << 1)
	#define BODYGROUP_SNIPER_BULLETS (1 << 2)
	#define BODYGROUP_SPY_MASK (1 << 0)
	#define BODYGROUP_MERASMUS_BOOK (1 << 1)
	#define BODYGROUP_MERASMUS_STAFF (1 << 3)
#else
	#error
#endif

static int bodygroupstr_to_bodygroup(const char[] str)
{
	char flagstrs[BODYGROUP_NUM][BODYGROUP_MAX];
	int num = ExplodeString(str, "|", flagstrs, BODYGROUP_NUM, BODYGROUP_MAX);

	int bodygroup = 0;

	for(int i = 0; i < num; ++i) {
	#if defined GAME_TF2
		if(StrEqual(flagstrs[i], "scout_hat")) {
			bodygroup |= BODYGROUP_SCOUT_HAT;
		} else if(StrEqual(flagstrs[i], "scout_headphones")) {
			bodygroup |= BODYGROUP_SCOUT_HEADPHONES;
		} else if(StrEqual(flagstrs[i], "scout_shoe_socks")) {
			bodygroup |= BODYGROUP_SCOUT_SHOESSOCKS;
		} else if(StrEqual(flagstrs[i], "scout_dog_tags")) {
			bodygroup |= BODYGROUP_SCOUT_DOGTAGS;
		} else if(StrEqual(flagstrs[i], "soldier_rockers")) {
			bodygroup |= BODYGROUP_SOLDIER_ROCKET;
		} else if(StrEqual(flagstrs[i], "soldier_helmet")) {
			bodygroup |= BODYGROUP_SOLDIER_HELMET;
		} else if(StrEqual(flagstrs[i], "soldier_medal")) {
			bodygroup |= BODYGROUP_SOLDIER_MEDAL;
		} else if(StrEqual(flagstrs[i], "soldier_grenades")) {
			bodygroup |= BODYGROUP_SOLDIER_GRENADES;
		} else if(StrEqual(flagstrs[i], "pyro_head")) {
			bodygroup |= BODYGROUP_PYRO_HEAD;
		} else if(StrEqual(flagstrs[i], "pyro_grenades")) {
			bodygroup |= BODYGROUP_PYRO_GRENADES;
		} else if(StrEqual(flagstrs[i], "demo_smile")) {
			bodygroup |= BODYGROUP_DEMO_SMILE;
		} else if(StrEqual(flagstrs[i], "demo_shoes")) {
			bodygroup |= BODYGROUP_DEMO_SHOES;
		} else if(StrEqual(flagstrs[i], "heavy_hands")) {
			bodygroup |= BODYGROUP_HEAVY_HANDS;
		} else if(StrEqual(flagstrs[i], "engineer_helmet")) {
			bodygroup |= BODYGROUP_ENGINEER_HELMET;
		} else if(StrEqual(flagstrs[i], "engineer_arm")) {
			bodygroup |= BODYGROUP_ENGINEER_ARM;
		} else if(StrEqual(flagstrs[i], "medic_backpack")) {
			bodygroup |= BODYGROUP_MEDIC_BACKPACK;
		} else if(StrEqual(flagstrs[i], "sniper_arrows")) {
			bodygroup |= BODYGROUP_SNIPER_ARROWS;
		} else if(StrEqual(flagstrs[i], "sniper_hat")) {
			bodygroup |= BODYGROUP_SNIPER_HAT;
		} else if(StrEqual(flagstrs[i], "sniper_bullets")) {
			bodygroup |= BODYGROUP_SNIPER_BULLETS;
		} else if(StrEqual(flagstrs[i], "spy_mask")) {
			bodygroup |= BODYGROUP_SPY_MASK;
		} else if(StrEqual(flagstrs[i], "merasmus_book")) {
			bodygroup |= BODYGROUP_MERASMUS_BOOK;
		} else if(StrEqual(flagstrs[i], "merasmus_staff")) {
			bodygroup |= BODYGROUP_MERASMUS_STAFF;
		} else
	#endif
		{
			bodygroup |= StringToInt(flagstrs[i]);
		}
	}

	return bodygroup;
}

void parse_models_kv(const char[] path, ConfigGroupInfo groupinfo, playermodelflags flags)
{
	KeyValues kvModels = new KeyValues("Playermodels");
	kvModels.ImportFromFile(path);

	if(kvModels.GotoFirstSubKey()) {
		groupinfo.models = new ArrayList();

		ConfigModelInfo modelinfo;

		char classesvalue[CLASS_NAME_MAX * TF_CLASS_COUNT_ALL];
		char flagsvalue[FLAGS_MAX * FLAGS_NUM];
		char intstr[INT_STR_MAX];
		char classname[CLASS_NAME_MAX];
		char bodygroupvalue[BODYGROUP_NUM * BODYGROUP_MAX];

		do {
			kvModels.GetSectionName(modelinfo.name, MODEL_NAME_MAX);

			kvModels.GetString("classes_whitelist", classesvalue, sizeof(classesvalue), "all");

			modelinfo.classes = 0;

			if(classesvalue[0] != '\0') {
				if(!parse_classes_str(modelinfo.classes, classesvalue, modelinfo.name)) {
					continue;
				}
			}

			kvModels.GetString("model", modelinfo.model, PLATFORM_MAX_PATH);

			kvModels.GetString("flags", flagsvalue, sizeof(flagsvalue), "");
			modelinfo.flags = flagsstr_to_flags(flagsvalue, flags);

			kvModels.GetString("bodygroup", bodygroupvalue, sizeof(bodygroupvalue), "");
			modelinfo.bodygroup = bodygroupstr_to_bodygroup(bodygroupvalue);

			kvModels.GetString("skin", intstr, INT_STR_MAX, "");
			modelinfo.skin = StringToInt(intstr);

			kvModels.GetString("original_class", classname, CLASS_NAME_MAX, "unknown");
			modelinfo.orig_class = TF2_GetClass(classname);

			int idx = modelinfos.PushArray(modelinfo, sizeof(ConfigModelInfo));

			modelinfoidmap.SetValue(modelinfo.name, idx);

			groupinfo.models.Push(idx);
		} while(kvModels.GotoNextKey());

		kvModels.GoBack();
	}

	delete kvModels;
}

static void load_models()
{
	modelinfos = new ArrayList(sizeof(ConfigModelInfo));
	modelinfoidmap = new StringMap();

	groupinfos = new ArrayList(sizeof(ConfigGroupInfo));

	char configpath[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, configpath, PLATFORM_MAX_PATH, "configs/playermodels2/groups.txt");
	KeyValues kvGroups = new KeyValues("Playermodels_groups");
	if(FileExists(configpath)) {
		kvGroups.ImportFromFile(configpath);

		if(kvGroups.GotoFirstSubKey()) {
			ConfigGroupInfo groupinfo;

			char flagsvalue[FLAGS_MAX * FLAGS_NUM];

			do {
				kvGroups.GetSectionName(groupinfo.name, MODEL_NAME_MAX);

				kvGroups.GetString("override", groupinfo.override, OVERRIDE_MAX);
				kvGroups.GetString("steamid", groupinfo.steamid, STEAMID_MAX);

				BuildPath(Path_SM, configpath, PLATFORM_MAX_PATH, "configs/playermodels2/%s.txt", groupinfo.name);
				if(FileExists(configpath)) {
					kvGroups.GetString("flags", flagsvalue, sizeof(flagsvalue), "");
					playermodelflags flags = flagsstr_to_flags(flagsvalue);

					parse_models_kv(configpath, groupinfo, flags);
				}

				groupinfos.PushArray(groupinfo, sizeof(ConfigGroupInfo));
			} while(kvGroups.GotoNextKey());

			kvGroups.GoBack();
		}
	}

	delete kvGroups;
}

public void OnPluginStart()
{
	GameData gamedata = new GameData("playermodel2");
	if(gamedata == null) {
		SetFailState("Gamedata not found.");
		return;
	}

#if defined GAME_TF2
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CBasePlayer::EquipWearable");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	EquipWearable = EndPrepSDKCall();
	if(EquipWearable == null) {
		SetFailState("Failed to create SDKCall for CBasePlayer::EquipWearable.");
		delete gamedata;
		return;
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayerShared::RecalculatePlayerBodygroups");
	RecalculatePlayerBodygroups = EndPrepSDKCall();
	if(RecalculatePlayerBodygroups == null) {
		SetFailState("Failed to create SDKCall for CTFPlayerShared::RecalculatePlayerBodygroups.");
		delete gamedata;
		return;
	}

	m_iAttributeDefinitionIndex_offset = gamedata.GetOffset("CEconItemView::m_iAttributeDefinitionIndex");
	if(m_iAttributeDefinitionIndex_offset == -1) {
		SetFailState("Failed to get CEconItemView::m_iAttributeDefinitionIndex offset from gamedata");
		return;
	}

	DynamicDetour tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::PlayTauntSceneFromItem");
	if(!tmp || !tmp.Enable(Hook_Pre, PlayTauntSceneFromItem)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::PlayTauntSceneFromItem");
		delete gamedata;
		return;
	}
	if(!tmp.Enable(Hook_Post, PlayTauntSceneFromItem_post)) {
		SetFailState("Failed to enable post detour for CTFPlayer::PlayTauntSceneFromItem");
		delete gamedata;
		return;
	}

	tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::PlayTauntOutroScene");
	if(!tmp || !tmp.Enable(Hook_Pre, PlayTauntOutroScene)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::PlayTauntOutroScene");
		delete gamedata;
		return;
	}
	if(!tmp.Enable(Hook_Post, PlayTauntOutroScene_post)) {
		SetFailState("Failed to enable post detour for CTFPlayer::PlayTauntOutroScene");
		delete gamedata;
		return;
	}

	tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::EndLongTaunt");
	if(!tmp || !tmp.Enable(Hook_Pre, EndLongTaunt)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::EndLongTaunt");
		delete gamedata;
		return;
	}
	if(!tmp.Enable(Hook_Post, EndLongTaunt_post)) {
		SetFailState("Failed to enable post detour for CTFPlayer::EndLongTaunt");
		delete gamedata;
		return;
	}
#endif

	delete gamedata;

	HookEvent("player_death", player_death);
	HookEvent("player_spawn", player_spawn);

	modelgameplay = TeamManager_NewGameplayGroup(Gameplay_Friendly);

#if defined GAME_TF2
	HookEvent("post_inventory_application", post_inventory_application);

	dummy_item_view = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
	TF2Items_SetClassname(dummy_item_view, "tf_wearable");
	TF2Items_SetItemIndex(dummy_item_view, 0);
	TF2Items_SetQuality(dummy_item_view, 0);
	TF2Items_SetLevel(dummy_item_view, 0);
	TF2Items_SetNumAttributes(dummy_item_view, 0);

	class_cache = new ArrayList();

	m_Shared_offset = FindSendPropInfo("CTFPlayer", "m_Shared");
	m_flInvisibility_offset = FindSendPropInfo("CTFPlayer", "m_flInvisChangeCompleteTime") - 8;
#endif

	load_models();

	RegAdminCmd("sm_rpm", sm_rpm, ADMFLAG_ROOT);

	RegConsoleCmd("sm_pm", sm_pm);

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

static void clean_file_path(char[] str)
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
	ConfigModelInfo modelinfo;

	char filepath[PLATFORM_MAX_PATH];

	int len = modelinfos.Length;
	for(int i = 0; i < len; ++i) {
		modelinfos.GetArray(i, modelinfo, sizeof(ConfigModelInfo));

		if(modelinfo.model[0] != '\0') {
			PrecacheModel(modelinfo.model);
		}

		Format(filepath, PLATFORM_MAX_PATH, "%s.dep", modelinfo.model);
		if(FileExists(filepath, true)) {
			File file = OpenFile(filepath, "r", true);

			while(!file.EndOfFile()) {
				file.ReadLine(filepath, PLATFORM_MAX_PATH);

				clean_file_path(filepath);

				AddFileToDownloadsTable(filepath);
			}

			delete file;
		}
	}
}

static Action sm_rpm(int client, int args)
{
	unload_models();
	load_models();

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
			handle_playerdata(i, playermodelslot_hack_all, handledatafrom_equip);

			int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
			player_weaponswitchpost(client, weapon);
		}
	}

	return Plugin_Handled;
}

static void unequip_model(int client)
{
	clear_playerdata(client, playermodelslot_hack_all, cleardatafrom_remove);

	if(player_flags[client] & playermodel_nogameplay) {
		TeamManager_RemovePlayerFromGameplayGroup(client, modelgameplay);
	}

	player_model[client][0] = '\0';
	player_skin[client] = -1;
	player_bodygroup[client] = -1;
	player_flags[client] = playermodel_noflags;
	player_modelclass[client] = TFClass_Unknown;
}

static void equip_model(int client, ConfigModelInfo modelinfo)
{
	if(modelinfo.model[0] != '\0') {
		strcopy(player_model[client], PLATFORM_MAX_PATH, modelinfo.model);
	}

	if(modelinfo.skin != -1) {
		player_skin[client] = modelinfo.skin;
	}

	if(modelinfo.bodygroup != -1) {
		player_bodygroup[client] = modelinfo.bodygroup;
	}

	player_flags[client] = modelinfo.flags;

	player_modelclass[client] = modelinfo.orig_class;

	if(player_flags[client] & playermodel_nogameplay) {
		TeamManager_AddPlayerToGameplayGroup(client, modelgameplay);
	}

	handle_playerdata(client, playermodelslot_hack_all, handledatafrom_equip);

	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	player_weaponswitchpost(client, weapon);
}

int menuhandler_model(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		if(TF2_IsPlayerInCondition(param1, TFCond_Taunting)) {
			CPrintToChat(param1, PM2_CHAT_PREFIX ... "can't change model mid taunt");
			return 0;
		}

		char intstr[INT_STR_MAX];
		menu.GetItem(param2, intstr, INT_STR_MAX);
		int idx = StringToInt(intstr);

		if(idx == -1) {
			unequip_model(param1);
		} else {
			ConfigModelInfo modelinfo;
			modelinfos.GetArray(idx, modelinfo, sizeof(ConfigModelInfo));

			equip_model(param1, modelinfo);
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}

	return 0;
}

int menuhandler_group(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		if(TF2_IsPlayerInCondition(param1, TFCond_Taunting)) {
			CPrintToChat(param1, PM2_CHAT_PREFIX ... "can't change model mid taunt");
			return 0;
		}

		char intstr[INT_STR_MAX];
		menu.GetItem(param2, intstr, INT_STR_MAX);
		int idx = StringToInt(intstr);

		if(idx == -1) {
			unequip_model(param1);
		} else {
			ConfigGroupInfo groupinfo;
			groupinfos.GetArray(idx, groupinfo, sizeof(ConfigGroupInfo));

			Menu mmenu = CreateMenu(menuhandler_model);
			mmenu.SetTitle("Models");

			mmenu.AddItem("-1", "remove");

			ConfigModelInfo modelinfo;

			int len = groupinfo.models.Length;
			for(int i = 0; i < len; ++i) {
				idx = groupinfo.models.Get(i);

				modelinfos.GetArray(idx, modelinfo, sizeof(ConfigModelInfo));

				IntToString(idx, intstr, INT_STR_MAX);
				mmenu.AddItem(intstr, modelinfo.name);
			}

			mmenu.Display(param1, MENU_TIME_FOREVER);
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}

	return 0;
}

static Action sm_pm(int client, int args)
{
	if(TF2_IsPlayerInCondition(client, TFCond_Taunting)) {
		CPrintToChat(client, PM2_CHAT_PREFIX ... "can't change model mid taunt");
		return Plugin_Handled;
	}

	ConfigGroupInfo groupinfo;

	char clientsteam[STEAMID_MAX];

	Menu menu = CreateMenu(menuhandler_group);
	menu.SetTitle("Groups");

	menu.AddItem("-1", "remove");

	char intstr[INT_STR_MAX];

	int len = groupinfos.Length;
	for(int i = 0; i < len; ++i) {
		groupinfos.GetArray(i, groupinfo, sizeof(ConfigGroupInfo));

		if(groupinfo.override[0] != '\0') {
			if(!CheckCommandAccess(client, groupinfo.override, ADMFLAG_GENERIC)) {
				continue;
			}
		}

		if(groupinfo.steamid[0] != '\0') {
			if(GetClientAuthId(client, AuthId_SteamID64, clientsteam, STEAMID_MAX)) {
				if(!StrEqual(clientsteam, groupinfo.steamid)) {
					continue;
				}
			} else {
				continue;
			}
		}

		IntToString(i, intstr, INT_STR_MAX);
		menu.AddItem(intstr, groupinfo.name);
	}

	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

static void frame_spawn(int client)
{
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	player_weaponswitchpost(client, weapon);
}

static void player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	handle_playerdata(client, playermodelslot_hack_all, handledatafrom_spawn);

	RequestFrame(frame_spawn, client);
}

static void player_death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
#if defined GAME_TF2
	int flags = event.GetInt("death_flags");

	if(!(flags & TF_DEATHFLAG_DEADRINGER))
#endif
	{
		clear_playerdata(client, playermodelslot_hack_all, cleardatafrom_death);
	}
}

#if defined GAME_TF2
static bool class_to_classname(TFClassType type, char[] name, int length)
{
	switch(type)
	{
		case TFClass_Scout: { strcopy(name, length, "scout"); return true; }
		case TFClass_Soldier: { strcopy(name, length, "soldier"); return true; }
		case TFClass_Sniper: { strcopy(name, length, "sniper"); return true; }
		case TFClass_Spy: { strcopy(name, length, "spy"); return true; }
		case TFClass_Medic: { strcopy(name, length, "medic"); return true; }
		case TFClass_DemoMan: { strcopy(name, length, "demoman"); return true; }
		case TFClass_Pyro: { strcopy(name, length, "pyro"); return true; }
		case TFClass_Engineer: { strcopy(name, length, "engineer"); return true; }
		case TFClass_Heavy: { strcopy(name, length, "heavy"); return true; }
	}

	return false;
}

static ArrayList get_classes_for_taunt(int id)
{
	ArrayList ret = new ArrayList();

	char classname[CLASS_NAME_MAX];
	char key[17 + CLASS_NAME_MAX];
	char intstr[INT_STR_MAX];

	for(TFClassType i = TFClass_Scout; i <= TFClass_Engineer; ++i) {
		class_to_classname(i, classname, CLASS_NAME_MAX);

		FormatEx(key, sizeof(key), "used_by_classes/%s", classname);

		TF2Econ_GetItemDefinitionString(id, key, intstr, INT_STR_MAX);

		if(StrEqual(intstr, "1")) {
			ret.Push(i);
		}
	}

	return ret;
}

#if defined _tauntmanager_included_
public Action TauntManager_ApplyTauntModel(int client, const char[] tauntModel, bool hasBonemergeSupport)
{
	if(hasBonemergeSupport) {
		strcopy(animation_override, PLATFORM_MAX_PATH, tauntModel);
		handle_playerdata(client, playermodelslot_animation, handledatafrom_taunt_start);
		return Plugin_Handled;
	} else {
		//TODO!!! support for non-bonemerge
		return Plugin_Continue;
	}
}

public Action TauntManager_RemoveTauntModel(int client)
{
	handle_playerdata(client, playermodelslot_animation, handledatafrom_taunt_end);
	return Plugin_Handled;
}
#endif

public MRESReturn PlayTauntSceneFromItem(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	int m_iAttributeDefinitionIndex = -1;
	if(!hParams.IsNull(1)) {
		m_iAttributeDefinitionIndex = hParams.GetObjectVar(1, m_iAttributeDefinitionIndex_offset, ObjectValueType_Int);
	}

	tempclass = TFClass_Unknown;
	tmpplayerclass[pThis] = TFClass_Unknown;
	taunting[pThis] = true;

	bool valid = true;

	if(m_iAttributeDefinitionIndex != -1) {
		TFClassType class = TF2_GetPlayerClass(pThis);

		bool found = false;

		ArrayList classes = get_classes_for_taunt(m_iAttributeDefinitionIndex);
		int len = classes.Length;
		for(int i = 0; i < len; ++i) {
			TFClassType supported = classes.Get(i);
			if(class == supported) {
				found = true;
				break;
			}
		}

		if(!found && len > 0) {
			if(class == TFClass_Spy) {
				if(TF2_IsPlayerInCondition(pThis, TFCond_Cloaked) ||
					TF2_IsPlayerInCondition(pThis, TFCond_CloakFlicker) ||
					TF2_IsPlayerInCondition(pThis, TFCond_Stealthed) ||
					TF2_IsPlayerInCondition(pThis, TFCond_StealthedUserBuffFade) ||
					TF2_IsPlayerInCondition(pThis, TFCond_Disguised) ||
					TF2_IsPlayerInCondition(pThis, TFCond_Disguising)) {
					valid = false;
				}
			}

			if(valid) {
				TFClassType desiredclass = classes.Get(GetRandomInt(0, len-1));
				GetModelForClass(desiredclass, animation_override, PLATFORM_MAX_PATH);
				handle_playerdata(pThis, playermodelslot_animation, handledatafrom_taunt_start);
				TF2_SetPlayerClass(pThis, desiredclass);
				tempclass = class;
				tmpplayerclass[pThis] = desiredclass;
			}
		}

		delete classes;
	}

	if(!valid) {
		hReturn.Value = false;
		return MRES_Supercede;
	} else {
		return MRES_Ignored;
	}
}

static MRESReturn EndLongTaunt(int pThis, DHookReturn hReturn)
{
	if(tmpplayerclass[pThis] != TFClass_Unknown) {
		tempclass = TF2_GetPlayerClass(pThis);
		TF2_SetPlayerClass(pThis, tmpplayerclass[pThis]);
	}
	return MRES_Ignored;
}

static MRESReturn PlayTauntOutroScene(int pThis, DHookReturn hReturn)
{
	if(tmpplayerclass[pThis] != TFClass_Unknown) {
		tempclass = TF2_GetPlayerClass(pThis);
		TF2_SetPlayerClass(pThis, tmpplayerclass[pThis]);
	}
	tmpplayerclass[pThis] = TFClass_Unknown;
	return MRES_Ignored;
}

static MRESReturn PlayTauntSceneFromItem_post(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if(tempclass != TFClass_Unknown) {
		TF2_SetPlayerClass(pThis, tempclass);
	}
	tempclass = TFClass_Unknown;
	return MRES_Ignored;
}

static MRESReturn EndLongTaunt_post(int pThis, DHookReturn hReturn)
{
	if(tempclass != TFClass_Unknown) {
		TF2_SetPlayerClass(pThis, tempclass);
	}
	tempclass = TFClass_Unknown;
	return MRES_Ignored;
}

static MRESReturn PlayTauntOutroScene_post(int pThis, DHookReturn hReturn)
{
	if(tempclass != TFClass_Unknown) {
		TF2_SetPlayerClass(pThis, tempclass);
	}
	tempclass = TFClass_Unknown;
	return MRES_Ignored;
}

public void TF2_OnConditionAdded(int client, TFCond condition)
{
	switch(condition) {
		case TFCond_Disguised:
		{ clear_playerdata(client, playermodelslot_animation, cleardatafrom_disguise_start); }
	}
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	switch(condition) {
		case TFCond_Disguised:
		{ handle_playerdata(client, playermodelslot_animation, handledatafrom_disguise_end); }
		case TFCond_Taunting: {
			taunting[client] = false;

			handle_playerdata(client, playermodelslot_animation, handledatafrom_taunt_end);

			int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
			player_weaponswitchpost(client, weapon);
		}
	}
}

void frame_inventory(int client)
{
	handle_playerdata(client, playermodelslot_animation, handledatafrom_inventory);

	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	player_weaponswitchpost(client, weapon);
}

void post_inventory_application(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	RequestFrame(frame_inventory, client);
}

static const TFClassType classes_withsecondaryshotgun[] =
{
	TFClass_Soldier,
	TFClass_Heavy,
	TFClass_Pyro,
};

static const TFClassType classes_withsecondarypistol[] =
{
	TFClass_Engineer,
	TFClass_Scout,
};

static bool class_shotgun_is_secondary(TFClassType class)
{
	for(int i = sizeof(classes_withsecondaryshotgun)-1; i--;) {
		if(classes_withsecondaryshotgun[i] == class) {
			return true;
		}
	}

	return false;
}

static bool class_pistol_is_secondary(TFClassType class)
{
	for(int i = sizeof(classes_withsecondarypistol)-1; i--;) {
		if(classes_withsecondarypistol[i] == class) {
			return true;
		}
	}

	return false;
}

static bool is_pistol_and_secondary(const char[] classname)
{
	return (StrEqual(classname, "tf_weapon_handgun_scout_secondary") ||
			StrEqual(classname, "tf_weapon_pistol"))
}

static bool is_shotgun_and_secondary(const char[] classname)
{
	if(StrEqual(classname, "tf_weapon_shotgun_primary") ||
		StrEqual(classname, "tf_weapon_shotgun_building_rescue")) {
		return false;
	} else {
		return (StrContains(classname, "tf_weapon_shotgun") != -1);
	}
}

static TFClassType get_class_for_weapon(int weapon, int item, TFClassType class)
{
	int idx = class_cache.FindValue(item);
	if(idx != -1) {
		ArrayList tmp = class_cache.Get(++idx);
		int len = tmp.Length;
		for(int i = len-1; i--;) {
			TFClassType it = tmp.Get(i);
			if(it == class) {
				return it;
			}
		}
		return tmp.Get(GetRandomInt(0, len-1));
	} else {
		ArrayList tmp = new ArrayList();

		TFClassType it = TFClass_Unknown;

		char classname[64];
		GetEntityClassname(weapon, classname, sizeof(classname));

		bool secondshot = is_shotgun_and_secondary(classname);
		if(secondshot) {
			for(int i = sizeof(classes_withsecondaryshotgun)-1; i--;) {
				tmp.Push(classes_withsecondaryshotgun[i]);
			}
		}

		bool secondpistol = is_pistol_and_secondary(classname);
		if(secondpistol) {
			for(int i = sizeof(classes_withsecondarypistol)-1; i--;) {
				tmp.Push(classes_withsecondarypistol[i]);
			}
		}

		for(int i = TF_CLASS_COUNT_ALL; --i;) {
			TFClassType icls = view_as<TFClassType>(i);

			if(secondshot && class_shotgun_is_secondary(icls) ||
				secondpistol && class_pistol_is_secondary(icls)) {
				if(icls == class) {
					it = icls;
				}
				continue;
			}

			int slot = TF2Econ_GetItemLoadoutSlot(item, icls);
			if(slot != -1) {
				tmp.Push(icls);
				if(icls == class) {
					it = icls;
				}
			}
		}

		int len = tmp.Length;
		if(len > 0) {
			class_cache.Push(item);
			class_cache.Push(tmp);
		} else {
			delete tmp;
			len = 0;
		}

		if(it != TFClass_Unknown) {
			return it;
		} else {
			if(len > 0) {
				return tmp.Get(GetRandomInt(0, len-1));
			} else {
				return TFClass_Unknown;
			}
		}
	}
}
#endif

static void player_weaponswitchpost(int client, int weapon)
{
#if defined GAME_TF2
	if(taunting[client] || TF2_IsPlayerInCondition(client, TFCond_Taunting)) {
		return;
	}

	TFClassType weapon_class = TFClass_Unknown;
	TFClassType player_class = TF2_GetPlayerClass(client);

	if(IsValidEntity(weapon)) {
		int m_iItemDefinitionIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
		int slot = TF2Econ_GetItemLoadoutSlot(m_iItemDefinitionIndex, player_class);
		int wepinslot = GetPlayerWeaponSlot(client, slot);

		if(slot == -1 || wepinslot != weapon) {
			weapon_class = get_class_for_weapon(weapon, m_iItemDefinitionIndex, player_class);
		}
	}

	if(weapon_class != TFClass_Unknown && weapon_class != player_class) {
		GetModelForClass(weapon_class, animation_override, PLATFORM_MAX_PATH);
		handle_playerdata(client, playermodelslot_animation, handledatafrom_weaponswitch);
	} else {
		handle_playerdata(client, playermodelslot_animation, handledatafrom_weaponswitch);
	}
#endif
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			unequip_model(i);
			OnClientDisconnect(i);
		}
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_PostThinkPost, player_postthinkpost);
	SDKHook(client, SDKHook_WeaponSwitchPost, player_weaponswitchpost);
}

static void delete_playermodelentity(int client)
{
	if(player_modelentity[client] != INVALID_ENT_REFERENCE) {
		int entity = EntRefToEntIndex(player_modelentity[client]);
		player_modelentity[client] = INVALID_ENT_REFERENCE;
		if(!IsValidEntity(entity)) {
			return;
		}
	#if defined GAME_TF2
		char classname[21];
		GetEntityClassname(entity, classname, sizeof(classname));
		if(StrEqual(classname, "playermodel_wearable")) {
			TF2_RemoveWearable(client, entity);
		}
	#endif
		AcceptEntityInput(entity, "ClearParent");
		RemoveEntity(entity);
	}
}

public void OnClientDisconnect(int client)
{
	delete_playermodelentity(client);

#if defined GAME_TF2
	tmpplayerclass[client] = TFClass_Unknown;
	taunting[client] = false;
#endif

	player_model[client][0] = '\0';
	player_skin[client] = -1;
	player_bodygroup[client] = -1;
	player_flags[client] = playermodel_noflags;
}

#if defined GAME_TF2
int calc_spy_alpha(int client)
{
	if(!TF2_IsPlayerInCondition(client, TFCond_Disguised)) {
		float invis = GetEntDataFloat(client, m_flInvisibility_offset);
		if(invis > 0.0) {
			invis = 1.0 - invis;
			int a = RoundToCeil(255 * invis);
			if(a < 0) {
				a = 0;
			}
			if(a > 255) {
				a = 255;
			}
			return a;
		}
	}
	return -1;
}
#endif

static void player_postthinkpost(int client)
{
	if(player_modelentity[client] == INVALID_ENT_REFERENCE) {
		return;
	}

	int entity = EntRefToEntIndex(player_modelentity[client]);
	if(!IsValidEntity(entity)) {
		player_modelentity[client] = INVALID_ENT_REFERENCE;
		return;
	}

	int r = 255;
	int g = 255;
	int b = 255;
	int a = 255;
	GetEntityRenderColor(client, r, g, b, a);

#if defined GAME_TF2
	if(TF2_GetPlayerClass(client) == TFClass_Spy) {
		int mod = calc_spy_alpha(client);
		if(mod != -1 && mod < a) {
			a = mod;
		}
	}
#endif

	SetEntityRenderColor(entity, r, g, b, a);

	SetEntityRenderMode(client, RENDER_NONE);
}

#if defined _SENDPROXYMANAGER_INC_
Action proxy_renderclr(int iEntity, const char[] cPropName, int &iValue, int iElement, int iClient)
{
	if(iClient == iEntity) {
		if(!TF2_IsPlayerInCondition(iEntity, TFCond_Disguised)) {
			iValue = 0;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

Action proxy_rendermode(int iEntity, const char[] cPropName, int &iValue, int iElement, int iClient)
{
	if(iClient == iEntity) {
		iValue = view_as<int>(RENDER_TRANSCOLOR);
		return Plugin_Changed;
	}

	return Plugin_Continue;
}
#endif

#if defined GAME_TF2
static void set_custom_model(int client, const char[] model)
{
	SetVariantString(model);
	AcceptEntityInput(client, "SetCustomModel");
	SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);

	SetVariantBool(true);
	AcceptEntityInput(client, "SetCustomModelRotates");

	SetVariantBool(true);
	AcceptEntityInput(client, "SetCustomModelVisibleToSelf");
}

static void clear_custommodel(int client)
{
	SetVariantString("");
	AcceptEntityInput(client, "SetCustomModel");
	SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 0);
}
#endif

static void clear_playerdata(int client, playermodelslot which, cleardatafrom from, handledatafrom reapply_from = handledatafrom_unknown)
{
	//TODO!! optimize using cleardatafrom and handledatafrom

	switch(which) {
		case playermodelslot_hack_all: {
			clear_playerdata(client, playermodelslot_animation, from);
			clear_playerdata(client, playermodelslot_skin, from);
			clear_playerdata(client, playermodelslot_bodygroup, from);
		}
		case playermodelslot_skin: {
		#if defined GAME_TF2
			SetEntProp(client, Prop_Send, "m_bForcedSkin", false);
			SetEntProp(client, Prop_Send, "m_nForcedSkin", 0);
		#endif
		}
		case playermodelslot_bodygroup: {
		#if defined GAME_TF2
			Address player_addr = GetEntityAddress(client);

			Address m_Shared = (player_addr + view_as<Address>(m_Shared_offset));
			SDKCall(RecalculatePlayerBodygroups, m_Shared);

			Event event = CreateEvent("post_inventory_application");
			event.SetInt("userid", GetClientUserId(client));
			event.FireToClient(client);
			event.Cancel();
		#endif
		}
		case playermodelslot_animation, playermodelslot_model: {
			delete_playermodelentity(client);

		#if defined GAME_TF2
			SetVariantVector3D(NULL_VECTOR);
			AcceptEntityInput(client, "SetCustomModelRotation");

			SetVariantVector3D(NULL_VECTOR);
			AcceptEntityInput(client, "SetCustomModelOffset");

			SetVariantBool(true);
			AcceptEntityInput(client, "SetCustomModelRotates");

			SetVariantBool(true);
			AcceptEntityInput(client, "SetCustomModelVisibleToSelf");

			AcceptEntityInput(client, "ClearCustomModelRotation");

			SetVariantString("");
			AcceptEntityInput(client, "SetCustomModel");
			SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 0);
		#endif

		#if defined _SENDPROXYMANAGER_INC_
			SendProxy_Unhook(client, "m_clrRender", proxy_renderclr);
			SendProxy_Unhook(client, "m_nRenderMode", proxy_rendermode);
		#endif

			SetEntityRenderMode(client, RENDER_NORMAL);
			SetEntityRenderColor(client, 255, 255, 255, 255);

			int effects = GetEntProp(client, Prop_Send, "m_fEffects");
			effects &= ~(EF_NOSHADOW|EF_NORECEIVESHADOW|EF_NODRAW);
			SetEntProp(client, Prop_Send, "m_fEffects", effects);
		}
	}
}

enum playermodelmethod
{
	playermodelmethod_setcustommodel,
	playermodelmethod_bonemerge,
};

static void handle_playerdata(int client, playermodelslot which, handledatafrom from)
{
	//TODO!! optimize using handledatafrom

	if(which != playermodelslot_hack_all) {
		clear_playerdata(client, which, cleardatafrom_reapply, from);
	}

	switch(which) {
		case playermodelslot_hack_all: {
			handle_playerdata(client, playermodelslot_animation, from);
			handle_playerdata(client, playermodelslot_skin, from);
			handle_playerdata(client, playermodelslot_bodygroup, from);
		}
		case playermodelslot_skin: {
			int new_skin = player_skin[client];

			if(new_skin != -1) {
			#if defined GAME_TF2
				if(player_modelentity[client] != INVALID_ENT_REFERENCE) {
					int entity = EntRefToEntIndex(player_modelentity[client]);
					SetEntProp(entity, Prop_Send, "m_iTeamNum", new_skin);
				} else {
					SetEntProp(client, Prop_Send, "m_bForcedSkin", true);
					SetEntProp(client, Prop_Send, "m_nForcedSkin", new_skin);
				}
			#endif
			}
		}
		case playermodelslot_bodygroup: {
			int new_bodygroup = player_bodygroup[client];

			if(new_bodygroup != -1) {
				int entity = client;
				if(player_modelentity[client] != INVALID_ENT_REFERENCE) {
					entity = EntRefToEntIndex(player_modelentity[client]);
				}

				SetEntProp(entity, Prop_Send, "m_nBody", new_bodygroup);
			}
		}
		case playermodelslot_animation, playermodelslot_model: {
			char new_animation[PLATFORM_MAX_PATH];
			if(animation_override[0] != '\0') {
				strcopy(new_animation, PLATFORM_MAX_PATH, animation_override);
				animation_override[0] = '\0';
			}

			char new_model[PLATFORM_MAX_PATH];
			strcopy(new_model, PLATFORM_MAX_PATH, player_model[client]);

			if(new_animation[0] == '\0' && new_model[0] == '\0') {
				return;
			}

			if(new_animation[0] == '\0') {
				if(new_model[0] != '\0') {
					char old_model[PLATFORM_MAX_PATH];
				#if defined GAME_TF2
					GetModelForPlayerClass(client, old_model, PLATFORM_MAX_PATH);
				#else
					GetEntPropString(client, Prop_Data, "m_ModelName", old_model, PLATFORM_MAX_PATH);
				#endif
					if(StrEqual(old_model, new_model)) {
						return;
					}
				}
			} else {
				if(new_model[0] == '\0') {
					char old_model[PLATFORM_MAX_PATH];
				#if defined GAME_TF2
					GetModelForPlayerClass(client, old_model, PLATFORM_MAX_PATH);
				#else
					GetEntPropString(client, Prop_Data, "m_ModelName", old_model, PLATFORM_MAX_PATH);
				#endif
					if(StrEqual(old_model, new_animation)) {
						return;
					}
				}
			}

			playermodelmethod method = playermodelmethod_bonemerge;

			if(player_modelclass[client] != TF2_GetPlayerClass(client) &&
				!(player_flags[client] & playermodel_nevermerge) ||
				(player_flags[client] & playermodel_alwaysmerge)) {
				method = playermodelmethod_bonemerge;
			} else {
				method = playermodelmethod_setcustommodel;
			}

			if(new_animation[0] != '\0' &&
				!(player_flags[client] & playermodel_nevermerge)) {
				method = playermodelmethod_bonemerge;
			}

			switch(method) {
				case playermodelmethod_bonemerge: {
					int effects = GetEntProp(client, Prop_Send, "m_fEffects");
					effects |= (EF_NOSHADOW|EF_NORECEIVESHADOW);
					SetEntProp(client, Prop_Send, "m_fEffects", effects);

				#if defined GAME_TF2
					if(new_animation[0] != '\0') {
						set_custom_model(client, new_animation);
					}

					if(new_model[0] == '\0') {
						GetModelForPlayerClass(client, new_model, PLATFORM_MAX_PATH);
					}
				#endif

					bool entity_was_created = false;

					int entity = -1;
					if(player_modelentity[client] != INVALID_ENT_REFERENCE) {
						entity = EntRefToEntIndex(player_modelentity[client]);
						if(IsValidEntity(entity)) {
							entity_was_created = false;
						} else {
							entity = -1;
						}
					}

					if(entity == -1) {
					#if defined GAME_TF2
						entity = TF2Items_GiveNamedItem(client, dummy_item_view);
					#endif
						entity_was_created = true;
					}

					if(entity_was_created) {
						float pos[3];
						GetClientAbsOrigin(client, pos);

						DispatchKeyValueVector(entity, "origin", pos);
						DispatchKeyValue(entity, "model", new_model);

						SetEntPropString(entity, Prop_Data, "m_iClassname", "playermodel_wearable");

					#if defined GAME_TF2
						SDKCall(EquipWearable, client, entity);
						SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", 1);
					#else
						DispatchSpawn(entity);
					#endif

						SetEntPropString(entity, Prop_Data, "m_iClassname", "playermodel_wearable");

						SetEntityModel(entity, new_model);

						SetEntProp(entity, Prop_Send, "m_bClientSideAnimation", 0);
						SetEntProp(entity, Prop_Send, "m_bClientSideFrameReset", 0);

						SetEntPropFloat(entity, Prop_Send, "m_flPlaybackRate", 1.0);

						SetEntProp(entity, Prop_Send, "m_iTeamNum", GetClientTeam(client));

						SetVariantString("!activator");
						AcceptEntityInput(entity, "SetParent", client);

						SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);

					#if defined _SENDPROXYMANAGER_INC_
						SendProxy_Hook(client, "m_clrRender", Prop_Int, proxy_renderclr, true);
						SendProxy_Hook(client, "m_nRenderMode", Prop_Int, proxy_rendermode, true);
					#endif

						SetEntityRenderMode(client, RENDER_NONE);

						SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
						SetEntityRenderColor(entity, 255, 255, 255, 255);

						//SDKHook(entity, SDKHook_SetTransmit, OnPropTransmit);

						effects = GetEntProp(entity, Prop_Send, "m_fEffects");
						effects |= EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES;
						effects &= ~(EF_NOSHADOW|EF_NORECEIVESHADOW);
						SetEntProp(entity, Prop_Send, "m_fEffects", effects);

						player_modelentity[client] = EntIndexToEntRef(entity);
					} else {
						SetEntityModel(entity, new_model);
					}
				}
				case playermodelmethod_setcustommodel: {
				#if defined GAME_TF2
					set_custom_model(client, new_model);
				#endif
				}
			}
		}
	}
}
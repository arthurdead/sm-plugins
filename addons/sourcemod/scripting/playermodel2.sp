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
#define PM2_CHAT_PREFIX "{dodgerblue}[PM2]{default} "

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
	int bodygroup;
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
	handledatafrom_equip,
};

enum cleardatafrom
{
	cleardatafrom_death,
	cleardatafrom_disconnect,
	cleardatafrom_remove,
	cleardatafrom_disguise_start,
	cleardatafrom_taunt_start,
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
static char currenttauntmodel[MAXPLAYERS+1][PLATFORM_MAX_PATH];
static ConVar tf_always_loser;
static int player_viewmodelentity[MAXPLAYERS+1][2];
#endif

static int modelgameplay = -1;

static ArrayList modelinfos;
static StringMap modelinfoidmap;

static ArrayList groupinfos;

static int modelprecache = INVALID_STRING_TABLE;

static char animation_override[PLATFORM_MAX_PATH];

static char player_model[MAXPLAYERS+1][PLATFORM_MAX_PATH];
static int player_skin[MAXPLAYERS+1] = {-1, ...};
static int player_bodygroup[MAXPLAYERS+1] = {-1, ...};
static int player_modelentity[MAXPLAYERS+1] = {INVALID_ENT_REFERENCE, ...};
static playermodelflags player_flags[MAXPLAYERS+1];
static TFClassType player_modelclass[MAXPLAYERS+1];

#if defined GAME_TF2
static void get_model_for_class(TFClassType class, char[] model, int length)
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
	if(str[0] == '\0') {
		return def;
	}

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
			if(!remove) {
				flags &= ~playermodel_nevermerge;
			}
		} else if(StrEqual(flagstrs[i][start], "nevermerge")) {
			REMOVE_OR_ADD_FLAG(flags, playermodel_nevermerge)
			if(!remove) {
				flags &= ~playermodel_alwaysmerge;
			}
		} else {
			LogError(PM2_CON_PREFIX ... "unknown flag %s", flagstrs[i][start]);
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
		ConfigVariationInfo varinfo;

		char classesvalue[CLASS_NAME_MAX * TF_CLASS_COUNT_ALL];
		char flagsvalue[FLAGS_MAX * FLAGS_NUM];
		char intstr[INT_STR_MAX];
		char classname[CLASS_NAME_MAX];
		char bodygroupvalue[BODYGROUP_NUM * BODYGROUP_MAX];

		do {
			kvModels.GetSectionName(modelinfo.name, MODEL_NAME_MAX);
		#if defined DEBUG
			PrintToServer(PM2_CON_PREFIX ... "  %s", modelinfo.name);
		#endif

			kvModels.GetString("classes_whitelist", classesvalue, sizeof(classesvalue), "all");

			modelinfo.classes = 0;

			if(classesvalue[0] != '\0') {
				if(!parse_classes_str(modelinfo.classes, classesvalue, modelinfo.name)) {
					continue;
				}
			}

			kvModels.GetString("model", modelinfo.model, PLATFORM_MAX_PATH, "");

			kvModels.GetString("flags", flagsvalue, sizeof(flagsvalue), "");
			modelinfo.flags = flagsstr_to_flags(flagsvalue, flags);
		#if defined DEBUG
			PrintToServer(PM2_CON_PREFIX ... "    flags = %s = %i", flagsvalue, modelinfo.flags);
		#endif

			kvModels.GetString("bodygroup", bodygroupvalue, sizeof(bodygroupvalue), "-1");
			modelinfo.bodygroup = bodygroupstr_to_bodygroup(bodygroupvalue);
		#if defined DEBUG
			PrintToServer(PM2_CON_PREFIX ... "    bodygroup = %s = %i", bodygroupvalue, modelinfo.bodygroup);
		#endif

			kvModels.GetString("skin", intstr, INT_STR_MAX, "-1");
			modelinfo.skin = StringToInt(intstr);
		#if defined DEBUG
			PrintToServer(PM2_CON_PREFIX ... "    skin = %i", modelinfo.skin);
		#endif

			kvModels.GetString("original_class", classname, CLASS_NAME_MAX, "unknown");
			modelinfo.orig_class = TF2_GetClass(classname);

			modelinfo.variations = null;

			if(kvModels.JumpToKey("variations")) {
				if(kvModels.GotoFirstSubKey()) {
					modelinfo.variations = new ArrayList(sizeof(ConfigVariationInfo));

				#if defined DEBUG
					PrintToServer(PM2_CON_PREFIX ... "    variations");
				#endif

					do {
						kvModels.GetSectionName(varinfo.name, MODEL_NAME_MAX);
					#if defined DEBUG
						PrintToServer(PM2_CON_PREFIX ... "      %s", varinfo.name);
					#endif

						kvModels.GetString("flags", flagsvalue, sizeof(flagsvalue), "");
						varinfo.flags = flagsstr_to_flags(flagsvalue, modelinfo.flags);
					#if defined DEBUG
						PrintToServer(PM2_CON_PREFIX ... "        flags = %s = %i", flagsvalue, varinfo.flags);
					#endif

						kvModels.GetString("bodygroup", bodygroupvalue, sizeof(bodygroupvalue), "-1");
						varinfo.bodygroup = bodygroupstr_to_bodygroup(bodygroupvalue);
					#if defined DEBUG
						PrintToServer(PM2_CON_PREFIX ... "        bodygroup = %s = %i", bodygroupvalue, varinfo.bodygroup);
					#endif

						kvModels.GetString("skin", intstr, INT_STR_MAX, "-1");
						varinfo.skin = StringToInt(intstr);
					#if defined DEBUG
						PrintToServer(PM2_CON_PREFIX ... "        skin = %i", varinfo.skin);
					#endif

						modelinfo.variations.PushArray(varinfo, sizeof(ConfigVariationInfo));
					} while(kvModels.GotoNextKey());
					kvModels.GoBack();
				}
				kvModels.GoBack();
			}

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

		#if defined DEBUG
			PrintToServer(PM2_CON_PREFIX ... "groups");
		#endif

			do {
				kvGroups.GetSectionName(groupinfo.name, MODEL_NAME_MAX);
			#if defined DEBUG
				PrintToServer(PM2_CON_PREFIX ... "%s", groupinfo.name);
			#endif

				kvGroups.GetString("override", groupinfo.override, OVERRIDE_MAX);
			#if defined DEBUG
				PrintToServer(PM2_CON_PREFIX ... "  override = %s", groupinfo.override);
			#endif

				kvGroups.GetString("steamid", groupinfo.steamid, STEAMID_MAX);
			#if defined DEBUG
				PrintToServer(PM2_CON_PREFIX ... "  steamid = %s", groupinfo.steamid);
			#endif

				BuildPath(Path_SM, configpath, PLATFORM_MAX_PATH, "configs/playermodels2/%s.txt", groupinfo.name);
				if(FileExists(configpath)) {
					kvGroups.GetString("flags", flagsvalue, sizeof(flagsvalue), "");
					playermodelflags flags = flagsstr_to_flags(flagsvalue);
				#if defined DEBUG
					PrintToServer(PM2_CON_PREFIX ... "  flags = %s = %i", flagsvalue, flags);
					PrintToServer(PM2_CON_PREFIX ... "  models");
				#endif

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

#if defined GAME_TF2
	HookEvent("player_changeclass", player_changeclass);

	dummy_item_view = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
	TF2Items_SetClassname(dummy_item_view, "tf_wearable");
	TF2Items_SetItemIndex(dummy_item_view, 65535);
	TF2Items_SetQuality(dummy_item_view, 0);
	TF2Items_SetLevel(dummy_item_view, 0);
	TF2Items_SetNumAttributes(dummy_item_view, 0);

	class_cache = new ArrayList();

	m_Shared_offset = FindSendPropInfo("CTFPlayer", "m_Shared");
	m_flInvisibility_offset = FindSendPropInfo("CTFPlayer", "m_flInvisChangeCompleteTime") - 8;

	tf_always_loser = FindConVar("tf_always_loser");
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

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "teammanager_gameplay")) {
		modelgameplay = TeamManager_NewGameplayGroup(Gameplay_Friendly);
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "teammanager_gameplay")) {
		modelgameplay = -1;
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
	PrecacheModel("models/error.mdl");

	modelprecache = FindStringTable("modelprecache");

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

static void equip_model_helper(int client, ConfigModelInfo modelinfo)
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
}

static void equip_model(int client, ConfigModelInfo modelinfo)
{
	equip_model_helper(client, modelinfo);

	handle_playerdata(client, playermodelslot_hack_all, handledatafrom_equip);
}

static void equip_model_variation(int client, ConfigModelInfo modelinfo, ConfigVariationInfo varinfo)
{
	equip_model_helper(client, modelinfo);

	player_flags[client] = varinfo.flags;

	if(varinfo.skin != -1) {
		player_skin[client] = varinfo.skin;
	}

	if(varinfo.bodygroup != -1) {
		player_bodygroup[client] = varinfo.bodygroup;
	}

	handle_playerdata(client, playermodelslot_hack_all, handledatafrom_equip);
}

int menuhandler_variation(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		char intstr[INT_STR_MAX];
		menu.GetItem(param2, intstr, INT_STR_MAX);
		int vidx = StringToInt(intstr);

		if(vidx == -1) {
			unequip_model(param1);
			return 0;
		}

		menu.GetItem(0, intstr, INT_STR_MAX);
		int midx = StringToInt(intstr);

		ConfigModelInfo modelinfo;
		modelinfos.GetArray(midx, modelinfo, sizeof(ConfigModelInfo));

		if(vidx == -2) {
			equip_model(param1, modelinfo);
		} else {
			ConfigVariationInfo varinfo;
			modelinfo.variations.GetArray(vidx, varinfo, sizeof(ConfigVariationInfo));

			equip_model_variation(param1, modelinfo, varinfo);
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}

	return 0;
}

int menuhandler_model(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		char intstr[INT_STR_MAX];
		menu.GetItem(param2, intstr, INT_STR_MAX);
		int idx = StringToInt(intstr);

		if(idx == -1) {
			unequip_model(param1);
		} else {
			ConfigModelInfo modelinfo;
			modelinfos.GetArray(idx, modelinfo, sizeof(ConfigModelInfo));

			if(modelinfo.variations) {
				Menu vmenu = CreateMenu(menuhandler_variation);
				vmenu.SetTitle(modelinfo.name);

				IntToString(idx, intstr, INT_STR_MAX);
				vmenu.AddItem(intstr, "", ITEMDRAW_IGNORE);

				vmenu.AddItem("-1", "remove");

				vmenu.AddItem("-2", "default");

				ConfigVariationInfo varinfo;

				int len = modelinfo.variations.Length;
				for(int i = 0; i < len; ++i) {
					modelinfo.variations.GetArray(i, varinfo, sizeof(ConfigVariationInfo));

					IntToString(i, intstr, INT_STR_MAX);
					vmenu.AddItem(intstr, varinfo.name);
				}

				vmenu.Display(param1, MENU_TIME_FOREVER);
			} else {
				equip_model(param1, modelinfo);
			}
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}

	return 0;
}

int menuhandler_group(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		char intstr[INT_STR_MAX];
		menu.GetItem(param2, intstr, INT_STR_MAX);
		int idx = StringToInt(intstr);

		if(idx == -1) {
			unequip_model(param1);
		} else {
			ConfigGroupInfo groupinfo;
			groupinfos.GetArray(idx, groupinfo, sizeof(ConfigGroupInfo));

			Menu mmenu = CreateMenu(menuhandler_model);
			mmenu.SetTitle(groupinfo.name);

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
	handle_playerdata(client, playermodelslot_hack_all, handledatafrom_spawn);
}

static void player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

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

		delete_playerviewmodelentity(client);
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
		strcopy(currenttauntmodel[client], PLATFORM_MAX_PATH, tauntModel);
		handle_playerdata(client, playermodelslot_animation, handledatafrom_taunt_start);
		return Plugin_Handled;
	} else {
		//TODO!!! support for non-bonemerge
		clear_playerdata(client, playermodelslot_hack_all, cleardatafrom_taunt_start);
		return Plugin_Continue;
	}
}

public Action TauntManager_RemoveTauntModel(int client)
{
	currenttauntmodel[client][0] = '\0';
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
				if(currenttauntmodel[pThis][0] == '\0') {
					get_model_for_class(desiredclass, currenttauntmodel[pThis], PLATFORM_MAX_PATH);
					handle_playerdata(pThis, playermodelslot_animation, handledatafrom_taunt_start);
				}
			#if defined DEBUG
				PrintToServer(PM2_CON_PREFIX ... "PlayTauntSceneFromItem");
			#endif
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
	#if defined DEBUG
		PrintToServer(PM2_CON_PREFIX ... "EndLongTaunt");
	#endif
		TF2_SetPlayerClass(pThis, tmpplayerclass[pThis]);
	}
	return MRES_Ignored;
}

static MRESReturn PlayTauntOutroScene(int pThis, DHookReturn hReturn)
{
	if(tmpplayerclass[pThis] != TFClass_Unknown) {
		tempclass = TF2_GetPlayerClass(pThis);
	#if defined DEBUG
		PrintToServer(PM2_CON_PREFIX ... "PlayTauntOutroScene");
	#endif
		TF2_SetPlayerClass(pThis, tmpplayerclass[pThis]);
	}
	tmpplayerclass[pThis] = TFClass_Unknown;
	return MRES_Ignored;
}

static MRESReturn PlayTauntSceneFromItem_post(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if(tempclass != TFClass_Unknown) {
	#if defined DEBUG
		PrintToServer(PM2_CON_PREFIX ... "PlayTauntSceneFromItem_post");
	#endif
		TF2_SetPlayerClass(pThis, tempclass);
	}
	tempclass = TFClass_Unknown;
	return MRES_Ignored;
}

static MRESReturn EndLongTaunt_post(int pThis, DHookReturn hReturn)
{
	if(tempclass != TFClass_Unknown) {
	#if defined DEBUG
		PrintToServer(PM2_CON_PREFIX ... "EndLongTaunt_post");
	#endif
		TF2_SetPlayerClass(pThis, tempclass);
	}
	tempclass = TFClass_Unknown;
	return MRES_Ignored;
}

static MRESReturn PlayTauntOutroScene_post(int pThis, DHookReturn hReturn)
{
	if(tempclass != TFClass_Unknown) {
	#if defined DEBUG
		PrintToServer(PM2_CON_PREFIX ... "PlayTauntOutroScene_post");
	#endif
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
			currenttauntmodel[client][0] = '\0';

			handle_playerdata(client, playermodelslot_animation, handledatafrom_taunt_end);
		}
	}
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

static ArrayList get_class_cache(int weapon, int item, int &bitmask = 0)
{
	int idx = class_cache.FindValue(item);
	if(idx != -1) {
		bitmask = class_cache.Get(++idx);
		ArrayList tmp = class_cache.Get(++idx);
		return tmp;
	} else {
		ArrayList tmp = new ArrayList();

		/*char classname[64];
		GetEntityClassname(weapon, classname, sizeof(classname));

		bool secondshot = is_shotgun_and_secondary(classname);
		if(secondshot) {
			for(int i = sizeof(classes_withsecondaryshotgun)-1; i--;) {
				TFClassType icls = classes_withsecondaryshotgun[i];
				tmp.Push(icls);
				bitmask |= BIT_FOR_CLASS(icls);
			}
		}

		bool secondpistol = is_pistol_and_secondary(classname);
		if(secondpistol) {
			for(int i = sizeof(classes_withsecondarypistol)-1; i--;) {
				TFClassType icls = classes_withsecondarypistol[i];
				tmp.Push(icls);
				bitmask |= BIT_FOR_CLASS(icls);
			}
		}*/

		for(int i = TF_CLASS_COUNT_ALL; --i;) {
			TFClassType icls = view_as<TFClassType>(i);

			/*if(secondshot && class_shotgun_is_secondary(icls) ||
				secondpistol && class_pistol_is_secondary(icls)) {
				continue;
			}*/

			int slot = TF2Econ_GetItemLoadoutSlot(item, icls);
			if(slot != -1) {
				tmp.Push(icls);
				bitmask |= BIT_FOR_CLASS(icls);
			}
		}

		int len = tmp.Length;
		if(len > 0) {
			class_cache.Push(item);
			class_cache.Push(bitmask);
			class_cache.Push(tmp);
		} else {
			delete tmp;
			len = 0;
		}

		if(len > 0) {
			return tmp;
		} else {
			return null;
		}
	}
}

static TFClassType get_class_for_weapon(int weapon, TFClassType player_class, int &bitmask = 0)
{
	int m_iItemDefinitionIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");

	TFClassType weapon_class = TFClass_Unknown;

	ArrayList cache = get_class_cache(weapon, m_iItemDefinitionIndex, bitmask);
	if(cache) {
		if(cache.FindValue(player_class) != -1) {
			weapon_class = player_class;
		} else {
			weapon_class = cache.Get(GetRandomInt(0, cache.Length-1));
		}
	}

	return weapon_class;
}

static int get_viewmodelentity(int client, int i)
{
	int entity = -1;
	if(player_viewmodelentity[client][i] != INVALID_ENT_REFERENCE) {
		entity = EntRefToEntIndex(player_viewmodelentity[client][i]);
		if(!IsValidEntity(entity)) {
			player_viewmodelentity[client][i] = INVALID_ENT_REFERENCE;
			entity = -1;
		}
	}

	return entity;
}

static void get_arm_model_for_class(int client, TFClassType class, char[] model, int length)
{
	switch(class)
	{
		case TFClass_Unknown: { strcopy(model, length, "models/error.mdl"); }
		case TFClass_Engineer: {
			int weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
			if(weapon != -1 && GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 142) {
				strcopy(model, length, "models/weapons/c_models/c_engineer_gunslinger.mdl");
			} else {
				strcopy(model, length, "models/weapons/c_models/c_engineer_arms.mdl");
			}
		}
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

static int get_or_create_viewmodelentity(int client, int i)
{
	int entity = get_viewmodelentity(client, i);

	if(entity == -1) {
		TF2Items_SetClassname(dummy_item_view, "tf_wearable_vm");
		entity = TF2Items_GiveNamedItem(client, dummy_item_view);
		float pos[3];
		GetClientAbsOrigin(client, pos);
		DispatchKeyValueVector(entity, "origin", pos);
		DispatchKeyValue(entity, "model", "models/error.mdl");
		SDKCall(EquipWearable, client, entity);
		SetEntPropString(entity, Prop_Data, "m_iClassname", "playermodel_wearable_vm");
		SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", 1);
		SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);
		SetEntProp(entity, Prop_Send, "m_iTeamNum", GetClientTeam(client));
		player_viewmodelentity[client][i] = EntIndexToEntRef(entity);
	}

	return entity;
}

static void player_changeclass(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	delete_playerviewmodelentity(client, 0);
}
#endif

static void player_weaponequippost(int client, int weapon)
{
	player_weaponswitchpost(client, weapon);
}

static void player_weaponswitchpost(int client, int weapon)
{
#if defined GAME_TF2
	if(taunting[client] || TF2_IsPlayerInCondition(client, TFCond_Taunting)) {
		return;
	}

	TFClassType player_class = TF2_GetPlayerClass(client);

	TFClassType weapon_class = TFClass_Unknown;
	int bitmask = 0;
	if(IsValidEntity(weapon)) {
		weapon_class = get_class_for_weapon(weapon, player_class, bitmask);
	}

	if(weapon_class != TFClass_Unknown /*&& weapon_class != player_class*/) {
		get_model_for_class(weapon_class, animation_override, PLATFORM_MAX_PATH);
	}

	handle_playerdata(client, playermodelslot_animation, handledatafrom_weaponswitch);

	if(weapon_class != TFClass_Unknown) {
		if((weapon_class == TFClass_Pyro) &&
			!!(bitmask & BIT_FOR_CLASS(TFClass_Soldier)) &&
			(player_class != TFClass_Pyro)) {
			weapon_class = TFClass_Soldier;
		}

		char model[PLATFORM_MAX_PATH];
		get_arm_model_for_class(client, weapon_class, model, PLATFORM_MAX_PATH);

		int viewmodel_index = GetEntProp(weapon, Prop_Send, "m_nViewModelIndex");
		int viewmodel = GetEntPropEnt(client, Prop_Send, "m_hViewModel", viewmodel_index);

		SetEntPropString(viewmodel, Prop_Data, "m_ModelName", model);
		int idx = PrecacheModel(model);
		SetEntProp(viewmodel, Prop_Send, "m_nModelIndex", idx);
		SetEntProp(weapon, Prop_Send, "m_iViewModelIndex", idx);

	#if defined DEBUG
		PrintToServer(PM2_CON_PREFIX ... "%i %s %i", weapon_class, model, idx);
	#endif

		delete_playerviewmodelentity(client, 1);

		bool different_class = (weapon_class != player_class);

		if(different_class) {
			int entity = get_or_create_viewmodelentity(client, 0);

			SetVariantString("!activator");
			AcceptEntityInput(entity, "SetParent", viewmodel);

			int effects = GetEntProp(entity, Prop_Send, "m_fEffects");
			effects |= EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES;
			SetEntProp(entity, Prop_Send, "m_fEffects", effects);

			get_arm_model_for_class(client, player_class, model, PLATFORM_MAX_PATH);
			idx = PrecacheModel(model);

			SetEntityModel(entity, model);
			SetEntProp(entity, Prop_Send, "m_nModelIndex", idx);

			SetEntPropEnt(entity, Prop_Send, "m_hWeaponAssociatedWith", weapon);

		#if defined DEBUG
			PrintToServer(PM2_CON_PREFIX ... "%i %s %i", player_class, model, idx);
		#endif

			entity = get_or_create_viewmodelentity(client, 1);

			idx = GetEntProp(weapon, Prop_Send, "m_iWorldModelIndex");
			ReadStringTable(modelprecache, idx, model, PLATFORM_MAX_PATH);

		#if defined DEBUG && 0
			PrintToServer(PM2_CON_PREFIX ... "%s", model);
		#endif

			SetEntityModel(entity, model);
			SetEntProp(entity, Prop_Send, "m_nModelIndex", idx);

			SetVariantString("!activator");
			AcceptEntityInput(entity, "SetParent", viewmodel);

			effects = GetEntProp(entity, Prop_Send, "m_fEffects");
			effects |= EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES;
			SetEntProp(entity, Prop_Send, "m_fEffects", effects);
		}

		if(different_class) {
			int effects = GetEntProp(viewmodel, Prop_Send, "m_fEffects");
			effects |= EF_NODRAW;
			SetEntProp(viewmodel, Prop_Send, "m_fEffects", effects);
		} else {
			int effects = GetEntProp(viewmodel, Prop_Send, "m_fEffects");
			effects &= ~EF_NODRAW;
			SetEntProp(viewmodel, Prop_Send, "m_fEffects", effects);
		}
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
	player_viewmodelentity[client][0] = INVALID_ENT_REFERENCE;
	player_viewmodelentity[client][1] = INVALID_ENT_REFERENCE;

	SDKHook(client, SDKHook_PostThinkPost, player_postthinkpost);
	SDKHook(client, SDKHook_WeaponEquipPost, player_weaponequippost);
	SDKHook(client, SDKHook_WeaponSwitchPost, player_weaponswitchpost);
}

#if defined GAME_TF2
static void delete_playerviewmodelentity(int client, int i = -1)
{
#if defined DEBUG && 0
	PrintToServer(PM2_CON_PREFIX ... "delete_playerviewmodelentity(%i)", client);
#endif

	if(i == -1) {
		delete_playerviewmodelentity(client, 0);
		delete_playerviewmodelentity(client, 1);
		return;
	}

	int entity = get_viewmodelentity(client, i);
	if(entity != -1) {
	#if defined GAME_TF2
		TF2_RemoveWearable(client, entity);
	#endif
		AcceptEntityInput(entity, "ClearParent");
		RemoveEntity(entity);
		player_viewmodelentity[client][i] = INVALID_ENT_REFERENCE;
	}
}
#endif

static bool delete_playermodelentity(int client)
{
#if defined DEBUG && 0
	PrintToServer(PM2_CON_PREFIX ... "delete_playermodelentity(%i)", client);
#endif

	int entity = get_modelentity(client);
	if(entity != -1) {
	#if defined GAME_TF2
		TF2_RemoveWearable(client, entity);
	#endif
		AcceptEntityInput(entity, "ClearParent");
		RemoveEntity(entity);
		player_modelentity[client] = INVALID_ENT_REFERENCE;
		return true;
	}

	return false;
}

public void OnClientDisconnect(int client)
{
	delete_playermodelentity(client);
	delete_playerviewmodelentity(client);

#if defined GAME_TF2
	tmpplayerclass[client] = TFClass_Unknown;
	taunting[client] = false;
	currenttauntmodel[client][0] = '\0';
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
	int entity = get_modelentity(client);
	if(entity == -1) {
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
static Action proxy_renderclr(int iEntity, const char[] cPropName, int &iValue, int iElement, int iClient)
{
	if(iClient == iEntity) {
		if(!TF2_IsPlayerInCondition(iEntity, TFCond_Disguised)) {
			iValue = 0;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

static Action proxy_rendermode(int iEntity, const char[] cPropName, int &iValue, int iElement, int iClient)
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

static void reset_custommodel(int client)
{
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
}

static void recalculate_bodygroups(int client)
{
	Address player_addr = GetEntityAddress(client);

	Address m_Shared = (player_addr + view_as<Address>(m_Shared_offset));
	SDKCall(RecalculatePlayerBodygroups, m_Shared);

	Event event = CreateEvent("post_inventory_application");
	event.SetInt("userid", GetClientUserId(client));
	event.FireToClient(client);
	event.Cancel();
}
#endif

static void clear_playerdata(int client, playermodelslot which, cleardatafrom from, handledatafrom reapply_from = handledatafrom_unknown)
{
	//TODO!! optimize using cleardatafrom and handledatafrom

	switch(which) {
		case playermodelslot_hack_all: {
			clear_playerdata(client, playermodelslot_skin, from);
			clear_playerdata(client, playermodelslot_bodygroup, from);
			clear_playerdata(client, playermodelslot_animation, from);
		}
		case playermodelslot_skin: {
		#if defined GAME_TF2
			SetEntProp(client, Prop_Send, "m_bForcedSkin", false);
			SetEntProp(client, Prop_Send, "m_nForcedSkin", 0);
		#endif
		}
		case playermodelslot_bodygroup: {
		#if defined GAME_TF2
			recalculate_bodygroups(client);
		#endif
		}
		case playermodelslot_animation, playermodelslot_model: {
			reset_custommodel(client);

			delete_playermodelentity(client);

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

static int get_modelentity(int client)
{
	int entity = -1;
	if(player_modelentity[client] != INVALID_ENT_REFERENCE) {
		entity = EntRefToEntIndex(player_modelentity[client]);
		if(!IsValidEntity(entity)) {
			player_modelentity[client] = INVALID_ENT_REFERENCE;
			entity = -1;
		}
	}

	return entity;
}

static int get_modelentity_or_client(int client)
{
	int entity = get_modelentity(client);
	if(entity == -1) {
		entity = client;
	}
	return entity;
}

Action model_transmit(int entity, int client)
{
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if(client == owner) {
	#if defined GAME_TF2
		bool thirdperson = (
			TF2_IsPlayerInCondition(client, TFCond_Taunting) ||
			TF2_IsPlayerInCondition(client, TFCond_HalloweenBombHead) ||
			TF2_IsPlayerInCondition(client, TFCond_HalloweenGiant) ||
			TF2_IsPlayerInCondition(client, TFCond_HalloweenTiny) ||
			TF2_IsPlayerInCondition(client, TFCond_HalloweenGhostMode) ||
			TF2_IsPlayerInCondition(client, TFCond_HalloweenKart) ||
			TF2_IsPlayerInCondition(client, TFCond_MeleeOnly) ||
			TF2_IsPlayerInCondition(client, TFCond_SwimmingCurse) ||
			!!(GetEntProp(owner, Prop_Send, "m_iStunFlags") & (TF_STUNFLAG_THIRDPERSON)) ||
			tf_always_loser.BoolValue ||
			GetEntProp(owner, Prop_Send, "m_bIsReadyToHighFive") == 1 ||
			GetEntProp(owner, Prop_Send, "m_nForceTauntCam") == 1
		);
	#else
		#error
	#endif
		if(!thirdperson) {
			return Plugin_Handled;
		}
	} else {
		bool firstperson = (
			(GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") == owner &&
			GetEntProp(client, Prop_Send, "m_iObserverMode") == OBS_MODE_IN_EYE)
		);
		if(firstperson) {
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

#if defined GAME_TF2
static int team_for_skin(int skin)
{
	if(skin == 0) {
		return 2;
	} else {
		return 3;
	}
}
#endif

static void handle_playerdata(int client, playermodelslot which, handledatafrom from)
{
	//TODO!! optimize using handledatafrom

	switch(which) {
		case playermodelslot_hack_all: {
			handle_playerdata(client, playermodelslot_animation, from);
			handle_playerdata(client, playermodelslot_bodygroup, from);
			handle_playerdata(client, playermodelslot_skin, from);
		}
		case playermodelslot_skin: {
			int new_skin = player_skin[client];

			if(new_skin != -1) {
				int entity = get_modelentity(client);

			#if defined GAME_TF2
				if(entity != -1) {
					SetEntProp(entity, Prop_Send, "m_iTeamNum", team_for_skin(new_skin));
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
				int entity = get_modelentity_or_client(client);

				SetEntProp(entity, Prop_Send, "m_nBody", new_bodygroup);
			}
		}
		case playermodelslot_animation, playermodelslot_model: {
			TFClassType player_class = TF2_GetPlayerClass(client);

			if(animation_override[0] == '\0' && from != handledatafrom_weaponswitch) {
				int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

				if(IsValidEntity(weapon)) {
					TFClassType weapon_class = get_class_for_weapon(weapon, player_class);

					if(weapon_class != TFClass_Unknown && weapon_class != player_class) {
						get_model_for_class(weapon_class, animation_override, PLATFORM_MAX_PATH);
					}
				}
			}

			char new_animation[PLATFORM_MAX_PATH];
			if(currenttauntmodel[client][0] != '\0') {
				strcopy(new_animation, PLATFORM_MAX_PATH, currenttauntmodel[client]);
			} else if(animation_override[0] != '\0') {
				strcopy(new_animation, PLATFORM_MAX_PATH, animation_override);
				animation_override[0] = '\0';
			}

			char new_model[PLATFORM_MAX_PATH];
			strcopy(new_model, PLATFORM_MAX_PATH, player_model[client]);

			if(new_animation[0] == '\0' && new_model[0] == '\0') {
				return;
			}

			playermodelmethod method = playermodelmethod_bonemerge;

			bool model_is_for_class = (player_modelclass[client] == player_class);

			if(!model_is_for_class &&
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

			bool set_bodygroups = false;
			if(method == playermodelmethod_bonemerge) {
				if(new_model[0] == '\0') {
					get_model_for_class(player_class, new_model, PLATFORM_MAX_PATH);
					set_bodygroups = true;
				}
			}

			if(StrEqual(new_model, new_animation)) {
				clear_playerdata(client, which, cleardatafrom_reapply, from);
				return;
			}

		#if defined DEBUG && 0
			PrintToServer(PM2_CON_PREFIX ... "%s | %s | %i | %i", new_model, new_animation, from, set_bodygroups);
		#endif

			bool do_clear_data = (
				new_animation[0] != '\0' ||
				from == handledatafrom_taunt_end
			);
			if(do_clear_data) {
				clear_playerdata(client, which, cleardatafrom_reapply, from);
			}

			switch(method) {
				case playermodelmethod_bonemerge: {
					int effects = GetEntProp(client, Prop_Send, "m_fEffects");
					effects |= (EF_NOSHADOW|EF_NORECEIVESHADOW);
					SetEntProp(client, Prop_Send, "m_fEffects", effects);

				#if defined GAME_TF2
					if(new_animation[0] != '\0') {
						set_custom_model(client, new_animation);
					#if defined DEBUG && 0
						PrintToServer(PM2_CON_PREFIX ... "set_custom_model(%s) %i", new_animation, from);
					#endif
					}
				#endif

					int entity = get_modelentity(client);
					bool entity_was_created = (entity == -1);

					if(entity_was_created) {
					#if defined GAME_TF2
						TF2Items_SetClassname(dummy_item_view, "tf_wearable");
						entity = TF2Items_GiveNamedItem(client, dummy_item_view);
					#endif

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
					#if defined DEBUG && 0
						PrintToServer(PM2_CON_PREFIX ... "SetEntityModel(%s) %i", new_model, from);
					#endif

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

						SDKHook(entity, SDKHook_SetTransmit, model_transmit);

						effects = GetEntProp(entity, Prop_Send, "m_fEffects");
						effects |= EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES;
						effects &= ~(EF_NOSHADOW|EF_NORECEIVESHADOW);
						SetEntProp(entity, Prop_Send, "m_fEffects", effects);

						player_modelentity[client] = EntIndexToEntRef(entity);

						if(do_clear_data) {
							handle_playerdata(client, playermodelslot_bodygroup, from);
							handle_playerdata(client, playermodelslot_skin, from);
						}
					} else {
						SetEntityModel(entity, new_model);
					#if defined DEBUG && 0
						PrintToServer(PM2_CON_PREFIX ... "SetEntityModel(%s) %i", new_model, from);
					#endif
					}

					if(set_bodygroups) {
						int body = GetEntProp(client, Prop_Send, "m_nBody");
					#if defined DEBUG && 0
						PrintToServer(PM2_CON_PREFIX ... "%i", body);
					#endif
						SetEntProp(entity, Prop_Send, "m_nBody", body);
					}
				}
				case playermodelmethod_setcustommodel: {
				#if defined GAME_TF2
					set_custom_model(client, new_model);
					#if defined DEBUG && 0
					PrintToServer(PM2_CON_PREFIX ... "set_custom_model(%s) %i", new_model, from);
					#endif
				#endif
				}
			}
		}
	}
}
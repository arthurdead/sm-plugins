#include <sourcemod>
#include <sdkhooks>
#include <dhooks>
#include <morecolors>
#include <tf2items>
#include <tf_econ_data>
#tryinclude <tauntmanager>
#include <teammanager_gameplay>
#include <tf2utils>
#include <stocksoup/memory>

//#define DEBUG

//#define ENABLE_SENDPROXY

#if defined ENABLE_SENDPROXY
#include <sendproxy>
#endif

/*
TODO!!!

support for hiding weapons in specific slots
support for hiding hats in specific equip regions
*/

#define INT_STR_MAX 4
#define MODEL_NAME_MAX 64
#define OVERRIDE_MAX 64
#define STEAMID_MAX 64

#define PM2_CON_PREFIX "[PM2] "
#define PM2_CHAT_PREFIX "{dodgerblue}[PM2]{default} "

#define CLASS_NAME_MAX 10
#define TF_CLASS_COUNT_ALL 10

#define BIT_FOR_CLASS(%1) (1 << (view_as<int>(%1)-1))

#define OBS_MODE_IN_EYE 4

#define EF_BONEMERGE 0x001
#define EF_BONEMERGE_FASTCULL 0x080
#define EF_PARENT_ANIMATES 0x200
#define EF_NODRAW 0x020
#define EF_NOSHADOW 0x010
#define EF_NORECEIVESHADOW 0x040

enum config_flags
{
	config_flags_none = 0,
	config_flags_hide_wearables = (1 << 1),
	config_flags_hide_weapons = (1 << 2),
	config_flags_no_gameplay = (1 << 3),
	config_flags_no_weapons = (1 << 4),
	config_flags_no_wearables = (1 << 5),
	config_flags_never_bonemerge = (1 << 6),
	config_flags_always_bonemerge = (1 << 7)
};

enum model_method
{
	model_method_remove,
	model_method_setcustommodel,
	model_method_bonemerge
};

enum struct ConfigGroupInfo
{
	char name[MODEL_NAME_MAX];
	char override[OVERRIDE_MAX];
	char steamid[STEAMID_MAX];
	ArrayList configs;
}

enum struct ConfigVariationInfo
{
	char name[MODEL_NAME_MAX];
	int skin;
	int bodygroups;
	config_flags flags;
}

enum struct ConfigInfo
{
	char name[MODEL_NAME_MAX];
	int classes_allowed;
	ArrayList variations;

	char model[PLATFORM_MAX_PATH];
	TFClassType model_class;
	config_flags flags;
	int skin;
	int bodygroups;
}

enum struct PlayerConfigInfo
{
	int idx;

	char model[PLATFORM_MAX_PATH];
	TFClassType model_class;
	config_flags flags;
	int skin;
	int bodygroups;

	void clear()
	{
		this.idx = -1;
		this.flags = config_flags_none;
		this.model[0] = '\0';
		this.model_class = TFClass_Unknown;
		this.skin = -1;
		this.bodygroups = -1;
	}
}

enum struct WeaponClassCache
{
	int item;
	ArrayList classes;
	int bitmask;
}

enum struct ThirdpartyModelInfo
{
	char model[PLATFORM_MAX_PATH];
	TFClassType class;
	bool bonemerge;

	void clear()
	{
		this.model[0] = '\0';
		this.class = TFClass_Unknown;
		this.bonemerge = true;
	}
}

enum struct TauntVarsInfo
{
	bool attempting_to_taunt;
	TFClassType class_pre_taunt;
	TFClassType class;

	void clear()
	{
		this.class = TFClass_Unknown;
		this.class_pre_taunt = TFClass_Unknown;
		this.attempting_to_taunt = false;
	}
}

#define TF2_MAXPLAYERS 33

static TauntVarsInfo player_taunt_vars[TF2_MAXPLAYERS+1];

static TFClassType player_weapon_animation_class[TF2_MAXPLAYERS+1];

static ThirdpartyModelInfo player_thirdparty_model[TF2_MAXPLAYERS+1];
static ThirdpartyModelInfo player_custom_taunt_model[TF2_MAXPLAYERS+1];
static PlayerConfigInfo player_config[TF2_MAXPLAYERS+1];

static int player_model_entity[TF2_MAXPLAYERS+1] = {INVALID_ENT_REFERENCE, ...};
static int player_viewmodel_entities[TF2_MAXPLAYERS+1][2];

static bool tf_taunt_first_person[TF2_MAXPLAYERS+1];
static bool cl_first_person_uses_world_model[TF2_MAXPLAYERS+1];

static bool dont_handle_SetCustomModel_call;

static ArrayList weapons_class_cache;
static ConVar tf_always_loser;

static int CTFPlayer_m_Shared_offset = -1;
static int CTFPlayer_m_PlayerClass_offset = -1;
static int CTFPlayer_m_flInvisibility_offset = -1;
static int CEconItemView_m_iAttributeDefinitionIndex_offset = -1;

static Handle CBasePlayer_EquipWearable;
static Handle CTFPlayer_IsAllowedToTaunt;
static Handle CTFPlayerShared_RecalculatePlayerBodygroups;

static Handle AI_CriteriaSet_AppendCriteria;
static Handle AI_CriteriaSet_RemoveCriteria;

static Handle dummy_item_view;

static ArrayList groups;
static ArrayList configs;
static StringMap config_idx_map;

static int no_damage_gameplay_group = INVALID_GAMEPLAY_GROUP;

static int modelprecache = INVALID_STRING_TABLE;

static ConVar pm2_viewmodels;

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

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("playermodel2");
	return APLRes_Success;
}

static void unload_configs()
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			unequip_config(i, true);
		}
	}

	ConfigGroupInfo group_info;
	int len = groups.Length;
	for(int i = 0; i < len; ++i) {
		groups.GetArray(i, group_info, sizeof(ConfigGroupInfo));
		delete group_info.configs;
	}

	ConfigInfo config_info;
	len = configs.Length;
	for(int i = 0; i < len; ++i) {
		configs.GetArray(i, config_info, sizeof(ConfigInfo));
		delete config_info.variations;
	}
	delete configs;
	delete config_idx_map;
}

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

#define FLAGS_NUM 7
#define FLAGS_MAX 18

#define REMOVE_OR_ADD_FLAG(%1,%2) \
	if(remove) { \
		%1 &= ~(%2); \
	} else { \
		%1 |= (%2); \
	}

static config_flags parse_flags_str(const char[] str, config_flags def = config_flags_none)
{
	if(str[0] == '\0') {
		return def;
	}

	char strs[FLAGS_NUM][FLAGS_MAX];
	int num = ExplodeString(str, "|", strs, FLAGS_NUM, FLAGS_MAX);

	config_flags flags = def;

	for(int i = 0; i < num; ++i) {
		bool remove = (strs[i][0] == '~');
		int start = (remove ? 1 : 0);

		if(StrEqual(strs[i][start], "hide_wearables")) {
			REMOVE_OR_ADD_FLAG(flags, config_flags_hide_wearables)
		} else if(StrEqual(strs[i][start], "no_gameplay")) {
			REMOVE_OR_ADD_FLAG(flags, config_flags_no_gameplay)
		} else if(StrEqual(strs[i][start], "no_weapons")) {
			REMOVE_OR_ADD_FLAG(flags, config_flags_no_weapons)
			if(!remove) {
				flags |= config_flags_no_gameplay;
			}
		} else if(StrEqual(strs[i][start], "no_wearables")) {
			REMOVE_OR_ADD_FLAG(flags, config_flags_no_wearables)
		} else if(StrEqual(strs[i][start], "hide_weapons")) {
			REMOVE_OR_ADD_FLAG(flags, config_flags_hide_weapons)
		} else if(StrEqual(strs[i][start], "always_bonemerge")) {
			REMOVE_OR_ADD_FLAG(flags, config_flags_always_bonemerge)
			if(!remove) {
				flags &= ~config_flags_never_bonemerge;
			}
		} else if(StrEqual(strs[i][start], "never_bonemerge")) {
			REMOVE_OR_ADD_FLAG(flags, config_flags_never_bonemerge)
			if(!remove) {
				flags &= ~config_flags_always_bonemerge;
			}
		} else {
			LogError(PM2_CON_PREFIX ... "unknown flag %s", strs[i][start]);
		}
	}

	return flags;
}

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
#define BODYGROUP_PYRO_PROPANE (1 << 2)
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

static int translate_classes_bodygroups(int old, TFClassType source, TFClassType target)
{
	int new_body = 0;

	switch(target) {
		case TFClass_Scout: {
			new_body |= BODYGROUP_SCOUT_HAT|BODYGROUP_SCOUT_HEADPHONES|BODYGROUP_SCOUT_DOGTAGS;
		}
		case TFClass_Soldier: {
			new_body |= BODYGROUP_SOLDIER_HELMET|BODYGROUP_SOLDIER_MEDAL|BODYGROUP_SOLDIER_GRENADES;
		}
		case TFClass_Engineer: {
			new_body |= BODYGROUP_ENGINEER_HELMET;
		}
		case TFClass_Sniper: {
			new_body |= BODYGROUP_SNIPER_HAT;
		}
		case TFClass_Pyro: {
			new_body |= BODYGROUP_PYRO_GRENADES|BODYGROUP_PYRO_PROPANE;
		}
		case TFClass_Medic: {
			new_body |= BODYGROUP_MEDIC_BACKPACK;
		}
	}

	switch(source) {
		case TFClass_Scout: {
			if(old & BODYGROUP_SCOUT_HAT) {
				switch(target) {
					case TFClass_Soldier: {
						new_body |= BODYGROUP_SOLDIER_HELMET;
					}
					case TFClass_Engineer: {
						new_body |= BODYGROUP_ENGINEER_HELMET;
					}
					case TFClass_Sniper: {
						new_body |= BODYGROUP_SNIPER_HAT;
					}
				}
			}
		}
		case TFClass_Soldier: {
			if(old & BODYGROUP_SOLDIER_HELMET) {
				switch(target) {
					case TFClass_Scout: {
						new_body |= BODYGROUP_SCOUT_HAT;
					}
					case TFClass_Engineer: {
						new_body |= BODYGROUP_ENGINEER_HELMET;
					}
					case TFClass_Sniper: {
						new_body |= BODYGROUP_SNIPER_HAT;
					}
				}
			}
		}
		case TFClass_Engineer: {
			if(old & BODYGROUP_ENGINEER_HELMET) {
				switch(target) {
					case TFClass_Scout: {
						new_body |= BODYGROUP_SCOUT_HAT;
					}
					case TFClass_Soldier: {
						new_body |= BODYGROUP_SOLDIER_HELMET;
					}
					case TFClass_Sniper: {
						new_body |= BODYGROUP_SNIPER_HAT;
					}
				}
			}
		}
		case TFClass_Sniper: {
			if(old & BODYGROUP_SNIPER_HAT) {
				switch(target) {
					case TFClass_Scout: {
						new_body |= BODYGROUP_SCOUT_HAT;
					}
					case TFClass_Soldier: {
						new_body |= BODYGROUP_SOLDIER_HELMET;
					}
					case TFClass_Engineer: {
						new_body |= BODYGROUP_ENGINEER_HELMET;
					}
				}
			}
		}
	}

	return new_body;
}

static int parse_bodygroups_str(const char[] str)
{
	char strs[BODYGROUP_NUM][BODYGROUP_MAX];
	int num = ExplodeString(str, "|", strs, BODYGROUP_NUM, BODYGROUP_MAX);

	int bodygroups = 0;

	for(int i = 0; i < num; ++i) {
		if(StrEqual(strs[i], "scout_hat")) {
			bodygroups |= BODYGROUP_SCOUT_HAT;
		} else if(StrEqual(strs[i], "scout_headphones")) {
			bodygroups |= BODYGROUP_SCOUT_HEADPHONES;
		} else if(StrEqual(strs[i], "scout_shoe_socks")) {
			bodygroups |= BODYGROUP_SCOUT_SHOESSOCKS;
		} else if(StrEqual(strs[i], "scout_dog_tags")) {
			bodygroups |= BODYGROUP_SCOUT_DOGTAGS;
		} else if(StrEqual(strs[i], "soldier_rockers")) {
			bodygroups |= BODYGROUP_SOLDIER_ROCKET;
		} else if(StrEqual(strs[i], "soldier_helmet")) {
			bodygroups |= BODYGROUP_SOLDIER_HELMET;
		} else if(StrEqual(strs[i], "soldier_medal")) {
			bodygroups |= BODYGROUP_SOLDIER_MEDAL;
		} else if(StrEqual(strs[i], "soldier_grenades")) {
			bodygroups |= BODYGROUP_SOLDIER_GRENADES;
		} else if(StrEqual(strs[i], "pyro_head")) {
			bodygroups |= BODYGROUP_PYRO_HEAD;
		} else if(StrEqual(strs[i], "pyro_grenades")) {
			bodygroups |= BODYGROUP_PYRO_GRENADES;
		} else if(StrEqual(strs[i], "pyro_propane")) {
			bodygroups |= BODYGROUP_PYRO_PROPANE;
		} else if(StrEqual(strs[i], "demo_smile")) {
			bodygroups |= BODYGROUP_DEMO_SMILE;
		} else if(StrEqual(strs[i], "demo_shoes")) {
			bodygroups |= BODYGROUP_DEMO_SHOES;
		} else if(StrEqual(strs[i], "heavy_hands")) {
			bodygroups |= BODYGROUP_HEAVY_HANDS;
		} else if(StrEqual(strs[i], "engineer_helmet")) {
			bodygroups |= BODYGROUP_ENGINEER_HELMET;
		} else if(StrEqual(strs[i], "engineer_arm")) {
			bodygroups |= BODYGROUP_ENGINEER_ARM;
		} else if(StrEqual(strs[i], "medic_backpack")) {
			bodygroups |= BODYGROUP_MEDIC_BACKPACK;
		} else if(StrEqual(strs[i], "sniper_arrows")) {
			bodygroups |= BODYGROUP_SNIPER_ARROWS;
		} else if(StrEqual(strs[i], "sniper_hat")) {
			bodygroups |= BODYGROUP_SNIPER_HAT;
		} else if(StrEqual(strs[i], "sniper_bullets")) {
			bodygroups |= BODYGROUP_SNIPER_BULLETS;
		} else if(StrEqual(strs[i], "spy_mask")) {
			bodygroups |= BODYGROUP_SPY_MASK;
		} else if(StrEqual(strs[i], "merasmus_book")) {
			bodygroups |= BODYGROUP_MERASMUS_BOOK;
		} else if(StrEqual(strs[i], "merasmus_staff")) {
			bodygroups |= BODYGROUP_MERASMUS_STAFF;
		} else {
			bodygroups |= StringToInt(strs[i]);
		}
	}

	return bodygroups;
}

static void parse_config_kv(const char[] path, ConfigGroupInfo group, config_flags flags)
{
	KeyValues kv = new KeyValues("playermodel2_config");
	kv.ImportFromFile(path);

	if(kv.GotoFirstSubKey()) {
		group.configs = new ArrayList();

		ConfigInfo info;
		ConfigVariationInfo variation;

		char classes_str[CLASS_NAME_MAX * TF_CLASS_COUNT_ALL];
		char flags_str[FLAGS_MAX * FLAGS_NUM];
		char int_str[INT_STR_MAX];
		char classname[CLASS_NAME_MAX];
		char bodygroups_str[BODYGROUP_NUM * BODYGROUP_MAX];

		do {
			kv.GetSectionName(info.name, MODEL_NAME_MAX);

			kv.GetString("classes_whitelist", classes_str, sizeof(classes_str), "all");

			info.classes_allowed = 0;

			if(classes_str[0] != '\0') {
				if(!parse_classes_str(info.classes_allowed, classes_str, info.name)) {
					continue;
				}
			}

			kv.GetString("model", info.model, PLATFORM_MAX_PATH, "");

			kv.GetString("flags", flags_str, sizeof(flags_str), "");
			info.flags = parse_flags_str(flags_str, flags);

			kv.GetString("bodygroups", bodygroups_str, sizeof(bodygroups_str), "-1");
			info.bodygroups = parse_bodygroups_str(bodygroups_str);

			kv.GetString("skin", int_str, INT_STR_MAX, "-1");
			info.skin = StringToInt(int_str);

			kv.GetString("model_class", classname, CLASS_NAME_MAX, "unknown");
			info.model_class = TF2_GetClass(classname);
			if(info.model_class == TFClass_Unknown) {
				info.flags |= config_flags_never_bonemerge;
			}

			info.variations = null;

			if(kv.JumpToKey("variations")) {
				if(kv.GotoFirstSubKey()) {
					info.variations = new ArrayList(sizeof(ConfigVariationInfo));

					do {
						kv.GetSectionName(variation.name, MODEL_NAME_MAX);

						kv.GetString("flags", flags_str, sizeof(flags_str), "");
						variation.flags = parse_flags_str(flags_str, info.flags);

						kv.GetString("bodygroups", bodygroups_str, sizeof(bodygroups_str), "-1");
						variation.bodygroups = parse_bodygroups_str(bodygroups_str);

						kv.GetString("skin", int_str, INT_STR_MAX, "-1");
						variation.skin = StringToInt(int_str);

						info.variations.PushArray(variation, sizeof(ConfigVariationInfo));
					} while(kv.GotoNextKey());
					kv.GoBack();
				}
				kv.GoBack();
			}

			int idx = configs.PushArray(info, sizeof(ConfigInfo));

			config_idx_map.SetValue(info.name, idx);

			group.configs.Push(idx);
		} while(kv.GotoNextKey());

		kv.GoBack();
	}

	delete kv;
}

static void load_configs()
{
	configs = new ArrayList(sizeof(ConfigInfo));
	config_idx_map = new StringMap();

	groups = new ArrayList(sizeof(ConfigGroupInfo));

	char any_file_path[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, any_file_path, PLATFORM_MAX_PATH, "configs/playermodels2/groups.txt");
	if(FileExists(any_file_path)) {
		KeyValues kv = new KeyValues("playermodel2_groups");
		kv.ImportFromFile(any_file_path);

		if(kv.GotoFirstSubKey()) {
			ConfigGroupInfo info;

			char flags_str[FLAGS_MAX * FLAGS_NUM];

			do {
				kv.GetSectionName(info.name, MODEL_NAME_MAX);
				kv.GetString("override", info.override, OVERRIDE_MAX);
				kv.GetString("steamid", info.steamid, STEAMID_MAX);

				BuildPath(Path_SM, any_file_path, PLATFORM_MAX_PATH, "configs/playermodels2/%s.txt", info.name);
				if(FileExists(any_file_path)) {
					kv.GetString("flags", flags_str, sizeof(flags_str), "");
					config_flags flags = parse_flags_str(flags_str);

					parse_config_kv(any_file_path, info, flags);
				}

				groups.PushArray(info, sizeof(ConfigGroupInfo));
			} while(kv.GotoNextKey());

			kv.GoBack();
		}

		delete kv;
	}
}

public void OnPluginStart()
{
	for(int i = 0; i < sizeof(player_viewmodel_entities); ++i) {
		player_viewmodel_entities[i][0] = INVALID_ENT_REFERENCE;
		player_viewmodel_entities[i][1] = INVALID_ENT_REFERENCE;
	}

	for(int i = 0; i < TF2_MAXPLAYERS+1; ++i) {
		player_thirdparty_model[i].clear();
		player_custom_taunt_model[i].clear();
		player_config[i].clear();
	}

	GameData gamedata = new GameData("playermodel2");
	if(gamedata == null) {
		SetFailState("Gamedata not found.");
		return;
	}

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CBasePlayer::EquipWearable");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	CBasePlayer_EquipWearable = EndPrepSDKCall();
	if(CBasePlayer_EquipWearable == null) {
		SetFailState("Failed to create SDKCall for CBasePlayer::EquipWearable.");
		delete gamedata;
		return;
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayerShared::RecalculatePlayerBodygroups");
	CTFPlayerShared_RecalculatePlayerBodygroups = EndPrepSDKCall();
	if(CTFPlayerShared_RecalculatePlayerBodygroups == null) {
		SetFailState("Failed to create SDKCall for CTFPlayerShared::RecalculatePlayerBodygroups.");
		delete gamedata;
		return;
	}

	CEconItemView_m_iAttributeDefinitionIndex_offset = gamedata.GetOffset("CEconItemView::m_iAttributeDefinitionIndex");
	if(CEconItemView_m_iAttributeDefinitionIndex_offset == -1) {
		SetFailState("Failed to get CEconItemView::m_iAttributeDefinitionIndex offset from gamedata");
		delete gamedata;
		return;
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "AI_CriteriaSet::AppendCriteria");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	AI_CriteriaSet_AppendCriteria = EndPrepSDKCall();
	if(AI_CriteriaSet_AppendCriteria == null) {
		SetFailState("Failed to create SDKCall for AI_CriteriaSet::AppendCriteria.");
		delete gamedata;
		return;
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "AI_CriteriaSet::RemoveCriteria");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	AI_CriteriaSet_RemoveCriteria = EndPrepSDKCall();
	if(AI_CriteriaSet_RemoveCriteria == null) {
		SetFailState("Failed to create SDKCall for AI_CriteriaSet::RemoveCriteria.");
		delete gamedata;
		return;
	}

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayer::IsAllowedToTaunt");
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	CTFPlayer_IsAllowedToTaunt = EndPrepSDKCall();
	if(CTFPlayer_IsAllowedToTaunt == null) {
		SetFailState("Failed to create SDKCall for CTFPlayer::IsAllowedToTaunt.");
		delete gamedata;
		return;
	}

	DynamicDetour detour_tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::PlayTauntSceneFromItem");
	if(!detour_tmp || !detour_tmp.Enable(Hook_Pre, CTFPlayer_PlayTauntSceneFromItem_detour)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::PlayTauntSceneFromItem");
		delete gamedata;
		return;
	}
	if(!detour_tmp.Enable(Hook_Post, CTFPlayer_PlayTauntSceneFromItem_detour_post)) {
		SetFailState("Failed to enable post detour for CTFPlayer::PlayTauntSceneFromItem");
		delete gamedata;
		return;
	}

	detour_tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::Taunt");
	if(!detour_tmp || !detour_tmp.Enable(Hook_Pre, CTFPlayer_Taunt_detour)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::Taunt");
		delete gamedata;
		return;
	}
	if(!detour_tmp.Enable(Hook_Post, CTFPlayer_Taunt_detour_post)) {
		SetFailState("Failed to enable post detour for CTFPlayer::Taunt");
		delete gamedata;
		return;
	}

	detour_tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::PlayTauntOutroScene");
	if(!detour_tmp || !detour_tmp.Enable(Hook_Pre, CTFPlayer_PlayTauntOutroScene_detour)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::PlayTauntOutroScene");
		delete gamedata;
		return;
	}
	if(!detour_tmp.Enable(Hook_Post, CTFPlayer_PlayTauntOutroScene_detour_post)) {
		SetFailState("Failed to enable post detour for CTFPlayer::PlayTauntOutroScene");
		delete gamedata;
		return;
	}

	detour_tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::PlayTauntRemapInputScene");
	if(!detour_tmp || !detour_tmp.Enable(Hook_Pre, CTFPlayer_PlayTauntRemapInputScene_detour)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::PlayTauntRemapInputScene");
		delete gamedata;
		return;
	}
	if(!detour_tmp.Enable(Hook_Post, CTFPlayer_PlayTauntRemapInputScene_detour_post)) {
		SetFailState("Failed to enable post detour for CTFPlayer::PlayTauntRemapInputScene");
		delete gamedata;
		return;
	}

	detour_tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::EndLongTaunt");
	if(!detour_tmp || !detour_tmp.Enable(Hook_Pre, CTFPlayer_EndLongTaunt_detour)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::EndLongTaunt");
		delete gamedata;
		return;
	}
	if(!detour_tmp.Enable(Hook_Post, CTFPlayer_EndLongTaunt_detour_post)) {
		SetFailState("Failed to enable post detour for CTFPlayer::EndLongTaunt");
		delete gamedata;
		return;
	}

	detour_tmp = DynamicDetour.FromConf(gamedata, "CTFPlayerClassShared::SetCustomModel");
	if(!detour_tmp || !detour_tmp.Enable(Hook_Pre, CTFPlayerClassShared_SetCustomModel_detour)) {
		SetFailState("Failed to enable pre detour for CTFPlayerClassShared::SetCustomModel");
		delete gamedata;
		return;
	}

	detour_tmp = DynamicDetour.FromConf(gamedata, "CTFPlayerShared::RecalculatePlayerBodygroups");
	if(!detour_tmp || !detour_tmp.Enable(Hook_Post, CTFPlayerShared_RecalculatePlayerBodygroups_detour_post)) {
		SetFailState("Failed to enable post detour for CTFPlayerShared::RecalculatePlayerBodygroups");
		delete gamedata;
		return;
	}

	//ModifyOrAppendCriteria_hook = DynamicHook.FromConf(gamedata, "CBaseEntity::ModifyOrAppendCriteria");

	delete gamedata;

	HookEvent("player_death", player_death);
	HookEvent("player_spawn", player_spawn);

	HookEvent("post_inventory_application", post_inventory_application);

	dummy_item_view = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
	TF2Items_SetClassname(dummy_item_view, "tf_wearable");
	TF2Items_SetItemIndex(dummy_item_view, 65535);
	TF2Items_SetQuality(dummy_item_view, 0);
	TF2Items_SetLevel(dummy_item_view, 0);
	TF2Items_SetNumAttributes(dummy_item_view, 0);

	weapons_class_cache = new ArrayList(sizeof(WeaponClassCache));

	CTFPlayer_m_Shared_offset = FindSendPropInfo("CTFPlayer", "m_Shared");
	CTFPlayer_m_PlayerClass_offset = FindSendPropInfo("CTFPlayer", "m_PlayerClass");

	//TODO!! unhardcode?
	CTFPlayer_m_flInvisibility_offset = FindSendPropInfo("CTFPlayer", "m_flInvisChangeCompleteTime") - 8;

	tf_always_loser = FindConVar("tf_always_loser");

	load_configs();

	pm2_viewmodels = CreateConVar("pm2_viewmodels", "0");

	RegAdminCmd("sm_rpm", sm_rpm, ADMFLAG_ROOT);
	RegConsoleCmd("sm_pm", sm_pm);

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			if(IsPlayerAlive(i) &&
				GetClientTeam(i) > 1 &&
				TF2_GetPlayerClass(i) != TFClass_Unknown) {
				on_player_spawned(i);
			}
			OnClientPutInServer(i);
		}
	}
}

static void CTFPlayerClassShared_SetCustomModel_detour_frame(int client)
{
	client = GetClientOfUserId(client);
	if(client == 0) {
		return;
	}

	handle_playermodel(client);
}

static MRESReturn CTFPlayerClassShared_SetCustomModel_detour(Address pThis, DHookParam hParams)
{
	if(dont_handle_SetCustomModel_call) {
		dont_handle_SetCustomModel_call = false;
		return MRES_Ignored;
	}

	Address player_addr = view_as<Address>(view_as<int>(pThis) - CTFPlayer_m_PlayerClass_offset);
	int client = GetEntityFromAddress(player_addr);

	char model[PLATFORM_MAX_PATH];
	if(!hParams.IsNull(1)) {
		hParams.GetString(1, model, PLATFORM_MAX_PATH);
	}

	if(model[0] == '\0') {
		player_thirdparty_model[client].clear();
	} else {
		PrecacheModel(model);
		strcopy(player_thirdparty_model[client].model, PLATFORM_MAX_PATH, model);

		ReplaceString(model, PLATFORM_MAX_PATH, "\\", "/");

		//TODO!!! move this to a file
		if(
			(StrContains(model, "models/props_") == 0) ||
			(StrContains(model, "models/buildables/") == 0) ||
			(StrContains(model, "models/items/") == 0) ||
			(StrContains(model, "models/flag/") == 0) ||
			(StrContains(model, "models/egypt/") == 0) ||
			StrEqual(model, "models/player/saxton_hale_jungle_inferno/saxton_hale.mdl") ||
			StrEqual(model, "models/freak_fortress_2/terraria/eoc/eoc.mdl")
		) {
			player_thirdparty_model[client].bonemerge = false;
		}
	}

	RequestFrame(CTFPlayerClassShared_SetCustomModel_detour_frame, GetClientUserId(client));

	return MRES_Supercede;
}

static MRESReturn CTFPlayerShared_RecalculatePlayerBodygroups_detour_post(Address pThis)
{
	return MRES_Ignored;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "teammanager_gameplay")) {
		no_damage_gameplay_group = TeamManager_NewGameplayGroup(Gameplay_Friendly);
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "teammanager_gameplay")) {
		no_damage_gameplay_group = INVALID_GAMEPLAY_GROUP;
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

	ConfigInfo info;

	char any_file_path[PLATFORM_MAX_PATH];

	int len = configs.Length;
	for(int i = 0; i < len; ++i) {
		configs.GetArray(i, info, sizeof(ConfigInfo));

		if(info.model[0] != '\0') {
			PrecacheModel(info.model);
		}

		Format(any_file_path, PLATFORM_MAX_PATH, "%s.dep", info.model);
		if(FileExists(any_file_path, true)) {
			File file = OpenFile(any_file_path, "r", true);

			while(!file.EndOfFile()) {
				file.ReadLine(any_file_path, PLATFORM_MAX_PATH);

				clean_file_path(any_file_path);

				AddFileToDownloadsTable(any_file_path);
			}

			delete file;
		}
	}
}

static Action sm_rpm(int client, int args)
{
	unload_configs();
	load_configs();
	return Plugin_Handled;
}

static void unequip_config_basic(int client)
{
	if(player_config[client].flags & config_flags_no_gameplay) {
		TeamManager_RemovePlayerFromGameplayGroup(client, no_damage_gameplay_group);
	}

	if(player_config[client].flags & config_flags_hide_wearables) {
		SDKUnhook(client, SDKHook_PostThinkPost, player_think_wearables_alpha);
		toggle_player_wearables(client, true);
	}

	if(player_config[client].flags & config_flags_hide_weapons) {
		SDKUnhook(client, SDKHook_PostThinkPost, player_think_weapons_alpha);
		toggle_player_weapons(client, true);
	}
}

static void unequip_config(int client, bool force = false, bool from_unload = false)
{
	unequip_config_basic(client);

	player_config[client].clear();

	remove_playermodel(client);
}

static bool can_equip_config(int client)
{
	return (player_thirdparty_model[client].model[0] == '\0');
}

static bool equip_config_basic(int client, int idx, ConfigInfo info)
{
	if(!can_equip_config(client)) {
		CPrintToChat(client, PM2_CHAT_PREFIX ... "you cannot equip a model at this time");
		return false;
	}

	unequip_config_basic(client);

	player_config[client].idx = idx;

	if(info.model[0] != '\0') {
		strcopy(player_config[client].model, PLATFORM_MAX_PATH, info.model);
	}

	if(info.skin != -1) {
		player_config[client].skin = info.skin;
	}

	if(info.bodygroups != -1) {
		player_config[client].bodygroups = info.bodygroups;
	}

	player_config[client].flags = info.flags;
	player_config[client].model_class = info.model_class;

	if(player_config[client].flags & config_flags_no_gameplay) {
		TeamManager_AddPlayerToGameplayGroup(client, no_damage_gameplay_group);
		CPrintToChat(client, PM2_CHAT_PREFIX ... "the model you equipped can not participate in normal gameplay");
	}

	if(player_config[client].flags & config_flags_no_weapons) {
		TF2_RemoveAllWeapons(client);
	}

	if(player_config[client].flags & config_flags_no_wearables) {
		remove_all_player_wearables(client);
	}

	if(player_config[client].flags & config_flags_hide_wearables) {
		SDKHook(client, SDKHook_PostThinkPost, player_think_wearables_alpha);
	}

	if(player_config[client].flags & config_flags_hide_weapons) {
		SDKHook(client, SDKHook_PostThinkPost, player_think_weapons_alpha);
	}

	return true;
}

static void equip_config(int client, int idx, ConfigInfo info)
{
	if(!equip_config_basic(client, idx, info)) {
		return;
	}

	handle_playermodel(client);
}

static void equip_config_variation(int client, int idx, ConfigInfo info, ConfigVariationInfo variation)
{
	if(!equip_config_basic(client, idx, info)) {
		return;
	}

	player_config[client].flags = variation.flags;

	if(variation.skin != -1) {
		player_config[client].skin = variation.skin;
	}

	if(variation.bodygroups != -1) {
		player_config[client].bodygroups = variation.bodygroups;
	}

	handle_playermodel(client);
}

static int handle_variation_menu(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		char int_str[INT_STR_MAX];
		menu.GetItem(0, int_str, INT_STR_MAX);
		int group_idx = StringToInt(int_str);

		menu.GetItem(1, int_str, INT_STR_MAX);
		int config_idx = StringToInt(int_str);

		menu.GetItem(param2, int_str, INT_STR_MAX);
		int variation_idx = StringToInt(int_str);

		ConfigInfo info;
		configs.GetArray(config_idx, info, sizeof(ConfigInfo));

		switch(variation_idx) {
			case -1: {
				unequip_config(param1);
			}
			case -2: {
				equip_config(param1, config_idx, info);
			}
			default: {
				ConfigVariationInfo variation;
				info.variations.GetArray(variation_idx, variation, sizeof(ConfigVariationInfo));
				equip_config_variation(param1, config_idx, info, variation);
			}
		}

		display_variation_menu(param1, info, config_idx, group_idx);
	} else if(action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			char int_str[INT_STR_MAX];
			menu.GetItem(0, int_str, INT_STR_MAX);
			int group_idx = StringToInt(int_str);

			display_group_menu(param1, group_idx);
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}

	return 0;
}

static void display_variation_menu(int client, ConfigInfo info, int config_idx, int group_idx)
{
	Menu menu = new Menu(handle_variation_menu);
	menu.SetTitle(info.name);
	menu.ExitBackButton = true;

	char int_str[INT_STR_MAX];
	IntToString(group_idx, int_str, INT_STR_MAX);
	menu.AddItem(int_str, "", ITEMDRAW_IGNORE);

	IntToString(config_idx, int_str, INT_STR_MAX);
	menu.AddItem(int_str, "", ITEMDRAW_IGNORE);

	menu.AddItem("-1", "remove");

	menu.AddItem("-2", "default");

	ConfigVariationInfo variation;

	int len = info.variations.Length;
	for(int i = 0; i < len; ++i) {
		info.variations.GetArray(i, variation, sizeof(ConfigVariationInfo));

		IntToString(i, int_str, INT_STR_MAX);
		menu.AddItem(int_str, variation.name);
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

static int handle_group_menu(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		char int_str[INT_STR_MAX];
		menu.GetItem(0, int_str, INT_STR_MAX);
		int group_idx = StringToInt(int_str);

		menu.GetItem(param2, int_str, INT_STR_MAX);
		int config_idx = StringToInt(int_str);

		if(config_idx == -1) {
			unequip_config(param1);
		} else {
			ConfigInfo info;
			configs.GetArray(config_idx, info, sizeof(ConfigInfo));

			if(info.variations != null) {
				display_variation_menu(param1, info, config_idx, group_idx);
				return 0;
			} else {
				equip_config(param1, config_idx, info);
			}
		}

		display_group_menu(param1, group_idx);
	} else if(action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			display_groups_menu(param1);
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}

	return 0;
}

static void display_group_menu(int client, int idx)
{
	ConfigGroupInfo group;
	groups.GetArray(idx, group, sizeof(ConfigGroupInfo));

	Menu menu = new Menu(handle_group_menu);
	menu.SetTitle(group.name);
	menu.ExitBackButton = true;

	char int_str[INT_STR_MAX];
	IntToString(idx, int_str, INT_STR_MAX);
	menu.AddItem(int_str, "", ITEMDRAW_IGNORE);

	menu.AddItem("-1", "remove");

	ConfigInfo info;

	int len = group.configs.Length;
	for(int i = 0; i < len; ++i) {
		idx = group.configs.Get(i);

		configs.GetArray(idx, info, sizeof(ConfigInfo));

		IntToString(idx, int_str, INT_STR_MAX);
		menu.AddItem(int_str, info.name);
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

static int handle_groups_menu(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		char int_str[INT_STR_MAX];
		menu.GetItem(param2, int_str, INT_STR_MAX);
		int idx = StringToInt(int_str);

		if(idx == -1) {
			unequip_config(param1);
			display_groups_menu(param1);
		} else {
			display_group_menu(param1, idx);
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}

	return 0;
}

static void display_groups_menu(int client)
{
	char clientsteam[STEAMID_MAX];

	Menu menu = new Menu(handle_groups_menu);
	menu.SetTitle("Groups");

	menu.AddItem("-1", "remove");

	char int_str[INT_STR_MAX];

	ConfigGroupInfo info;

	int len = groups.Length;
	for(int i = 0; i < len; ++i) {
		groups.GetArray(i, info, sizeof(ConfigGroupInfo));

		if(info.override[0] != '\0') {
			if(!CheckCommandAccess(client, info.override, ADMFLAG_GENERIC)) {
				continue;
			}
		}

		if(info.steamid[0] != '\0') {
			if(GetClientAuthId(client, AuthId_SteamID64, clientsteam, STEAMID_MAX)) {
				if(!StrEqual(clientsteam, info.steamid)) {
					continue;
				}
			} else {
				continue;
			}
		}

		IntToString(i, int_str, INT_STR_MAX);
		menu.AddItem(int_str, info.name);
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

static Action sm_pm(int client, int args)
{
	display_groups_menu(client);
	return Plugin_Handled;
}

static void on_player_spawned(int client)
{
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	handle_weapon_switch(client, weapon, false);

	SDKHook(client, SDKHook_PostThinkPost, player_think_no_weapon);

	handle_playermodel(client);
}

static void player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	TFClassType player_class = TF2_GetPlayerClass(client);
	if(player_class == TFClass_Unknown ||
		GetClientTeam(client) < 2) {
		return;
	}

	on_player_spawned(client);
}

static void player_death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int flags = event.GetInt("death_flags");

	if(!(flags & TF_DEATHFLAG_DEADRINGER)) {
		SDKUnhook(client, SDKHook_PostThinkPost, player_think_no_weapon);

		delete_player_model_entity(client);
		delete_player_viewmodel_entities(client);
	}
}

static Action timer_ragdoll_reset_model(Handle timer, DataPack data)
{
	data.Reset();

	int owner = data.ReadCell();

	char model_original[PLATFORM_MAX_PATH];
	data.ReadString(model_original, PLATFORM_MAX_PATH);

	//SetEntPropString(owner, Prop_Send, "m_iszCustomModel", model_original);
	set_player_custom_model(owner, model_original);

	return Plugin_Continue;
}

static void frame_ragdoll_created(int entity)
{
	int owner = GetEntProp(entity, Prop_Send, "m_iPlayerIndex");

	char model_original[PLATFORM_MAX_PATH];
	GetEntPropString(owner, Prop_Send, "m_iszCustomModel", model_original, PLATFORM_MAX_PATH);

	char model[PLATFORM_MAX_PATH];
	if(player_thirdparty_model[owner].model[0] != '\0') {
		strcopy(model, PLATFORM_MAX_PATH, player_thirdparty_model[owner].model);
		if(player_thirdparty_model[owner].class != TFClass_Unknown) {
			SetEntProp(entity, Prop_Send, "m_iClass", player_thirdparty_model[owner].class);
		}
	} else if(player_config[owner].model[0] != '\0') {
		strcopy(model, PLATFORM_MAX_PATH, player_config[owner].model);
		if(player_config[owner].model_class != TFClass_Unknown) {
			SetEntProp(entity, Prop_Send, "m_iClass", player_config[owner].model_class);
		}
	}

	//SetEntPropString(owner, Prop_Send, "m_iszCustomModel", model);
	set_player_custom_model(owner, model);

	DataPack data;
	CreateDataTimer(0.1, timer_ragdoll_reset_model, data);
	data.WriteCell(owner);
	data.WriteString(model_original);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "tf_ragdoll")) {
		RequestFrame(frame_ragdoll_created, entity);
	}
}

static bool get_class_name(TFClassType type, char[] name, int length)
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

	char class_name[CLASS_NAME_MAX];
	char key[17 + CLASS_NAME_MAX];
	char int_str[INT_STR_MAX];

	for(TFClassType i = TFClass_Scout; i <= TFClass_Engineer; ++i) {
		get_class_name(i, class_name, CLASS_NAME_MAX);

		FormatEx(key, sizeof(key), "used_by_classes/%s", class_name);

		TF2Econ_GetItemDefinitionString(id, key, int_str, INT_STR_MAX);

		if(StrEqual(int_str, "1")) {
			ret.Push(i);
		}
	}

	return ret;
}

#if defined _tauntmanager_included_
public Action TauntManager_ApplyTauntModel(int client, const char[] tauntModel, TFClassType modelClass, bool hasBonemergeSupport)
{
#if defined DEBUG
	PrintToServer(PM2_CON_PREFIX ... "TauntManager_ApplyTauntModel %s %i %i", tauntModel, modelClass, hasBonemergeSupport);
#endif
	player_taunt_vars[client].attempting_to_taunt = true;
	player_custom_taunt_model[client].bonemerge = hasBonemergeSupport;
	player_custom_taunt_model[client].class = modelClass;
	strcopy(player_custom_taunt_model[client].model, PLATFORM_MAX_PATH, tauntModel);
	handle_playermodel(client);
	return Plugin_Handled;
}

public Action TauntManager_RemoveTauntModel(int client)
{
#if defined DEBUG
	PrintToServer(PM2_CON_PREFIX ... "TauntManager_RemoveTauntModel");
#endif
	player_custom_taunt_model[client].clear();
	return Plugin_Handled;
}
#endif

static void handle_taunt_attempt(int client, ArrayList supported_classes)
{
	TFClassType player_class = player_taunt_vars[client].class_pre_taunt;

	int len = supported_classes.Length;
	if(len > 0) {
		TFClassType desired_class = TFClass_Unknown;
		if(supported_classes.FindValue(player_class) != -1) {
			desired_class = player_class;
		} else {
			desired_class = supported_classes.Get(GetRandomInt(0, len-1));
		}
		player_taunt_vars[client].class = desired_class;
		handle_playermodel(client);
		TF2_SetPlayerClass(client, desired_class);
	}
}

static bool handle_taunt_attempt_pre(int client)
{
	player_taunt_vars[client].class_pre_taunt = TFClass_Unknown;
	player_taunt_vars[client].class = TFClass_Unknown;

	if(!SDKCall(CTFPlayer_IsAllowedToTaunt, client)) {
		return false;
	}

	player_taunt_vars[client].attempting_to_taunt = true;
	player_taunt_vars[client].class_pre_taunt = TF2_GetPlayerClass(client);

	return true;
}

static MRESReturn CTFPlayer_Taunt_detour(int pThis, DHookParam hParams)
{
	if(!handle_taunt_attempt_pre(pThis)) {
		return MRES_Ignored;
	}

	ArrayList supported_classes = new ArrayList();

#if defined _tauntmanager_included_
	TauntManager_CodeTaunt code_taunt = TauntManager_GetCurrentCodeTaunt(pThis);
	if(code_taunt != TauntManager_InvalidCodeTaunt) {
		TauntManager_GetCodeTauntUsableClasses(code_taunt, supported_classes);
	} else
#endif
	{
		int weapon = GetEntPropEnt(pThis, Prop_Send, "m_hActiveWeapon");
		if(weapon != -1) {
			TFClassType player_class = TF2_GetPlayerClass(pThis);
			TFClassType weapon_class = get_class_for_weapon(weapon, player_class);
			supported_classes.Push(weapon_class);
		}
	}

	handle_taunt_attempt(pThis, supported_classes);

	delete supported_classes;

#if defined DEBUG
	PrintToServer(PM2_CON_PREFIX ... "CTFPlayer::Taunt(%i)::pre", pThis);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class = %i", player_taunt_vars[pThis].class);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class_pre_taunt = %i", player_taunt_vars[pThis].class_pre_taunt);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.attempting_to_taunt = %i", player_taunt_vars[pThis].attempting_to_taunt);
#endif

	return MRES_Ignored;
}

static MRESReturn CTFPlayer_PlayTauntSceneFromItem_detour(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if(!handle_taunt_attempt_pre(pThis)) {
		return MRES_Ignored;
	}

	int m_iAttributeDefinitionIndex = -1;
	if(!hParams.IsNull(1)) {
		m_iAttributeDefinitionIndex = hParams.GetObjectVar(1, CEconItemView_m_iAttributeDefinitionIndex_offset, ObjectValueType_Int);
	}

	if(m_iAttributeDefinitionIndex != -1) {
		ArrayList supported_classes = get_classes_for_taunt(m_iAttributeDefinitionIndex);

		handle_taunt_attempt(pThis, supported_classes);

		delete supported_classes;
	}

#if defined DEBUG
	PrintToServer(PM2_CON_PREFIX ... "CTFPlayer::PlayTauntSceneFromItem(%i)::pre", pThis);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class = %i", player_taunt_vars[pThis].class);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class_pre_taunt = %i", player_taunt_vars[pThis].class_pre_taunt);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.attempting_to_taunt = %i", player_taunt_vars[pThis].attempting_to_taunt);
#endif

	return MRES_Ignored;
}

static void handle_taunt_attempt_post(int client)
{
	if(player_taunt_vars[client].class_pre_taunt != TFClass_Unknown) {
		TF2_SetPlayerClass(client, player_taunt_vars[client].class_pre_taunt);
		player_taunt_vars[client].class_pre_taunt = TFClass_Unknown;
	}
}

static void handle_taunt_attempt_outro(int client)
{
	if(player_taunt_vars[client].class != TFClass_Unknown) {
		player_taunt_vars[client].class_pre_taunt = TF2_GetPlayerClass(client);
		TF2_SetPlayerClass(client, player_taunt_vars[client].class);
	}
}

static MRESReturn CTFPlayer_Taunt_detour_post(int pThis, DHookParam hParams)
{
#if defined DEBUG
	PrintToServer(PM2_CON_PREFIX ... "CTFPlayer::Taunt(%i)::post", pThis);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class = %i", player_taunt_vars[pThis].class);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class_pre_taunt = %i", player_taunt_vars[pThis].class_pre_taunt);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.attempting_to_taunt = %i", player_taunt_vars[pThis].attempting_to_taunt);
#endif
	handle_taunt_attempt_post(pThis);
	return MRES_Ignored;
}

static MRESReturn CTFPlayer_PlayTauntOutroScene_detour(int pThis, DHookReturn hReturn)
{
#if defined DEBUG
	PrintToServer(PM2_CON_PREFIX ... "CTFPlayer::PlayTauntOutroScene(%i)::pre", pThis);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class = %i", player_taunt_vars[pThis].class);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class_pre_taunt = %i", player_taunt_vars[pThis].class_pre_taunt);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.attempting_to_taunt = %i", player_taunt_vars[pThis].attempting_to_taunt);
#endif
	handle_taunt_attempt_outro(pThis);
	return MRES_Ignored;
}

static MRESReturn CTFPlayer_PlayTauntRemapInputScene_detour(int pThis, DHookReturn hReturn)
{
#if defined DEBUG && 0
	PrintToServer(PM2_CON_PREFIX ... "CTFPlayer::PlayTauntRemapInputScene(%i)::pre", pThis);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class = %i", player_taunt_vars[pThis].class);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class_pre_taunt = %i", player_taunt_vars[pThis].class_pre_taunt);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.attempting_to_taunt = %i", player_taunt_vars[pThis].attempting_to_taunt);
#endif
	handle_taunt_attempt_outro(pThis);
	return MRES_Ignored;
}

static MRESReturn CTFPlayer_EndLongTaunt_detour(int pThis, DHookReturn hReturn)
{
#if defined DEBUG
	PrintToServer(PM2_CON_PREFIX ... "CTFPlayer::EndLongTaunt(%i)::pre", pThis);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class = %i", player_taunt_vars[pThis].class);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class_pre_taunt = %i", player_taunt_vars[pThis].class_pre_taunt);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.attempting_to_taunt = %i", player_taunt_vars[pThis].attempting_to_taunt);
#endif
	handle_taunt_attempt_outro(pThis);
	return MRES_Ignored;
}

static MRESReturn CTFPlayer_PlayTauntSceneFromItem_detour_post(int pThis, DHookReturn hReturn, DHookParam hParams)
{
#if defined DEBUG
	PrintToServer(PM2_CON_PREFIX ... "CTFPlayer::PlayTauntSceneFromItem(%i)::post", pThis);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class = %i", player_taunt_vars[pThis].class);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class_pre_taunt = %i", player_taunt_vars[pThis].class_pre_taunt);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.attempting_to_taunt = %i", player_taunt_vars[pThis].attempting_to_taunt);
#endif
	handle_taunt_attempt_post(pThis);
	return MRES_Ignored;
}

static MRESReturn CTFPlayer_EndLongTaunt_detour_post(int pThis, DHookReturn hReturn)
{
#if defined DEBUG
	PrintToServer(PM2_CON_PREFIX ... "CTFPlayer::EndLongTaunt(%i)::post", pThis);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class = %i", player_taunt_vars[pThis].class);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class_pre_taunt = %i", player_taunt_vars[pThis].class_pre_taunt);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.attempting_to_taunt = %i", player_taunt_vars[pThis].attempting_to_taunt);
#endif
	handle_taunt_attempt_post(pThis);
	return MRES_Ignored;
}

static MRESReturn CTFPlayer_PlayTauntRemapInputScene_detour_post(int pThis, DHookReturn hReturn)
{
#if defined DEBUG && 0
	PrintToServer(PM2_CON_PREFIX ... "CTFPlayer::PlayTauntRemapInputScene(%i)::post", pThis);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class = %i", player_taunt_vars[pThis].class);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class_pre_taunt = %i", player_taunt_vars[pThis].class_pre_taunt);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.attempting_to_taunt = %i", player_taunt_vars[pThis].attempting_to_taunt);
#endif
	handle_taunt_attempt_post(pThis);
	return MRES_Ignored;
}

static MRESReturn CTFPlayer_PlayTauntOutroScene_detour_post(int pThis, DHookReturn hReturn)
{
#if defined DEBUG
	PrintToServer(PM2_CON_PREFIX ... "CTFPlayer::PlayTauntOutroScene(%i)::post", pThis);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class = %i", player_taunt_vars[pThis].class);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.class_pre_taunt = %i", player_taunt_vars[pThis].class_pre_taunt);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_vars.attempting_to_taunt = %i", player_taunt_vars[pThis].attempting_to_taunt);
#endif
	handle_taunt_attempt_post(pThis);
	return MRES_Ignored;
}

public void TF2_OnConditionAdded(int client, TFCond condition)
{
	switch(condition) {
		case TFCond_Taunting: {
		#if defined DEBUG
			PrintToServer(PM2_CON_PREFIX ... "TF2_OnConditionAdded taunt");
		#endif
			player_taunt_vars[client].attempting_to_taunt = true;
		}
		case TFCond_Disguised:
		{ remove_playermodel(client); }
	}
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	switch(condition) {
		case TFCond_Taunting: {
		#if defined DEBUG
			PrintToServer(PM2_CON_PREFIX ... "TF2_OnConditionRemoved taunt");
		#endif
			player_taunt_vars[client].clear();
			player_custom_taunt_model[client].clear();
			handle_playermodel(client);
		}
		case TFCond_Disguised:
		{ handle_playermodel(client); }
	}
}

static void get_weapon_class_cache(int item, WeaponClassCache cache)
{
	int idx = weapons_class_cache.FindValue(item);
	if(idx != -1) {
		weapons_class_cache.GetArray(idx, cache, sizeof(WeaponClassCache));
	} else {
		cache.item = item;
		cache.classes = new ArrayList();

		for(int i = TF_CLASS_COUNT_ALL; --i;) {
			TFClassType class = view_as<TFClassType>(i);

			int slot = TF2Econ_GetItemLoadoutSlot(item, class);
			if(slot != -1) {
				cache.classes.Push(class);
				cache.bitmask |= BIT_FOR_CLASS(class);
			}
		}

		int len = cache.classes.Length;
		if(len > 0) {
			weapons_class_cache.PushArray(cache, sizeof(WeaponClassCache));
		} else {
			delete cache.classes;
		}
	}
}

static TFClassType translate_weapon_classname_to_class(int weapon)
{
	char classname[64];
	GetEntityClassname(weapon, classname, sizeof(classname));

	if(StrContains(classname, "tf_weapon") == 0) {
		if(StrContains(classname[9], "_shotgun") == 0) {
			if(StrEqual(classname[17], "_soldier")) {
				return TFClass_Soldier;
			} else if(StrEqual(classname[17], "_hwg")) {
				return TFClass_Heavy;
			} else if(StrEqual(classname[17], "_pyro")) {
				return TFClass_Pyro;
			} else if(StrEqual(classname[17], "_primary")) {
				return TFClass_Engineer;
			}
		} else if(StrContains(classname[9], "_pistol") == 0) {
			if(StrEqual(classname[16], "_scout")) {
				return TFClass_Scout;
			} else if(classname[17] == '\0') {
				return TFClass_Engineer;
			}
		} else if(StrContains(classname[9], "_revolver") == 0) {
			if(StrEqual(classname[18], "_secondary")) {
				return TFClass_Engineer;
			} else if(classname[19] == '\0') {
				return TFClass_Spy;
			}
		} else if(StrEqual(classname[9], "_bat")) {
			return TFClass_Scout;
		} else if(StrEqual(classname[9], "_club")) {
			return TFClass_Sniper;
		} else if(StrEqual(classname[9], "_shovel")) {
			return TFClass_Soldier;
		} else if(StrEqual(classname[9], "_bottle")) {
			return TFClass_DemoMan;
		} else if(StrEqual(classname[9], "_bonesaw")) {
			return TFClass_Medic;
		} else if(StrEqual(classname[9], "_fireaxe")) {
			return TFClass_Pyro;
		} else if(StrEqual(classname[9], "_knife")) {
			return TFClass_Spy;
		} else if(StrEqual(classname[9], "_wrench")) {
			return TFClass_Engineer;
		}
	}

	return TFClass_Unknown;
}

static TFClassType get_class_for_weapon(int weapon, TFClassType player_class)
{
	int m_iItemDefinitionIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");

	TFClassType weapon_class = TFClass_Unknown;

	WeaponClassCache info;
	get_weapon_class_cache(m_iItemDefinitionIndex, info);

	if(info.classes != null) {
		if(info.bitmask & BIT_FOR_CLASS(player_class)) {
			weapon_class = player_class;
		} else {
			int len = info.classes.Length;
			if(len > 1) {
				weapon_class = translate_weapon_classname_to_class(weapon);
			}

			if(weapon_class == TFClass_Unknown) {
				weapon_class = info.classes.Get(GetRandomInt(0, len-1));
			}
		}
	}

	return weapon_class;
}

static int get_player_viewmodel_entity(int client, int which)
{
	int entity = -1;
	if(player_viewmodel_entities[client][which] != INVALID_ENT_REFERENCE) {
		entity = EntRefToEntIndex(player_viewmodel_entities[client][which]);
		if(!IsValidEntity(entity)) {
			player_viewmodel_entities[client][which] = INVALID_ENT_REFERENCE;
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

static int get_or_create_player_viewmodel_entity(int client, int which)
{
	int entity = get_player_viewmodel_entity(client, which);

	if(entity == -1) {
		TF2Items_SetClassname(dummy_item_view, "tf_wearable_vm");
		entity = TF2Items_GiveNamedItem(client, dummy_item_view);
		float pos[3];
		GetClientAbsOrigin(client, pos);
		DispatchKeyValueVector(entity, "origin", pos);
		DispatchKeyValue(entity, "model", "models/error.mdl");
		SDKCall(CBasePlayer_EquipWearable, client, entity);
		SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", 1);
		SetEntPropString(entity, Prop_Data, "m_iClassname", "playermodel_wearable_vm");
		SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);
		SetEntProp(entity, Prop_Send, "m_iTeamNum", GetClientTeam(client));
		player_viewmodel_entities[client][which] = EntIndexToEntRef(entity);
	}

	return entity;
}

static void player_think_no_weapon(int client)
{
#if 0
	#define STUNMAGICINDEX 247

	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(weapon == -1) {
		SetEntProp(client, Prop_Send, "m_iStunIndex", STUNMAGICINDEX);
		int flags = GetEntProp(client, Prop_Send, "m_iStunFlags");
		flags |= (TF_STUNFLAG_NOSOUNDOREFFECT|TF_STUNFLAG_THIRDPERSON);
		SetEntProp(client, Prop_Send, "m_iStunFlags", flags);
		flags = GetEntProp(client, Prop_Send, "m_nPlayerCond");
		flags |= (1 << view_as<int>(TFCond_Dazed));
		SetEntProp(client, Prop_Send, "m_nPlayerCond", flags);
	} else {
		if(GetEntProp(client, Prop_Send, "m_iStunIndex") == STUNMAGICINDEX) {
			SetEntProp(client, Prop_Send, "m_iStunIndex", -1);
			int flags = GetEntProp(client, Prop_Send, "m_iStunFlags");
			flags &= ~(TF_STUNFLAG_NOSOUNDOREFFECT|TF_STUNFLAG_THIRDPERSON);
			SetEntProp(client, Prop_Send, "m_iStunFlags", flags);
			flags = GetEntProp(client, Prop_Send, "m_nPlayerCond");
			flags &= ~(1 << view_as<int>(TFCond_Dazed));
			SetEntProp(client, Prop_Send, "m_nPlayerCond", flags);
		}
	}
#endif
}

static int get_model_index(const char[] model)
{
	if(modelprecache == INVALID_STRING_TABLE) {
		modelprecache = FindStringTable("modelprecache");
		if(modelprecache == INVALID_STRING_TABLE) {
			return INVALID_STRING_INDEX;
		}
	}

	int idx = FindStringIndex(modelprecache, model);
	if(idx == INVALID_STRING_INDEX) {
		idx = PrecacheModel(model);
	}
	return idx;
}

static void get_model_index_path(int idx, char[] model, int len)
{
	if(modelprecache == INVALID_STRING_TABLE) {
		modelprecache = FindStringTable("modelprecache");
		if(modelprecache == INVALID_STRING_TABLE) {
			strcopy(model, len, "models/error.mdl");
		}
	}

	ReadStringTable(modelprecache, idx, model, len);
}

static void handle_weapon_switch(int client, int weapon, bool do_playermodel)
{
#if defined DEBUG
	PrintToServer(PM2_CON_PREFIX ... "handle_weapon_switch(%i)", client);
#endif

	TFClassType player_class = TFClass_Unknown;

	if(player_taunt_vars[client].class_pre_taunt != TFClass_Unknown) {
		player_class = player_taunt_vars[client].class_pre_taunt;
	} else {
		player_class = TF2_GetPlayerClass(client);
	}

	TFClassType weapon_class = TFClass_Unknown;
	if(weapon != -1) {
		weapon_class = get_class_for_weapon(weapon, player_class);
	}

	player_weapon_animation_class[client] = weapon_class;

	if(pm2_viewmodels.BoolValue) {
		if(weapon != -1) {
			if(weapon_class != TFClass_Unknown) {
				char model[PLATFORM_MAX_PATH];
				get_arm_model_for_class(client, weapon_class, model, PLATFORM_MAX_PATH);

				int viewmodel_index = GetEntProp(weapon, Prop_Send, "m_nViewModelIndex");
				int viewmodel = GetEntPropEnt(client, Prop_Send, "m_hViewModel", viewmodel_index);

				SetEntPropString(viewmodel, Prop_Data, "m_ModelName", model);
				int idx = get_model_index(model);
				SetEntProp(viewmodel, Prop_Send, "m_nModelIndex", idx);
				SetEntProp(weapon, Prop_Send, "m_iViewModelIndex", idx);

				delete_player_viewmodel_entity(client, 1);

				TFClassType arm_class = TFClass_Unknown;

				if(player_thirdparty_model[client].model[0] != '\0' &&
					player_thirdparty_model[client].class != TFClass_Unknown) {
					arm_class = player_thirdparty_model[client].class;
				} else if(player_config[client].model[0] != '\0' &&
							player_config[client].model_class != TFClass_Unknown) {
					arm_class = player_config[client].model_class;
				} else {
					arm_class = player_class;
				}

			#if defined DEBUG
				PrintToServer(PM2_CON_PREFIX ... "  arm_class = %i", arm_class);
			#endif

				bool different_class = (arm_class != weapon_class);

				if(different_class) {
					int entity = get_or_create_player_viewmodel_entity(client, 0);

					SetEntPropEnt(entity, Prop_Send, "m_hWeaponAssociatedWith", weapon);

					SetVariantString("!activator");
					AcceptEntityInput(entity, "SetParent", viewmodel);

					int effects = GetEntProp(entity, Prop_Send, "m_fEffects");
					effects |= (EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES);
					SetEntProp(entity, Prop_Send, "m_fEffects", effects);

					get_arm_model_for_class(client, arm_class, model, PLATFORM_MAX_PATH);
					idx = get_model_index(model);

					SetEntityModel(entity, model);
					SetEntProp(entity, Prop_Send, "m_nModelIndex", idx);
					SetEntProp(entity, Prop_Send, "m_nBody", 0);

					idx = GetEntProp(weapon, Prop_Send, "m_iWorldModelIndex");
					if(idx != -1) {
						entity = get_or_create_player_viewmodel_entity(client, 1);

						SetEntPropEnt(entity, Prop_Send, "m_hWeaponAssociatedWith", weapon);

						get_model_index_path(idx, model, PLATFORM_MAX_PATH);

						SetEntityModel(entity, model);
						SetEntProp(entity, Prop_Send, "m_nModelIndex", idx);

						SetVariantString("!activator");
						AcceptEntityInput(entity, "SetParent", viewmodel);

						effects = GetEntProp(entity, Prop_Send, "m_fEffects");
						effects |= (EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES);
						SetEntProp(entity, Prop_Send, "m_fEffects", effects);
					}
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
		}
	}

	if(do_playermodel && !player_taunt_vars[client].attempting_to_taunt) {
		handle_playermodel(client);
	}
}

static void player_weapon_switch(int client, int weapon)
{
	handle_weapon_switch(client, weapon, true);
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			unequip_config(i, true, true);
			OnClientDisconnect(i);
		}
	}
}

static void tf_taunt_first_person_query(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any data)
{
	if(result == ConVarQuery_Okay && StrEqual(cvarValue, "1")) {
		tf_taunt_first_person[client] = true;
	}
}

static void cl_first_person_uses_world_model_query(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any data)
{
	if(result == ConVarQuery_Okay && StrEqual(cvarValue, "1")) {
		cl_first_person_uses_world_model[client] = true;
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponSwitchPost, player_weapon_switch);

	if(!IsFakeClient(client)) {
		QueryClientConVar(client, "tf_taunt_first_person", tf_taunt_first_person_query);
		QueryClientConVar(client, "cl_first_person_uses_world_model", cl_first_person_uses_world_model_query);
	}
}

static void delete_player_viewmodel_entity(int client, int which, int weapon = -1)
{
	int entity = get_player_viewmodel_entity(client, which);
	if(entity != -1) {
		AcceptEntityInput(entity, "ClearParent");
		TF2_RemoveWearable(client, entity);
		RemoveEntity(entity);
		player_viewmodel_entities[client][which] = INVALID_ENT_REFERENCE;

		if(which == 0) {
			if(weapon == -1) {
				weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
			}
			if(weapon != -1) {
				int viewmodel_index = GetEntProp(weapon, Prop_Send, "m_nViewModelIndex");
				int viewmodel = GetEntPropEnt(client, Prop_Send, "m_hViewModel", viewmodel_index);

				int effects = GetEntProp(viewmodel, Prop_Send, "m_fEffects");
				effects &= ~EF_NODRAW;
				SetEntProp(viewmodel, Prop_Send, "m_fEffects", effects);
			}
		}
	}
}

static void delete_player_viewmodel_entities(int client, int weapon = -1)
{
	delete_player_viewmodel_entity(client, 0, weapon);
	delete_player_viewmodel_entity(client, 1, weapon);
}

static int get_or_create_player_model_entity(int client)
{
	int entity = get_player_model_entity(client);
	if(entity != -1) {
		return entity;
	}

	int effects = GetEntProp(client, Prop_Send, "m_fEffects");
	effects |= (EF_NOSHADOW|EF_NORECEIVESHADOW);
	SetEntProp(client, Prop_Send, "m_fEffects", effects);

	TF2Items_SetClassname(dummy_item_view, "tf_wearable");
	entity = TF2Items_GiveNamedItem(client, dummy_item_view);

	float pos[3];
	GetClientAbsOrigin(client, pos);

	DispatchKeyValueVector(entity, "origin", pos);
	DispatchKeyValue(entity, "model", "models/error.mdl");

	SDKCall(CBasePlayer_EquipWearable, client, entity);
	SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", 1);

	SetEntPropString(entity, Prop_Data, "m_iClassname", "playermodel_wearable");

	SetEntProp(entity, Prop_Send, "m_bClientSideAnimation", 0);
	SetEntProp(entity, Prop_Send, "m_bClientSideFrameReset", 0);

	SetEntPropFloat(entity, Prop_Send, "m_flPlaybackRate", 1.0);

	SetEntProp(entity, Prop_Send, "m_iTeamNum", GetClientTeam(client));

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", client);

	SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);

	SDKHook(client, SDKHook_PostThinkPost, player_think_model);

#if defined _SENDPROXYMANAGER_INC_ && defined ENABLE_SENDPROXY
	SendProxy_Hook(client, "m_clrRender", Prop_Int, proxy_renderclr, true);
	SendProxy_Hook(client, "m_nRenderMode", Prop_Int, proxy_rendermode, true);
#endif

	SetEntityRenderMode(client, RENDER_NONE);

	SDKHook(entity, SDKHook_SetTransmit, player_model_entity_transmit);

	effects = GetEntProp(entity, Prop_Send, "m_fEffects");
	effects |= (EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES);
	effects &= ~(EF_NOSHADOW|EF_NORECEIVESHADOW);
	SetEntProp(entity, Prop_Send, "m_fEffects", effects);

	player_model_entity[client] = EntIndexToEntRef(entity);

	return entity;
}

static void delete_player_model_entity(int client)
{
	int entity = get_player_model_entity(client);
	if(entity != -1) {
		AcceptEntityInput(entity, "ClearParent");
		TF2_RemoveWearable(client, entity);
		RemoveEntity(entity);
		player_model_entity[client] = INVALID_ENT_REFERENCE;
	}

	SDKUnhook(client, SDKHook_PostThinkPost, player_think_model);

#if defined _SENDPROXYMANAGER_INC_ && defined ENABLE_SENDPROXY
	SendProxy_Unhook(client, "m_clrRender", sendproxy_render_color);
	SendProxy_Unhook(client, "m_nRenderMode", sendproxy_player_render_mode);
#endif

	SetEntityRenderMode(client, RENDER_NORMAL);

	int effects = GetEntProp(client, Prop_Send, "m_fEffects");
	effects &= ~(EF_NOSHADOW|EF_NORECEIVESHADOW);
	SetEntProp(client, Prop_Send, "m_fEffects", effects);
}

public void OnClientDisconnect(int client)
{
	player_thirdparty_model[client].clear();
	player_custom_taunt_model[client].clear();
	player_config[client].clear();

	player_taunt_vars[client].clear();

	player_weapon_animation_class[client] = TFClass_Unknown;

	if(IsValidEntity(client)) {
		delete_player_model_entity(client);
		delete_player_viewmodel_entities(client);
	}

	tf_taunt_first_person[client] = false;
	cl_first_person_uses_world_model[client] = false;
}

static void remove_all_player_wearables(int client)
{
#if defined CAN_GET_UTLVECTOR
	int len = GetEntPropArraySize(client, Prop_Send, "m_hMyWearables");
	for(int i = 0; i < len; ++i) {
		int entity = GetEntPropEnt(client, Prop_Send, "m_hMyWearables", i);
		if(entity != -1) {
			AcceptEntityInput(entity, "ClearParent");
			TF2_RemoveWearable(client, entity);
			RemoveEntity(entity);
		}
	}
#else
	int entity = -1;
	while((entity = FindEntityByClassname(entity, "tf_wearable*")) != -1) {
		int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		if(owner == client) {
			AcceptEntityInput(entity, "ClearParent");
			TF2_RemoveWearable(owner, entity);
			RemoveEntity(entity);
		}
	}
#endif
}

#if !defined CAN_GET_UTLVECTOR
public void OnGameFrame()
{
	int entity = -1;
	while((entity = FindEntityByClassname(entity, "tf_wearable*")) != -1) {
		int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		if(owner != -1) {
			if(player_config[owner].flags & config_flags_hide_wearables) {
				SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
				set_entity_alpha(entity, 0);
			}
		}
	}
}
#endif

static void toggle_player_wearables(int client, bool value)
{
#if defined CAN_GET_UTLVECTOR
	int len = GetEntPropArraySize(client, Prop_Send, "m_hMyWearables");
	for(int i = 0; i < len; ++i) {
		int entity = GetEntPropEnt(client, Prop_Send, "m_hMyWearables", i);
		if(entity != -1) {
			SetEntityRenderMode(entity, value ? RENDER_NORMAL : RENDER_TRANSCOLOR);
			set_entity_alpha(entity, value ? 255 : 0);
		}
	}
#else
	int entity = -1;
	while((entity = FindEntityByClassname(entity, "tf_wearable*")) != -1) {
		int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		if(owner == client) {
			SetEntityRenderMode(entity, value ? RENDER_NORMAL : RENDER_TRANSCOLOR);
			set_entity_alpha(entity, value ? 255 : 0);
		}
	}
#endif
}

static void post_inventory_application_frame(int userid)
{
	int client = GetClientOfUserId(userid);
	if(client == 0) {
		return;
	}

	if(player_config[client].flags & config_flags_no_weapons) {
		TF2_RemoveAllWeapons(client);
	}

	if(player_config[client].flags & config_flags_no_wearables) {
		remove_all_player_wearables(client);
	}
}

static void post_inventory_application(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");

	RequestFrame(post_inventory_application_frame, userid);
}

static void set_entity_alpha(int entity, int a)
{
	int r = 255;
	int g = 255;
	int b = 255;
	int __a = 255;
	GetEntityRenderColor(entity, r, g, b, __a);
	__a = a;
	SetEntityRenderColor(entity, r, g, b, a);
}

static void toggle_player_weapons(int client, bool value)
{
	int len = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	for(int i = 0; i < len; ++i) {
		int entity = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if(entity != -1) {
			SetEntityRenderMode(entity, value ? RENDER_NORMAL : RENDER_TRANSCOLOR);
			set_entity_alpha(entity, value ? 255 : 0);
		}
	}
}

static void player_think_weapons_alpha(int client)
{
	int entity = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(entity != -1) {
		SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
		set_entity_alpha(entity, 0);
	}
}

static void player_think_wearables_alpha(int client)
{
#if defined CAN_GET_UTLVECTOR
	toggle_player_wearables(client, false);
#endif
}

static void player_think_model(int client)
{
	int entity = get_player_model_entity(client);
	if(entity == -1) {
		return;
	}

	if(!GetEntProp(client, Prop_Send, "m_bCustomModelRotates")) {
		SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 0);
	} else {
		SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);
	}

	SetEntityRenderMode(client, RENDER_NONE);

	int r = 255;
	int g = 255;
	int b = 255;
	int a = 255;
	GetEntityRenderColor(client, r, g, b, a);

	float invisibility = (1.0 - GetEntDataFloat(client, CTFPlayer_m_flInvisibility_offset));
	int invisibility_alpha = RoundToCeil(255 * invisibility);
	if(invisibility_alpha < a) {
		a = invisibility_alpha;
	}

	SetEntityRenderColor(entity, r, g, b, a);
}

#if defined ENABLE_SENDPROXY
static Action sendproxy_player_render_color(int iEntity, const char[] cPropName, int &iValue, int iElement, int iClient)
{
	if(iClient == iEntity) {
		if(!TF2_IsPlayerInCondition(iEntity, TFCond_Disguised)) {
			int r = (iValue & 255);
			int g = ((iValue >> 8) & 255);
			int b = ((iValue >> 16) & 255);
			int a = 0;

			iValue = a;
			iValue = (iValue << 8) + b;
			iValue = (iValue << 8) + g;
			iValue = (iValue << 8) + r;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

static Action sendproxy_player_render_mode(int entity, const char[] prop, int &value, int element, int client)
{
	if(client == entity) {
		value = view_as<int>(RENDER_TRANSCOLOR);
		return Plugin_Changed;
	}

	return Plugin_Continue;
}
#endif

static void set_player_custom_model(int client, const char[] model)
{
	dont_handle_SetCustomModel_call = true;
	SetVariantString(model);
	AcceptEntityInput(client, "SetCustomModel");
}

static void recalculate_player_bodygroups(int client)
{
	Address player_addr = GetEntityAddress(client);

	Address m_Shared = (player_addr + view_as<Address>(CTFPlayer_m_Shared_offset));
	SDKCall(CTFPlayerShared_RecalculatePlayerBodygroups, m_Shared);

	Event event = CreateEvent("post_inventory_application");
	event.SetInt("userid", GetClientUserId(client));
	event.FireToClient(client);
	event.Cancel();
}

static void remove_playermodel(int client)
{
	set_player_custom_model(client, "");
	SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 0);

	SetEntProp(client, Prop_Send, "m_bForcedSkin", 0);
	SetEntProp(client, Prop_Send, "m_nForcedSkin", 0);

	recalculate_player_bodygroups(client);

	delete_player_model_entity(client);
	delete_player_viewmodel_entities(client);
}

static int get_player_model_entity(int client)
{
	int entity = -1;
	if(player_model_entity[client] != INVALID_ENT_REFERENCE) {
		entity = EntRefToEntIndex(player_model_entity[client]);
		if(!IsValidEntity(entity)) {
			player_model_entity[client] = INVALID_ENT_REFERENCE;
			entity = -1;
		}
	}

	return entity;
}

static int get_model_entity_or_client(int client)
{
	int entity = get_model_entity(client);
	if(entity == -1) {
		entity = client;
	}
	return entity;
}

static bool is_player_in_thirdperson(int client)
{
	if(cl_first_person_uses_world_model[client] || tf_taunt_first_person[client]) {
		return false;
	}

	return (TF2_IsPlayerInCondition(client, TFCond_Taunting) ||
			TF2_IsPlayerInCondition(client, TFCond_HalloweenThriller) ||
			TF2_IsPlayerInCondition(client, TFCond_Bonked) ||
			!!(GetEntProp(client, Prop_Send, "m_iStunFlags") & TF_STUNFLAG_THIRDPERSON) ||
			GetEntProp(client, Prop_Send, "m_bIsReadyToHighFive") == 1 ||
			GetEntProp(client, Prop_Send, "m_nForceTauntCam") == 1 ||
			TF2_IsPlayerInCondition(client, TFCond_HalloweenKart) ||
			TF2_IsPlayerInCondition(client, TFCond_HalloweenBombHead) ||
			TF2_IsPlayerInCondition(client, TFCond_HalloweenGiant) ||
			TF2_IsPlayerInCondition(client, TFCond_HalloweenTiny) ||
			TF2_IsPlayerInCondition(client, TFCond_HalloweenGhostMode) ||
			TF2_IsPlayerInCondition(client, TFCond_MeleeOnly) ||
			TF2_IsPlayerInCondition(client, TFCond_SwimmingCurse) ||
			tf_always_loser.BoolValue);
}

Action player_model_entity_transmit(int entity, int client)
{
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if(client == owner) {
		if(!is_player_in_thirdperson(client)) {
			return Plugin_Handled;
		}
	} else {
		bool firstperson = (
			(GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") == owner && GetEntProp(client, Prop_Send, "m_iObserverMode") == OBS_MODE_IN_EYE)
		);
		if(firstperson) {
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

static int team_for_skin(int skin)
{
	if(skin == 0) {
		return 2;
	} else {
		return 3;
	}
}

static void handle_playermodel(int client)
{
#if defined DEBUG
	PrintToServer(PM2_CON_PREFIX ... "handle_playermodel(%i)", client);
	PrintToServer(PM2_CON_PREFIX ... "  player_taunt_animation_class = %i", player_taunt_vars[client].class);
	PrintToServer(PM2_CON_PREFIX ... "  player_weapon_animation_class = %i", player_weapon_animation_class[client]);

	PrintToServer(PM2_CON_PREFIX ... "  player_thirdparty_model.model = %s", player_thirdparty_model[client].model);
	PrintToServer(PM2_CON_PREFIX ... "  player_thirdparty_model.class = %i", player_thirdparty_model[client].class);
	PrintToServer(PM2_CON_PREFIX ... "  player_thirdparty_model.bonemerge = %i", player_thirdparty_model[client].bonemerge);

	PrintToServer(PM2_CON_PREFIX ... "  player_custom_taunt_model.model = %s", player_custom_taunt_model[client].model);
	PrintToServer(PM2_CON_PREFIX ... "  player_custom_taunt_model.class = %i", player_custom_taunt_model[client].class);
	PrintToServer(PM2_CON_PREFIX ... "  player_custom_taunt_model.bonemerge = %i", player_custom_taunt_model[client].bonemerge);

	PrintToServer(PM2_CON_PREFIX ... "  player_config.model = %s", player_config[client].model);
	PrintToServer(PM2_CON_PREFIX ... "  player_config.model_class = %i", player_config[client].model_class);
#endif

	TFClassType player_class = TFClass_Unknown;

	if(player_taunt_vars[client].class_pre_taunt != TFClass_Unknown) {
		player_class = player_taunt_vars[client].class_pre_taunt;
	} else {
		player_class = TF2_GetPlayerClass(client);
	}

	bool has_any_model = (player_thirdparty_model[client].model[0] != '\0' || player_config[client].model[0] != '\0');

	char animation_model[PLATFORM_MAX_PATH];
	if(player_custom_taunt_model[client].model[0] != '\0' &&
		player_custom_taunt_model[client].bonemerge &&
		(has_any_model || player_custom_taunt_model[client].class != player_class)) {
		strcopy(animation_model, PLATFORM_MAX_PATH, player_custom_taunt_model[client].model);
	} else if(player_taunt_vars[client].class != TFClass_Unknown) {
		if(player_taunt_vars[client].class != player_class) {
			get_model_for_class(player_taunt_vars[client].class, animation_model, PLATFORM_MAX_PATH);
		}
	} else if(player_weapon_animation_class[client] != TFClass_Unknown &&
				player_weapon_animation_class[client] != player_class) {
		get_model_for_class(player_weapon_animation_class[client], animation_model, PLATFORM_MAX_PATH);
	}

	bool bonemerge = true;
	bool from_config = false;
	TFClassType model_class = TFClass_Unknown;

	char player_model[PLATFORM_MAX_PATH];
	if(player_custom_taunt_model[client].model[0] != '\0' &&
		(!player_custom_taunt_model[client].bonemerge ||
		(!has_any_model && player_custom_taunt_model[client].class == player_class))) {
		strcopy(player_model, PLATFORM_MAX_PATH, player_custom_taunt_model[client].model);
		bonemerge = false;
	} else if(player_thirdparty_model[client].model[0] != '\0') {
		strcopy(player_model, PLATFORM_MAX_PATH, player_thirdparty_model[client].model);
		model_class = player_thirdparty_model[client].class;

		if(player_thirdparty_model[client].bonemerge) {
			if(player_thirdparty_model[client].class == player_class) {
				if(animation_model[0] == '\0') {
					bonemerge = false;
				}
			}
		} else {
			bonemerge = false;
		}
	} else if(player_config[client].model[0] != '\0') {
		from_config = true;
		strcopy(player_model, PLATFORM_MAX_PATH, player_config[client].model);
		model_class = player_config[client].model_class;

		if(player_config[client].flags & config_flags_never_bonemerge) {
			bonemerge = false;
		} else if(!(player_config[client].flags & config_flags_always_bonemerge)) {
			if(player_config[client].model_class == player_class) {
				if(animation_model[0] == '\0') {
					bonemerge = false;
				}
			}
		}
	}

#if defined DEBUG
	PrintToServer(PM2_CON_PREFIX ... "  animation_model = %s", animation_model);
	PrintToServer(PM2_CON_PREFIX ... "  player_model = %s", player_model);
	PrintToServer(PM2_CON_PREFIX ... "  bonemerge = %i", bonemerge);
	PrintToServer(PM2_CON_PREFIX ... "  model_class = %i", model_class);
#endif

	if(player_model[0] == '\0' && animation_model[0] == '\0') {
		remove_playermodel(client);
	} else if(bonemerge) {
		delete_player_model_entity(client);

		if(animation_model[0] == '\0' && player_model[0] == '\0') {
			LogError(PM2_CON_PREFIX ... "tried to set empty model");
			return;
		}

		if(animation_model[0] == '\0') {
			get_model_for_class(player_class, animation_model, PLATFORM_MAX_PATH);
		}
		if(player_model[0] == '\0') {
			get_model_for_class(player_class, player_model, PLATFORM_MAX_PATH);
			model_class = player_class;
		}

		set_player_custom_model(client, animation_model);
		SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);

		int entity = get_or_create_player_model_entity(client);

		if(from_config) {
			int bodygroups = player_config[client].bodygroups;
			if(bodygroups != -1) {
				SetEntProp(entity, Prop_Send, "m_nBody", bodygroups);
			} else {
				if(model_class != TFClass_Unknown) {
					bodygroups = GetEntProp(client, Prop_Send, "m_nBody");
					if(model_class != player_class) {
						bodygroups = translate_classes_bodygroups(bodygroups, player_class, model_class);
					}
					SetEntProp(entity, Prop_Send, "m_nBody", bodygroups);
				}
			}

			int skin = player_config[client].skin;
			if(skin != -1) {
				SetEntProp(entity, Prop_Send, "m_iTeamNum", team_for_skin(skin));
			}
		} else {
			if(model_class != TFClass_Unknown) {
				int bodygroups = GetEntProp(client, Prop_Send, "m_nBody");
				if(model_class != player_class) {
					bodygroups = translate_classes_bodygroups(bodygroups, player_class, model_class);
				}
				SetEntProp(entity, Prop_Send, "m_nBody", bodygroups);
			}
		}

		SetEntityModel(entity, player_model);
	} else {
		delete_player_model_entity(client);

		if(player_model[0] == '\0') {
			LogError(PM2_CON_PREFIX ... "tried to set empty model");
			return;
		}

		set_player_custom_model(client, player_model);
		SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);
	}
}
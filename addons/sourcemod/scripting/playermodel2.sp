#include <sourcemod>
#include <sdkhooks>
#include <dhooks>
#include <morecolors>
#include <tf2items>
#include <tf_econ_data>
#include <tf2utils>
#include <stocksoup/memory>
#include <regex>
#include <bit>

//#define DEBUG_CONFIG
//#define DEBUG_MODEL
//#define DEBUG_VIEWMODEL
//#define DEBUG_TAUNT
//#define DEBUG_PROXYSEND
//#define DEBUG_WEAPONSWITCH

#undef REQUIRE_EXTENSIONS
#include <proxysend>
#define REQUIRE_EXTENSIONS

#undef REQUIRE_PLUGIN
#include <teammanager_gameplay>
#include <economy>
#tryinclude <tauntmanager>
#define REQUIRE_PLUGIN

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

#define MAX_SOUND_VAR_NAME 32
#define MAX_SOUND_VAR_VALUE 32

#define BIT_FOR_CLASS(%1) (1 << (view_as<int>(%1)-1))
#define MASK_ALL_CLASSES 0xFFF

#define OBS_MODE_IN_EYE 4

#define WL_Eyes 3

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
	config_flags_always_bonemerge = (1 << 7),
	config_flags_no_voicelines = (1 << 8)
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

	char model[PLATFORM_MAX_PATH];
	TFClassType model_class;
	config_flags flags;
	int skin;
	int bodygroups;
}

enum struct SoundInfo
{
	char path[PLATFORM_MAX_PATH];
	bool is_script;
}

enum struct SoundReplacementInfo
{
	bool source_is_script;
	Regex source_regex;
	ArrayList destinations;
}

enum struct ConfigInfo
{
	char name[MODEL_NAME_MAX];
	int classes_allowed;
	ArrayList variations;

	ArrayList sound_precaches;

	ArrayList sound_replacements;
	StringMap sound_variables;

	char arm_model[PLATFORM_MAX_PATH];
	char model[PLATFORM_MAX_PATH];
	TFClassType model_class;
	config_flags flags;
	int skin;
	int bodygroups;

	char econ_description[ECON_MAX_ITEM_DESCRIPTION];
	int econ_price;
}

enum struct PlayerConfigInfo
{
	int idx;

	ArrayList sound_replacements;
	StringMap sound_variables;

	int classes_allowed;
	char arm_model[PLATFORM_MAX_PATH];
	char model[PLATFORM_MAX_PATH];
	TFClassType model_class;
	config_flags flags;
	int skin;
	int bodygroups;

	void clear()
	{
		this.idx = -1;
		this.classes_allowed = 0;
		this.sound_replacements = null;
		this.sound_variables = null;
		this.flags = config_flags_none;
		this.arm_model[0] = '\0';
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
	int taunt_model_idx;

	void clear()
	{
		this.class = TFClass_Unknown;
		this.class_pre_taunt = TFClass_Unknown;
		this.attempting_to_taunt = false;
		this.taunt_model_idx = -1;
	}
}

#define TF2_MAXPLAYERS 33

static TauntVarsInfo player_taunt_vars[TF2_MAXPLAYERS+1];

static TFClassType player_weapon_animation_class[TF2_MAXPLAYERS+1];

static ThirdpartyModelInfo player_thirdparty_model[TF2_MAXPLAYERS+1];
static ThirdpartyModelInfo player_custom_taunt_model[TF2_MAXPLAYERS+1];
static PlayerConfigInfo player_config[TF2_MAXPLAYERS+1];

static PlayerConfigInfo player_econ_configs[TF2_MAXPLAYERS+1][TF_CLASS_COUNT_ALL];

static GlobalForward fwd_changed;

static int player_model_entity[TF2_MAXPLAYERS+1] = {INVALID_ENT_REFERENCE, ...};
static int player_viewmodel_entities[TF2_MAXPLAYERS+1][2];

static bool player_tpose[TF2_MAXPLAYERS+1];
static bool player_loser[TF2_MAXPLAYERS+1];
static bool player_swim[TF2_MAXPLAYERS+1];

static bool tf_taunt_first_person[TF2_MAXPLAYERS+1];
static bool cl_first_person_uses_world_model[TF2_MAXPLAYERS+1];

static Handle player_weapon_switch_timer[TF2_MAXPLAYERS+1];

static bool dont_handle_SetCustomModel_call;

static char player_custom_model[TF2_MAXPLAYERS+1][PLATFORM_MAX_PATH];
static char player_entity_model[TF2_MAXPLAYERS+1][PLATFORM_MAX_PATH];

static ArrayList weapons_class_cache;
static ConVar tf_always_loser;

static int CTFPlayer_m_Shared_offset = -1;
static int CTFPlayer_m_PlayerClass_offset = -1;
static int CTFPlayer_m_flInvisibility_offset = -1;
static int CEconItemView_m_iAttributeDefinitionIndex_offset = -1;

static DynamicHook CBaseEntity_ModifyOrAppendCriteria_hook;
static DynamicHook CBasePlayer_GetSceneSoundToken_hook;

static Handle CBasePlayer_EquipWearable;
static Handle CTFPlayer_IsAllowedToTaunt;
static Handle CTFPlayerShared_RecalculatePlayerBodygroups;

static Handle AI_CriteriaSet_AppendCriteria;
static Handle AI_CriteriaSet_RemoveCriteria;

static Handle dummy_item_view;

static ArrayList groups;
static ArrayList configs;
static StringMap config_idx_map;

static ConfigGroupInfo econ_group;
static StringMap econ_to_config_map;

static int no_damage_gameplay_group = INVALID_GAMEPLAY_GROUP;
static bool tauntmanager_loaded;
static bool economy_loaded;
static bool proxysend_loaded;

static ConVar randomizer_fix_taunt;

static int modelprecache = INVALID_STRING_TABLE;

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

static int native_pm2_get_model(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	int len = GetNativeCell(3);

	TFClassType player_class = get_player_class(client);

	if(player_thirdparty_model[client].model[0] != '\0') {
		SetNativeString(2, player_thirdparty_model[client].model, len);
	} else if((player_config[client].model[0] != '\0') && !!(player_config[client].classes_allowed & BIT_FOR_CLASS(player_class))) {
		SetNativeString(2, player_config[client].model, len);
	} else if(player_econ_configs[client][player_class].model[0] != '\0') {
		SetNativeString(2, player_econ_configs[client][player_class].model, len);
	} else {
		SetNativeString(2, "", len);
	}

	return 0;
}

static int native_pm2_is_thirdperson(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	return is_player_in_thirdperson(client);
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("playermodel2");
	CreateNative("pm2_get_model", native_pm2_get_model);
	CreateNative("pm2_is_thirdperson", native_pm2_is_thirdperson);
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

	SoundReplacementInfo sound_info;

	ConfigInfo config_info;
	len = configs.Length;
	for(int i = 0; i < len; ++i) {
		configs.GetArray(i, config_info, sizeof(ConfigInfo));
		delete config_info.variations;
		int replacements_len = config_info.sound_replacements.Length;
		for(int k = 0; k < replacements_len; ++k) {
			config_info.sound_replacements.GetArray(k, sound_info, sizeof(SoundReplacementInfo));
			delete sound_info.destinations;
			delete sound_info.source_regex;
		}
		delete config_info.sound_replacements;
		delete config_info.sound_precaches;
		delete config_info.sound_variables;
	}
	delete configs;
	delete config_idx_map;
	delete econ_to_config_map;
}

static bool parse_classes_str(int &classes, const char[] str, const char[] modelname)
{
	if(StrEqual(str, "all") || StrEqual(str, "any")) {
		classes = MASK_ALL_CLASSES;
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
		} else if(StrEqual(strs[i][start], "no_voicelines")) {
			REMOVE_OR_ADD_FLAG(flags, config_flags_no_voicelines)
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
			new_body |= BODYGROUP_SOLDIER_HELMET|BODYGROUP_SOLDIER_GRENADES;
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

static bool parse_config_kv_basic(KeyValues kv, ConfigInfo info, config_flags flags)
{
	bool valid = true;

	char any_file_path[PLATFORM_MAX_PATH];
	char regex_error_str[128];

	char flags_str[FLAGS_MAX * FLAGS_NUM];
	kv.GetString("flags", flags_str, sizeof(flags_str), "");
	info.flags = parse_flags_str(flags_str, flags);

	kv.GetString("arm_model", info.arm_model, PLATFORM_MAX_PATH, info.arm_model);

	SoundInfo sound_info;

	if(kv.JumpToKey("precache")) {
		if(kv.JumpToKey("sounds")) {
			if(!info.sound_precaches) {
				info.sound_precaches = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
			}

			if(kv.GotoFirstSubKey(false)) {
				char sound_value[32];

				do {
					kv.GetSectionName(sound_info.path, PLATFORM_MAX_PATH);
					kv.GetString(NULL_STRING, sound_value, PLATFORM_MAX_PATH, "");
					sound_info.is_script = StrEqual(sound_value, "script");
					info.sound_precaches.PushArray(sound_info, sizeof(SoundInfo));
				} while(kv.GotoNextKey(false));
				kv.GoBack();
			}
			kv.GoBack();
		}
		kv.GoBack();
	}

	if(kv.JumpToKey("sound_replacements")) {
		SoundReplacementInfo sound_replace_info;

		if(kv.JumpToKey("sample")) {
			if(!info.sound_replacements) {
				info.sound_replacements = new ArrayList(sizeof(SoundReplacementInfo));
			}

			sound_replace_info.source_is_script = false;

			if(kv.GotoFirstSubKey(false)) {
				do {
					kv.GetSectionName(any_file_path, PLATFORM_MAX_PATH);

					RegexError regex_code;
					sound_replace_info.source_regex = new Regex(any_file_path, PCRE_UTF8, regex_error_str, sizeof(regex_error_str), regex_code);
					if(regex_code != REGEX_ERROR_NONE) {
						delete sound_replace_info.source_regex;
						LogError(PM2_CON_PREFIX ... " config %s has invalid sound replace regex \"%s\": \"%s\" (%i)", info.name, any_file_path, regex_error_str, regex_code);
						valid = false;
						break;
					}

				#if defined DEBUG_CONFIG
					PrintToServer(PM2_CON_PREFIX ... "created regex %s", any_file_path);
				#endif

					if(kv.GotoFirstSubKey(false)) {
						char value[7];

						sound_replace_info.destinations = new ArrayList(sizeof(SoundInfo));

						do {
							kv.GetSectionName(sound_info.path, PLATFORM_MAX_PATH);
							kv.GetString(NULL_STRING, value, 7, "sample");
							sound_info.is_script = StrEqual(value, "script");

							sound_replace_info.destinations.PushArray(sound_info, sizeof(SoundInfo));
						} while(kv.GotoNextKey(false));
						kv.GoBack();
					}

					info.sound_replacements.PushArray(sound_replace_info, sizeof(SoundReplacementInfo));
				} while(kv.GotoNextKey(false));
				kv.GoBack();
			}

			if(!valid) {
				delete info.sound_replacements;
			}

			kv.GoBack();
		}
		kv.GoBack();
	}

	if(!valid) {
		return false;
	}

	if(kv.JumpToKey("sound_variables")) {
		if(kv.GotoFirstSubKey(false)) {
			if(!info.sound_variables) {
				info.sound_variables = new StringMap();
			}

			char sound_var_name[MAX_SOUND_VAR_NAME];
			char sound_var_value[MAX_SOUND_VAR_VALUE];

			do {
				kv.GetSectionName(sound_var_name, MAX_SOUND_VAR_NAME);
				kv.GetString(NULL_STRING, sound_var_value, MAX_SOUND_VAR_VALUE);

				info.sound_variables.SetString(sound_var_name, sound_var_value);
			} while(kv.GotoNextKey(false));
			kv.GoBack();
		}
		kv.GoBack();
	}

	return true;
}

void clone_config_basic(ConfigInfo info, ConfigInfo other)
{
	strcopy(info.arm_model, MODEL_NAME_MAX, other.arm_model);

	if(other.sound_precaches != null) {
		info.sound_precaches = other.sound_precaches.Clone();
	} else {
		info.sound_precaches = null;
	}

	if(other.sound_replacements != null) {
		SoundReplacementInfo other_sound_info;
		SoundReplacementInfo sound_info;

		info.sound_replacements = other.sound_replacements.Clone();

		int replacements_len = other.sound_replacements.Length;
		for(int k = 0; k < replacements_len; ++k) {
			other.sound_replacements.GetArray(k, other_sound_info, sizeof(SoundReplacementInfo));
			info.sound_replacements.GetArray(k, sound_info, sizeof(SoundReplacementInfo));
			sound_info.destinations = other_sound_info.destinations.Clone();
			sound_info.source_regex = view_as<Regex>(CloneHandle(other_sound_info.source_regex));
			info.sound_replacements.SetArray(k, sound_info, sizeof(SoundReplacementInfo));
		}
	} else {
		info.sound_replacements = null;
	}

	if(other.sound_variables != null) {
		info.sound_variables = other.sound_variables.Clone();
	} else {
		info.sound_variables = null;
	}
}

static void parse_config_kv(const char[] path, ConfigGroupInfo group, ConfigInfo group_config_info, bool econ = false)
{
	KeyValues kv = new KeyValues("playermodel2_config");
	kv.ImportFromFile(path);

	if(kv.GotoFirstSubKey()) {
		group.configs = new ArrayList();

		ConfigInfo info;
		ConfigVariationInfo variation;

		char flags_str[FLAGS_MAX * FLAGS_NUM];
		char classes_str[CLASS_NAME_MAX * TF_CLASS_COUNT_ALL];
		char int_str[INT_STR_MAX];
		char classname[CLASS_NAME_MAX];
		char bodygroups_str[BODYGROUP_NUM * BODYGROUP_MAX];

		do {
			bool valid = true;

			kv.GetSectionName(info.name, MODEL_NAME_MAX);

			clone_config_basic(info, group_config_info);

			if(!parse_config_kv_basic(kv, info, group_config_info.flags)) {
				continue;
			}

			if(econ) {
				info.econ_price = kv.GetNum("price");

				kv.GetString("description", info.econ_description, ECON_MAX_ITEM_DESCRIPTION, "");
			}

			kv.GetString("classes_whitelist", classes_str, sizeof(classes_str), "all");

			info.classes_allowed = 0;

			if(classes_str[0] != '\0') {
				if(!parse_classes_str(info.classes_allowed, classes_str, info.name)) {
					continue;
				}
			}

			kv.GetString("model", info.model, PLATFORM_MAX_PATH, "");

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

						kv.GetString("model", variation.model, PLATFORM_MAX_PATH, "");

						kv.GetString("model_class", classname, CLASS_NAME_MAX, "unknown");
						variation.model_class = TF2_GetClass(classname);

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

static void free_group_config_info(ConfigInfo group_config_info)
{
	if(group_config_info.sound_replacements != null) {
		int replacements_len = group_config_info.sound_replacements.Length;
		SoundReplacementInfo sound_info;
		for(int k = 0; k < replacements_len; ++k) {
			group_config_info.sound_replacements.GetArray(k, sound_info, sizeof(SoundReplacementInfo));
			delete sound_info.destinations;
			delete sound_info.source_regex;
		}
	}
	delete group_config_info.sound_replacements;
	delete group_config_info.sound_precaches;
	delete group_config_info.sound_variables;
}

static void load_configs()
{
	configs = new ArrayList(sizeof(ConfigInfo));
	config_idx_map = new StringMap();
	econ_to_config_map = new StringMap();

	groups = new ArrayList(sizeof(ConfigGroupInfo));

	char any_file_path[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, any_file_path, PLATFORM_MAX_PATH, "configs/playermodels2/groups.txt");
	if(FileExists(any_file_path)) {
		KeyValues kv = new KeyValues("playermodel2_groups");
		kv.ImportFromFile(any_file_path);

		if(kv.GotoFirstSubKey()) {
			ConfigGroupInfo info;

			ConfigInfo group_config_info;

			do {
				kv.GetSectionName(info.name, MODEL_NAME_MAX);
				kv.GetString("override", info.override, OVERRIDE_MAX);
				kv.GetString("steamid", info.steamid, STEAMID_MAX);

				kv.GetString("file", any_file_path, PLATFORM_MAX_PATH, "");
				if(any_file_path[0] == '\0') {
					BuildPath(Path_SM, any_file_path, PLATFORM_MAX_PATH, "configs/playermodels2/%s.txt", info.name);
				}
				if(FileExists(any_file_path)) {
					parse_config_kv_basic(kv, group_config_info, config_flags_none);

					parse_config_kv(any_file_path, info, group_config_info);
				}

				free_group_config_info(group_config_info);

				groups.PushArray(info, sizeof(ConfigGroupInfo));
			} while(kv.GotoNextKey());

			kv.GoBack();
		}

		delete kv;
	}

	BuildPath(Path_SM, any_file_path, PLATFORM_MAX_PATH, "configs/playermodels2/econ.txt");
	if(FileExists(any_file_path)) {
		ConfigInfo group_config_info;
		parse_config_kv(any_file_path, econ_group, group_config_info, true);
		free_group_config_info(group_config_info);
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
		for(TFClassType j = TFClass_Scout; j <= TFClass_Engineer; ++j) {
			player_econ_configs[i][j].clear();
		}
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

	CBaseEntity_ModifyOrAppendCriteria_hook = DynamicHook.FromConf(gamedata, "CBaseEntity::ModifyOrAppendCriteria");
	CBasePlayer_GetSceneSoundToken_hook = DynamicHook.FromConf(gamedata, "CBasePlayer::GetSceneSoundToken");

	delete gamedata;

	fwd_changed = new GlobalForward("pm2_model_changed", ET_Ignore, Param_Cell);

	HookEvent("player_death", player_death);
	HookEvent("player_spawn", player_spawn);

	HookEvent("post_inventory_application", post_inventory_application);

	HookEvent("player_changeclass", player_changeclass);

	dummy_item_view = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
	TF2Items_SetClassname(dummy_item_view, "tf_wearable");
	TF2Items_SetItemIndex(dummy_item_view, 65535);
	TF2Items_SetQuality(dummy_item_view, 0);
	TF2Items_SetLevel(dummy_item_view, 0);
	TF2Items_SetNumAttributes(dummy_item_view, 0);

	//AddNormalSoundHook(sound_hook);

	weapons_class_cache = new ArrayList(sizeof(WeaponClassCache));

	CTFPlayer_m_Shared_offset = FindSendPropInfo("CTFPlayer", "m_Shared");
	CTFPlayer_m_PlayerClass_offset = FindSendPropInfo("CTFPlayer", "m_PlayerClass");

	//TODO!! unhardcode?
	CTFPlayer_m_flInvisibility_offset = FindSendPropInfo("CTFPlayer", "m_flInvisChangeCompleteTime") - 8;

	tf_always_loser = FindConVar("tf_always_loser");
	tf_always_loser.AddChangeHook(tf_always_loser_changed);

	load_configs();

	RegAdminCmd("sm_rpm", sm_rpm, ADMFLAG_ROOT);
	RegConsoleCmd("sm_pm", sm_pm);

	RegConsoleCmd("sm_civilian", sm_civilian);
	RegConsoleCmd("sm_civ", sm_civilian);
	RegConsoleCmd("sm_tpose", sm_civilian);

	RegConsoleCmd("sm_loser", sm_loser);

	RegConsoleCmd("sm_swim", sm_swim);

	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i)) {
			continue;
		}

		OnClientPutInServer(i);

		if(!is_player_state_valid(i)) {
			continue;
		}

		on_player_spawned(i);
	}

	proxysend_loaded = LibraryExists("proxysend");
}

static bool is_player_state_valid(int client)
{
	if(!IsPlayerAlive(client) ||
		GetClientTeam(client) < 2 ||
		TF2_GetPlayerClass(client) == TFClass_Unknown) {
		return false;
	}

	return true;
}

static void set_player_screen_overlay(int client, const char[] path)
{
	int flags = GetCommandFlags("r_screenoverlay");
	SetCommandFlags("r_screenoverlay", flags & ~FCVAR_CHEAT);
	ClientCommand(client, "r_screenoverlay \"%s\"", path);
	SetCommandFlags("r_screenoverlay", flags);
}

static void frame_enable_swim(int client)
{
	set_player_screen_overlay(client, "");
}

static Action sm_swim(int client, int args)
{
	player_swim[client] = !player_swim[client];

	if(player_swim[client]) {
		RequestFrame(frame_enable_swim, client);
		if(proxysend_loaded) {
			proxysend_hook_cond(client, TFCond_SwimmingCurse, player_proxysend_swim_cond, false);
			proxysend_hook(client, "m_nWaterLevel", player_proxysend_water_level, false);
		}
		CReplyToCommand(client, PM2_CHAT_PREFIX ... "You are now swimming!");
	} else {
		if(proxysend_loaded) {
			proxysend_unhook(client, "m_nWaterLevel", player_proxysend_water_level);
			proxysend_unhook_cond(client, TFCond_SwimmingCurse, player_proxysend_swim_cond);
		}
		CReplyToCommand(client, PM2_CHAT_PREFIX ... "You are no longer swimming.");
	}

	return Plugin_Handled;
}

static Action sm_civilian(int client, int args)
{
	player_tpose[client] = !player_tpose[client];

	if(player_tpose[client]) {
		TF2_RemoveAllWeapons(client);
		SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 0);
		CReplyToCommand(client, PM2_CHAT_PREFIX ... "You are now a civilian!");
	} else {
		SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 1);
		CReplyToCommand(client, PM2_CHAT_PREFIX ... "You are no longer a civilian.");
	}

	return Plugin_Handled;
}

static Action sm_loser(int client, int args)
{
	player_loser[client] = !player_loser[client];

	if(player_loser[client]) {
		TF2_RemoveAllWeapons(client);
		if(proxysend_loaded) {
			proxysend_hook_cond(client, TFCond_Dazed, player_proxysend_loser_cond, false);
			proxysend_hook(client, "m_iStunFlags", player_proxysend_stunflags, false);
			proxysend_hook(client, "m_iStunIndex", player_proxysend_stunindex, false);
		}
		CReplyToCommand(client, PM2_CHAT_PREFIX ... "You are now a loser! Congratulations.");
	} else {
		if(proxysend_loaded) {
			proxysend_unhook_cond(client, TFCond_Dazed, player_proxysend_loser_cond);
			proxysend_unhook(client, "m_iStunFlags", player_proxysend_stunflags);
			proxysend_unhook(client, "m_iStunIndex", player_proxysend_stunindex);
		}
		CReplyToCommand(client, PM2_CHAT_PREFIX ... "You are no longer a loser! Congratulations.");
	}

	return Plugin_Handled;
}

static void tf_always_loser_changed(ConVar convar, const char[] oldValue, const char[] newValue)
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			!is_player_state_valid(i)) {
			continue;
		}

		if(!player_taunts_in_firstperson(i)) {
			int weapon = GetEntPropEnt(i, Prop_Send, "m_hActiveWeapon");
			handle_viewmodel(i, weapon);
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
			StrEqual(model, "models/player/saxton_hale_jungle_inferno/saxton_hale.mdl")
		) {
			player_thirdparty_model[client].bonemerge = false;
		}

		if(StrContains(model, "models/bots/") == 0) {
			if(strncmp(model[12], "demo", 4) == 0) {
				player_thirdparty_model[client].class = TFClass_DemoMan;
			} else if(strncmp(model[12], "engineer", 8) == 0) {
				player_thirdparty_model[client].class = TFClass_Engineer;
			} else if(strncmp(model[12], "heavy", 5) == 0) {
				player_thirdparty_model[client].class = TFClass_Heavy;
			} else if(strncmp(model[12], "medic", 5) == 0) {
				player_thirdparty_model[client].class = TFClass_Medic;
			} else if(strncmp(model[12], "pyro", 4) == 0) {
				player_thirdparty_model[client].class = TFClass_Pyro;
			} else if(strncmp(model[12], "scout", 5) == 0) {
				player_thirdparty_model[client].class = TFClass_Scout;
			} else if(strncmp(model[12], "sniper", 6) == 0) {
				player_thirdparty_model[client].class = TFClass_Sniper;
			} else if(strncmp(model[12], "soldier", 7) == 0) {
				player_thirdparty_model[client].class = TFClass_Soldier;
			} else if(strncmp(model[12], "spy", 6) == 0) {
				player_thirdparty_model[client].class = TFClass_Spy;
			} else if(strncmp(model[12], "skeleton_sniper", 15) == 0) {
				player_thirdparty_model[client].class = TFClass_Sniper;
			} else if(strncmp(model[12], "merasmus", 8) == 0) {
				player_thirdparty_model[client].class = TFClass_Sniper;
			} else if(StrEqual(model[12], "headless_hatman.mdl")) {
				player_thirdparty_model[client].class = TFClass_DemoMan;
			}
		}
	}

	RequestFrame(CTFPlayerClassShared_SetCustomModel_detour_frame, GetClientUserId(client));

	return MRES_Supercede;
}

static MRESReturn CTFPlayerShared_RecalculatePlayerBodygroups_detour_post(Address pThis)
{
	return MRES_Ignored;
}

public void OnAllPluginsLoaded()
{
	tauntmanager_loaded = LibraryExists("tauntmanager");
	economy_loaded = LibraryExists("economy");

	randomizer_fix_taunt = FindConVar("randomizer_fix_taunt");
	if(randomizer_fix_taunt != null) {
		randomizer_fix_taunt.BoolValue = false;
	}
}

public void OnConfigsExecuted()
{
	if(randomizer_fix_taunt != null) {
		randomizer_fix_taunt.BoolValue = false;
	}
}

static void on_econ_cat_registered(int cat_idx)
{
	ConfigInfo info;

	int len = econ_group.configs.Length;
	for(int i = 0; i < len; ++i) {
		int conf_idx = econ_group.configs.Get(i);

		configs.GetArray(conf_idx, info, sizeof(ConfigInfo));

		econ_get_or_register_item(cat_idx, info.name, "", "playermodel", info.econ_price, null);
	}
}

public void econ_loaded()
{
	econ_get_or_register_category("Playermodels", ECON_INVALID_CATEGORY, on_econ_cat_registered);
}

public Action econ_items_conflict(const char[] classname1, int item1_idx, const char[] classname2, int item2_idx)
{
	if(!StrEqual(classname2, "playermodel")) {
		return Plugin_Continue;
	}

	int conf_idx1 = econ_idx_to_conf_idx(item1_idx);
	int conf_idx2 = econ_idx_to_conf_idx(item2_idx);
	if(conf_idx1 == -1 || conf_idx2 == -1) {
		return Plugin_Continue;
	}

	int classes1 = configs.Get(conf_idx1, ConfigInfo::classes_allowed);
	int classes2 = configs.Get(conf_idx2, ConfigInfo::classes_allowed);

	if(classes1 == classes2 ||
		classes1 & classes2) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

static int econ_idx_to_conf_idx(int idx)
{
	char str[5];
	pack_int_in_str(idx, str);

	int conf_idx = -1;
	econ_to_config_map.GetValue(str, conf_idx);

	return conf_idx;
}

public void econ_cache_item(const char[] classname, int item_idx, StringMap settings)
{
	char name[ECON_MAX_ITEM_NAME];
	econ_get_item_name(item_idx, name, ECON_MAX_ITEM_NAME);

	int conf_idx = -1;
	config_idx_map.GetValue(name, conf_idx);

	char str[5];
	pack_int_in_str(item_idx, str);

	econ_to_config_map.SetValue(str, conf_idx);
}

public void econ_modify_menu(const char[] classname, int item_idx)
{
	int conf_idx = econ_idx_to_conf_idx(item_idx);
	if(conf_idx == -1) {
		return;
	}

	ConfigInfo config_info;
	configs.GetArray(conf_idx, config_info, sizeof(ConfigInfo));

	int classes_str_len = (CLASS_NAME_MAX * TF_CLASS_COUNT_ALL);
	char[] classes_str = new char[classes_str_len];
	strcopy(classes_str, classes_str_len, "Classes: ");

	if(config_info.classes_allowed == MASK_ALL_CLASSES) {
		StrCat(classes_str, classes_str_len, "all");
	} else {
		char tmp_classname[CLASS_NAME_MAX];
		for(TFClassType i = TFClass_Scout; i <= TFClass_Engineer; ++i) {
			if(config_info.classes_allowed & BIT_FOR_CLASS(i)) {
				get_class_name(i, tmp_classname, CLASS_NAME_MAX);

				StrCat(classes_str, classes_str_len, tmp_classname);
				StrCat(classes_str, classes_str_len, "|");
			}
		}

		classes_str_len = strlen(classes_str);
		classes_str[classes_str_len-1] = '\0';
	}

	econ_menu_add_item(classes_str);
}

public void econ_handle_item(int client, const char[] classname, int item_idx, int inv_idx, econ_item_action action)
{
	switch(action) {
		case econ_item_equip: {
			unequip_config(client, true);

			int conf_idx = econ_idx_to_conf_idx(item_idx);
			if(conf_idx == -1) {
				return;
			}

			ConfigInfo config_info;
			configs.GetArray(conf_idx, config_info, sizeof(ConfigInfo));

			for(TFClassType i = TFClass_Scout; i <= TFClass_Engineer; ++i) {
				if(config_info.classes_allowed & BIT_FOR_CLASS(i)) {
					copy_config_vars(client, player_econ_configs[client][i], conf_idx, config_info);
				}
			}

			if(IsClientInGame(client) && is_player_state_valid(client)) {
				handle_playermodel(client);
			}
		}
		case econ_item_unequip: {
			int conf_idx = econ_idx_to_conf_idx(item_idx);
			if(conf_idx == -1) {
				return;
			}

			ConfigInfo config_info;
			configs.GetArray(conf_idx, config_info, sizeof(ConfigInfo));

			for(TFClassType i = TFClass_Scout; i <= TFClass_Engineer; ++i) {
				if(config_info.classes_allowed & BIT_FOR_CLASS(i)) {
					player_econ_configs[client][i].clear();
				}
			}

			if(IsClientInGame(client)) {
				handle_playermodel(client);
			}
		}
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "teammanager_gameplay")) {
		no_damage_gameplay_group = TeamManager_NewGameplayGroup(Gameplay_Friendly);
	} else if(StrEqual(name, "tauntmanager")) {
		tauntmanager_loaded = true;
	} else if(StrEqual(name, "economy")) {
		econ_register_item_class("playermodel", true);
		economy_loaded = true;
	} else if(StrEqual(name, "proxysend")) {
		proxysend_loaded = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "teammanager_gameplay")) {
		no_damage_gameplay_group = INVALID_GAMEPLAY_GROUP;
	} else if(StrEqual(name, "tauntmanager")) {
		tauntmanager_loaded = false;
	} else if(StrEqual(name, "economy")) {
		econ_to_config_map.Clear();
		economy_loaded = false;
	} else if(StrEqual(name, "proxysend")) {
		proxysend_loaded = false;
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

static void load_depfile(const char[] model)
{
	char any_file_path[PLATFORM_MAX_PATH];
	Format(any_file_path, PLATFORM_MAX_PATH, "%s.dep", model);
	if(FileExists(any_file_path, true)) {
		File file = OpenFile(any_file_path, "r", true);

		while(!file.EndOfFile()) {
			file.ReadLine(any_file_path, PLATFORM_MAX_PATH);

			clean_file_path(any_file_path);

			if(FileExists(any_file_path, true)) {
				AddFileToDownloadsTable(any_file_path);
			}
		}

		delete file;
	}
}

public void OnMapStart()
{
	PrecacheModel("models/error.mdl");

	modelprecache = FindStringTable("modelprecache");

	ConfigInfo info;
	ConfigVariationInfo variation;

	SoundReplacementInfo sound_replace_info;
	SoundInfo sound_info;

	int configs_len = configs.Length;
	for(int i = 0; i < configs_len; ++i) {
		configs.GetArray(i, info, sizeof(ConfigInfo));

		if(info.model[0] != '\0') {
			PrecacheModel(info.model);
			load_depfile(info.model);
		}

		if(info.sound_replacements != null) {
			int sound_replaces_len = info.sound_replacements.Length;
			for(int j = 0; j < sound_replaces_len; ++j) {
				info.sound_replacements.GetArray(j, sound_replace_info, sizeof(SoundReplacementInfo));
				int sounds_len = sound_replace_info.destinations.Length;
				for(int k = 0; k < sounds_len; ++k) {
					sound_replace_info.destinations.GetArray(k, sound_info, sizeof(SoundInfo));
					if(sound_info.is_script) {
						PrecacheScriptSound(sound_info.path);
					#if defined DEBUG_CONFIG
						PrintToServer(PM2_CON_PREFIX ... "precached sound script %s from replace", sound_info.path);
					#endif
					} else {
						PrecacheSound(sound_info.path);
					#if defined DEBUG_CONFIG
						PrintToServer(PM2_CON_PREFIX ... "precached sound %s from replace", sound_info.path);
					#endif
					}
				}
			}
		}

		if(info.sound_precaches != null) {
			int sounds_len = info.sound_precaches.Length;
			for(int j = 0; j < sounds_len; ++j) {
				info.sound_precaches.GetArray(j, sound_info, sizeof(SoundInfo));
				if(sound_info.is_script) {
					PrecacheScriptSound(sound_info.path);
				#if defined DEBUG_CONFIG
					PrintToServer(PM2_CON_PREFIX ... "precached sound script %s from precache", sound_info.path);
				#endif
				} else {
					PrecacheSound(sound_info.path);
				#if defined DEBUG_CONFIG
					PrintToServer(PM2_CON_PREFIX ... "precached sound %s from precache", sound_info.path);
				#endif
				}
			}
		}

		if(info.variations != null) {
			int variations_len = info.variations.Length;
			for(int j = 0; j < variations_len; ++j) {
				info.variations.GetArray(j, variation, sizeof(ConfigVariationInfo));

				if(variation.model[0] != '\0') {
					PrecacheModel(variation.model);
					load_depfile(variation.model);
				}
			}
		}
	}

	//TODO!!! support for precaching a whole sound folder
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
		if(is_player_state_valid(client)) {
			toggle_player_wearables(client, true);
		}
	}

	if(player_config[client].flags & config_flags_hide_weapons) {
		SDKUnhook(client, SDKHook_PostThinkPost, player_think_weapons_alpha);
		if(is_player_state_valid(client)) {
			toggle_player_weapons(client, true);
		}
	}
}

static void unequip_config(int client, bool force = false)
{
	unequip_config_basic(client);

	player_config[client].clear();

	if(IsClientInGame(client) && is_player_state_valid(client)) {
		handle_playermodel(client);
	}
}

static void copy_config_vars(int client, PlayerConfigInfo plrinfo, int idx, ConfigInfo info)
{
	plrinfo.clear();

	plrinfo.idx = idx;

	if(info.model[0] != '\0') {
		strcopy(plrinfo.model, PLATFORM_MAX_PATH, info.model);
	}

	if(info.arm_model[0] != '\0') {
		strcopy(plrinfo.arm_model, PLATFORM_MAX_PATH, info.arm_model);
	}

	if(info.skin != -1) {
		plrinfo.skin = info.skin;
	}

	if(info.bodygroups != -1) {
		plrinfo.bodygroups = info.bodygroups;
	}

	plrinfo.classes_allowed = info.classes_allowed;

	plrinfo.sound_variables = info.sound_variables;
	plrinfo.sound_replacements = info.sound_replacements;
	plrinfo.flags = info.flags;
	plrinfo.model_class = info.model_class;

	if(plrinfo.flags & config_flags_no_gameplay) {
		TeamManager_AddPlayerToGameplayGroup(client, no_damage_gameplay_group);
		CPrintToChat(client, PM2_CHAT_PREFIX ... "the model you equipped can not participate in normal gameplay");
	}

	if(IsClientInGame(client) && is_player_state_valid(client)) {
		if(plrinfo.flags & config_flags_no_weapons) {
			TF2_RemoveAllWeapons(client);
		}

		if(plrinfo.flags & config_flags_no_wearables) {
			remove_all_player_wearables(client);
		}
	}

	if(plrinfo.flags & config_flags_hide_wearables) {
		SDKHook(client, SDKHook_PostThinkPost, player_think_wearables_alpha);
	}

	if(plrinfo.flags & config_flags_hide_weapons) {
		SDKHook(client, SDKHook_PostThinkPost, player_think_weapons_alpha);
	}
}

static bool equip_config_basic(int client, int idx, ConfigInfo info)
{
	unequip_config_basic(client);

	copy_config_vars(client, player_config[client], idx, info);

	return true;
}

static void equip_config(int client, int idx, ConfigInfo info)
{
	if(!equip_config_basic(client, idx, info)) {
		return;
	}

	if(is_player_state_valid(client)) {
		if(!player_taunts_in_firstperson(client)) {
			int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
			handle_viewmodel(client, weapon);
		}

		handle_playermodel(client);
	}
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

	if(variation.model[0] != '\0') {
		strcopy(player_config[client].model, PLATFORM_MAX_PATH, variation.model);
	}

	if(variation.model_class != TFClass_Unknown) {
		player_config[client].model_class = variation.model_class;
	}

	if(!player_taunts_in_firstperson(client)) {
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		handle_viewmodel(client, weapon);
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

	menu.AddItem("-2", info.name);

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

	TFClassType class = TF2_GetPlayerClass(client);

	int len = group.configs.Length;
	for(int i = 0; i < len; ++i) {
		idx = group.configs.Get(i);

		configs.GetArray(idx, info, sizeof(ConfigInfo));

		if(!(info.classes_allowed & BIT_FOR_CLASS(class))) {
			continue;
		}

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
	SDKHook(client, SDKHook_PostThinkPost, player_think_taunt_prop);

	handle_playermodel(client);
}

static void player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(TF2_GetPlayerClass(client) == TFClass_Unknown ||
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
		SDKUnhook(client, SDKHook_PostThinkPost, player_think_taunt_prop);

		if(proxysend_loaded) {
			proxysend_unhook_cond(client, TFCond_SwimmingCurse, player_proxysend_swim_cond);

			proxysend_unhook_cond(client, TFCond_Dazed, player_proxysend_loser_cond);
			proxysend_unhook(client, "m_iStunFlags", player_proxysend_stunflags);
			proxysend_unhook(client, "m_iStunIndex", player_proxysend_stunindex);
		}

		if(player_tpose[client]) {
			SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 1);
		}
		player_tpose[client] = false;
		player_loser[client] = false;
		player_swim[client] = false;

		remove_playermodel(client);
	}
}

static Action timer_ragdoll_reset_model(Handle timer, DataPack data)
{
	data.Reset();

	int owner = GetClientOfUserId(data.ReadCell());
	if(owner == 0) {
		return Plugin_Continue;
	}

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

	TFClassType player_class = get_player_class(owner);

	char model[PLATFORM_MAX_PATH];
	if(player_thirdparty_model[owner].model[0] != '\0') {
		strcopy(model, PLATFORM_MAX_PATH, player_thirdparty_model[owner].model);
		if(player_thirdparty_model[owner].class != TFClass_Unknown) {
			SetEntProp(entity, Prop_Send, "m_iClass", player_thirdparty_model[owner].class);
		}
	} else if((player_config[owner].model[0] != '\0') && !!(player_config[owner].classes_allowed & BIT_FOR_CLASS(player_class))) {
		strcopy(model, PLATFORM_MAX_PATH, player_config[owner].model);
		if(player_config[owner].model_class != TFClass_Unknown) {
			SetEntProp(entity, Prop_Send, "m_iClass", player_config[owner].model_class);
		}
	} else if(player_econ_configs[owner][player_class].model[0] != '\0') {
		strcopy(model, PLATFORM_MAX_PATH, player_econ_configs[owner][player_class].model);
		if(player_econ_configs[owner][player_class].model_class != TFClass_Unknown) {
			SetEntProp(entity, Prop_Send, "m_iClass", player_econ_configs[owner][player_class].model_class);
		}
	}

	//SetEntPropString(owner, Prop_Send, "m_iszCustomModel", model);
	set_player_custom_model(owner, model);

	DataPack data;
	CreateDataTimer(0.1, timer_ragdoll_reset_model, data);
	data.WriteCell(GetClientUserId(owner));
	data.WriteString(model_original);
}

static void frame_taunt_prop_created(int entity)
{
#if defined DEBUG_TAUNT
	PrintToServer(PM2_CON_PREFIX ... "taunt prop created");
#endif
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "tf_ragdoll")) {
		RequestFrame(frame_ragdoll_created, entity);
	} else if(StrEqual(classname, "tf_taunt_prop")) {
		RequestFrame(frame_taunt_prop_created, entity);
	}
}

static void get_class_name(TFClassType type, char[] name, int length)
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

static void get_taunt_prop_models(int id, ArrayList &models, ArrayList &classes)
{
	char class_name[CLASS_NAME_MAX];
	char key[41 + CLASS_NAME_MAX];
	char model[PLATFORM_MAX_PATH];

	bool has_intro = false;

	for(TFClassType i = TFClass_Scout; i <= TFClass_Engineer; ++i) {
		get_class_name(i, class_name, CLASS_NAME_MAX);

		FormatEx(key, sizeof(key), "taunt/custom_taunt_prop_scene_per_class/%s", class_name);

		if(TF2Econ_GetItemDefinitionString(id, key, model, PLATFORM_MAX_PATH)) {
			has_intro = true;
			break;
		}
	}

	if(!has_intro) {
		models = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
		classes = new ArrayList();

		for(TFClassType i = TFClass_Scout; i <= TFClass_Engineer; ++i) {
			get_class_name(i, class_name, CLASS_NAME_MAX);

			FormatEx(key, sizeof(key), "taunt/custom_taunt_prop_per_class/%s", class_name);

			if(TF2Econ_GetItemDefinitionString(id, key, model, PLATFORM_MAX_PATH)) {
				models.PushString(model);
				classes.Push(i);
			}
		}

		if(models.Length == 0) {
			delete classes;
			delete models;
		}
	}
}

public Action TauntManager_ApplyTauntModel(int client, const char[] tauntModel, TFClassType modelClass, bool hasBonemergeSupport)
{
#if defined DEBUG_TAUNT
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
#if defined DEBUG_TAUNT
	PrintToServer(PM2_CON_PREFIX ... "TauntManager_RemoveTauntModel");
#endif
	player_custom_taunt_model[client].clear();
	return Plugin_Handled;
}

public void TauntManager_OnCodeTauntStatePre(int client)
{
	handle_taunt_attempt_pre_safe(client);

#if defined _tauntmanager_included_
	if(tauntmanager_loaded) {
		TauntManager_CodeTaunt code_taunt = TauntManager_GetCurrentCodeTaunt(client);
		if(code_taunt != TauntManager_InvalidCodeTaunt) {
			ArrayList supported_classes = new ArrayList();
			TauntManager_GetCodeTauntUsableClasses(code_taunt, supported_classes);
			handle_taunt_attempt(client, supported_classes);
			delete supported_classes;
		}
	}
#endif
}

public void TauntManager_OnCodeTauntStatePost(int client)
{
	handle_taunt_attempt_post(client);
}

//TODO!!! refactor this
static void handle_taunt_attempt(int client, ArrayList supported_classes)
{
	TFClassType player_class = get_player_class(client);

	int len = supported_classes.Length;
	if(len > 0) {
		TFClassType desired_class = TFClass_Unknown;
		if(player_custom_taunt_model[client].class != TFClass_Unknown) {
			desired_class = player_custom_taunt_model[client].class;
		} else if(supported_classes.FindValue(player_class) != -1) {
			desired_class = player_class;
		} else {
			desired_class = supported_classes.Get(GetRandomInt(0, len-1));
		}
		player_taunt_vars[client].class = desired_class;
		handle_playermodel(client);
		TF2_SetPlayerClass(client, desired_class);
	}
}

static bool handle_taunt_attempt_pre_safe(int client)
{
	player_taunt_vars[client].class = TFClass_Unknown;

	player_taunt_vars[client].attempting_to_taunt = true;
	player_taunt_vars[client].class_pre_taunt = TF2_GetPlayerClass(client);

	return true;
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
	TauntManager_CodeTaunt code_taunt = TauntManager_InvalidCodeTaunt;
	if(tauntmanager_loaded) {
		code_taunt = TauntManager_GetCurrentCodeTaunt(pThis);
		if(code_taunt != TauntManager_InvalidCodeTaunt) {
			TauntManager_GetCodeTauntUsableClasses(code_taunt, supported_classes);
		}
	}
	if(code_taunt == TauntManager_InvalidCodeTaunt)
#endif
	{
		int weapon = GetEntPropEnt(pThis, Prop_Send, "m_hActiveWeapon");
		if(weapon != -1) {
			TFClassType player_class = get_player_class(pThis);
			TFClassType weapon_class = get_class_for_weapon(weapon, player_class);
			supported_classes.Push(weapon_class);
		}
	}

	handle_taunt_attempt(pThis, supported_classes);

	delete supported_classes;

#if defined DEBUG_TAUNT
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
		ArrayList supported_classes;
		ArrayList models;
		get_taunt_prop_models(m_iAttributeDefinitionIndex, models, supported_classes)

		if(supported_classes != null) {
			TFClassType player_class = player_taunt_vars[pThis].class_pre_taunt;

			int idx = supported_classes.FindValue(player_class);
			if(idx == -1) {
				idx = GetRandomInt(0, supported_classes.Length-1);
			}

			char model[PLATFORM_MAX_PATH];
			models.GetString(idx, model, PLATFORM_MAX_PATH);

			player_taunt_vars[pThis].taunt_model_idx = get_model_index(model);

			delete models;
			delete supported_classes;
		}

		supported_classes = get_classes_for_taunt(m_iAttributeDefinitionIndex);

		handle_taunt_attempt(pThis, supported_classes);

		delete supported_classes;
	}

#if defined DEBUG_TAUNT
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
#if defined DEBUG_TAUNT
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
#if defined DEBUG_TAUNT
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
#if defined DEBUG_TAUNT && 0
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
#if defined DEBUG_TAUNT
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
#if defined DEBUG_TAUNT
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
#if defined DEBUG_TAUNT
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
#if defined DEBUG_TAUNT && 0
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
#if defined DEBUG_TAUNT
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
		#if defined DEBUG_TAUNT
			PrintToServer(PM2_CON_PREFIX ... "TF2_OnConditionAdded taunt");
		#endif
			player_taunt_vars[client].attempting_to_taunt = true;
		}
		case TFCond_Disguised:
		{
			if(get_player_model_entity(client) == -1 &&
				player_custom_model[client][0] == '\0') {
				return;
			}

			remove_playermodel(client);

			Call_StartForward(fwd_changed);
			Call_PushCell(client);
			Call_Finish();
		}
	}
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	switch(condition) {
		case TFCond_Taunting: {
		#if defined DEBUG_TAUNT
			PrintToServer(PM2_CON_PREFIX ... "TF2_OnConditionRemoved taunt");
		#endif
			player_taunt_vars[client].clear();
			player_custom_taunt_model[client].clear();
			int len = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
			for(int i = 0; i < len; ++i) {
				int entity = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
				if(entity != -1) {
					SetEntProp(entity, Prop_Send, "m_nModelIndexOverrides", 0, _, 0);
				}
			}
			if(!player_taunts_in_firstperson(client)) {
				int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
				handle_viewmodel(client, weapon);
			}
			handle_playermodel(client);
		}
		case TFCond_HalloweenThriller,
				TFCond_Bonked,
				TFCond_HalloweenKart,
				TFCond_HalloweenBombHead,
				TFCond_HalloweenGiant,
				TFCond_HalloweenTiny,
				TFCond_HalloweenGhostMode,
				TFCond_MeleeOnly,
				TFCond_SwimmingCurse: {
			if(!player_taunts_in_firstperson(client)) {
				int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
				handle_viewmodel(client, weapon);
			}
		}
		case TFCond_Disguised: {
			int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
			handle_viewmodel(client, weapon);
			handle_playermodel(client);
		}
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

static void player_think_taunt_prop(int client)
{
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(weapon != -1) {
		if(player_taunt_vars[client].taunt_model_idx != -1) {
			SetEntProp(weapon, Prop_Send, "m_nModelIndexOverrides", player_taunt_vars[client].taunt_model_idx, _, 0);
		}
	}
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
			return;
		}
	}

	ReadStringTable(modelprecache, idx, model, len);
}

static TFClassType get_player_class(int client)
{
	if(player_taunt_vars[client].class_pre_taunt != TFClass_Unknown) {
		return player_taunt_vars[client].class_pre_taunt;
	} else {
		return TF2_GetPlayerClass(client);
	}
}

static void handle_viewmodel(int client, int weapon)
{
	if(weapon == -1) {
		delete_player_viewmodel_entities(client);
		return;
	}

	TFClassType player_class = get_player_class(client);
	TFClassType weapon_class = get_class_for_weapon(weapon, player_class);

	if(weapon_class != TFClass_Unknown) {
		int viewmodel_index = GetEntProp(weapon, Prop_Send, "m_nViewModelIndex");
		int viewmodel = GetEntPropEnt(client, Prop_Send, "m_hViewModel", viewmodel_index);

		if(viewmodel != -1) {
			char model[PLATFORM_MAX_PATH];
			get_arm_model_for_class(client, weapon_class, model, PLATFORM_MAX_PATH);

			SetEntPropString(viewmodel, Prop_Data, "m_ModelName", model);
			int idx = get_model_index(model);
			SetEntProp(viewmodel, Prop_Send, "m_nModelIndex", idx);
			SetEntProp(weapon, Prop_Send, "m_iViewModelIndex", idx);
			SetEntityModel(weapon, model);

		#if defined DEBUG_VIEWMODEL
			PrintToServer(PM2_CON_PREFIX ... "  weapon_class = %i", weapon_class);
			PrintToServer(PM2_CON_PREFIX ... "  weapon_arm_model = %s, %i", model, idx);
		#endif

			TFClassType arm_class = player_class;

			bool has_custom_arm_model = false;

			if(!TF2_IsPlayerInCondition(client, TFCond_Disguised)) {
				if(!!(player_config[client].classes_allowed & BIT_FOR_CLASS(player_class))) {
					if(StrEqual(player_config[client].arm_model, "model_class")) {
						if(player_config[client].model_class != TFClass_Unknown) {
							arm_class = player_config[client].model_class;
						}
					} else if(player_config[client].arm_model[0] != '\0') {
						has_custom_arm_model = true;
					}
				}
			}

		#if defined DEBUG_VIEWMODEL
			PrintToServer(PM2_CON_PREFIX ... "  arm_class = %i", arm_class);
		#endif

			bool different_class = (arm_class != weapon_class);

			if(different_class || has_custom_arm_model) {
				delete_player_viewmodel_entity(client, 0);
				int entity = get_or_create_player_viewmodel_entity(client, 0);

				SetEntPropEnt(entity, Prop_Send, "m_hWeaponAssociatedWith", weapon);

				SetVariantString("!activator");
				AcceptEntityInput(entity, "SetParent", viewmodel);

				int effects = GetEntProp(entity, Prop_Send, "m_fEffects");
				effects |= (EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES);
				SetEntProp(entity, Prop_Send, "m_fEffects", effects);

				if(has_custom_arm_model) {
					strcopy(model, PLATFORM_MAX_PATH, player_config[client].arm_model);
				} else {
					get_arm_model_for_class(client, arm_class, model, PLATFORM_MAX_PATH);
				}
				idx = get_model_index(model);
			#if defined DEBUG_VIEWMODEL
				PrintToServer(PM2_CON_PREFIX ... "  arm_model = %s, %i", model, idx);
			#endif

				SetEntityModel(entity, model);
				SetEntProp(entity, Prop_Send, "m_nModelIndex", idx);
				SetEntProp(entity, Prop_Send, "m_nBody", 0);

				delete_player_viewmodel_entity(client, 1);

				idx = GetEntProp(weapon, Prop_Send, "m_iWorldModelIndex");
				if(idx != -1) {
					entity = get_or_create_player_viewmodel_entity(client, 1);

					SetEntPropEnt(entity, Prop_Send, "m_hWeaponAssociatedWith", weapon);

					get_model_index_path(idx, model, PLATFORM_MAX_PATH);

				#if defined DEBUG_VIEWMODEL
					PrintToServer(PM2_CON_PREFIX ... "  weapon_model = %s, %i", model, idx);
				#endif

					SetEntityModel(entity, model);
					SetEntProp(entity, Prop_Send, "m_nModelIndex", idx);

					SetVariantString("!activator");
					AcceptEntityInput(entity, "SetParent", viewmodel);

					effects = GetEntProp(entity, Prop_Send, "m_fEffects");
					effects |= (EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES);
					SetEntProp(entity, Prop_Send, "m_fEffects", effects);
				}
			}

			if(different_class || has_custom_arm_model) {
				int effects = GetEntProp(viewmodel, Prop_Send, "m_fEffects");
				effects |= EF_NODRAW;
				SetEntProp(viewmodel, Prop_Send, "m_fEffects", effects);
			} else {
				delete_player_viewmodel_entities(client, weapon);

				int effects = GetEntProp(viewmodel, Prop_Send, "m_fEffects");
				effects &= ~EF_NODRAW;
				SetEntProp(viewmodel, Prop_Send, "m_fEffects", effects);
			}
		} else {
			delete_player_viewmodel_entities(client, weapon);
		}
	}
}

static void handle_weapon_switch(int client, int weapon, bool do_playermodel)
{
#if defined DEBUG_VIEWMODEL
	PrintToServer(PM2_CON_PREFIX ... "handle_weapon_switch(%i)", client);
#endif

	TFClassType weapon_class = TFClass_Unknown;
	if(weapon != -1) {
		TFClassType player_class = get_player_class(client);
		weapon_class = get_class_for_weapon(weapon, player_class);
	}

	player_weapon_animation_class[client] = weapon_class;

	handle_viewmodel(client, weapon);

	if(do_playermodel &&
		!player_taunt_vars[client].attempting_to_taunt &&
		!TF2_IsPlayerInCondition(client, TFCond_Disguised)) {
		handle_playermodel(client);
	}
}

static Action timer_handle_weapon_switch(Handle timer, DataPack data)
{
	data.Reset();

	int client = GetClientOfUserId(data.ReadCell());
	if(client == 0) {
		return Plugin_Continue;
	}

	player_weapon_switch_timer[client] = null;

	int weapon = -1;
	int ref = data.ReadCell();
	if(ref != INVALID_ENT_REFERENCE) {
		weapon = EntRefToEntIndex(ref);
		if(!IsValidEntity(weapon)) {
			weapon = -1;
		}
	}

	handle_weapon_switch(client, weapon, true);

	return Plugin_Continue;
}

static void player_weapon_switch(int client, int weapon)
{
#if defined DEBUG_WEAPONSWITCH
	PrintToServer(PM2_CON_PREFIX ... "player_weapon_switch(%i)", client);
#endif

	if(player_weapon_switch_timer[client] != null) {
		KillTimer(player_weapon_switch_timer[client]);
	}

	DataPack data;
	player_weapon_switch_timer[client] = CreateDataTimer(0.1, timer_handle_weapon_switch, data, TIMER_FLAG_NO_MAPCHANGE);
	data.WriteCell(GetClientUserId(client));
	data.WriteCell(weapon == -1 ? INVALID_ENT_REFERENCE : EntIndexToEntRef(weapon));
}

public void OnPluginEnd()
{
	if(randomizer_fix_taunt != null) {
		randomizer_fix_taunt.BoolValue = true;
	}

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			unequip_config(i, true);
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

static Action player_proxysend_loser_cond(int entity, const char[] prop, int &value, int element, int client)
{
#if defined DEBUG_PROXYSEND
	PrintToServer(PM2_CON_PREFIX ... "player_proxysend_loser_cond(%i, %s, %i, %i, %i)", entity, prop, value, element, client);
#endif
	int weapon = GetEntPropEnt(entity, Prop_Send, "m_hActiveWeapon");
	if((weapon == -1 || player_loser[entity]) && !player_tpose[entity]) {
		value |= get_bit_for_cond(TFCond_Dazed);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

static Action player_proxysend_water_level(int entity, const char[] prop, int &value, int element, int client)
{
	if(player_swim[entity]) {
		value = WL_Eyes;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

static Action player_proxysend_swim_cond(int entity, const char[] prop, int &value, int element, int client)
{
	if(player_swim[entity]) {
		value |= get_bit_for_cond(TFCond_SwimmingCurse);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

static Action player_proxysend_stunflags(int entity, const char[] prop, int &value, int element, int client)
{
	int weapon = GetEntPropEnt(entity, Prop_Send, "m_hActiveWeapon");
	if((weapon == -1 || player_loser[entity]) && !player_tpose[entity]) {
		value |= (TF_STUNFLAG_NOSOUNDOREFFECT|TF_STUNFLAG_THIRDPERSON);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

static Action player_proxysend_stunindex(int entity, const char[] prop, int &value, int element, int client)
{
	int weapon = GetEntPropEnt(entity, Prop_Send, "m_hActiveWeapon");
	if((weapon == -1 || player_loser[entity]) && !player_tpose[entity]) {
		value = 247;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponSwitchPost, player_weapon_switch);

	if(!IsFakeClient(client)) {
		QueryClientConVar(client, "tf_taunt_first_person", tf_taunt_first_person_query);
		QueryClientConVar(client, "cl_first_person_uses_world_model", cl_first_person_uses_world_model_query);
	}

	CBaseEntity_ModifyOrAppendCriteria_hook.HookEntity(Hook_Post, client, CBaseEntity_ModifyOrAppendCriteria_detour_post);
	//CBasePlayer_GetSceneSoundToken_hook.HookEntity(Hook_Pre, client, CBasePlayer_GetSceneSoundToken_detour);
}

//TODO!!! handle client-side sounds
static bool is_sound_client_side(const char[] sample)
{
	if(StrContains(sample, "player/footsteps/") == 0) {
		return true;
	}
	return false;
}

static Action sound_hook(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if(entity >= 1 && entity <= MaxClients) {
	#if defined DEBUG_CONFIG
		PrintToServer(PM2_CON_PREFIX ... "sound_hook %i %s, %s", entity, sample, soundEntry);
	#endif
		if(player_config[entity].idx != -1) {
			bool was_client_side = is_sound_client_side(sample);
		#if defined DEBUG_CONFIG
			PrintToServer(PM2_CON_PREFIX ... "was_client_side = %i", was_client_side);
		#endif

			bool anything_changed = false;

			if(player_config[entity].sound_variables != null) {
				char sound_var_value[MAX_SOUND_VAR_VALUE];

				char player_class_name[CLASS_NAME_MAX + MAX_SOUND_VAR_VALUE];

				if(player_config[entity].sound_variables.GetString("player_class", sound_var_value, MAX_SOUND_VAR_VALUE)) {
					TFClassType player_class = get_player_class(entity);
					get_class_name(player_class, player_class_name, sizeof(player_class_name));
					if(StrEqual(sound_var_value, "model_class")) {
						TFClassType model_class = player_config[entity].model_class;
						if(model_class != TFClass_Unknown) {
							char model_class_name[CLASS_NAME_MAX];
							get_class_name(model_class, model_class_name, CLASS_NAME_MAX);
							ReplaceString(sample, PLATFORM_MAX_PATH, player_class_name, model_class_name);
							anything_changed = true;
						#if defined DEBUG_CONFIG
							PrintToServer(PM2_CON_PREFIX ... "replaced sound variable %s with %s", player_class_name, model_class_name);
						#endif
							strcopy(player_class_name, sizeof(player_class_name), model_class_name);
						}
					}
				}

				if(player_config[entity].sound_variables.GetString("player_class_append", sound_var_value, MAX_SOUND_VAR_VALUE)) {
					char player_class_name_new[CLASS_NAME_MAX + MAX_SOUND_VAR_VALUE];
					strcopy(player_class_name_new, sizeof(player_class_name_new), player_class_name);
					StrCat(player_class_name_new, sizeof(player_class_name_new), sound_var_value);
					ReplaceString(sample, PLATFORM_MAX_PATH, player_class_name, player_class_name_new);
					anything_changed = true;
				#if defined DEBUG_CONFIG
					PrintToServer(PM2_CON_PREFIX ... "replaced sound variable %s with %s", player_class_name, player_class_name_new);
				#endif
					strcopy(player_class_name, sizeof(player_class_name), player_class_name_new);
				}

				if(player_config[entity].sound_variables.GetString("vo", sound_var_value, MAX_SOUND_VAR_VALUE)) {
					ReplaceString(sample, PLATFORM_MAX_PATH, "vo/", sound_var_value);
					anything_changed = true;
				#if defined DEBUG_CONFIG
					PrintToServer(PM2_CON_PREFIX ... "replaced sound variable vo/ with %s", sound_var_value);
				#endif
				}
			}
			if(player_config[entity].sound_replacements != null) {
				int sounds_len = player_config[entity].sound_replacements.Length;
				SoundReplacementInfo sound_replace_info;
				SoundInfo sound_info;
				for(int i = 0; i < sounds_len; ++i) {
					player_config[entity].sound_replacements.GetArray(i, sound_replace_info, sizeof(SoundReplacementInfo));
					int matched = 0;
					if(sound_replace_info.source_is_script) {
						if(soundEntry[0] != '\0' && sound_replace_info.source_regex.Match(soundEntry) > 0) {
							matched = 1;
						}
					} else if(sound_replace_info.source_regex.Match(sample) > 0) {
						matched = 2;
					}
					if(matched > 0) {
						int destination_idx = GetRandomInt(0, sound_replace_info.destinations.Length-1);
						sound_replace_info.destinations.GetArray(destination_idx, sound_info, sizeof(SoundInfo));
						if(sound_info.is_script) {
						#if defined DEBUG_CONFIG
							PrintToServer(PM2_CON_PREFIX ... "replaced %s %s with sound script %s", matched == 2 ? "sound" : "sound script", matched == 2 ? sample : soundEntry, sound_info.path);
						#endif
							if(GetGameSoundParams(sound_info.path, channel, level, volume, pitch, sample, PLATFORM_MAX_PATH, entity)) {
								strcopy(soundEntry, PLATFORM_MAX_PATH, sound_info.path);
								anything_changed = true;
							}
						} else {
						#if defined DEBUG_CONFIG
							PrintToServer(PM2_CON_PREFIX ... "replaced %s %s with sound %s", matched == 2 ? "sound" : "sound script", matched == 2 ? sample : soundEntry, sound_info.path);
						#endif
							strcopy(sample, PLATFORM_MAX_PATH, sound_info.path);
							anything_changed = true;
						}
					}
				}
			}
			if(anything_changed) {
				if(was_client_side) {
					clients[numClients++] = entity;
				}
				return Plugin_Changed;
			} else if(player_config[entity].flags & config_flags_no_voicelines) {
				return Plugin_Stop;
			}
		}
	}

	return Plugin_Continue;
}

static MRESReturn CBaseEntity_ModifyOrAppendCriteria_detour_post(int pThis, DHookParam hParams)
{
	return MRES_Ignored;
}

static MRESReturn CBasePlayer_GetSceneSoundToken_detour(int pThis, DHookReturn hReturn)
{
	if(player_config[pThis].sound_variables != null) {
		char sound_var_value[MAX_SOUND_VAR_VALUE];

		if(player_config[pThis].sound_variables.GetString("token", sound_var_value, MAX_SOUND_VAR_VALUE)) {
			hReturn.SetString(sound_var_value);
			return MRES_Supercede;
		}
	}

	return MRES_Ignored;
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

	SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
	SDKHook(client, SDKHook_PostThinkPost, player_think_model);

	if(proxysend_loaded) {
		proxysend_hook(client, "m_clrRender", player_proxysend_render_color, false);
		proxysend_hook(client, "m_nRenderMode", player_proxysend_render_mode, false);
	}

	ChangeEdictState(client);

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
		player_entity_model[client][0] = '\0';
	}

	SDKUnhook(client, SDKHook_PostThinkPost, player_think_model);

	if(proxysend_loaded) {
		proxysend_unhook(client, "m_clrRender", player_proxysend_render_color);
		proxysend_unhook(client, "m_nRenderMode", player_proxysend_render_mode);
	}

	ChangeEdictState(client);

	if(GetEntityRenderMode(client) == RENDER_NONE) {
		SetEntityRenderMode(client, RENDER_NORMAL);
	}

	int effects = GetEntProp(client, Prop_Send, "m_fEffects");
	effects &= ~(EF_NOSHADOW|EF_NORECEIVESHADOW);
	SetEntProp(client, Prop_Send, "m_fEffects", effects);
}

public void OnClientDisconnect(int client)
{
	player_custom_model[client][0] = '\0';
	player_entity_model[client][0] = '\0';

	player_thirdparty_model[client].clear();
	player_custom_taunt_model[client].clear();
	player_config[client].clear();

	player_taunt_vars[client].clear();

	player_tpose[client] = false;
	player_loser[client] = false;
	player_swim[client] = false;

	for(TFClassType i = TFClass_Scout; i <= TFClass_Engineer; ++i) {
		player_econ_configs[client][i].clear();
	}

	player_weapon_animation_class[client] = TFClass_Unknown;

	if(IsValidEntity(client)) {
		delete_player_model_entity(client);
		delete_player_viewmodel_entities(client);
	}

	tf_taunt_first_person[client] = false;
	cl_first_person_uses_world_model[client] = false;

	if(player_weapon_switch_timer[client] != null) {
		KillTimer(player_weapon_switch_timer[client]);
		player_weapon_switch_timer[client] = null;
	}
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

	handle_playermodel(client);
}

static void player_changeclass(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	handle_playermodel(client);
}

static void post_inventory_application(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);

	if(proxysend_loaded) {
		proxysend_unhook_cond(client, TFCond_Dazed, player_proxysend_loser_cond);
		proxysend_unhook(client, "m_iStunFlags", player_proxysend_stunflags);
		proxysend_unhook(client, "m_iStunIndex", player_proxysend_stunindex);
	}

	if(player_tpose[client]) {
		SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 1);
	}
	player_tpose[client] = false;
	player_loser[client] = false;

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

	if(get_player_class(client) == TFClass_Spy) {
		if(!TF2_IsPlayerInCondition(client, TFCond_Disguised)) {
			float invisibility = (1.0 - GetEntDataFloat(client, CTFPlayer_m_flInvisibility_offset));
			int invisibility_alpha = RoundToCeil(255 * invisibility);
			if(invisibility_alpha < a) {
				a = invisibility_alpha;
			}
		}
	}

	SetEntityRenderColor(entity, r, g, b, a);
}

static Action player_proxysend_render_color(int entity, const char[] prop, int &r, int &g, int &b, int &a, int element, int client)
{
#if defined DEBUG_PROXYSEND
	static float lastprint = 0.0;
	if(lastprint <= GetGameTime()) {
		PrintToServer(PM2_CON_PREFIX ... "player_proxysend_render_color(%i, %s, [%i, %i, %i, %i], %i, %i)", entity, prop, r, g, b, a, element, client);
		lastprint = GetGameTime() + 1.0;
	}
#endif

	if(get_player_model_entity(entity) != -1 && !TF2_IsPlayerInCondition(entity, TFCond_Disguised)) {
		a = 0;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

static Action player_proxysend_render_mode(int entity, const char[] prop, int &value, int element, int client)
{
#if defined DEBUG_PROXYSEND
	static float lastprint = 0.0;
	if(lastprint <= GetGameTime()) {
		PrintToServer(PM2_CON_PREFIX ... "player_proxysend_render_mode(%i, %s, %i, %i, %i)", entity, prop, value, element, client);
		lastprint = GetGameTime() + 1.0;
	}
#endif

	if(get_player_model_entity(entity) != -1 && !TF2_IsPlayerInCondition(entity, TFCond_Disguised)) {
		value = view_as<int>(RENDER_TRANSCOLOR);
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

static void set_player_custom_model(int client, const char[] model)
{
	dont_handle_SetCustomModel_call = true;
	SetVariantString(model);
	AcceptEntityInput(client, "SetCustomModel");
	strcopy(player_custom_model[client], PLATFORM_MAX_PATH, model);
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
	recalculate_player_bodygroups(client);

	//SetEntProp(client, Prop_Send, "m_bForcedSkin", 0);
	//SetEntProp(client, Prop_Send, "m_nForcedSkin", 0);

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

static bool player_taunts_in_firstperson(int client)
{
	if(cl_first_person_uses_world_model[client] || tf_taunt_first_person[client]) {
		return true;
	}
	return false;
}

static bool is_player_in_thirdperson(int client)
{
	if(player_taunts_in_firstperson(client)) {
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
#if defined DEBUG_MODEL
	PrintToServer(PM2_CON_PREFIX ... "handle_playermodel(%i)", client);
	PrintToServer(PM2_CON_PREFIX ... "  TFCond_Disguised = %i", TF2_IsPlayerInCondition(client, TFCond_Disguised));
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

	if(TF2_IsPlayerInCondition(client, TFCond_Disguised)) {
		return;
	}

	TFClassType player_class = get_player_class(client);

	bool config_valid = ((player_config[client].model[0] != '\0') && !!(player_config[client].classes_allowed & BIT_FOR_CLASS(player_class)));

	bool has_any_model = (
		player_thirdparty_model[client].model[0] != '\0' ||
		config_valid ||
		player_econ_configs[client][player_class].model[0] != '\0'
	);

	TFClassType anim_class = player_class;

	char animation_model[PLATFORM_MAX_PATH];
	if(player_custom_taunt_model[client].model[0] != '\0' &&
		player_custom_taunt_model[client].bonemerge &&
		(has_any_model || player_custom_taunt_model[client].class != player_class)) {
		strcopy(animation_model, PLATFORM_MAX_PATH, player_custom_taunt_model[client].model);
		anim_class = player_custom_taunt_model[client].class;
	} else if(player_taunt_vars[client].class != TFClass_Unknown) {
		if(player_taunt_vars[client].class != player_class) {
			get_model_for_class(player_taunt_vars[client].class, animation_model, PLATFORM_MAX_PATH);
			anim_class = player_taunt_vars[client].class;
		}
	} else if(player_weapon_animation_class[client] != TFClass_Unknown &&
				player_weapon_animation_class[client] != player_class) {
		get_model_for_class(player_weapon_animation_class[client], animation_model, PLATFORM_MAX_PATH);
		anim_class = player_weapon_animation_class[client];
	}

	bool bonemerge = true;
	int from = 0;
	TFClassType model_class = player_class;

	char player_model[PLATFORM_MAX_PATH];
	if(player_custom_taunt_model[client].model[0] != '\0' &&
		(!player_custom_taunt_model[client].bonemerge ||
		(!has_any_model && player_custom_taunt_model[client].class == player_class))) {
		strcopy(player_model, PLATFORM_MAX_PATH, player_custom_taunt_model[client].model);
		model_class = player_custom_taunt_model[client].class;
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
	} else if(config_valid) {
		from = 1;
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
	} else if(player_econ_configs[client][player_class].model[0] != '\0') {
		from = 2;
		strcopy(player_model, PLATFORM_MAX_PATH, player_econ_configs[client][player_class].model);
		model_class = player_econ_configs[client][player_class].model_class;

		if(player_econ_configs[client][player_class].flags & config_flags_never_bonemerge) {
			bonemerge = false;
		} else if(!(player_econ_configs[client][player_class].flags & config_flags_always_bonemerge)) {
			if(player_econ_configs[client][player_class].model_class == player_class) {
				if(animation_model[0] == '\0') {
					bonemerge = false;
				}
			}
		}
	}

#if defined DEBUG_MODEL
	PrintToServer(PM2_CON_PREFIX ... "  animation_model = %s", animation_model);
	PrintToServer(PM2_CON_PREFIX ... "  player_model = %s", player_model);
	PrintToServer(PM2_CON_PREFIX ... "  bonemerge = %i", bonemerge);
	PrintToServer(PM2_CON_PREFIX ... "  model_class = %i", model_class);
	PrintToServer(PM2_CON_PREFIX ... "  anim_class = %i", anim_class);
#endif

	if(player_model[0] == '\0' && animation_model[0] == '\0') {
		if(get_player_model_entity(client) == -1 &&
			player_custom_model[client][0] == '\0') {
			return;
		}

		remove_playermodel(client);

		Call_StartForward(fwd_changed);
		Call_PushCell(client);
		Call_Finish();
	} else if(bonemerge) {
		if(animation_model[0] == '\0') {
			get_model_for_class(player_class, animation_model, PLATFORM_MAX_PATH);
			anim_class = player_class;
		}
		if(player_model[0] == '\0') {
			get_model_for_class(player_class, player_model, PLATFORM_MAX_PATH);
			model_class = player_class;
		}

		if(animation_model[0] == '\0' && player_model[0] == '\0') {
			LogError(PM2_CON_PREFIX ... "tried to set empty model");
			return;
		}

		bool same_custom_model = StrEqual(player_custom_model[client], animation_model);
		bool same_entity_model = StrEqual(player_entity_model[client], player_model) && get_player_model_entity(client) != -1;

		if(same_custom_model && same_entity_model) {
			return;
		}

		if(!same_custom_model) {
			set_player_custom_model(client, animation_model);
			SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);
		}

		if(!same_entity_model) {
			delete_player_model_entity(client);
			int entity = get_or_create_player_model_entity(client);

			bool set_bodygroups = true;

			if(from == 1) {
				int bodygroups = player_config[client].bodygroups;
				if(bodygroups != -1) {
					SetEntProp(entity, Prop_Send, "m_nBody", bodygroups);
					set_bodygroups = false;
				}

				int skin = player_config[client].skin;
				if(skin != -1) {
					SetEntProp(entity, Prop_Send, "m_iTeamNum", team_for_skin(skin));
				}
			} else if(from == 2) {
				int bodygroups = player_econ_configs[client][player_class].bodygroups;
				if(bodygroups != -1) {
					SetEntProp(entity, Prop_Send, "m_nBody", bodygroups);
					set_bodygroups = false;
				}

				int skin = player_econ_configs[client][player_class].skin;
				if(skin != -1) {
					SetEntProp(entity, Prop_Send, "m_iTeamNum", team_for_skin(skin));
				}
			}

			if(set_bodygroups) {
				int bodygroups = GetEntProp(client, Prop_Send, "m_nBody");
				if(model_class != player_class) {
					bodygroups = translate_classes_bodygroups(bodygroups, player_class, model_class);
				}
				SetEntProp(entity, Prop_Send, "m_nBody", bodygroups);
			}

			SetEntityModel(entity, player_model);
			strcopy(player_entity_model[client], PLATFORM_MAX_PATH, player_model);

			Call_StartForward(fwd_changed);
			Call_PushCell(client);
			Call_Finish();
		}
	} else {
		if(player_model[0] == '\0') {
			LogError(PM2_CON_PREFIX ... "tried to set empty model");
			return;
		}

		if(StrEqual(player_custom_model[client], player_model)) {
			return;
		}

		delete_player_model_entity(client);
		set_player_custom_model(client, player_model);
		SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);

		Call_StartForward(fwd_changed);
		Call_PushCell(client);
		Call_Finish();
	}
}
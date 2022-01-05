#include <sourcemod>
#include <sdkhooks>
#include <dhooks>
#include <morecolors>
#include <tf2items>
#include <tf_econ_data>
#tryinclude <tauntmanager>
#tryinclude <sendproxy>
#include <teammanager_gameplay>
#include <tf2utils>
#tryinclude <shapeshift_funcs>

//#define DEBUG

//#define ENABLE_SENDPROXY

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

enum playermodelslot
{
	playermodelslot_animation,
	playermodelslot_model,
	playermodelslot_skin,
	playermodelslot_bodygroup,
};

enum playermodelflags
{
	playermodel_noflags = 0,
	playermodel_hidehats = (1 << 1),
	playermodel_hideweapons = (1 << 2),
	playermodel_nogameplay = (1 << 3),
	playermodel_noweapons = (1 << 4),
	playermodel_nohats = (1 << 5),
	playermodel_nevermerge = (1 << 6),
	playermodel_alwaysmerge = (1 << 7),
};

enum playermodelmethod
{
	playermodelmethod_none,
	playermodelmethod_setcustommodel,
	playermodelmethod_bonemerge,
};

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
	TFClassType orig_class;
	int classes;
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
	handledatafrom_shapeshift,
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

enum handleswitchfrom
{
	handleswitchfrom_spawn,
	handleswitchfrom_switch,
	handleswitchfrom_unequip,
	handleswitchfrom_equip,
	handleswitchfrom_taunt_end,
};

static Handle dummy_item_view = null;
static Handle EquipWearable = null;
static Handle RecalculatePlayerBodygroups = null;
static int m_Shared_offset = -1;
static int m_flInvisibility_offset = -1;
static int m_iAttributeDefinitionIndex_offset = -1;
static ArrayList class_cache = null;
static ConVar tf_always_loser = null;

static bool attempting_to_taunt[MAXPLAYERS+1];
static int player_viewmodelentity[MAXPLAYERS+1][2];
static bool tf_taunt_first_person[MAXPLAYERS+1];
static bool cl_first_person_uses_world_model[MAXPLAYERS+1];

static int modelgameplay = -1;
static ArrayList modelinfos = null;
static StringMap modelinfoidmap = null;
static ArrayList groupinfos = null;
static int modelprecache = INVALID_STRING_TABLE;
static DynamicHook ModifyOrAppendCriteria_hook = null;
static Handle AppendCriteria = null;
static Handle RemoveCriteria = null;
static bool spawning[MAXPLAYERS+1] = {true, ...};
static Handle spawn_timer[MAXPLAYERS+1] = {null, ...};

static bool tauntmodel_hasbonemerge[MAXPLAYERS+1] = {true, ...};
static TFClassType last_taunt_class = TFClass_Unknown;
static TFClassType player_tauntclass[MAXPLAYERS+1] = {TFClass_Unknown, ...};

static playermodelmethod player_modelmethod[MAXPLAYERS+1] = {playermodelmethod_none, ...};
static char player_tauntanimation[MAXPLAYERS+1][PLATFORM_MAX_PATH];
static char player_weaponanimation[MAXPLAYERS+1][PLATFORM_MAX_PATH];

static int player_model_idx[MAXPLAYERS+1] = {-1, ...};
static char player_model[MAXPLAYERS+1][PLATFORM_MAX_PATH];
static int player_skin[MAXPLAYERS+1] = {-1, ...};
static int player_bodygroup[MAXPLAYERS+1] = {-1, ...};
static int player_modelentity[MAXPLAYERS+1] = {INVALID_ENT_REFERENCE, ...};
static playermodelflags player_flags[MAXPLAYERS+1] = {playermodel_noflags, ...};
static TFClassType player_modelclass[MAXPLAYERS+1] = {TFClass_Unknown, ...};

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
			REMOVE_OR_ADD_FLAG(flags, playermodel_noweapons)
			if(!remove) {
				flags |= playermodel_nogameplay;
			}
		} else if(StrEqual(flagstrs[i][start], "nohats")) {
			REMOVE_OR_ADD_FLAG(flags, playermodel_nohats)
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

static int calculate_class_bodygroups(int old_body, TFClassType source, TFClassType target)
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
			if(old_body & BODYGROUP_SCOUT_HAT) {
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
			if(old_body & BODYGROUP_SOLDIER_HELMET) {
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
			if(old_body & BODYGROUP_ENGINEER_HELMET) {
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
			if(old_body & BODYGROUP_SNIPER_HAT) {
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

static int bodygroupstr_to_bodygroup(const char[] str)
{
	char flagstrs[BODYGROUP_NUM][BODYGROUP_MAX];
	int num = ExplodeString(str, "|", flagstrs, BODYGROUP_NUM, BODYGROUP_MAX);

	int bodygroup = 0;

	for(int i = 0; i < num; ++i) {
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
		} else if(StrEqual(flagstrs[i], "pyro_propane")) {
			bodygroup |= BODYGROUP_PYRO_PROPANE;
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
		} else {
			bodygroup |= StringToInt(flagstrs[i]);
		}
	}

	return bodygroup;
}

static void parse_models_kv(const char[] path, ConfigGroupInfo groupinfo, playermodelflags flags)
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

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "AI_CriteriaSet::AppendCriteria");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	AppendCriteria = EndPrepSDKCall();
	if(AppendCriteria == null) {
		SetFailState("Failed to create SDKCall for AI_CriteriaSet::AppendCriteria.");
		delete gamedata;
		return;
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "AI_CriteriaSet::RemoveCriteria");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	RemoveCriteria = EndPrepSDKCall();
	if(RemoveCriteria == null) {
		SetFailState("Failed to create SDKCall for AI_CriteriaSet::RemoveCriteria.");
		delete gamedata;
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

	tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::Taunt");
	if(!tmp || !tmp.Enable(Hook_Pre, Taunt)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::Taunt");
		delete gamedata;
		return;
	}
	if(!tmp.Enable(Hook_Post, Taunt_post)) {
		SetFailState("Failed to enable post detour for CTFPlayer::Taunt");
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

	tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::PlayTauntRemapInputScene");
	if(!tmp || !tmp.Enable(Hook_Pre, PlayTauntRemapInputScene)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::PlayTauntRemapInputScene");
		delete gamedata;
		return;
	}
	if(!tmp.Enable(Hook_Post, PlayTauntRemapInputScene_post)) {
		SetFailState("Failed to enable post detour for CTFPlayer::PlayTauntRemapInputScene");
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

	ModifyOrAppendCriteria_hook = DynamicHook.FromConf(gamedata, "CBaseEntity::ModifyOrAppendCriteria");

	delete gamedata;

	HookEvent("player_death", player_death);
	HookEvent("player_spawn", player_spawn);

	HookEvent("player_changeclass", player_changeclass);
	HookEvent("post_inventory_application", post_inventory_application);

	dummy_item_view = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
	TF2Items_SetClassname(dummy_item_view, "tf_wearable");
	TF2Items_SetItemIndex(dummy_item_view, 65535);
	TF2Items_SetQuality(dummy_item_view, 0);
	TF2Items_SetLevel(dummy_item_view, 0);
	TF2Items_SetNumAttributes(dummy_item_view, 0);

	class_cache = new ArrayList(3);

	m_Shared_offset = FindSendPropInfo("CTFPlayer", "m_Shared");
	m_flInvisibility_offset = FindSendPropInfo("CTFPlayer", "m_flInvisChangeCompleteTime") - 8;

	tf_always_loser = FindConVar("tf_always_loser");

	load_models();

	RegAdminCmd("sm_rpm", sm_rpm, ADMFLAG_ROOT);

	RegConsoleCmd("sm_pm", sm_pm);

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			spawning[i] = false;
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
			
		}
	}

	return Plugin_Handled;
}

#if 0
static bool is_player_inrespawnroom(int client)
{
	float pos[3];
	GetClientAbsOrigin(client, pos);

	return TF2Util_IsPointInRespawnRoom(pos, client, true);
}
#endif

static void frame_unhide_hats(int client)
{
	hide_hats(client, false);
}

static void frame_unhide_weapons(int client)
{
	hide_weapons(client, false);
}

static void unequip_model(int client, bool unload = false)
{
#if 0
	if(!unload) {
		if(player_flags[client] & playermodel_nogameplay) {
			if(!is_player_inrespawnroom(client)) {
				CPrintToChat(client, PM2_CHAT_PREFIX ... "this model can only be unequipped inside a respawn room");
				return;
			}
		}
	}
#endif

	delete_viewmodelentity(client);

	clear_playerdata(client, playermodelslot_hack_all, cleardatafrom_remove);

	if(player_flags[client] & playermodel_nogameplay) {
		TeamManager_RemovePlayerFromGameplayGroup(client, modelgameplay);
	}

	if(player_flags[client] & playermodel_hidehats) {
		SDKUnhook(client, SDKHook_PostThinkPost, player_think_hatsalpha);
		RequestFrame(frame_unhide_hats, client);
	}

	if(player_flags[client] & playermodel_hideweapons) {
		SDKUnhook(client, SDKHook_PostThinkPost, player_think_weaponsalpha);
		RequestFrame(frame_unhide_weapons, client);
	}

	player_model_idx[client] = -1;
	player_model[client][0] = '\0';
	player_skin[client] = -1;
	player_bodygroup[client] = -1;
	player_flags[client] = playermodel_noflags;
	player_modelclass[client] = TFClass_Unknown;

	if(!unload) {
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		handle_weaponswitch(client, weapon, handleswitchfrom_unequip);
	}
}

static bool equip_model_helper(int client, int idx, ConfigModelInfo modelinfo, bool is_var)
{
	if(player_flags[client] & playermodel_nogameplay) {
		TeamManager_RemovePlayerFromGameplayGroup(client, modelgameplay);
	}

	if(player_flags[client] & playermodel_hidehats) {
		RequestFrame(frame_unhide_hats, client);
	}

	if(player_flags[client] & playermodel_hideweapons) {
		RequestFrame(frame_unhide_weapons, client);
	}

#if 0
	if(player_model_idx[client] != idx && modelinfo.flags & playermodel_nogameplay) {
		if(!is_player_inrespawnroom(client)) {
			CPrintToChat(client, PM2_CHAT_PREFIX ... "this model can only be equipped inside a respawn room");
			return false;
		}
	}
#endif

	delete_viewmodelentity(client, 0);

	player_model_idx[client] = idx;

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
		CPrintToChat(client, PM2_CHAT_PREFIX ... "the model you equipped can not participate in normal gameplay");
	}

	if(player_flags[client] & playermodel_noweapons) {
		TF2_RemoveAllWeapons(client);
	}

	if(player_flags[client] & playermodel_nohats) {
		remove_all_wearables(client);
	}

	if(player_flags[client] & playermodel_hidehats) {
		SDKHook(client, SDKHook_PostThinkPost, player_think_hatsalpha);
	}

	if(player_flags[client] & playermodel_hideweapons) {
		SDKHook(client, SDKHook_PostThinkPost, player_think_weaponsalpha);
	}

	return true;
}

static void equip_model(int client, int idx, ConfigModelInfo modelinfo)
{
	if(!equip_model_helper(client, idx, modelinfo, false)) {
		return;
	}

	handle_playerdata(client, playermodelslot_hack_all, handledatafrom_equip);
}

static void equip_model_variation(int client, int idx, ConfigModelInfo modelinfo, ConfigVariationInfo varinfo)
{
	if(!equip_model_helper(client, idx, modelinfo, true)) {
		return;
	}

	player_flags[client] = varinfo.flags;

	if(varinfo.skin != -1) {
		player_skin[client] = varinfo.skin;
	}

	if(varinfo.bodygroup != -1) {
		player_bodygroup[client] = varinfo.bodygroup;
	}

	handle_playerdata(client, playermodelslot_hack_all, handledatafrom_equip);
}

static int menuhandler_variation(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		char intstr[INT_STR_MAX];
		menu.GetItem(0, intstr, INT_STR_MAX);
		int gidx = StringToInt(intstr);
		menu.GetItem(1, intstr, INT_STR_MAX);
		int midx = StringToInt(intstr);
		menu.GetItem(param2, intstr, INT_STR_MAX);
		int vidx = StringToInt(intstr);

		ConfigModelInfo modelinfo;
		modelinfos.GetArray(midx, modelinfo, sizeof(ConfigModelInfo));

		switch(vidx) {
			case -1: {
				unequip_model(param1);
				display_variation_menu(param1, modelinfo, midx, gidx);
				return 0;
			}
			case -2: {
				equip_model(param1, midx, modelinfo);
				display_variation_menu(param1, modelinfo, midx, gidx);
				return 0;
			}
			default: {
				ConfigVariationInfo varinfo;
				modelinfo.variations.GetArray(vidx, varinfo, sizeof(ConfigVariationInfo));
				equip_model_variation(param1, midx, modelinfo, varinfo);
				display_variation_menu(param1, modelinfo, midx, gidx);
				return 0;
			}
		}
	} else if(action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack) {
			char intstr[INT_STR_MAX];
			menu.GetItem(0, intstr, INT_STR_MAX);
			int gidx = StringToInt(intstr);

			display_group_menu(param1, gidx);
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}

	return 0;
}

static void display_variation_menu(int client, ConfigModelInfo modelinfo, int midx, int gidx)
{
	Menu vmenu = CreateMenu(menuhandler_variation);
	vmenu.SetTitle(modelinfo.name);
	vmenu.ExitBackButton = true;

	char intstr[INT_STR_MAX];
	IntToString(gidx, intstr, INT_STR_MAX);
	vmenu.AddItem(intstr, "", ITEMDRAW_IGNORE);

	IntToString(midx, intstr, INT_STR_MAX);
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

	vmenu.Display(client, MENU_TIME_FOREVER);
}

static int menuhandler_model(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		char intstr[INT_STR_MAX];
		menu.GetItem(0, intstr, INT_STR_MAX);
		int gidx = StringToInt(intstr);
		menu.GetItem(param2, intstr, INT_STR_MAX);
		int midx = StringToInt(intstr);

		if(midx == -1) {
			unequip_model(param1);
			display_group_menu(param1, gidx);
			return 0;
		} else {
			ConfigModelInfo modelinfo;
			modelinfos.GetArray(midx, modelinfo, sizeof(ConfigModelInfo));

			if(modelinfo.variations) {
				display_variation_menu(param1, modelinfo, midx, gidx);
				return 0;
			} else {
				equip_model(param1, midx, modelinfo);
				display_group_menu(param1, gidx);
				return 0;
			}
		}
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
	ConfigGroupInfo groupinfo;
	groupinfos.GetArray(idx, groupinfo, sizeof(ConfigGroupInfo));

	Menu mmenu = CreateMenu(menuhandler_model);
	mmenu.SetTitle(groupinfo.name);
	mmenu.ExitBackButton = true;

	char intstr[INT_STR_MAX];
	IntToString(idx, intstr, INT_STR_MAX);
	mmenu.AddItem(intstr, "", ITEMDRAW_IGNORE);

	mmenu.AddItem("-1", "remove");

	ConfigModelInfo modelinfo;

	int len = groupinfo.models.Length;
	for(int i = 0; i < len; ++i) {
		idx = groupinfo.models.Get(i);

		modelinfos.GetArray(idx, modelinfo, sizeof(ConfigModelInfo));

		IntToString(idx, intstr, INT_STR_MAX);
		mmenu.AddItem(intstr, modelinfo.name);
	}

	mmenu.Display(client, MENU_TIME_FOREVER);
}

static int menuhandler_group(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		char intstr[INT_STR_MAX];
		menu.GetItem(param2, intstr, INT_STR_MAX);
		int idx = StringToInt(intstr);

		if(idx == -1) {
			unequip_model(param1);
			display_groups_menu(param1);
			return 0;
		} else {
			display_group_menu(param1, idx);
			return 0;
		}
	} else if(action == MenuAction_End) {
		delete menu;
	}

	return 0;
}

static void display_groups_menu(int client)
{
	char clientsteam[STEAMID_MAX];

	Menu menu = CreateMenu(menuhandler_group);
	menu.SetTitle("Groups");

	menu.AddItem("-1", "remove");

	char intstr[INT_STR_MAX];

	ConfigGroupInfo groupinfo;

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
}

static Action sm_pm(int client, int args)
{
	display_groups_menu(client);
	return Plugin_Handled;
}

static Action timer_spawn(Handle timer, int client)
{
	client = GetClientOfUserId(client);
	if(client == 0) {
		return Plugin_Continue;
	}

	spawn_timer[client] = null;

	if(TF2_GetPlayerClass(client) == TFClass_Unknown) {
		return Plugin_Continue;
	}

	SDKHook(client, SDKHook_PostThinkPost, player_think_noweapon);

	spawning[client] = false;

	return Plugin_Continue;
}

static void player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int usrid = event.GetInt("userid");
	int client = GetClientOfUserId(usrid);

	delete_viewmodelentity(client, 0);

	spawning[client] = true;

	if(spawn_timer[client] != null) {
		KillTimer(spawn_timer[client]);
	}
	spawn_timer[client] = CreateTimer(0.5, timer_spawn, usrid);
}

static void frame_ragdoll(int entity)
{
	int owner = GetEntProp(entity, Prop_Send, "m_iPlayerIndex");

#if defined DEBUG && 1
	PrintToServer(PM2_CON_PREFIX ... "%i %i", entity, player_modelclass[owner]);
#endif

	if(player_modelclass[owner] != TFClass_Unknown) {
		SetEntProp(entity, Prop_Send, "m_iClass", player_modelclass[owner]);
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "tf_ragdoll")) {
		RequestFrame(frame_ragdoll, entity);
	}
}

static void player_death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int flags = event.GetInt("death_flags");

	if(!(flags & TF_DEATHFLAG_DEADRINGER)) {
		SDKUnhook(client, SDKHook_PostThinkPost, player_think_noweapon);

		

		delete_viewmodelentity(client);
	}
}

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
	tauntmodel_hasbonemerge[client] = hasBonemergeSupport;
	if(hasBonemergeSupport) {
		strcopy(player_tauntanimation[client], PLATFORM_MAX_PATH, tauntModel);
		handle_playerdata(client, playermodelslot_animation, handledatafrom_taunt_start);
		return Plugin_Handled;
	} else {
		//TODO!!! support for non-bonemerge
		clear_playerdata(client, playermodelslot_animation, cleardatafrom_taunt_start);
		return Plugin_Continue;
	}
}

public Action TauntManager_RemoveTauntModel(int client)
{
	player_tauntanimation[client][0] = '\0';
	tauntmodel_hasbonemerge[client] = true;
	return Plugin_Handled;
}
#endif

static void handle_tauntattempt(int client, ArrayList classes)
{
	TFClassType player_class = TF2_GetPlayerClass(client);

	int len = classes.Length;
	if(len > 0) {
		TFClassType desiredclass = TFClass_Unknown;
		if(classes.FindValue(player_class) != -1) {
			desiredclass = player_class;
		} else {
			desiredclass = classes.Get(GetRandomInt(0, len-1));
		}
		if(player_tauntanimation[client][0] == '\0') {
			get_model_for_class(desiredclass, player_tauntanimation[client], PLATFORM_MAX_PATH);
		}
	#if defined DEBUG
		PrintToServer(PM2_CON_PREFIX ... "handle_tauntattempt");
	#endif
		if(tauntmodel_hasbonemerge[client]) {
			handle_playerdata(client, playermodelslot_animation, handledatafrom_taunt_start);
		}
		TF2_SetPlayerClass(client, desiredclass);
		last_taunt_class = player_class;
		player_tauntclass[client] = desiredclass;
	}
}

public MRESReturn Taunt(int pThis, DHookParam hParams)
{
	last_taunt_class = TFClass_Unknown;
	player_tauntclass[pThis] = TFClass_Unknown;
	attempting_to_taunt[pThis] = true;

	ArrayList classes = new ArrayList();

#if defined _tauntmanager_included_
	TauntManager_CodeTaunt codetaunt = TauntManager_GetCurrentCodeTaunt(pThis);
	if(codetaunt != TauntManager_InvalidCodeTaunt) {
		TauntManager_GetCodeTauntUsableClasses(codetaunt, classes);
	} else
#endif
	{
		int weapon = GetEntPropEnt(pThis, Prop_Send, "m_hActiveWeapon");
		if(weapon != -1) {
			TFClassType player_class = TF2_GetPlayerClass(pThis);
			TFClassType weapon_class = get_class_for_weapon(weapon, player_class);
			classes.Push(weapon_class);
		}
	}

	handle_tauntattempt(pThis, classes);

	delete classes;

	return MRES_Ignored;
}

public MRESReturn PlayTauntSceneFromItem(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	last_taunt_class = TFClass_Unknown;
	player_tauntclass[pThis] = TFClass_Unknown;
	attempting_to_taunt[pThis] = true;

	int m_iAttributeDefinitionIndex = -1;
	if(!hParams.IsNull(1)) {
		m_iAttributeDefinitionIndex = hParams.GetObjectVar(1, m_iAttributeDefinitionIndex_offset, ObjectValueType_Int);
	}

	if(m_iAttributeDefinitionIndex != -1) {
		ArrayList classes = get_classes_for_taunt(m_iAttributeDefinitionIndex);

		handle_tauntattempt(pThis, classes);

		delete classes;
	}

	return MRES_Ignored;
}

static MRESReturn PlayTauntRemapInputScene(int pThis, DHookReturn hReturn)
{
	if(player_tauntclass[pThis] != TFClass_Unknown) {
		last_taunt_class = TF2_GetPlayerClass(pThis);
	#if defined DEBUG && 0
		PrintToServer(PM2_CON_PREFIX ... "PlayTauntRemapInputScene");
	#endif
		TF2_SetPlayerClass(pThis, player_tauntclass[pThis]);
	}
	return MRES_Ignored;
}

static MRESReturn Taunt_post(int pThis, DHookParam hParams)
{
	if(last_taunt_class != TFClass_Unknown) {
	#if defined DEBUG
		PrintToServer(PM2_CON_PREFIX ... "Taunt_post %i", last_taunt_class);
	#endif
		TF2_SetPlayerClass(pThis, last_taunt_class);
	}
	last_taunt_class = TFClass_Unknown;
	player_tauntclass[pThis] = TFClass_Unknown;
	return MRES_Ignored;
}

static MRESReturn EndLongTaunt(int pThis, DHookReturn hReturn)
{
	if(player_tauntclass[pThis] != TFClass_Unknown) {
		last_taunt_class = TF2_GetPlayerClass(pThis);
	#if defined DEBUG
		PrintToServer(PM2_CON_PREFIX ... "EndLongTaunt");
	#endif
		TF2_SetPlayerClass(pThis, player_tauntclass[pThis]);
	}
	return MRES_Ignored;
}

static MRESReturn PlayTauntOutroScene(int pThis, DHookReturn hReturn)
{
	if(player_tauntclass[pThis] != TFClass_Unknown) {
		last_taunt_class = TF2_GetPlayerClass(pThis);
	#if defined DEBUG
		PrintToServer(PM2_CON_PREFIX ... "PlayTauntOutroScene");
	#endif
		TF2_SetPlayerClass(pThis, player_tauntclass[pThis]);
	}
	player_tauntclass[pThis] = TFClass_Unknown;
	return MRES_Ignored;
}

static MRESReturn PlayTauntSceneFromItem_post(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if(last_taunt_class != TFClass_Unknown) {
	#if defined DEBUG
		PrintToServer(PM2_CON_PREFIX ... "PlayTauntSceneFromItem_post");
	#endif
		TF2_SetPlayerClass(pThis, last_taunt_class);
	}
	last_taunt_class = TFClass_Unknown;
	return MRES_Ignored;
}

static MRESReturn EndLongTaunt_post(int pThis, DHookReturn hReturn)
{
	if(last_taunt_class != TFClass_Unknown) {
	#if defined DEBUG
		PrintToServer(PM2_CON_PREFIX ... "EndLongTaunt_post");
	#endif
		TF2_SetPlayerClass(pThis, last_taunt_class);
	}
	last_taunt_class = TFClass_Unknown;
	return MRES_Ignored;
}

static MRESReturn PlayTauntRemapInputScene_post(int pThis, DHookReturn hReturn)
{
	if(last_taunt_class != TFClass_Unknown) {
	#if defined DEBUG && 0
		PrintToServer(PM2_CON_PREFIX ... "PlayTauntRemapInputScene_post");
	#endif
		TF2_SetPlayerClass(pThis, last_taunt_class);
	}
	last_taunt_class = TFClass_Unknown;
	return MRES_Ignored;
}

static MRESReturn PlayTauntOutroScene_post(int pThis, DHookReturn hReturn)
{
	if(last_taunt_class != TFClass_Unknown) {
	#if defined DEBUG
		PrintToServer(PM2_CON_PREFIX ... "PlayTauntOutroScene_post");
	#endif
		TF2_SetPlayerClass(pThis, last_taunt_class);
	}
	last_taunt_class = TFClass_Unknown;
	return MRES_Ignored;
}

public void TF2_OnConditionAdded(int client, TFCond condition)
{
	switch(condition) {
		case TFCond_Disguised:
		{  }
	}
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	switch(condition) {
		case TFCond_Taunting: {
			player_tauntanimation[client][0] = '\0';
			handle_playerdata(client, playermodelslot_animation, handledatafrom_taunt_end);
		}
		case TFCond_Disguised:
		{  }
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
		bitmask = class_cache.Get(idx, 2);
		ArrayList tmp = class_cache.Get(idx, 1);
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
			#if defined DEBUG && 0
				PrintToServer(PM2_CON_PREFIX ... "%i", icls);
			#endif
				bitmask |= BIT_FOR_CLASS(icls);
			}
		}

		int len = tmp.Length;
		if(len > 0) {
		#if defined DEBUG && 0
			PrintToServer(PM2_CON_PREFIX ... "%i %i", item, bitmask);
		#endif
			idx = class_cache.Push(item);
			class_cache.Set(idx, bitmask, 2);
			class_cache.Set(idx, tmp, 1);
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
	if(cache != null) {
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

static int get_bodygroup_for_arm(TFClassType class)
{
	return 0;
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
}

#if defined _shapeshift_funcs_included_
public Action OnShapeShift(int client, int currentClass, int &targetClass)
{
	return Plugin_Continue;
}
#endif

static void player_think_noweapon(int client)
{
#if 0
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(weapon != -1) {
		tf_always_loser.ReplicateToClient(client, tf_always_loser.BoolValue ? "1" : "0");
	} else {
		tf_always_loser.ReplicateToClient(client, "1");
	}
#endif
}

static void handle_weaponswitch(int client, int weapon, handleswitchfrom from)
{
	bool weapon_valid = (weapon != -1);

#if defined DEBUG && 0
	PrintToServer(PM2_CON_PREFIX ... "handle_weaponswitch %i %i", from, spawning[client]);
#endif

	TFClassType player_class = TF2_GetPlayerClass(client);

	TFClassType weapon_class = TFClass_Unknown;
	int bitmask = 0;
	if(weapon_valid) {
		weapon_class = get_class_for_weapon(weapon, player_class, bitmask);
	}

	if(weapon_class != TFClass_Unknown) {
		get_model_for_class(weapon_class, player_weaponanimation[client], PLATFORM_MAX_PATH);
		handle_playerdata(client, playermodelslot_animation, handledatafrom_weaponswitch);

		char model[PLATFORM_MAX_PATH];
		get_arm_model_for_class(client, weapon_class, model, PLATFORM_MAX_PATH);

		int viewmodel_index = GetEntProp(weapon, Prop_Send, "m_nViewModelIndex");
		int viewmodel = GetEntPropEnt(client, Prop_Send, "m_hViewModel", viewmodel_index);

		SetEntPropString(viewmodel, Prop_Data, "m_ModelName", model);
		int idx = PrecacheModel(model);
		SetEntProp(viewmodel, Prop_Send, "m_nModelIndex", idx);
		SetEntProp(weapon, Prop_Send, "m_iViewModelIndex", idx);

	#if defined DEBUG && 0
		PrintToServer(PM2_CON_PREFIX ... "handle_weaponswitch viewmodel a %i %s %i", weapon_class, model, idx);
	#endif

		delete_viewmodelentity(client, 1);

		TFClassType arm_class = player_class;
		if(player_modelclass[client] != TFClass_Unknown) {
			arm_class = player_modelclass[client];
		}

		bool different_class = (weapon_class != arm_class);

		if(different_class) {
			int entity = get_or_create_viewmodelentity(client, 0);

			SetVariantString("!activator");
			AcceptEntityInput(entity, "SetParent", viewmodel);

			int effects = GetEntProp(entity, Prop_Send, "m_fEffects");
			effects |= EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES;
			SetEntProp(entity, Prop_Send, "m_fEffects", effects);

			get_arm_model_for_class(client, arm_class, model, PLATFORM_MAX_PATH);
			idx = PrecacheModel(model);

			SetEntityModel(entity, model);
			SetEntProp(entity, Prop_Send, "m_nModelIndex", idx);
			SetEntProp(entity, Prop_Send, "m_nBody", get_bodygroup_for_arm(arm_class));

			SetEntPropEnt(entity, Prop_Send, "m_hWeaponAssociatedWith", weapon);

		#if defined DEBUG && 0
			PrintToServer(PM2_CON_PREFIX ... "handle_weaponswitch viewmodel f %i %s %i", arm_class, model, idx);
		#endif

			entity = get_or_create_viewmodelentity(client, 1);

			idx = GetEntProp(weapon, Prop_Send, "m_iWorldModelIndex");
			ReadStringTable(modelprecache, idx, model, PLATFORM_MAX_PATH);

			int id = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
			SetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex", id);
			id = GetEntProp(weapon, Prop_Send, "m_iEntityLevel");
			SetEntProp(entity, Prop_Send, "m_iEntityLevel", id);
			id = GetEntProp(weapon, Prop_Send, "m_iItemIDHigh");
			SetEntProp(entity, Prop_Send, "m_iItemIDHigh", id);
			id = GetEntProp(weapon, Prop_Send, "m_iItemIDLow");
			SetEntProp(entity, Prop_Send, "m_iItemIDLow", id);

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
}

static void player_weaponswitchpost(int client, int weapon)
{
	handle_weaponswitch(client, weapon, handleswitchfrom_switch);
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			unequip_model(i, true);
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
	player_viewmodelentity[client][0] = INVALID_ENT_REFERENCE;
	player_viewmodelentity[client][1] = INVALID_ENT_REFERENCE;

	SDKHook(client, SDKHook_WeaponSwitchPost, player_weaponswitchpost);

	ModifyOrAppendCriteria_hook.HookEntity(Hook_Post, client, ModifyOrAppendCriteria);

	if(!IsFakeClient(client)) {
		QueryClientConVar(client, "tf_taunt_first_person", tf_taunt_first_person_query);
		QueryClientConVar(client, "cl_first_person_uses_world_model", cl_first_person_uses_world_model_query);
	}
}

public MRESReturn ModifyOrAppendCriteria(int pThis, DHookParam hParams)
{
	Address criteriaSet = hParams.GetAddress(1);

	return MRES_Ignored;
}

static void delete_viewmodelentity(int client, int i = -1, int weapon = -1)
{
	if(i == -1) {
		delete_viewmodelentity(client, 0, weapon);
		delete_viewmodelentity(client, 1, weapon);
		return;
	}

	int entity = get_viewmodelentity(client, i);
	if(entity != -1) {
		TF2_RemoveWearable(client, entity);
		AcceptEntityInput(entity, "ClearParent");
		RemoveEntity(entity);
		player_viewmodelentity[client][i] = INVALID_ENT_REFERENCE;

		if(i == 0) {
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

static int get_or_create_modelentity(int client)
{
	int entity = get_modelentity(client);
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

	SDKCall(EquipWearable, client, entity);
	SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", 1);

	SetEntPropString(entity, Prop_Data, "m_iClassname", "playermodel_wearable");

	SetEntProp(entity, Prop_Send, "m_bClientSideAnimation", 0);
	SetEntProp(entity, Prop_Send, "m_bClientSideFrameReset", 0);

	SetEntPropFloat(entity, Prop_Send, "m_flPlaybackRate", 1.0);

	SetEntProp(entity, Prop_Send, "m_iTeamNum", GetClientTeam(client));

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", client);

	SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);

	SDKHook(client, SDKHook_PostThinkPost, player_think_modelalpha);

#if defined _SENDPROXYMANAGER_INC_ && defined ENABLE_SENDPROXY
	SendProxy_Hook(client, "m_clrRender", Prop_Int, proxy_renderclr, true);
	SendProxy_Hook(client, "m_nRenderMode", Prop_Int, proxy_rendermode, true);
#endif

	SetEntityRenderMode(client, RENDER_NONE);

	SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
	SetEntityRenderColor(entity, 255, 255, 255, 255);

	SDKHook(entity, SDKHook_SetTransmit, model_transmit);

	effects = GetEntProp(entity, Prop_Send, "m_fEffects");
	effects |= (EF_BONEMERGE|EF_BONEMERGE_FASTCULL|EF_PARENT_ANIMATES);
	effects &= ~EF_NOSHADOW;
	effects &= ~EF_NORECEIVESHADOW;
	SetEntProp(entity, Prop_Send, "m_fEffects", effects);

	player_modelentity[client] = EntIndexToEntRef(entity);

	return entity;
}

static void delete_modelentity(int client)
{
#if defined DEBUG && 0
	PrintToServer(PM2_CON_PREFIX ... "delete_modelentity(%i)", client);
#endif

	int entity = get_modelentity(client);
	if(entity != -1) {
		TF2_RemoveWearable(client, entity);
		AcceptEntityInput(entity, "ClearParent");
		RemoveEntity(entity);
		player_modelentity[client] = INVALID_ENT_REFERENCE;
	}

	SDKUnhook(client, SDKHook_PostThinkPost, player_think_modelalpha);

#if defined _SENDPROXYMANAGER_INC_ && defined ENABLE_SENDPROXY
	SendProxy_Unhook(client, "m_clrRender", proxy_renderclr);
	SendProxy_Unhook(client, "m_nRenderMode", proxy_rendermode);
#endif

	SetEntityRenderMode(client, RENDER_NORMAL);

	int r = 255;
	int g = 255;
	int b = 255;
	int a = 255;
	GetEntityRenderColor(client, r, g, b, a);
	SetEntityRenderColor(client, r, g, b, a);

	int effects = GetEntProp(client, Prop_Send, "m_fEffects");
	effects &= ~EF_NOSHADOW;
	effects &= ~EF_NORECEIVESHADOW;
	SetEntProp(client, Prop_Send, "m_fEffects", effects);
}

public void OnClientDisconnect(int client)
{
	clear_playerdata(client, playermodelslot_hack_all, cleardatafrom_disconnect);

	spawning[client] = true;
	tauntmodel_hasbonemerge[client] = true;

	player_tauntclass[client] = TFClass_Unknown;
	attempting_to_taunt[client] = false;
	player_tauntanimation[client][0] = '\0';
	player_weaponanimation[client][0] = '\0';
	player_modelmethod[client] = playermodelmethod_none;

	if(spawn_timer[client] != null) {
		KillTimer(spawn_timer[client]);
	}
	spawn_timer[client] = null;

	player_model_idx[client] = -1;
	player_model[client][0] = '\0';
	player_skin[client] = -1;
	player_bodygroup[client] = -1;
	player_flags[client] = playermodel_noflags;
	player_modelclass[client] = TFClass_Unknown;

	tf_taunt_first_person[client] = false;
	cl_first_person_uses_world_model[client] = false;
}

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

static void remove_all_wearables(int client)
{
#if defined CAN_GET_UTLVECTOR
	int len = GetEntPropArraySize(client, Prop_Send, "m_hMyWearables");
	for(int i = 0; i < len; ++i) {
		int entity = GetEntPropEnt(client, Prop_Send, "m_hMyWearables", i);
		if(entity != -1) {
			TF2_RemoveWearable(client, entity);
			RemoveEntity(entity);
		}
	}
#else
	int entity = -1;
	while((entity = FindEntityByClassname(entity, "tf_wearable*")) != -1) {
		int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		if(owner == client) {
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
			if(player_flags[owner] & playermodel_hidehats) {
				SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
				set_entity_alpha(entity, 0);
			}
		}
	}
}
#endif

static void hide_hats(int client, bool value)
{
#if defined CAN_GET_UTLVECTOR
	int len = GetEntPropArraySize(client, Prop_Send, "m_hMyWearables");
	for(int i = 0; i < len; ++i) {
		int entity = GetEntPropEnt(client, Prop_Send, "m_hMyWearables", i);
		if(entity != -1) {
			SetEntityRenderMode(entity, value ? RENDER_TRANSCOLOR : RENDER_NORMAL);
			set_entity_alpha(entity, value ? 0 : 255);
		}
	}
#else
	int entity = -1;
	while((entity = FindEntityByClassname(entity, "tf_wearable*")) != -1) {
		int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		if(owner == client) {
			SetEntityRenderMode(entity, value ? RENDER_TRANSCOLOR : RENDER_NORMAL);
			set_entity_alpha(entity, value ? 0 : 255);
		}
	}
#endif
}

static void frame_inventory(int client)
{
	if(player_flags[client] & playermodel_noweapons) {
		TF2_RemoveAllWeapons(client);
	}

	if(player_flags[client] & playermodel_nohats) {
		remove_all_wearables(client);
	}
}

static void post_inventory_application(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	RequestFrame(frame_inventory, client);
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

static void hide_weapons(int client, bool value)
{
	int len = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	for(int i = 0; i < len; ++i) {
		int entity = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if(entity != -1) {
			SetEntityRenderMode(entity, value ? RENDER_TRANSCOLOR : RENDER_NORMAL);
			set_entity_alpha(entity, value ? 0 : 255);
		}
	}
}

static void player_think_weaponsalpha(int client)
{
	int entity = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(entity != -1) {
		SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
		set_entity_alpha(entity, 0);
	}
}

static void player_think_hatsalpha(int client)
{
#if defined CAN_GET_UTLVECTOR
	hide_hats(client, true);
#endif
}

static void player_think_modelalpha(int client)
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

	if(TF2_GetPlayerClass(client) == TFClass_Spy) {
		int mod = calc_spy_alpha(client);
		if(mod != -1 && mod < a) {
			a = mod;
		}
	}

	SetEntityRenderColor(entity, r, g, b, a);

	SetEntityRenderMode(client, RENDER_NONE);
}

#if defined _SENDPROXYMANAGER_INC_ && defined ENABLE_SENDPROXY
static Action proxy_renderclr(int iEntity, const char[] cPropName, int &iValue, int iElement, int iClient)
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

static Action proxy_rendermode(int iEntity, const char[] cPropName, int &iValue, int iElement, int iClient)
{
	if(iClient == iEntity) {
		iValue = view_as<int>(RENDER_TRANSCOLOR);
		return Plugin_Changed;
	}

	return Plugin_Continue;
}
#endif

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

static void clear_playerdata(int client, playermodelslot which, cleardatafrom from, handledatafrom reapply_from = handledatafrom_unknown)
{
#if defined DEBUG
	PrintToServer(PM2_CON_PREFIX ... "clear_playerdata %i %i %i", which, from, reapply_from);
#endif

	switch(which) {
		case playermodelslot_hack_all: {
			clear_playerdata(client, playermodelslot_skin, from);
			clear_playerdata(client, playermodelslot_bodygroup, from);
			clear_playerdata(client, playermodelslot_animation, from);
		}
		case playermodelslot_skin: {
			SetEntProp(client, Prop_Send, "m_bForcedSkin", false);
			SetEntProp(client, Prop_Send, "m_nForcedSkin", 0);
		}
		case playermodelslot_bodygroup: {
			recalculate_bodygroups(client);
		}
		case playermodelslot_animation, playermodelslot_model: {
			if((reapply_from == handledatafrom_equip ||
				from == cleardatafrom_remove) &&
				TF2_IsPlayerInCondition(client, TFCond_Taunting))
			{
				return;
			}

			reset_custommodel(client);

			delete_modelentity(client);
			delete_viewmodelentity(client);
		}
	}
}

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

static bool is_player_thirdperson(int client)
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

Action model_transmit(int entity, int client)
{
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if(client == owner) {
		if(!is_player_thirdperson(client)) {
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

static int team_for_skin(int skin)
{
	if(skin == 0) {
		return 2;
	} else {
		return 3;
	}
}

static void handle_playerdata(int client, playermodelslot which, handledatafrom from)
{
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

				if(entity != -1) {
					SetEntProp(entity, Prop_Send, "m_iTeamNum", team_for_skin(new_skin));
				} else {
					SetEntProp(client, Prop_Send, "m_bForcedSkin", true);
					SetEntProp(client, Prop_Send, "m_nForcedSkin", new_skin);
				}
			}
		}
		case playermodelslot_bodygroup: {
			int new_bodygroup = player_bodygroup[client];

			if(new_bodygroup != -1) {
				int entity = get_modelentity_or_client(client);
				SetEntProp(entity, Prop_Send, "m_nBody", new_bodygroup);
			#if defined DEBUG && 0
				PrintToServer(PM2_CON_PREFIX ... "b1 %i", new_bodygroup);
			#endif
			} else {
				if(player_modelclass[client] != TFClass_Unknown) {
					int entity = get_modelentity(client);
					if(entity != -1) {
						TFClassType player_class = TF2_GetPlayerClass(client);
						int old_body = GetEntProp(client, Prop_Send, "m_nBody");
						new_bodygroup = calculate_class_bodygroups(old_body, player_class, player_modelclass[client]);
					#if defined DEBUG && 0
						PrintToServer(PM2_CON_PREFIX ... "b2 %i", new_bodygroup);
					#endif
						SetEntProp(entity, Prop_Send, "m_nBody", new_bodygroup);
					}
				}
			}
		}
		case playermodelslot_animation, playermodelslot_model: {
			if(from == handledatafrom_weaponswitch) {
				if(attempting_to_taunt[client] || TF2_IsPlayerInCondition(client, TFCond_Taunting)) {
					return;
				}
			}

			TFClassType player_class = TF2_GetPlayerClass(client);

			char new_animation[PLATFORM_MAX_PATH];
			if(player_tauntanimation[client][0] != '\0') {
				strcopy(new_animation, PLATFORM_MAX_PATH, player_tauntanimation[client]);
			} else if(player_weaponanimation[client][0] != '\0') {
				strcopy(new_animation, PLATFORM_MAX_PATH, player_weaponanimation[client]);
			}

			bool copy_bodygroups = false;
			char new_model[PLATFORM_MAX_PATH];
			if(player_model[client][0] == '\0') {
				get_model_for_class(player_class, new_model, PLATFORM_MAX_PATH);
				copy_bodygroups = true;
			} else {
				strcopy(new_model, PLATFORM_MAX_PATH, player_model[client]);
			}

			if(StrEqual(new_model, new_animation)) {
				clear_playerdata(client, playermodelslot_animation, cleardatafrom_reapply, from);
				return;
			}

			if((new_animation[0] != '\0' ||
				(player_flags[client] & playermodel_alwaysmerge)) &&
				!(player_flags[client] & playermodel_nevermerge)) {
				player_modelmethod[client] = playermodelmethod_bonemerge;
			} else {
				player_modelmethod[client] = playermodelmethod_setcustommodel;
			}

		#if defined DEBUG
			PrintToServer("handle_playerdata");
			PrintToServer("  new_model = %s", new_model);
			PrintToServer("  new_animation = %s", new_animation);
			PrintToServer("  player_tauntanimation = %s", player_tauntanimation[client]);
			PrintToServer("  player_weaponanimation = %s", player_weaponanimation[client]);
			PrintToServer("  method = %i", player_modelmethod[client]);
		#endif

			switch(player_modelmethod[client]) {
				case playermodelmethod_bonemerge: {
					if(new_animation[0] != '\0') {
						set_custom_model(client, new_animation);
					}

					delete_modelentity(client);

					int entity = get_or_create_modelentity(client);

					SetEntityModel(entity, new_model);

					if(copy_bodygroups) {
						int body = GetEntProp(client, Prop_Send, "m_nBody");
						SetEntProp(entity, Prop_Send, "m_nBody", body);
					}
				}
				case playermodelmethod_setcustommodel: {
					delete_modelentity(client);

					set_custom_model(client, new_model);
				#if defined DEBUG && 0
					PrintToServer(PM2_CON_PREFIX ... "set_custom_model(%s) %i", new_model, from);
				#endif
				}
			}
		}
	}
}
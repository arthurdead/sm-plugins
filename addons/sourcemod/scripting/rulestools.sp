#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <rulestools>
#include <datamaps>

static GlobalForward fwd_cleanup;
static GlobalForward fwd_create;
static GlobalForward fwd_uses_upgrades;

static int tf_objective_resource = INVALID_ENT_REFERENCE;
static int tf_gamerules = INVALID_ENT_REFERENCE;

static DynamicHook CGameRulesRoundCleanupShouldIgnore_dhook;
static DynamicHook CGameRulesRoundShouldCreateEntity_dhook;

static Handle CTeamplayRoundBasedRulesCleanUpMap;

static int m_nMannVsMachineWaveClassCounts_size = -1;
static int m_nMannVsMachineWaveClassCounts2_size = -1;

static int m_iszMannVsMachineWaveClassNames_offset = -1;
static int m_iszMannVsMachineWaveClassNames2_offset = -1;
static int m_iszMannVsMachineWaveClassNames_size = -1;
static int m_iszMannVsMachineWaveClassNames2_size = -1;

static int m_bMannVsMachineWaveClassActive_size = -1;
static int m_bMannVsMachineWaveClassActive2_size = -1;

static int m_nMannVsMachineWaveClassFlags_size = -1;
static int m_nMannVsMachineWaveClassFlags2_size = -1;

static bool got_objective_offsets;

static bool set_as_mvm;

static bool mode_is_mvm;

static ConVar tf_gamemode_arena;
static ConVar tf_gamemode_cp;
static ConVar tf_gamemode_ctf;
static ConVar tf_gamemode_sd;
static ConVar tf_gamemode_rd;
static ConVar tf_gamemode_pd;
static ConVar tf_gamemode_tc;
static ConVar tf_gamemode_payload;
static ConVar tf_gamemode_mvm;
static ConVar tf_gamemode_passtime;
static ConVar tf_gamemode_misc;
static ConVar tf_powerup_mode;
static ConVar tf_beta_content;
static ConVar tf_training_client_message;

static char entities_to_remove[][] = {
	"tf_logic_arena",
	"tf_logic_mann_vs_machine",
	"team_train_watcher",
	"tf_logic_robot_destruction",
	"tf_logic_player_destruction",
	"tf_logic_multiple_escort",
	"passtime_logic",
	"tf_logic_training_mode",
	"tf_logic_koth",
	"tf_logic_medieval",
	"tf_logic_competitive",
	"tf_logic_hybrid_ctf_cp",
	"competitive_stage_logic_case",
	"tf_logic_cp_timer",
	"bot_roster",
	"tf_logic_mannpower",
	"item_teamflag",
	"func_capturezone",
	"func_flagdetectionzone",
	"func_flag_alert"
};

static int native_is_gamemode_entity(Handle plugin, int params)
{
	int length = 0;
	GetNativeStringLength(1, length);
	char[] classname = new char[++length];
	GetNativeString(1, classname, length);

	for(int i = 0; i < sizeof(entities_to_remove); ++i) {
		if(StrEqual(entities_to_remove[i], classname)) {
			return 1;
		}
	}

	return 0;
}

static int native_clear_all_gamemodes(Handle plugin, int params)
{
	SDKCall(CTeamplayRoundBasedRulesCleanUpMap);

	tf_gamemode_arena.BoolValue = false;
	tf_gamemode_cp.BoolValue = false;
	tf_gamemode_ctf.BoolValue = false;
	tf_gamemode_sd.BoolValue = false;
	tf_gamemode_rd.BoolValue = false;
	tf_gamemode_pd.BoolValue = false;
	tf_gamemode_tc.BoolValue = false;
	tf_gamemode_payload.BoolValue = false;
	tf_gamemode_mvm.BoolValue = false;
	tf_gamemode_passtime.BoolValue = false;
	tf_gamemode_misc.BoolValue = true;
	tf_powerup_mode.BoolValue = false;
	tf_beta_content.BoolValue = false;
	tf_training_client_message.IntValue = 0;

	GameRules_SetProp("m_bBountyModeEnabled", 0);
	GameRules_SetProp("m_bPlayingKoth", 0);
	GameRules_SetProp("m_bPlayingMedieval", 0);
	GameRules_SetProp("m_bPlayingHybrid_CTF_CP", 0);
	GameRules_SetProp("m_bPlayingSpecialDeliveryMode", 0);
	GameRules_SetProp("m_bPlayingRobotDestructionMode", 0);
	GameRules_SetProp("m_bPowerupMode", 0);
	GameRules_SetProp("m_bPlayingMannVsMachine", 0);
	GameRules_SetProp("m_bIsInTraining", 0);
	GameRules_SetProp("m_bAllowTrainingAchievements", 0);
	GameRules_SetProp("m_bIsTrainingHUDVisible", 0);
	GameRules_SetProp("m_bIsInItemTestingMode", 0);
	GameRules_SetProp("m_bMapHasMatchSummaryStage", 0);
	GameRules_SetProp("m_bCompetitiveMode", 0);
	GameRules_SetProp("m_halloweenScenario", MVM_CLASS_FLAG_NONE);
	GameRules_SetProp("m_nGameType", TF_GAMETYPE_UNDEFINED);
	GameRules_SetProp("m_nHudType", TF_HUDTYPE_UNDEFINED);

	if(tf_gamerules == INVALID_ENT_REFERENCE) {
		int gamerules = FindEntityByClassname(-1, "tf_gamerules");
		if(gamerules != -1) {
			tf_gamerules = EntIndexToEntRef(gamerules);
		}
	}

	int gamerules = EntRefToEntIndex(tf_gamerules);

	SetEntProp(gamerules, Prop_Data, "m_nHudType", TF_HUDTYPE_UNDEFINED);
	SetEntProp(gamerules, Prop_Data, "m_bOvertimeAllowedForCTF", 0);

	for(int i = 0; i < sizeof(entities_to_remove); ++i) {
		int entity = -1;
		while((entity = FindEntityByClassname(entity, entities_to_remove[i])) != -1) {
			RemoveEntity(entity);
		}
	}

	if(tf_objective_resource == INVALID_ENT_REFERENCE) {
		int objective = FindEntityByClassname(-1, "tf_objective_resource");
		if(objective != -1) {
			tf_objective_resource = EntIndexToEntRef(objective);
		}
	}

	ResetMannVsMachineWaveInfo();

	return 0;
}

static int native_SetMannVsMachineWaveClassName(Handle plugin, int params)
{
	int objective = EntRefToEntIndex(tf_objective_resource);
	if(objective == -1) {
		return 0;
	}

	int nIndex = GetNativeCell(1);

	int length = 0;
	GetNativeStringLength(2, length);
	char[] iszClassIconName = new char[++length];
	GetNativeString(2, iszClassIconName, length);

	Address iszClassIconName_pooled = AllocPooledString(iszClassIconName);

	if(nIndex < m_iszMannVsMachineWaveClassNames_size) {
		//SetEntPropString(objective, Prop_Send, "m_iszMannVsMachineWaveClassNames", iszClassIconName, nIndex);
		SetEntData(objective, m_iszMannVsMachineWaveClassNames_offset + (nIndex * 4), iszClassIconName_pooled, 4, true);
		return 0;
	}

	nIndex -= m_iszMannVsMachineWaveClassNames_size;

	if(nIndex < m_iszMannVsMachineWaveClassNames2_size) {
		//SetEntPropString(objective, Prop_Send, "m_iszMannVsMachineWaveClassNames2", iszClassIconName, nIndex);
		SetEntData(objective, m_iszMannVsMachineWaveClassNames2_offset + (nIndex * 4), iszClassIconName_pooled, 4, true);
	}

	return 0;
}

static int native_GetMannVsMachineWaveClassName(Handle plugin, int params)
{
	int objective = EntRefToEntIndex(tf_objective_resource);
	if(objective == -1) {
		return 0;
	}

	int nIndex = GetNativeCell(1);
	int length = GetNativeCell(3);

	char[] iszClassIconName = new char[++length];

	if(nIndex < m_iszMannVsMachineWaveClassNames_size) {
		GetEntPropString(objective, Prop_Send, "m_iszMannVsMachineWaveClassNames", iszClassIconName, length, nIndex);
		SetNativeString(2, iszClassIconName, length);
		return 0;
	}

	nIndex -= m_iszMannVsMachineWaveClassNames_size;

	if(nIndex < m_iszMannVsMachineWaveClassNames2_size) {
		GetEntPropString(objective, Prop_Send, "m_iszMannVsMachineWaveClassNames2", iszClassIconName, length, nIndex);
		SetNativeString(2, iszClassIconName, length);
	}

	return 0;
}

static int native_SetMannVsMachineWaveClassCount(Handle plugin, int params)
{
	int objective = EntRefToEntIndex(tf_objective_resource);
	if(objective == -1) {
		return 0;
	}

	int nIndex = GetNativeCell(1);
	int nCount = GetNativeCell(2);

	if(nIndex < m_nMannVsMachineWaveClassCounts_size) {
		SetEntProp(objective, Prop_Send, "m_nMannVsMachineWaveClassCounts", nCount, _, nIndex);
		return 0;
	}

	nIndex -= m_nMannVsMachineWaveClassCounts_size;

	if(nIndex < m_nMannVsMachineWaveClassCounts2_size) {
		SetEntProp(objective, Prop_Send, "m_nMannVsMachineWaveClassCounts2", nCount, _, nIndex);
	}

	return 0;
}

static int native_GetMannVsMachineWaveClassCount(Handle plugin, int params)
{
	int objective = EntRefToEntIndex(tf_objective_resource);
	if(objective == -1) {
		return 0;
	}

	int nIndex = GetNativeCell(1);

	if(nIndex < m_nMannVsMachineWaveClassCounts_size) {
		return GetEntProp(objective, Prop_Send, "m_nMannVsMachineWaveClassCounts", nIndex);
	}

	nIndex -= m_nMannVsMachineWaveClassCounts_size;

	if(nIndex < m_nMannVsMachineWaveClassCounts2_size) {
		return GetEntProp(objective, Prop_Send, "m_nMannVsMachineWaveClassCounts2", nIndex);
	}

	return 0;
}

static int native_SetMannVsMachineWaveClassActive(Handle plugin, int params)
{
	int objective = EntRefToEntIndex(tf_objective_resource);
	if(objective == -1) {
		return 0;
	}

	int nIndex = GetNativeCell(1);
	bool bActive = GetNativeCell(2) != 0;

	if(nIndex < m_bMannVsMachineWaveClassActive_size) {
		SetEntProp(objective, Prop_Send, "m_bMannVsMachineWaveClassActive", bActive, _, nIndex);
		return 0;
	}

	nIndex -= m_bMannVsMachineWaveClassActive_size;

	if(nIndex < m_bMannVsMachineWaveClassActive2_size) {
		SetEntProp(objective, Prop_Send, "m_bMannVsMachineWaveClassActive2", bActive, _, nIndex);
	}

	return 0;
}

static int native_GetMannVsMachineWaveClassActive(Handle plugin, int params)
{
	int objective = EntRefToEntIndex(tf_objective_resource);
	if(objective == -1) {
		return 0;
	}

	int nIndex = GetNativeCell(1);

	if(nIndex < m_bMannVsMachineWaveClassActive_size) {
		return GetEntProp(objective, Prop_Send, "m_bMannVsMachineWaveClassActive", nIndex);
	}

	nIndex -= m_bMannVsMachineWaveClassActive_size;

	if(nIndex < m_bMannVsMachineWaveClassActive2_size) {
		return GetEntProp(objective, Prop_Send, "m_bMannVsMachineWaveClassActive2", nIndex);
	}

	return 0;
}

static int native_SetMannVsMachineWaveClassFlags(Handle plugin, int params)
{
	int objective = EntRefToEntIndex(tf_objective_resource);
	if(objective == -1) {
		return 0;
	}

	int nIndex = GetNativeCell(1);
	int iFlags = GetNativeCell(2);

	if(nIndex < m_nMannVsMachineWaveClassFlags_size) {
		SetEntProp(objective, Prop_Send, "m_nMannVsMachineWaveClassFlags", iFlags, _, nIndex);
		return 0;
	}

	nIndex -= m_nMannVsMachineWaveClassFlags_size;

	if(nIndex < m_nMannVsMachineWaveClassFlags2_size) {
		SetEntProp(objective, Prop_Send, "m_nMannVsMachineWaveClassFlags2", iFlags, _, nIndex);
	}

	return 0;
}

static int native_GetMannVsMachineWaveClassFlags(Handle plugin, int params)
{
	int objective = EntRefToEntIndex(tf_objective_resource);
	if(objective == -1) {
		return 0;
	}

	int nIndex = GetNativeCell(1);

	if(nIndex < m_nMannVsMachineWaveClassFlags_size) {
		return GetEntProp(objective, Prop_Send, "m_nMannVsMachineWaveClassFlags", nIndex);
	}

	nIndex -= m_nMannVsMachineWaveClassFlags_size;

	if(nIndex < m_nMannVsMachineWaveClassFlags2_size) {
		return GetEntProp(objective, Prop_Send, "m_nMannVsMachineWaveClassFlags2", nIndex);
	}

	return 0;
}

static int native_get_objective_entity(Handle plugin, int params)
{
	return EntRefToEntIndex(tf_objective_resource);
}

static int native_get_gamerules_proxy(Handle plugin, int params)
{
	return EntRefToEntIndex(tf_gamerules);
}

static int native_CleanUpMap(Handle plugin, int params)
{
	SDKCall(CTeamplayRoundBasedRulesCleanUpMap);
	return 0;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int length)
{
	RegPluginLibrary("rulestools");

	CreateNative("clear_all_gamemodes", native_clear_all_gamemodes);
	CreateNative("is_gamemode_entity", native_is_gamemode_entity);

	CreateNative("get_objective_entity", native_get_objective_entity);
	CreateNative("get_gamerules_proxy", native_get_gamerules_proxy);

	CreateNative("SetMannVsMachineWaveClassFlags", native_SetMannVsMachineWaveClassFlags);
	CreateNative("GetMannVsMachineWaveClassFlags", native_GetMannVsMachineWaveClassFlags);

	CreateNative("SetMannVsMachineWaveClassName", native_SetMannVsMachineWaveClassName);
	CreateNative("GetMannVsMachineWaveClassName", native_GetMannVsMachineWaveClassName);

	CreateNative("SetMannVsMachineWaveClassCount", native_SetMannVsMachineWaveClassCount);
	CreateNative("GetMannVsMachineWaveClassCount", native_GetMannVsMachineWaveClassCount);

	CreateNative("SetMannVsMachineWaveClassActive", native_SetMannVsMachineWaveClassActive);
	CreateNative("GetMannVsMachineWaveClassActive", native_GetMannVsMachineWaveClassActive);

	CreateNative("CleanUpMap", native_CleanUpMap);

	CreateNative("IsMannVsMachineMode", native_IsMannVsMachineMode);

	return APLRes_Success;
}

static int native_IsMannVsMachineMode(Handle plugin, int params)
{
	return mode_is_mvm;
}

public void OnPluginStart()
{
	GameData gamedata = new GameData("rulestools");

	DynamicDetour tmp_detour = DynamicDetour.FromConf(gamedata, "CTFGameRules::GameModeUsesUpgrades");
	tmp_detour.Enable(Hook_Post, CTFGameRules_GameModeUsesUpgrades);

	tmp_detour = DynamicDetour.FromConf(gamedata, "CUpgrades::ReportUpgrade");
	tmp_detour.Enable(Hook_Pre, CUpgrades_ReportUpgrade_pre);
	tmp_detour.Enable(Hook_Post, CUpgrades_ReportUpgrade_post);

	CGameRulesRoundCleanupShouldIgnore_dhook = DynamicHook.FromConf(gamedata, "CGameRules::RoundCleanupShouldIgnore");
	CGameRulesRoundShouldCreateEntity_dhook = DynamicHook.FromConf(gamedata, "CGameRules::ShouldCreateEntity");

	StartPrepSDKCall(SDKCall_GameRules);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CTeamplayRoundBasedRules::CleanUpMap");
	CTeamplayRoundBasedRulesCleanUpMap = EndPrepSDKCall();

	delete gamedata;

	fwd_cleanup = new GlobalForward("should_cleanup_entity", ET_Hook, Param_Cell, Param_CellByRef);
	fwd_create = new GlobalForward("should_create_entity", ET_Hook, Param_String, Param_CellByRef);

	fwd_uses_upgrades = new GlobalForward("gamemode_uses_upgrades", ET_Hook, Param_CellByRef);

	tf_gamemode_arena = FindConVar("tf_gamemode_arena");
	tf_gamemode_cp = FindConVar("tf_gamemode_cp");
	tf_gamemode_ctf = FindConVar("tf_gamemode_ctf");
	tf_gamemode_sd = FindConVar("tf_gamemode_sd");
	tf_gamemode_rd = FindConVar("tf_gamemode_rd");
	tf_gamemode_pd = FindConVar("tf_gamemode_pd");
	tf_gamemode_tc = FindConVar("tf_gamemode_tc");
	tf_gamemode_payload = FindConVar("tf_gamemode_payload");
	tf_gamemode_mvm = FindConVar("tf_gamemode_mvm");
	tf_gamemode_passtime = FindConVar("tf_gamemode_passtime");
	tf_gamemode_misc = FindConVar("tf_gamemode_misc");
	tf_powerup_mode = FindConVar("tf_powerup_mode");
	tf_beta_content = FindConVar("tf_beta_content");
	tf_training_client_message = FindConVar("tf_training_client_message");
}

static int tmp_info_populator = -1;

static MRESReturn CUpgrades_ReportUpgrade_pre(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if(gamemode_uses_upgrades_no_mvm()) {
		GameRules_SetProp("m_bPlayingMannVsMachine", 1);
		tmp_info_populator = CreateEntityByName("info_populator");
	}
	return MRES_Ignored;
}

static MRESReturn CUpgrades_ReportUpgrade_post(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if(tmp_info_populator != -1) {
		GameRules_SetProp("m_bPlayingMannVsMachine", 0);
		RemoveEntity(tmp_info_populator);
		tmp_info_populator = -1;
	}
	return MRES_Ignored;
}

static MRESReturn CTFGameRules_GameModeUsesUpgrades(DHookReturn hReturn, DHookParam hParams)
{
	if(hReturn.Value == 1) {
		return MRES_Ignored;
	}

	hReturn.Value = gamemode_uses_upgrades_no_mvm();
	return MRES_Supercede;
}

static bool call_upgrades_forward()
{
	if(fwd_uses_upgrades.FunctionCount > 0) {
		Call_StartForward(fwd_uses_upgrades);
		bool uses = false;
		Call_PushCellRef(uses);
		Action res = Plugin_Continue;
		Call_Finish(res);

		if(res == Plugin_Changed) {
			return uses;
		} else if(res >= Plugin_Handled) {
			return false;
		}
	}

	return true;
}

static bool gamemode_uses_upgrades_no_mvm()
{
	if(!set_as_mvm && (tf_gamerules != INVALID_ENT_REFERENCE && GameRules_GetProp("m_bPlayingMannVsMachine") == 1)) {
		return false;
	}

	return call_upgrades_forward();
}

static MRESReturn CGameRulesRoundCleanupShouldIgnore(DHookReturn hReturn, DHookParam hParams)
{
	if(fwd_cleanup.FunctionCount > 0) {
		Call_StartForward(fwd_cleanup);
		Call_PushCell(hParams.Get(1));
		bool should = true;
		Call_PushCellRef(should);
		Action res = Plugin_Continue;
		Call_Finish(res);

		if(res == Plugin_Changed) {
			hReturn.Value = should;
			return MRES_Supercede;
		} else if(res >= Plugin_Handled) {
			hReturn.Value = false;
			return MRES_Supercede;
		}
	}

	return MRES_Ignored;
}

static MRESReturn CGameRulesRoundShouldCreateEntity(DHookReturn hReturn, DHookParam hParams)
{
	if(fwd_create.FunctionCount > 0) {
		Call_StartForward(fwd_create);
		char classname[64];
		hParams.GetString(1, classname, sizeof(classname));
		Call_PushString(classname);
		bool should = true;
		Call_PushCellRef(should);
		Action res = Plugin_Continue;
		Call_Finish(res);

		if(res == Plugin_Changed) {
			hReturn.Value = should;
			return MRES_Supercede;
		} else if(res >= Plugin_Handled) {
			hReturn.Value = false;
			return MRES_Supercede;
		}
	}

	return MRES_Ignored;
}

public void OnMapStart()
{
	int gamerules = FindEntityByClassname(-1, "tf_gamerules");
	if(gamerules != -1) {
		tf_gamerules = EntIndexToEntRef(gamerules);
	}

	CGameRulesRoundCleanupShouldIgnore_dhook.HookGamerules(Hook_Pre, CGameRulesRoundCleanupShouldIgnore);
	CGameRulesRoundShouldCreateEntity_dhook.HookGamerules(Hook_Pre, CGameRulesRoundShouldCreateEntity);

	int objective = FindEntityByClassname(-1, "tf_objective_resource");
	if(objective != -1) {
		tf_objective_resource = EntIndexToEntRef(objective);

		if(!got_objective_offsets) {
			m_nMannVsMachineWaveClassCounts_size = GetEntPropArraySize(objective, Prop_Send, "m_nMannVsMachineWaveClassCounts");
			m_nMannVsMachineWaveClassCounts2_size = GetEntPropArraySize(objective, Prop_Send, "m_nMannVsMachineWaveClassCounts2");

			m_iszMannVsMachineWaveClassNames_offset = GetEntSendPropOffs(objective, "m_iszMannVsMachineWaveClassNames", true);
			m_iszMannVsMachineWaveClassNames2_offset = GetEntSendPropOffs(objective, "m_iszMannVsMachineWaveClassNames2", true);
			m_iszMannVsMachineWaveClassNames_size = GetEntPropArraySize(objective, Prop_Send, "m_iszMannVsMachineWaveClassNames");
			m_iszMannVsMachineWaveClassNames2_size = GetEntPropArraySize(objective, Prop_Send, "m_iszMannVsMachineWaveClassNames2");

			m_bMannVsMachineWaveClassActive_size = GetEntPropArraySize(objective, Prop_Send, "m_bMannVsMachineWaveClassActive");
			m_bMannVsMachineWaveClassActive2_size = GetEntPropArraySize(objective, Prop_Send, "m_bMannVsMachineWaveClassActive2");

			m_nMannVsMachineWaveClassFlags_size = GetEntPropArraySize(objective, Prop_Send, "m_nMannVsMachineWaveClassFlags");
			m_nMannVsMachineWaveClassFlags2_size = GetEntPropArraySize(objective, Prop_Send, "m_nMannVsMachineWaveClassFlags2");
			got_objective_offsets = true;
		}
	}

	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, PLATFORM_MAX_PATH);

	mode_is_mvm = (
		FindEntityByClassname(-1, "tf_logic_mann_vs_machine") != -1 ||
		GameRules_GetProp("m_bPlayingMannVsMachine") ||
		StrContains(map, "mvm_") == 0
	);
}

public void OnMapEnd()
{
	tf_gamerules = INVALID_ENT_REFERENCE;
	tf_objective_resource = INVALID_ENT_REFERENCE;
}

public Action OnClientCommandKeyValues(int client, KeyValues kv)
{
	char name[32];
	kv.GetSectionName(name, sizeof(name));

	if(gamemode_uses_upgrades_no_mvm()) {
		if(StrEqual(name, "MVM_Upgrade") || StrEqual(name, "MvM_UpgradesDone")) {
			GameRules_SetProp("m_bPlayingMannVsMachine", 1);
			set_as_mvm = true;
		}
	}

	return Plugin_Continue;
}

public void OnClientCommandKeyValues_Post(int client, KeyValues kv)
{
	if(set_as_mvm) {
		GameRules_SetProp("m_bPlayingMannVsMachine", 0);
	}
}

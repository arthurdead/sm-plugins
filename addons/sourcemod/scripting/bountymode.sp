#include <sourcemod>
#include <sdktools>
#include <proxysend>
#include <dhooks>
#include <sdkhooks>
#include <keyvalues>
#include <tf2_stocks>

#pragma semicolon 1
#pragma newdecls required

#define SOLID_BBOX 2
#define SOLID_OBB 3
#define SOLID_VPHYSICS 6
#define EF_NODRAW 0x020

Handle hGrantOrRemoveAllUpgrades = null;
ArrayList g_MapUpgradeStations = null;
int g_UpgradeStation = INVALID_ENT_REFERENCE;
ConVar tf_gamemode_mvm = null;
ConVar tf_mvm_respec_enabled = null;
ConVar tf_mvm_respec_limit = null;
ConVar tf_mvm_respec_credit_goal = null;
bool g_bReportUpgradeSetMVM = false;
int g_SpawnedInfoPopulator = INVALID_ENT_REFERENCE;
int g_InfoPopulator = INVALID_ENT_REFERENCE;
int g_iPlayersInMVM = 0;
bool m_bIsInMVM[MAXPLAYERS] = {false,...};
bool g_bLateLoaded = false;
bool g_bIsEnabled = false;
DynamicDetour dhGameModeUsesUpgrades = null;
DynamicDetour dhReportUpgrade = null;
DynamicDetour dhCanPlayerUseRespec = null;
DynamicDetour dhAddCurrency = null;
DynamicDetour dhDistributeCurrencyAmount = null;
DynamicDetour dhAllocateBots = null;
KeyValues kvUpgrades = null;
int tf_gamerules = INVALID_ENT_REFERENCE;
ConVar tf_mvm_death_penalty = null;
ConVar tf_bountymode_currency_penalty_ondeath = null;
ConVar tf_bountymode_currency_starting = null;
ConVar tf_bountymode_currency_limit = null;
ConVar tf_bountymode_upgrades_wipeondeath = null;
ConVar tf_bountymode = null;
Handle hRemovePlayerAndItemUpgradesFromHistory = null;
Handle hAddPlayerCurrencySpent = null;
Handle hAddExperiencePoints = null;
Handle hRefundExperiencePoints = null;
ArrayList g_StationModels = null;
ArrayList g_CreatedStations = null;
ArrayList g_TempStations = null;
bool g_bDoingUpgradeHelper[MAXPLAYERS+1] = {false, ...};
int g_iLaserBeamIndex = -1;
bool g_bIsMVM = false;
bool g_bRemovingStations = false;
bool g_bRemovingStationModels = false;
Handle g_HUDSync = null;
int m_nExperiencePointsOffset = -1;
bool g_bGotSpawn[MAXPLAYERS+1] = {false, ...};
int g_hUpgradeEntity[MAXPLAYERS+1] = {INVALID_ENT_REFERENCE, ...};
int m_bPlayingMannVsMachineOffset = -1;

enum struct StationInfo
{
	float pos[3];
	float ang[3];
	int enabled;
}
ArrayList station_infos = null;

enum
{
	TF_CURRENCY_KILLED_PLAYER,
	TF_CURRENCY_KILLED_OBJECT,
	TF_CURRENCY_ASSISTED_PLAYER,
	TF_CURRENCY_BONUS_POINTS,
	TF_CURRENCY_CAPTURED_OBJECTIVE,
	TF_CURRENCY_ESCORT_REWARD,
	TF_CURRENCY_PACK_SMALL,
	TF_CURRENCY_PACK_MEDIUM,
	TF_CURRENCY_PACK_LARGE,
	TF_CURRENCY_PACK_CUSTOM,
	TF_CURRENCY_TIME_REWARD,
	TF_CURRENCY_WAVE_COLLECTION_BONUS,
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int length)
{
	g_bLateLoaded = late;
	return APLRes_Success;
}

enum FromWhere
{
	FromUpgradeZone,
	FromDeath,
	FromClientCMD,
};

#define SV_TAG_NAME "bountymode"

#define SOURCEMOD_DIDNT_IMPLEMENT_ADDSERVERTAGS

#if defined SOURCEMOD_DIDNT_IMPLEMENT_ADDSERVERTAGS
ConVar sv_tags = null;
bool just_added_new_tag = false;

void sv_tags_changed(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(just_added_new_tag) {
		return;
	}

	if(g_bIsEnabled) {
		AddBountyTagEx(newValue);
	}
}

void AddBountyTagEx(const char[] tags)
{
	if(StrContains(tags, SV_TAG_NAME) == -1) {
		char newtags[64];
		if(StrEqual(tags, "")) {
			Format(newtags, sizeof(newtags), "%s", SV_TAG_NAME);
		} else {
			Format(newtags, sizeof(newtags), "%s,%s", tags, SV_TAG_NAME);
		}

		just_added_new_tag = true;
		sv_tags.SetString(newtags);
		just_added_new_tag = false;
	}
}

void AddBountyTag()
{
	char tags[64];
	sv_tags.GetString(tags, sizeof(tags));

	AddBountyTagEx(tags);
}

void RemoveBountyTag()
{
	char tags[64];
	sv_tags.GetString(tags, sizeof(tags));

	if(StrEqual(tags, "")) {
		return;
	}

	int index = StrContains(tags, SV_TAG_NAME);
	if(index != -1) {
		if(StrEqual(tags, SV_TAG_NAME)) {
			strcopy(tags, sizeof(tags), "");
		} else {
			ReplaceString(tags, sizeof(tags), "," ... SV_TAG_NAME, "");
		}

		just_added_new_tag = true;
		sv_tags.SetString(tags);
		just_added_new_tag = false;
	}
}
#else
void AddBountyTag()
{
	AddServerTag(SV_TAG_NAME);
}

void RemoveBountyTag()
{
	RemoveServerTag(SV_TAG_NAME);
}
#endif

void cc_bountymode_changed(ConVar convar, const char[] oldValue, const char[] newValue)
{
	int value = StringToInt(newValue);

	if(value) {
		int entity = EntRefToEntIndex(tf_gamerules);
		if(entity != -1) {
			if(GameRules_GetProp("m_bPlayingMannVsMachine")) {
				g_bIsMVM = true;
			}
		}

		EnableBountyMode();
		AddBountyTag();
	} else {
		DisableBountyMode();
		RemoveBountyTag();
	}
}

public void OnPluginStart()
{
	GameData gamedata = new GameData("bountymode");

	dhGameModeUsesUpgrades = DynamicDetour.FromConf(gamedata, "CTFGameRules::GameModeUsesUpgrades");
	dhReportUpgrade = DynamicDetour.FromConf(gamedata, "CUpgrades::ReportUpgrade");
	dhCanPlayerUseRespec = DynamicDetour.FromConf(gamedata, "CTFGameRules::CanPlayerUseRespec");
	dhAddCurrency = DynamicDetour.FromConf(gamedata, "CTFPlayer::AddCurrency");
	dhDistributeCurrencyAmount = DynamicDetour.FromConf(gamedata, "CTFGameRules::DistributeCurrencyAmount");
	dhAllocateBots = DynamicDetour.FromConf(gamedata, "CPopulationManager::AllocateBots");

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CUpgrades::GrantOrRemoveAllUpgrades");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hGrantOrRemoveAllUpgrades = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CPopulationManager::AddPlayerCurrencySpent");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	hAddPlayerCurrencySpent = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CPopulationManager::RemovePlayerAndItemUpgradesFromHistory");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	hRemovePlayerAndItemUpgradesFromHistory = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayer::AddExperiencePoints");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL);
	hAddExperiencePoints = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayer::RefundExperiencePoints");
	hRefundExperiencePoints = EndPrepSDKCall();

	delete gamedata;

	m_bPlayingMannVsMachineOffset = FindSendPropInfo("CTFGameRulesProxy", "m_bPlayingMannVsMachine");

#if defined SOURCEMOD_DIDNT_IMPLEMENT_ADDSERVERTAGS
	sv_tags = FindConVar("sv_tags");
	sv_tags.AddChangeHook(sv_tags_changed);
	sv_tags.Flags &= ~FCVAR_NOTIFY;
#endif

	tf_gamemode_mvm = FindConVar("tf_gamemode_mvm");
	tf_gamemode_mvm.Flags &= ~FCVAR_NOTIFY;

	tf_mvm_respec_enabled = FindConVar("tf_mvm_respec_enabled");
	tf_mvm_respec_enabled.Flags &= ~FCVAR_NOTIFY;

	tf_mvm_respec_limit = FindConVar("tf_mvm_respec_limit");
	tf_mvm_respec_limit.Flags &= ~FCVAR_NOTIFY;

	tf_mvm_respec_credit_goal = FindConVar("tf_mvm_respec_credit_goal");
	tf_mvm_respec_credit_goal.Flags &= ~FCVAR_NOTIFY;

	tf_mvm_death_penalty = FindConVar("tf_mvm_death_penalty");
	tf_mvm_death_penalty.Flags &= ~FCVAR_NOTIFY;

	tf_bountymode_currency_penalty_ondeath = CreateConVar("tf_bountymode_currency_penalty_ondeath", "0", "The percentage of unspent money players lose when they die in Bounty Mode.\n");
	tf_bountymode_currency_starting = CreateConVar("tf_bountymode_currency_starting", "1000", "How much new players start with when playing Bounty Mode.\n");
	tf_bountymode_upgrades_wipeondeath = CreateConVar("tf_bountymode_upgrades_wipeondeath", "0", "If set to true, wipe player/item upgrades on death.\n");
	tf_bountymode = CreateConVar("tf_bountymode", "1", "Allow upgrades and award currency for mission objectives and killing enemy players.\n", FCVAR_REPLICATED);
	tf_bountymode_currency_limit = CreateConVar("tf_bountymode_currency_limit", "0", "The maximum amount a player can hold in Bounty Mode.\n");

	tf_bountymode.AddChangeHook(cc_bountymode_changed);

	m_nExperiencePointsOffset = FindSendPropInfo("CTFPlayer", "m_nExperienceLevelProgress") + 4;

	RegAdminCmd("sm_upgrdhel", sm_upgrdhel, ADMFLAG_GENERIC);
	RegAdminCmd("sm_upgrdset", sm_upgrdset, ADMFLAG_GENERIC);
	RegAdminCmd("sm_upgrdrel", sm_upgrdrel, ADMFLAG_GENERIC);
	RegAdminCmd("sm_upgrdtog", sm_upgrdtog, ADMFLAG_GENERIC);
	RegAdminCmd("sm_upgrdref", sm_upgrdref, ADMFLAG_GENERIC);
	RegAdminCmd("sm_upgrdrem", sm_upgrdrem, ADMFLAG_GENERIC);
	RegAdminCmd("sm_cashadd", sm_cashadd, ADMFLAG_GENERIC);
	RegAdminCmd("sm_cashset", sm_cashset, ADMFLAG_GENERIC);
	RegAdminCmd("sm_cashrem", sm_cashrem, ADMFLAG_GENERIC);
	RegAdminCmd("sm_lvladd", sm_lvladd, ADMFLAG_GENERIC);
	RegAdminCmd("sm_lvlset", sm_lvlset, ADMFLAG_GENERIC);
	RegAdminCmd("sm_lvlrem", sm_lvlrem, ADMFLAG_GENERIC);
	RegAdminCmd("sm_ptsadd", sm_ptsadd, ADMFLAG_GENERIC);
	RegAdminCmd("sm_ptsset", sm_ptsset, ADMFLAG_GENERIC);
	RegAdminCmd("sm_ptsrem", sm_ptsrem, ADMFLAG_GENERIC);

	RegConsoleCmd("sm_upgrade", sm_upgrade);

	char upgradefile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, upgradefile, sizeof(upgradefile), "configs/bountymode.txt");

	if(FileExists(upgradefile, true)) {
		kvUpgrades = new KeyValues("BountyMode");
		kvUpgrades.ImportFromFile(upgradefile);
	}
}

public void OnConfigsExecuted()
{
	
}

Action sm_upgrdrel(int client, int args)
{
	if(kvUpgrades) {
		delete kvUpgrades;
	}

	char upgradefile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, upgradefile, sizeof(upgradefile), "configs/bountymode.txt");

	if(FileExists(upgradefile, true)) {
		kvUpgrades = new KeyValues("BountyMode");
		kvUpgrades.ImportFromFile(upgradefile);
	}

	ParseKeyValues();

	DestroyStations();
	CreateStations(true);

	int entity = EntRefToEntIndex(tf_gamerules);
	if(entity != -1) {
		char script[PLATFORM_MAX_PATH];
		GameRules_GetPropString("m_pszCustomUpgradesFile", script, sizeof(script));

		SetVariantString(script);
		AcceptEntityInput(entity, "SetCustomUpgradesFile");
	}

	return Plugin_Handled;
}

Action sm_upgrdset(int client, int args)
{
	if(args != 1) {
		ReplyToCommand(client, "[SM] Usage: sm_upgrdset <script>");
		return Plugin_Handled;
	}

	int entity = EntRefToEntIndex(tf_gamerules);
	if(entity != -1) {
		char script[PLATFORM_MAX_PATH];
		GetCmdArg(1, script, sizeof(script));

		SetVariantString(script);
		AcceptEntityInput(entity, "SetCustomUpgradesFile");
	} else {
		ReplyToCommand(client, "[SM] tf_gamerules is not present");
		return Plugin_Handled;
	}

	return Plugin_Handled;
}

Action sm_upgrdtog(int client, int args)
{
	if(client == 0) {
		ReplyToCommand(client, "[SM] you must be ingame to use this comamnd.");
		return Plugin_Handled;
	}

	if(args != 1) {
		ReplyToCommand(client, "[SM] Usage: sm_upgrdtog <1/0>");
		return Plugin_Handled;
	}

	int entity = GetClientAimTarget(client, false);
	if(entity > 0) {
		char classname[64];
		GetEntityClassname(entity, classname, sizeof(classname));

		if(StrEqual(classname, "func_upgradestation")) {
			int value = GetCmdArgInt(1);

			if(value) {
				AcceptEntityInput(entity, "Enable");
			} else {
				AcceptEntityInput(entity, "Disable");
			}
		} else {
			ReplyToCommand(client, "[SM] the entity you are aiming is not a upgrade station (%s).", classname);
			return Plugin_Handled;
		}
	} else {
		ReplyToCommand(client, "[SM] you are not aiming at any entity.");
		return Plugin_Handled;
	}

	return Plugin_Handled;
}

Action sm_upgrdref(int client, int args)
{
	if(args != 1) {
		ReplyToCommand(client, "[SM] Usage: sm_upgrdref <filter>");
		return Plugin_Handled;
	}

	char filter[64];
	GetCmdArg(1, filter, sizeof(filter));

	char name[MAX_TARGET_LENGTH];
	bool isml = false;
	int targets[MAXPLAYERS];
	int count = ProcessTargetString(filter, client, targets, MAXPLAYERS, COMMAND_FILTER_ALIVE, name, sizeof(name), isml);
	if(count == 0) {
		ReplyToTargetError(client, count);
		return Plugin_Handled;
	}

	for(int i = 0; i < count; ++i) {
		int target = targets[i];

		GrantOrRemoveAllUpgrades(target, true, true);
	}

	return Plugin_Handled;
}

Action sm_upgrdrem(int client, int args)
{
	if(args != 1) {
		ReplyToCommand(client, "[SM] Usage: sm_upgrdrem <filter>");
		return Plugin_Handled;
	}

	char filter[64];
	GetCmdArg(1, filter, sizeof(filter));

	char name[MAX_TARGET_LENGTH];
	bool isml = false;
	int targets[MAXPLAYERS];
	int count = ProcessTargetString(filter, client, targets, MAXPLAYERS, COMMAND_FILTER_ALIVE, name, sizeof(name), isml);
	if(count == 0) {
		ReplyToTargetError(client, count);
		return Plugin_Handled;
	}

	for(int i = 0; i < count; ++i) {
		int target = targets[i];

		GrantOrRemoveAllUpgrades(target, true, false);
		RemovePlayerAndItemUpgradesFromHistory(i);
	}

	return Plugin_Handled;
}

int CalculateCurrencyAmount_ByType(int nType)
{
	switch(nType) {
		case TF_CURRENCY_KILLED_PLAYER: { return 40; }
		case TF_CURRENCY_KILLED_OBJECT: { return 40; }
		case TF_CURRENCY_ASSISTED_PLAYER: { return 20; }
		case TF_CURRENCY_BONUS_POINTS: { return 1; }
		case TF_CURRENCY_CAPTURED_OBJECTIVE: { return 100; }
		case TF_CURRENCY_ESCORT_REWARD: { return 10; }
		case TF_CURRENCY_PACK_SMALL: { return 5; }
		case TF_CURRENCY_PACK_MEDIUM: { return 10; }
		case TF_CURRENCY_PACK_LARGE: { return 25; }
		case TF_CURRENCY_TIME_REWARD: { return 5; }
		case TF_CURRENCY_WAVE_COLLECTION_BONUS: { return 100; }
		default: { return 0; }
	}
}

void RemoveCurrency(int client, int cash)
{
	int m_nCurrency = GetEntProp(client, Prop_Send, "m_nCurrency");
	if(m_nCurrency - cash < 0) {
		m_nCurrency = 0;
	} else {
		m_nCurrency -= cash;
	}
	SetEntProp(client, Prop_Send, "m_nCurrency", m_nCurrency);

	AddPlayerCurrencySpent(client, cash);
}

int LimitCash(int cash, int current)
{
	int nLimit = tf_bountymode_currency_limit.IntValue;
	if(nLimit > 0) {
		int nNewCurrency = cash + current;
		if(nNewCurrency > nLimit) {
			int nDelta = nNewCurrency - nLimit;
			if(nDelta) {
				cash -= nDelta;
			}
		}
	}

	return cash;
}

void AddCurrency(int client, int cash, bool dolimit = true)
{
	int m_nCurrency = GetEntProp(client, Prop_Send, "m_nCurrency");

	if(dolimit) {
		cash = LimitCash(cash, m_nCurrency);
	}

	if(m_nCurrency + cash > 30000) {
		m_nCurrency = 30000;
	} else {
		m_nCurrency += cash;
	}

	SetEntProp(client, Prop_Send, "m_nCurrency", m_nCurrency);
}

void SetExperienceLevel(int client, int level, bool set_points = false)
{
	SetEntProp(client, Prop_Send, "m_nExperienceLevel", level);
	if(level == 1) {
		SetEntProp(client, Prop_Send, "m_nExperienceLevelProgress", 0);
	}
	if(set_points) {
		int m_nExperiencePoints = GetEntData(client, m_nExperiencePointsOffset);
		int new_points = ((level - 1) * 400);
		if(m_nExperiencePoints < new_points) {
			if(m_nExperiencePoints + new_points > 8000) {
				m_nExperiencePoints = 8000;
			} else {
				m_nExperiencePoints += new_points;
			}
			SetEntData(client, m_nExperiencePointsOffset, m_nExperiencePoints);
		}
	}
}

void SetExperiencePoints(int client, int points)
{
	SetEntData(client, m_nExperiencePointsOffset, points);
	if(points > 0 && points >= 400) {
		SetExperienceLevel(client, (points / 400) + 1);
	} else {
		SetExperienceLevel(client, 1);
	}
}

Action sm_cash_helper(int client, int args, const char[] cmd, int type, int variable)
{
	if(args != 2) {
		ReplyToCommand(client, "[SM] Usage: %s <filter> <value>", cmd);
		return Plugin_Handled;
	}

	char filter[64];
	GetCmdArg(1, filter, sizeof(filter));

	char name[MAX_TARGET_LENGTH];
	bool isml = false;
	int targets[MAXPLAYERS];
	int count = ProcessTargetString(filter, client, targets, MAXPLAYERS, COMMAND_FILTER_ALIVE, name, sizeof(name), isml);
	if(count == 0) {
		ReplyToTargetError(client, count);
		return Plugin_Handled;
	}

	int cash = GetCmdArgInt(2);

	switch(variable) {
		case 0: {
			if(cash > 30000) {
				cash = 30000;
			}
			if(cash < 0) {
				cash = 0;
			}
		}
		case 1: {
			if(cash > 8000) {
				cash = 8000;
			}
		}
		case 2: {
			if(cash < 1) {
				cash = 1;
			}
			if(cash > 20) {
				cash = 20;
			}
		}
	}

	for(int i = 0; i < count; ++i) {
		int target = targets[i];

		switch(type) {
			case 0: {
				switch(variable) {
					case 0: { SetEntProp(target, Prop_Send, "m_nCurrency", cash); }
					case 1: { SetExperiencePoints(target, cash); }
					case 2: { SetExperienceLevel(target, cash, true); }
				}
			}
			case 1: {
				switch(variable) {
					case 0: { AddCurrency(target, cash, false); }
					case 1: {
						int m_nExperiencePoints = GetEntData(target, m_nExperiencePointsOffset);
						m_nExperiencePoints += cash;
						SetExperiencePoints(target, m_nExperiencePoints);
					}
					case 2: {
						int m_nExperienceLevel = GetEntProp(target, Prop_Send, "m_nExperienceLevel");
						m_nExperienceLevel += cash;
						SetExperienceLevel(target, m_nExperienceLevel, true);
					}
				}
			}
			case 2: {
				switch(variable) {
					case 0: { RemoveCurrency(target, cash); }
					case 1: {
						int m_nExperiencePoints = GetEntData(target, m_nExperiencePointsOffset);
						m_nExperiencePoints -= cash;
						SetExperiencePoints(target, m_nExperiencePoints);
					}
					case 2: {
						int m_nExperienceLevel = GetEntProp(target, Prop_Send, "m_nExperienceLevel");
						if(m_nExperienceLevel - cash < 1) {
							m_nExperienceLevel = 1;
						} else {
							m_nExperienceLevel -= cash;
						}
						SetExperienceLevel(target, m_nExperienceLevel, true);
					}
				}
			}
		}
	}

	return Plugin_Handled;
}

Action sm_cashrem(int client, int args) { return sm_cash_helper(client, args, "sm_cashrem", 2, 0); }
Action sm_cashadd(int client, int args) { return sm_cash_helper(client, args, "sm_cashadd", 1, 0); }
Action sm_cashset(int client, int args) { return sm_cash_helper(client, args, "sm_cashset", 0, 0); }

Action sm_ptsrem(int client, int args) { return sm_cash_helper(client, args, "sm_ptsrem", 2, 1); }
Action sm_ptsadd(int client, int args) { return sm_cash_helper(client, args, "sm_ptsadd", 1, 1); }
Action sm_ptsset(int client, int args) { return sm_cash_helper(client, args, "sm_ptsset", 0, 1); }

Action sm_lvlrem(int client, int args) { return sm_cash_helper(client, args, "sm_lvlrem", 2, 2); }
Action sm_lvladd(int client, int args) { return sm_cash_helper(client, args, "sm_lvladd", 1, 2); }
Action sm_lvlset(int client, int args) { return sm_cash_helper(client, args, "sm_lvlset", 0, 2); }

public void OnClientPutInServer(int client)
{
	if(g_bIsEnabled && !g_bIsMVM) {
		AddCurrency(client, tf_bountymode_currency_starting.IntValue, false);
	}
}

void EnableBountyMode()
{
	if(!g_bIsEnabled) {
		g_HUDSync = CreateHudSynchronizer();

		if(!g_bIsMVM) {
			for(int i = 1; i <= MaxClients; ++i) {
				if(IsClientInGame(i)) {
					AddCurrency(i, tf_bountymode_currency_starting.IntValue, false);
					//SendProxy_HookPropChangeSafe(i, "m_bInUpgradeZone", Prop_Int, InUpgradeZone);
				}
			}
		}

		if(!g_bIsMVM) {
			tf_mvm_respec_enabled.BoolValue = true;
			tf_mvm_respec_limit.IntValue = 0;
			tf_mvm_respec_credit_goal.IntValue = 0;
		}

		g_MapUpgradeStations = new ArrayList();

		Event bountymode_toggled = CreateEvent("bountymode_toggled");
		if(bountymode_toggled != null) {
			bountymode_toggled.SetInt("active", 1);
			bountymode_toggled.Fire();
		}

		GameRules_SetProp("m_bBountyModeEnabled", 1);

		if(!g_bIsMVM) {
			dhGameModeUsesUpgrades.Enable(Hook_Pre, GameModeUsesUpgradesPre);
			dhReportUpgrade.Enable(Hook_Pre, ReportUpgradePre);
			dhReportUpgrade.Enable(Hook_Post, ReportUpgradePost);
			dhCanPlayerUseRespec.Enable(Hook_Pre, CanPlayerUseRespecPre);
			dhAllocateBots.Enable(Hook_Pre, AllocateBotsPre);
			dhAddCurrency.Enable(Hook_Pre, AddCurrencyPre);
			dhDistributeCurrencyAmount.Enable(Hook_Pre, DistributeCurrencyAmountPre);
		}

		HookEvent("player_team", player_team);
		HookEvent("player_changeclass", player_changeclass);
		HookEvent("player_spawn", player_spawn);
		HookEvent("player_death", player_death);
		HookEvent("teamplay_flag_event", teamplay_flag_event);
		HookEvent("object_destroyed", object_destroyed);
		HookEvent("teamplay_round_start", teamplay_round_start);
		if(!g_bIsMVM) {
			HookUserMessage(GetUserMessageId("MVMResetPlayerUpgradeSpending"), MVMResetPlayerUpgradeSpending);
			HookUserMessage(GetUserMessageId("MVMLocalPlayerWaveSpendingValue"), MVMLocalPlayerWaveSpendingValue);
			HookUserMessage(GetUserMessageId("MVMPlayerUpgradedEvent"), MVMPlayerUpgradedEvent);
		}
		HookUserMessage(GetUserMessageId("TextMsg"), TextMsg, true);

		int entity = -1;
		while((entity = FindEntityByClassname(entity, "func_upgradestation")) != -1) {
			if(g_bLateLoaded) {
				StationCreated(entity);
			}
			g_MapUpgradeStations.Push(EntIndexToEntRef(entity));
		}

		if(g_bLateLoaded) {
			entity = FindEntityByClassname(-1, "info_populator");
			if(entity != -1) {
				PopulatorCreated(entity);
			}
		}

		g_bIsEnabled = true;
	}
}

void DeleteClientStation(int client)
{
	int entity = EntRefToEntIndex(g_hUpgradeEntity[client]);
	g_hUpgradeEntity[client] = INVALID_ENT_REFERENCE;
	if(entity != -1) {
		RemoveEntity(entity);
		SetEntProp(client, Prop_Send, "m_bInUpgradeZone", 0);
	}
}

void DisableBountyMode()
{
	if(g_bIsEnabled) {
		for(int i = 1; i <= MaxClients; ++i) {
			if(IsClientInGame(i)) {
				if(g_HUDSync != null) {
					ClearSyncHud(i, g_HUDSync);
				}
				if(!g_bIsMVM) {
					//SendProxy_UnhookPropChange(i, "m_bInUpgradeZone", InUpgradeZone);
					SetEntProp(i, Prop_Send, "m_nCurrency", 0);
					GrantOrRemoveAllUpgrades(i, true, false);
					RemovePlayerAndItemUpgradesFromHistory(i);
					SetEntProp(i, Prop_Send, "m_bInUpgradeZone", 0);
				}
				SetExperiencePoints(i, 0);
				DeleteClientStation(i);
			}
			m_bIsInMVM[i] = false;
		}

		delete g_HUDSync;

		g_bReportUpgradeSetMVM = false;

		Event bountymode_toggled = CreateEvent("bountymode_toggled");
		if(bountymode_toggled != null) {
			bountymode_toggled.SetInt("active", 0);
			bountymode_toggled.Fire();
		}

		GameRules_SetProp("m_bBountyModeEnabled", 0);

		g_MapUpgradeStations.Clear();
		delete g_MapUpgradeStations;

		if(!g_bIsMVM) {
			tf_mvm_respec_enabled.RestoreDefault();
			tf_mvm_respec_limit.RestoreDefault();
			tf_mvm_respec_credit_goal.RestoreDefault();
		}

		int entity = EntRefToEntIndex(g_SpawnedInfoPopulator);
		if(entity != -1) {
			g_SpawnedInfoPopulator = INVALID_ENT_REFERENCE;
			RemoveEntity(entity);
		}

		UnhookEvent("player_team", player_team);
		UnhookEvent("player_changeclass", player_changeclass);
		UnhookEvent("player_spawn", player_spawn);
		UnhookEvent("player_death", player_death);
		UnhookEvent("teamplay_flag_event", teamplay_flag_event);
		UnhookEvent("object_destroyed", object_destroyed);
		if(!g_bIsMVM) {
			UnhookUserMessage(GetUserMessageId("MVMResetPlayerUpgradeSpending"), MVMResetPlayerUpgradeSpending);
			UnhookUserMessage(GetUserMessageId("MVMLocalPlayerWaveSpendingValue"), MVMLocalPlayerWaveSpendingValue);
			UnhookUserMessage(GetUserMessageId("MVMPlayerUpgradedEvent"), MVMPlayerUpgradedEvent);
		}
		UnhookUserMessage(GetUserMessageId("TextMsg"), TextMsg, true);

		if(!g_bIsMVM) {
			if(g_iPlayersInMVM > 0) {
				proxysend_unhook(tf_gamerules, "m_bPlayingMannVsMachine", IsMVM);
			}
		}
		g_iPlayersInMVM = 0;

		if(!g_bIsMVM) {
			dhGameModeUsesUpgrades.Disable(Hook_Pre, GameModeUsesUpgradesPre);
			dhReportUpgrade.Disable(Hook_Pre, ReportUpgradePre);
			dhReportUpgrade.Disable(Hook_Post, ReportUpgradePost);
			dhCanPlayerUseRespec.Disable(Hook_Pre, CanPlayerUseRespecPre);
			dhAddCurrency.Disable(Hook_Pre, AddCurrencyPre);
			dhAllocateBots.Disable(Hook_Pre, AllocateBotsPre);
			dhDistributeCurrencyAmount.Disable(Hook_Pre, DistributeCurrencyAmountPre);
		}

		g_bIsEnabled = false;
	}
}

void DrawHull(int[] clients, int numClients, const float origin[3], const float angles[3]=NULL_VECTOR, const float mins[3]={-16.0, -16.0, 0.0}, const float maxs[3]={16.0, 16.0, 72.0}, float lifetime = 0.1, int drawcolor[4] = {255, 0, 0, 255})
{
	float corners[8][3];
	
	for (int i = 0; i < 3; i++)
	{
		corners[0][i] = mins[i];
	}
	
	corners[1][0] = maxs[0];
	corners[1][1] = mins[1];
	corners[1][2] = mins[2];
	
	corners[2][0] = maxs[0];
	corners[2][1] = maxs[1];
	corners[2][2] = mins[2];
	
	corners[3][0] = mins[0];
	corners[3][1] = maxs[1];
	corners[3][2] = mins[2];
	
	corners[4][0] = mins[0];
	corners[4][1] = mins[1];
	corners[4][2] = maxs[2];
	
	corners[5][0] = maxs[0];
	corners[5][1] = mins[1];
	corners[5][2] = maxs[2];
	
	for (int i = 0; i < 3; i++)
	{
		corners[6][i] = maxs[i];
	}
	
	corners[7][0] = mins[0];
	corners[7][1] = maxs[1];
	corners[7][2] = maxs[2];

	for(int i = 0; i < sizeof(corners); i++)
	{
		float rad[3];
		rad[0] = DegToRad(angles[2]);
		rad[1] = DegToRad(angles[0]);
		rad[2] = DegToRad(angles[1]);

		float cosAlpha = Cosine(rad[0]);
		float sinAlpha = Sine(rad[0]);
		float cosBeta = Cosine(rad[1]);
		float sinBeta = Sine(rad[1]);
		float cosGamma = Cosine(rad[2]);
		float sinGamma = Sine(rad[2]);

		float x = corners[i][0], y = corners[i][1], z = corners[i][2];
		float newX, newY, newZ;
		newY = cosAlpha*y - sinAlpha*z;
		newZ = cosAlpha*z + sinAlpha*y;
		y = newY;
		z = newZ;

		newX = cosBeta*x + sinBeta*z;
		newZ = cosBeta*z - sinBeta*x;
		x = newX;
		z = newZ;

		newX = cosGamma*x - sinGamma*y;
		newY = cosGamma*y + sinGamma*x;
		x = newX;
		y = newY;
		
		corners[i][0] = x;
		corners[i][1] = y;
		corners[i][2] = z;
	}

	for(int i = 0; i < sizeof(corners); i++)
	{
		AddVectors(origin, corners[i], corners[i]);
	}

	for(int i = 0; i < 4; i++)
	{
		int j = ( i == 3 ? 0 : i+1 );
		TE_SetupBeamPoints(corners[i], corners[j], g_iLaserBeamIndex, g_iLaserBeamIndex, 0, 120, lifetime, 1.0, 1.0, 2, 1.0, drawcolor, 0);
		TE_Send(clients, numClients);
	}

	for(int i = 4; i < 8; i++)
	{
		int j = ( i == 7 ? 4 : i+1 );
		TE_SetupBeamPoints(corners[i], corners[j], g_iLaserBeamIndex, g_iLaserBeamIndex, 0, 120, lifetime, 1.0, 1.0, 2, 1.0, drawcolor, 0);
		TE_Send(clients, numClients);
	}

	for(int i = 0; i < 4; i++)
	{
		TE_SetupBeamPoints(corners[i], corners[i+4], g_iLaserBeamIndex, g_iLaserBeamIndex, 0, 120, lifetime, 1.0, 1.0, 2, 1.0, drawcolor, 0);
		TE_Send(clients, numClients);
	}
}

void VectorAddRotatedOffset(const float angle[3], float buffer[3], const float offset[3])
{
	float vecForward[3]; float vecLeft[3]; float vecUp[3];
	GetAngleVectors(angle, vecForward, vecLeft, vecUp);

	ScaleVector(vecForward, offset[0]);
	ScaleVector(vecLeft, offset[1]);
	ScaleVector(vecUp, offset[2]);

	float vecAdd[3];
	AddVectors(vecAdd, vecForward, vecAdd);
	AddVectors(vecAdd, vecLeft, vecAdd);
	AddVectors(vecAdd, vecUp, vecAdd);

	AddVectors(buffer, vecAdd, buffer);
}

float g_UpgradeStationMins[3] =
{
	0.0,
	-141.0,
	0.0,
};

float g_UpgradeStationMaxs[3] =
{
	195.0,
	140.0,
	184.0,
};

void DrawStationHull(int[] clients, int numClients, const float origin[3], float angles[3], bool inverse, float lifetime = 0.1, int drawcolor[4] = {255, 0, 0, 255})
{
	DrawHull(clients, numClients, origin, angles, g_UpgradeStationMins, g_UpgradeStationMaxs, lifetime, drawcolor);

	if(!inverse) {
		angles[1] -= 180.0;
	}

	float start[3];
	start[0] = origin[0];
	start[1] = origin[1];
	start[2] = origin[2];

	float offset[3];
	if(!inverse) {
		offset[0] = -60.0;
	} else {
		offset[0] = g_UpgradeStationMaxs[0] - 60.0;
	}
	offset[1] = g_UpgradeStationMaxs[1];

	VectorAddRotatedOffset(angles, start, offset);

	float end[3];
	end[0] = start[0];
	end[1] = start[1];
	end[2] = start[2] + g_UpgradeStationMaxs[2];

	TE_SetupBeamPoints(start, end, g_iLaserBeamIndex, g_iLaserBeamIndex, 0, 120, lifetime, 1.0, 1.0, 2, 1.0, drawcolor, 0);
	TE_Send(clients, numClients);

	start[0] = origin[0];
	start[1] = origin[1];

	offset[1] = -g_UpgradeStationMaxs[1];

	VectorAddRotatedOffset(angles, start, offset);

	end[0] = start[0];
	end[1] = start[1];

	TE_SetupBeamPoints(start, end, g_iLaserBeamIndex, g_iLaserBeamIndex, 0, 120, lifetime, 1.0, 1.0, 2, 1.0, drawcolor, 0);
	TE_Send(clients, numClients);
}

bool TraceEntityFilter_DontHitEntity(int entity, int mask, any data)
{
	return entity != data;
}

public void OnGameFrame()
{
	int[] clients = new int[MaxClients];
	int numClients = 0;

	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i)) {
			continue;
		}

		if(g_HUDSync != null) {
			int team = GetClientTeam(i);

			int m_nExperienceLevel = GetEntProp(i, Prop_Send, "m_nExperienceLevel");
			int m_nExperiencePoints = GetEntData(i, m_nExperiencePointsOffset);
			int m_nExperienceLevelProgress = GetEntProp(i, Prop_Send, "m_nExperienceLevelProgress");

			int progress = 0;
			if(m_nExperiencePoints > 400) {
				progress = m_nExperiencePoints - ((m_nExperienceLevel - 1) * 400);
			} else {
				progress = m_nExperiencePoints;
			}

			progress /= 25;
			if(progress == 16) {
				progress = 0;
			}

			char progress_bar[64];
			StrCat(progress_bar, sizeof(progress_bar), "[");
			for(int j = 0; j < 16; ++j) {
				if(j >= progress) {
					StrCat(progress_bar, sizeof(progress_bar), "_");
				} else {
					StrCat(progress_bar, sizeof(progress_bar), "|");
				}
			}
			StrCat(progress_bar, sizeof(progress_bar), "]");

			if(!g_bIsMVM) {
				SetHudTextParams(0.17, 0.82, 0.1, team == 2 ? 255 : 0, 0, team == 3 ? 255 : 0, 255);
				int m_nCurrency = GetEntProp(i, Prop_Send, "m_nCurrency");
				ShowSyncHudText(i, g_HUDSync, "%s\nExp Points: %i\nExp Level: %i\nMoney: %i", progress_bar, m_nExperiencePoints, m_nExperienceLevel, m_nCurrency);
			} else {
				SetHudTextParams(0.17, 0.82, 0.1, team == 2 ? 255 : 0, 0, team == 3 ? 255 : 0, 255);
				ShowSyncHudText(i, g_HUDSync, "%s\nExp Points: %i\nExp Level: %i", progress_bar, m_nExperiencePoints, m_nExperienceLevel);
			}
		}

		if(g_bDoingUpgradeHelper[i]) {
			clients[numClients++] = i;

			float pos[3];
			GetClientEyePosition(i, pos);

			float ang[3];
			GetClientEyeAngles(i, ang);

			Handle trace = TR_TraceRayFilterEx(pos, ang, MASK_SOLID, RayType_Infinite, TraceEntityFilter_DontHitEntity, i);

			float end[3];
			TR_GetEndPosition(end, trace);

			delete trace;

			ang[0] = 0.0;

			int tmp[1];
			tmp[0] = i;

			DrawStationHull(tmp, 1, end, ang, true);
		}
	}

	if(numClients > 0) {
		int entity = -1;
		while((entity = FindEntityByClassname(entity, "func_upgradestation")) != -1) {
			float pos[3];
			GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);

			float ang[3];
			GetEntPropVector(entity, Prop_Data, "m_angAbsRotation", ang);

			float mins[3];
			GetEntPropVector(entity, Prop_Data, "m_vecMins", mins);

			float maxs[3];
			GetEntPropVector(entity, Prop_Data, "m_vecMaxs", maxs);

			int m_nSolidType = GetEntProp(entity, Prop_Send, "m_nSolidType");
			if(m_nSolidType == SOLID_BBOX) {
				DrawHull(clients, numClients, pos, NULL_VECTOR, mins, maxs);
			} else if(m_nSolidType == SOLID_OBB) {
				DrawHull(clients, numClients, pos, ang, mins, maxs);
			}
		}
	}
}

Action sm_upgrdhel(int client, int args)
{
	if(client == 0) {
		ReplyToCommand(client, "[SM] you must be ingame to use this comamnd.");
		return Plugin_Handled;
	}

	g_bDoingUpgradeHelper[client] = !g_bDoingUpgradeHelper[client];
	if(!g_bDoingUpgradeHelper[client]) {
		float pos[3];
		GetClientEyePosition(client, pos);

		float ang[3];
		GetClientEyeAngles(client, ang);

		Handle trace = TR_TraceRayFilterEx(pos, ang, MASK_SOLID, RayType_Infinite, TraceEntityFilter_DontHitEntity, client);

		float end[3];
		TR_GetEndPosition(end, trace);

		delete trace;

		ang[0] = 0.0;
		ang[1] += 180.0;

		float offset[3];
		offset[0] -= g_UpgradeStationMaxs[0];
		VectorAddRotatedOffset(ang, end, offset);

		int clients[1];
		clients[0] = client;

		DrawStationHull(clients, 1, end, ang, false, 2.0, view_as<int>({0, 0, 255, 255}));

		ang[1] -= 180.0;

		CreateTempStation(end, ang);

		ReplyToCommand(client, "pos = %f %f %f", end[0], end[1], end[2]);
		ReplyToCommand(client, "ang = %f %f %f", ang[0], ang[1], ang[2]);
	}

	return Plugin_Handled;
}

int CreateStationEntity()
{
	int func = CreateEntityByName("func_upgradestation");
	DispatchSpawn(func);

	int m_fEffects = GetEntProp(func, Prop_Send, "m_fEffects");
	m_fEffects |= EF_NODRAW;
	SetEntProp(func, Prop_Send, "m_fEffects", m_fEffects);

	SetEntProp(func, Prop_Send, "m_nSolidType", SOLID_OBB);

	SetEntityModel(func, "models/props_mvm/mvm_upgrade_center.mdl");

	return func;
}

Action sm_upgrade(int client, int args)
{
	if(client == 0) {
		ReplyToCommand(client, "[SM] you must be ingame to use this comamnd.");
		return Plugin_Handled;
	}

	DeleteClientStation(client);

	int func = CreateStationEntity();

	g_hUpgradeEntity[client] = EntIndexToEntRef(func);

	float mins[3];
	GetEntPropVector(client, Prop_Data, "m_vecMins", mins);

	float maxs[3];
	GetEntPropVector(client, Prop_Data, "m_vecMaxs", maxs);

	SetEntPropVector(func, Prop_Data, "m_vecMins", mins);
	SetEntPropVector(func, Prop_Data, "m_vecMaxs", maxs);

	float pos[3];
	GetClientAbsOrigin(client, pos);

	float ang[3];
	GetClientAbsAngles(client, ang);

	TeleportEntity(func, pos, ang);

	return Plugin_Handled;
}

int CreateStation(float ang[3], bool temp = false)
{
	int func = CreateStationEntity();

	if(temp) {
		g_TempStations.Push(EntIndexToEntRef(func));
	} else {
		g_CreatedStations.Push(EntIndexToEntRef(func));
	}

	SetEntPropVector(func, Prop_Data, "m_vecMins", g_UpgradeStationMins);
	SetEntPropVector(func, Prop_Data, "m_vecMaxs", g_UpgradeStationMaxs);

	return func;
}

void CreateStationModels(float pos[3], float ang[3])
{
	int center = CreateEntityByName("prop_dynamic_override");
	DispatchKeyValue(center, "model", "models/props_mvm/mvm_upgrade_center.mdl");
	SetEntProp(center, Prop_Send, "m_nSolidType", SOLID_VPHYSICS);
	DispatchSpawn(center);

	g_StationModels.Push(EntIndexToEntRef(center));

	TeleportEntity(center, pos, ang);

	int tools = CreateEntityByName("prop_dynamic_override");
	DispatchKeyValue(tools, "model", "models/props_mvm/mvm_upgrade_tools.mdl");
	SetEntProp(tools, Prop_Send, "m_nSolidType", SOLID_VPHYSICS);
	DispatchSpawn(tools);

	g_StationModels.Push(EntIndexToEntRef(tools));

	float tmp_pos[3];
	tmp_pos[0] = pos[0] + 1.0;
	tmp_pos[1] = pos[1];
	tmp_pos[2] = pos[2];

	TeleportEntity(tools, tmp_pos, ang);
}

void CreateTempStation(float pos[3], float ang[3], bool enabled = true)
{
	if(g_TempStations == null) {
		g_TempStations = new ArrayList();
	}
	if(g_StationModels == null) {
		g_StationModels = new ArrayList();
	}

	int func = CreateStation(ang, true);

	if(enabled) {
		AcceptEntityInput(func, "Enable");
	} else {
		AcceptEntityInput(func, "Disable");
	}

	TeleportEntity(func, pos, ang);

	CreateStationModels(pos, ang);
}

void CreateStations(bool do_func = false)
{
	if(station_infos != null) {
		if(g_StationModels == null) {
			g_StationModels = new ArrayList();
		}

		if(do_func) {
			if(g_CreatedStations == null) {
				g_CreatedStations = new ArrayList();
			}
		}

		for(int i = 0; i < station_infos.Length; ++i) {
			StationInfo info;
			station_infos.GetArray(i, info, sizeof(StationInfo));

			CreateStationModels(info.pos, info.ang);

			if(do_func) {
				int func = CreateStation(info.ang);

				if(info.enabled) {
					AcceptEntityInput(func, "Enable");
				} else {
					AcceptEntityInput(func, "Disable");
				}

				TeleportEntity(func, info.pos, info.ang);
			}
		}
	}
}

void ParseKeyValues()
{
	char mapname[PLATFORM_MAX_PATH];
	GetCurrentMap(mapname, sizeof(mapname));

	if(kvUpgrades != null) {
		if(kvUpgrades.JumpToKey(mapname)) {
			char script[PLATFORM_MAX_PATH];
			kvUpgrades.GetString("script", script, sizeof(script));

			if(!StrEqual(script, "")) {
				int entity = EntRefToEntIndex(tf_gamerules);
				if(entity != -1) {
					SetVariantString(script);
					AcceptEntityInput(entity, "SetCustomUpgradesFile");
				}
			}

			if(kvUpgrades.JumpToKey("stations")) {
				if(kvUpgrades.GotoFirstSubKey()) {
					station_infos = new ArrayList(sizeof(StationInfo));
					if(g_CreatedStations == null) {
						g_CreatedStations = new ArrayList();
					}
					if(g_StationModels == null) {
						g_StationModels = new ArrayList();
					}

					do {
						StationInfo info;

						info.enabled = kvUpgrades.GetNum("enabled", g_bIsEnabled || GameRules_GetProp("m_bPlayingMannVsMachine"));

						kvUpgrades.GetVector("pos", info.pos);
						kvUpgrades.GetVector("ang", info.ang);

						station_infos.PushArray(info, sizeof(StationInfo));

						int func = CreateStation(info.ang);

						if(info.enabled) {
							AcceptEntityInput(func, "Enable");
						} else {
							AcceptEntityInput(func, "Disable");
						}

						TeleportEntity(func, info.pos, info.ang);
					} while(kvUpgrades.GotoNextKey());
					kvUpgrades.GoBack();
				}
				kvUpgrades.GoBack();
			}
			kvUpgrades.GoBack();
		}
	}
}

public void OnMapStart()
{
	g_iLaserBeamIndex = PrecacheModel("materials/sprites/laser.vmt");

	PrecacheModel("models/props_mvm/mvm_upgrade_center.mdl");
	PrecacheModel("models/props_mvm/mvm_upgrade_tools.mdl");
	PrecacheModel("models/props_mvm/mvm_upgrade_sign.mdl");
	PrecacheSound("mvm/mvm_money_pickup.wav");

	tf_gamerules = FindEntityByClassname(-1, "tf_gamerules");
	if(tf_gamerules != -1) {
		tf_gamerules = EntIndexToEntRef(tf_gamerules);
	}

	ParseKeyValues();

	CreateStations();

	if(tf_bountymode.BoolValue) {
		if(GameRules_GetProp("m_bPlayingMannVsMachine")) {
			g_bIsMVM = true;
		}

		EnableBountyMode();
	}
}

public void OnPluginEnd()
{
	OnMapEnd();
}

void DestroyTempStations()
{
	if(g_TempStations != null) {
		g_bRemovingStations = true;

		for(int i = 0; i < g_TempStations.Length; ++i) {
			int entity = EntRefToEntIndex(g_TempStations.Get(i));
			if(entity != -1) {
				RemoveEntity(entity);
			}
		}

		g_bRemovingStations = false;

		delete g_TempStations;
	}
}

void DestroyStations()
{
	if(g_CreatedStations != null) {
		g_bRemovingStations = true;

		for(int i = 0; i < g_CreatedStations.Length; ++i) {
			int entity = EntRefToEntIndex(g_CreatedStations.Get(i));
			if(entity != -1) {
				RemoveEntity(entity);
			}
		}

		g_bRemovingStations = false;

		delete g_CreatedStations;
	}

	DestroyTempStations();

	if(g_StationModels != null) {
		g_bRemovingStationModels = true;

		for(int i = 0; i < g_StationModels.Length; i++) {
			int entity = EntRefToEntIndex(g_StationModels.Get(i));
			if(entity != -1) {
				RemoveEntity(entity);
			}
		}

		g_bRemovingStationModels = false;

		delete g_StationModels;
	}
}

public void OnMapEnd()
{
	if(g_bIsEnabled) {
		DisableBountyMode();
	}

	DestroyStations();
}

void NeedPopulator()
{
	int entity = EntRefToEntIndex(g_SpawnedInfoPopulator);
	if(entity == -1) {
		entity = CreateEntityByName("info_populator");
		DispatchSpawn(entity);
		g_SpawnedInfoPopulator = EntIndexToEntRef(entity);
	}
}

void DontNeedPopulator()
{
	int entity = EntRefToEntIndex(g_SpawnedInfoPopulator);
	if(entity != -1) {
		g_SpawnedInfoPopulator = INVALID_ENT_REFERENCE;
		RemoveEntity(entity);
	}
}

void SetAsInMVM(int client, bool is, FromWhere source)
{
	if(source != FromClientCMD) {
		bool was = m_bIsInMVM[client];
		m_bIsInMVM[client] = is;
		if(is && !was) {
			++g_iPlayersInMVM;
		} else if(!is && was) {
			--g_iPlayersInMVM;
		}
	}

	if(source != FromUpgradeZone) {
		if(is) {
			GameRules_SetPlayingMVM(1);
		} else {
			GameRules_SetPlayingMVM(0);
		}
	}

	if(source != FromClientCMD) {
		if(g_iPlayersInMVM == 1) {
			proxysend_hook(tf_gamerules, "m_bPlayingMannVsMachine", IsMVM, false);
			NeedPopulator();
		} else if(g_iPlayersInMVM == 0) {
			proxysend_unhook(tf_gamerules, "m_bPlayingMannVsMachine", IsMVM);
			DontNeedPopulator();
		}
	}
}

Action MVMLocalPlayerWaveSpendingValue(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	for(int i = 0; i < 7; ++i) {
		msg.ReadByte();
	}
	int client = msg.ReadByte();
	SetAsInMVM(client, true, FromUpgradeZone);
	return Plugin_Continue;
}

Action Timer_TextMsg(Handle timer, DataPack data)
{
	data.Reset();

	int dst = data.ReadCell();

	int len = data.ReadCell();
	char[] text = new char[len];
	data.ReadString(text, len);

	len = data.ReadCell();
	char[] param1 = new char[len];
	data.ReadString(param1, len);

	len = data.ReadCell();
	char[] param2 = new char[len];
	data.ReadString(param2, len);

	len = data.ReadCell();
	char[] param3 = new char[len];
	data.ReadString(param3, len);

	len = data.ReadCell();
	int[] players = new int[len];
	data.ReadCellArray(players, len);

	BfWrite usrmsg = view_as<BfWrite>(StartMessage("TextMsg", players, len));
	usrmsg.WriteByte(dst);
	usrmsg.WriteString(text);
	usrmsg.WriteString(param1);
	usrmsg.WriteString(param2);
	usrmsg.WriteString(param3);
	EndMessage();

	return Plugin_Continue;
}

Action TextMsg(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	int dst = msg.ReadByte();

	char text[64];
	msg.ReadString(text, sizeof(text));

	if(StrEqual(text, "#TF_PlayerLeveled")) {
		DataPack data = null;
		CreateDataTimer(0.1, Timer_TextMsg, data);

		data.WriteCell(dst);

		char[] newtext = "%s1 | %s2 has leveled-up to level %s3.";
		int len = strlen(newtext)+1;
		data.WriteCell(len);
		data.WriteString(newtext);

		len = sizeof(text);
		msg.ReadString(text, len);
		data.WriteCell(len);
		data.WriteString(text);

		len = sizeof(text);
		msg.ReadString(text, len);
		data.WriteCell(len);
		data.WriteString(text);

		len = sizeof(text);
		msg.ReadString(text, len);
		data.WriteCell(len);
		data.WriteString(text);

		data.WriteCell(playersNum);
		data.WriteCellArray(players, playersNum);

		return Plugin_Stop;
	}

	return Plugin_Continue;
}

Action MVMPlayerUpgradedEvent(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	int client = msg.ReadByte();
	SetAsInMVM(client, true, FromUpgradeZone);
	return Plugin_Continue;
}

Action MVMResetPlayerUpgradeSpending(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	int client = msg.ReadByte();
	SetAsInMVM(client, false, FromUpgradeZone);
	//DeleteClientStation(client);
	return Plugin_Continue;
}

void GrantOrRemoveAllUpgrades(int client, bool remove, bool refund)
{
	int entity = EntRefToEntIndex(g_UpgradeStation);
	if(entity != -1) {
		SetAsInMVM(client, true, FromDeath);
		SDKCall(hGrantOrRemoveAllUpgrades, entity, client, remove, refund);
		SetAsInMVM(client, false, FromDeath);
	}
}

int GetInfoPopulatorIndex()
{
	int entity = EntRefToEntIndex(g_InfoPopulator);
	if(entity == -1) {
		entity = EntRefToEntIndex(g_SpawnedInfoPopulator);
	}
	return entity;
}

void AddPlayerCurrencySpent(int client, int cash)
{
	int entity = GetInfoPopulatorIndex();
	if(entity != -1) {
		SDKCall(hAddPlayerCurrencySpent, entity, client, cash);
	}
}

void RemovePlayerAndItemUpgradesFromHistory(int client)
{
	int entity = GetInfoPopulatorIndex();
	if(entity != -1) {
		SDKCall(hRemovePlayerAndItemUpgradesFromHistory, entity, client);
	}
}

void InUpgradeZone(const int iEntity, const char[] cPropName, const int iOldValue, const int iNewValue, const int iElement)
{
	if(iNewValue == 1) {
		SetAsInMVM(iEntity, true, FromUpgradeZone);
	} else {
		SetAsInMVM(iEntity, false, FromUpgradeZone);
		DeleteClientStation(iEntity);
	}
}

void GameRules_SetPlayingMVM(int value)
{
#if 0
	int entity = EntRefToEntIndex(tf_gamerules);
	if(entity != -1) {
		//SetEntData(entity, m_bPlayingMannVsMachineOffset, value);
	}
#else
	GameRules_SetProp("m_bPlayingMannVsMachine", value);
#endif
}

public Action OnClientCommandKeyValues(int client, KeyValues kv)
{
	char name[32];
	kv.GetSectionName(name, sizeof(name));

	bool MvM_UpgradesDone = StrEqual(name, "MvM_UpgradesDone");

	if(g_bIsEnabled && !g_bIsMVM) {
		if(StrEqual(name, "MVM_Upgrade") ||
			StrEqual(name, "MvM_UpgradesBegin")) {
			SetAsInMVM(client, true, FromClientCMD);
		} else {
			if(MvM_UpgradesDone ||
				StrEqual(name, "MVM_Respec")) {
				SetAsInMVM(client, false, FromClientCMD);
			}
			if(MvM_UpgradesDone) {
				GameRules_SetPlayingMVM(1);
			}
		}
	}

	if(MvM_UpgradesDone) {
		DeleteClientStation(client);
	}

	return Plugin_Continue;
}

public void OnClientCommandKeyValues_Post(int client, KeyValues kv)
{
	char name[32];
	kv.GetSectionName(name, sizeof(name));

	bool MvM_UpgradesDone = StrEqual(name, "MvM_UpgradesDone");

	if(g_bIsEnabled && !g_bIsMVM) {
		if(StrEqual(name, "MVM_Upgrade") ||
			StrEqual(name, "MvM_UpgradesBegin")) {
			SetAsInMVM(client, false, FromClientCMD);
		} else if(MvM_UpgradesDone) {
			GameRules_SetPlayingMVM(0);
		}
	}

	if(MvM_UpgradesDone) {
		DeleteClientStation(client);
	}
}

public void OnClientDisconnect(int client)
{
	g_bDoingUpgradeHelper[client] = false;
	g_bGotSpawn[client] = false;

	DeleteClientStation(client);

	if(g_bIsEnabled && !g_bIsMVM) {
		SetAsInMVM(client, false, FromDeath);

		if(IsClientInGame(client)) {
			GrantOrRemoveAllUpgrades(client, true, false);
			RemovePlayerAndItemUpgradesFromHistory(client);
		}
	}
}

Action object_destroyed(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if(attacker != 0) {
		SDKCall(hAddExperiencePoints, attacker, CalculateCurrencyAmount_ByType(TF_CURRENCY_KILLED_OBJECT), !g_bIsMVM, -1);
	}

	return Plugin_Continue;
}

void RestorePlayerCurrency()
{
	int entity = GetInfoPopulatorIndex();
	if(entity != -1) {
		
	}
}

Action teamplay_round_start(Event event, const char[] name, bool dontBroadcast)
{
	RestorePlayerCurrency();

	DestroyTempStations();
	CreateStations();

	return Plugin_Continue;
}

Action teamplay_flag_event(Event event, const char[] name, bool dontBroadcast)
{
	int client = event.GetInt("player");
	int eventtype = event.GetInt("eventtype");

	//TODO!!! check if its ctf specifically

	if(eventtype == TF_FLAGEVENT_CAPTURED) {
		SDKCall(hAddExperiencePoints, client, CalculateCurrencyAmount_ByType(TF_CURRENCY_CAPTURED_OBJECTIVE), false, -1);
	}

	return Plugin_Continue;
}

Action Timer_WaitForSpawn(Handle timer, int client)
{
	client = GetClientOfUserId(client);
	if(client != -1) {
		if(g_bGotSpawn[client]) {
			SDKCall(hRefundExperiencePoints, client);
		} else {
			if(!g_bIsMVM) {
				SetEntProp(client, Prop_Send, "m_nCurrency", 0);
			}
			SetExperiencePoints(client, 0);
		}
		g_bGotSpawn[client] = false;
	}

	return Plugin_Continue;
}

Action player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	g_bGotSpawn[client] = true;
	return Plugin_Continue;
}

Action player_changeclass(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);

	g_bGotSpawn[client] = false;
	CreateTimer(0.1, Timer_WaitForSpawn, userid);

	return Plugin_Continue;
}

Action player_team(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	SDKCall(hRefundExperiencePoints, client);

	return Plugin_Continue;
}

Action player_death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int assister = GetClientOfUserId(event.GetInt("assister"));
	int flags = event.GetInt("death_flags");

	if(!(flags & TF_DEATHFLAG_DEADRINGER)) {
		if(attacker != 0 && attacker != client) {
			SDKCall(hAddExperiencePoints, attacker, CalculateCurrencyAmount_ByType(TF_CURRENCY_KILLED_PLAYER), !g_bIsMVM, client);
		}

		if(assister != 0 && assister != client) {
			SDKCall(hAddExperiencePoints, assister, CalculateCurrencyAmount_ByType(TF_CURRENCY_ASSISTED_PLAYER), !g_bIsMVM, -1);
		}

		if(!g_bIsMVM) {
			float flPenalty = tf_bountymode_currency_penalty_ondeath.FloatValue;
			if(flPenalty) {
				int m_nCurrency = GetEntProp(client, Prop_Send, "m_nCurrency");
				if(m_nCurrency) {
					int newcurrency = RoundToFloor(float(m_nCurrency) * flPenalty);
					if(newcurrency > 30000) {
						newcurrency = 30000;
					}
					if(newcurrency < 0) {
						newcurrency = 0;
					}
					if(newcurrency > 0) {
						RemoveCurrency(client, newcurrency);
					}
				}
			}

			if(tf_bountymode_upgrades_wipeondeath.BoolValue) {
				GrantOrRemoveAllUpgrades(client, true, false);
				RemovePlayerAndItemUpgradesFromHistory(client);
			}
		}
	}

	return Plugin_Continue;
}

MRESReturn ReportUpgradePre(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if(GetInfoPopulatorIndex() == -1) {
		if(GameRules_GetProp("m_bPlayingMannVsMachine")) {
			GameRules_SetPlayingMVM(0);
			g_bReportUpgradeSetMVM = true;
		}
	}

	NeedPopulator();

	return MRES_Ignored;
}

MRESReturn ReportUpgradePost(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if(g_bReportUpgradeSetMVM) {
		GameRules_SetPlayingMVM(1);
		g_bReportUpgradeSetMVM = false;
	}

	//DontNeedPopulator();

	return MRES_Ignored;
}

MRESReturn GameModeUsesUpgradesPre(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	hReturn.Value = 1;
	return MRES_Supercede;
}

MRESReturn AllocateBotsPre(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	return MRES_Supercede;
}

void OnCurrencyCollected(int nAmount, bool bCountAsDropped, bool bIsBonus)
{
	int entity = GetInfoPopulatorIndex();
	if(entity != -1) {
		
	}
}

MRESReturn DistributeCurrencyAmountPre(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	int shared = hParams.Get(3);
	int cash = hParams.Get(1);
	bool bCountAsDropped = hParams.Get(4);
	bool bIsBonus = hParams.Get(5);

	OnCurrencyCollected(cash, bCountAsDropped, bIsBonus);

	if(shared) {
		int client = hParams.Get(2);

		int team = GetClientTeam(client);

		for(int i = 1; i <= MaxClients; ++i) {
			if(!IsClientInGame(i) ||
				!IsPlayerAlive(i)) {
				continue;
			}

			if(GetClientTeam(i) != team) {
				continue;
			}

			AddCurrency(i, cash);
		}

		hReturn.Value = cash;
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

MRESReturn AddCurrencyPre(int pThis, DHookParam hParams)
{
	int nAmount = hParams.Get(1);
	int m_nCurrency = GetEntProp(pThis, Prop_Send, "m_nCurrency");

	int nLimit = tf_bountymode_currency_limit.IntValue;
	if(nLimit > 0) {
		int nNewCurrency = nAmount + m_nCurrency;
		if(nNewCurrency > nLimit) {
			int nDelta = nNewCurrency - nLimit;
			if(nDelta) {
				nAmount -= nDelta;
				hParams.Set(1, nAmount);
				return MRES_ChangedHandled;
			}
		}
	}

	return MRES_Ignored;
}

MRESReturn CanPlayerUseRespecPre(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	hReturn.Value = 1;
	return MRES_Supercede;
}

bool IsPlayer(int entity)
{
	return (entity >= 1 && entity <= MaxClients);
}

void UpgradeStartTouch(int entity, int other)
{
	if(IsPlayer(other)) {
		SetAsInMVM(other, true, FromUpgradeZone);
	}
}

void UpgradeEndTouch(int entity, int other)
{
	if(IsPlayer(other)) {
		SetAsInMVM(other, false, FromUpgradeZone);
		DeleteClientStation(other);
	}
}

void StationCreated(int entity)
{
	g_UpgradeStation = EntIndexToEntRef(entity);
	if(!g_bIsMVM) {
		SDKHook(entity, SDKHook_StartTouch, UpgradeStartTouch);
		SDKHook(entity, SDKHook_EndTouch, UpgradeEndTouch);
	}
}

void PopulatorCreated(int entity)
{
	g_InfoPopulator = EntIndexToEntRef(entity);
}

public void OnEntityDestroyed(int entity)
{
	if(entity == -1) {
		return;
	}

	if(entity & (1 << 31)) {
		entity = EntRefToEntIndex(entity);
	}

	if(g_SpawnedInfoPopulator != INVALID_ENT_REFERENCE) {
		if(entity == EntRefToEntIndex(g_SpawnedInfoPopulator)) {
			g_SpawnedInfoPopulator = INVALID_ENT_REFERENCE;
		}
	}

	if(g_InfoPopulator != INVALID_ENT_REFERENCE) {
		if(entity == EntRefToEntIndex(g_InfoPopulator)) {
			g_InfoPopulator = INVALID_ENT_REFERENCE;
		}
	}

	if(g_UpgradeStation != INVALID_ENT_REFERENCE) {
		if(entity == EntRefToEntIndex(g_UpgradeStation)) {
			if(g_MapUpgradeStations != null) {
				int index = g_MapUpgradeStations.FindValue(g_UpgradeStation);
				if(index != -1) {
					g_MapUpgradeStations.Erase(index);
				}
			}

			if(g_MapUpgradeStations != null && g_MapUpgradeStations.Length > 0) {
				g_UpgradeStation = g_MapUpgradeStations.Get(0);
			} else if(g_CreatedStations != null && g_CreatedStations.Length > 0) {
				g_UpgradeStation = g_CreatedStations.Get(0);
			} else if(g_TempStations != null && g_TempStations.Length > 0) {
				g_UpgradeStation = g_TempStations.Get(0);
			} else {
				g_UpgradeStation = INVALID_ENT_REFERENCE;
			}
		}
	}

	if(tf_gamerules != INVALID_ENT_REFERENCE) {
		if(entity == EntRefToEntIndex(tf_gamerules)) {
			tf_gamerules = INVALID_ENT_REFERENCE;
		}
	}

	if(!g_bRemovingStations) {
		if(g_CreatedStations != null) {
			int index = g_CreatedStations.FindValue(EntIndexToEntRef(entity));
			if(index != -1) {
				g_CreatedStations.Erase(index);
			}
		}
	}

	if(!g_bRemovingStations) {
		if(g_TempStations != null) {
			int index = g_TempStations.FindValue(EntIndexToEntRef(entity));
			if(index != -1) {
				g_TempStations.Erase(index);
			}
		}
	}

	if(!g_bRemovingStationModels) {
		if(g_StationModels != null) {
			int index = g_StationModels.FindValue(EntIndexToEntRef(entity));
			if(index != -1) {
				g_StationModels.Erase(index);
			}
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "func_upgradestation")) {
		StationCreated(entity);
	} else if(StrEqual(classname, "info_populator")) {
		PopulatorCreated(entity);
	} else if(StrEqual(classname, "tf_gamerules")) {
		tf_gamerules = EntIndexToEntRef(entity);
	}
}

Action IsMVM(int entity, const char[] prop, bool &value, int element, int client)
{
	value = false;
	return Plugin_Changed;
}
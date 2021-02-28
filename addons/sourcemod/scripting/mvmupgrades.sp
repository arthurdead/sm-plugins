#include <sourcemod>
#include <sdktools>
#include <sendproxy>
#include <dhooks>
#include <sdkhooks>
#include <keyvalues>
#include <tf2_stocks>

#define SENDPROXY_PER_PLAYER

#pragma semicolon 1
#pragma newdecls required

Handle hGrantOrRemoveAllUpgrades = null;
int g_UpgradeStation = -1;
ConVar tf_gamemode_mvm = null;
bool ReportUpgradeSetMVM = false;
bool HasInfoPopulator = false;
int InfoPopulatorIndex = -1;
int g_iPlayersInMVM = 0;
bool m_bIsInMVM[MAXPLAYERS] = {false,...};
bool g_bLateLoaded = false;
ConVar mvm_remove_upgrades_on_death = null;

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

public void OnPluginStart()
{
	GameData gamedata = new GameData("mvmupgrades");

	DynamicDetour dhGameModeUsesUpgrades = DynamicDetour.FromConf(gamedata, "CTFGameRules::GameModeUsesUpgrades");
	DynamicDetour dhReportUpgrade = DynamicDetour.FromConf(gamedata, "CUpgrades::ReportUpgrade");
	DynamicDetour dhCanPlayerUseRespec = DynamicDetour.FromConf(gamedata, "CTFGameRules::CanPlayerUseRespec");

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CUpgrades::GrantOrRemoveAllUpgrades");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hGrantOrRemoveAllUpgrades = EndPrepSDKCall();

	delete gamedata;

	dhGameModeUsesUpgrades.Enable(Hook_Pre, GameModeUsesUpgradesPre);
	dhReportUpgrade.Enable(Hook_Pre, ReportUpgradePre);
	dhReportUpgrade.Enable(Hook_Post, ReportUpgradePost);
	dhCanPlayerUseRespec.Enable(Hook_Pre, CanPlayerUseRespecPre);

	tf_gamemode_mvm = FindConVar("tf_gamemode_mvm");
	tf_gamemode_mvm.Flags &= ~FCVAR_NOTIFY;

	mvm_remove_upgrades_on_death = CreateConVar("mvm_remove_upgrades_on_death", "1");

	HookEvent("player_death", player_death);

	HookUserMessage(GetUserMessageId("MVMResetPlayerUpgradeSpending"), MVMResetPlayerUpgradeSpending);

	if(g_bLateLoaded) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientInGame(i)) {
				OnClientPutInServer(i);
			}
		}
	}
}

public void OnConfigsExecuted()
{
	ConVar tmp = FindConVar("tf_mvm_respec_enabled");
	tmp.BoolValue = true;

	tmp = FindConVar("tf_mvm_respec_limit");
	tmp.IntValue = 0;

	tmp = FindConVar("tf_mvm_respec_credit_goal");
	tmp.IntValue = 0;
}

void SetAsInMVM(int client, bool is, FromWhere source)
{
	bool was = m_bIsInMVM[client];
	m_bIsInMVM[client] = is;
	if(source != FromClientCMD) {
		if(is && !was) {
			g_iPlayersInMVM++;
		} else if(!is && was) {
			g_iPlayersInMVM--;
		}
	}

	if(source != FromUpgradeZone) {
		if(is) {
			GameRules_SetProp("m_bPlayingMannVsMachine", 1);
		} else {
			GameRules_SetProp("m_bPlayingMannVsMachine", 0);
		}
	}

	if(source != FromClientCMD) {
		if(g_iPlayersInMVM == 1) {
			SendProxy_HookGameRules("m_bPlayingMannVsMachine", Prop_Int, IsMVM);
			int ent = FindEntityByClassname(-1, "info_populator");
			if(ent == -1) {
				ent = CreateEntityByName("info_populator");
				DispatchSpawn(ent);
				InfoPopulatorIndex = ent;
			}
			HasInfoPopulator = true;
		} else if(g_iPlayersInMVM == 0) {
			SendProxy_UnhookGameRules("m_bPlayingMannVsMachine", IsMVM);
			if(InfoPopulatorIndex != -1) {
				RemoveEntity(InfoPopulatorIndex);
				InfoPopulatorIndex = -1;
				HasInfoPopulator = false;
			}
		}
	}
}

Action MVMResetPlayerUpgradeSpending(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	int client = BfReadByte(msg);
	SetAsInMVM(client, false, FromUpgradeZone);
	return Plugin_Continue;
}

void GrantOrRemoveAllUpgrades(int client, bool remove, bool refund)
{
	if(g_UpgradeStation != -1) {
		SetAsInMVM(client, true, FromDeath);
		SDKCall(hGrantOrRemoveAllUpgrades, g_UpgradeStation, client, remove, refund);
		SetAsInMVM(client, false, FromDeath);
	}
}

void InUpgradeZone(const int iEntity, const char[] cPropName, const int iOldValue, const int iNewValue, const int iElement)
{
	if(iNewValue == 1) {
		SetAsInMVM(iEntity, true, FromUpgradeZone);
	} else {
		SetAsInMVM(iEntity, false, FromUpgradeZone);
	}
}

public Action OnClientCommandKeyValues(int client, KeyValues kv)
{
	char name[32];
	kv.GetSectionName(name, sizeof(name));

	if(StrEqual(name, "MVM_Upgrade") ||
		StrEqual(name, "MvM_UpgradesBegin")) {
		SetAsInMVM(client, true, FromClientCMD);
	} else if(StrEqual(name, "MvM_UpgradesDone") ||
				StrEqual(name, "MVM_Respec")) {
		SetAsInMVM(client, false, FromClientCMD);
	}

	return Plugin_Continue;
}

public void OnClientCommandKeyValues_Post(int client, KeyValues kv)
{
	char name[32];
	kv.GetSectionName(name, sizeof(name));

	if(StrEqual(name, "MVM_Upgrade") ||
		StrEqual(name, "MvM_UpgradesBegin")) {
		SetAsInMVM(client, false, FromClientCMD);
	}
}

public void OnClientPutInServer(int client)
{
	SendProxy_HookPropChangeSafe(client, "m_bInUpgradeZone", Prop_Int, InUpgradeZone);
}

public void OnClientDisconnected(int client)
{
	SetAsInMVM(client, false, FromDeath);
}

public void OnPluginEnd()
{
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientInGame(i)) {
			GrantOrRemoveAllUpgrades(i, true, false);
		}
	}
}

void player_death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int flags = event.GetInt("death_flags");

	if(!(flags & TF_DEATHFLAG_DEADRINGER)) {
		if(mvm_remove_upgrades_on_death.BoolValue) {
			GrantOrRemoveAllUpgrades(client, true, false);
		}
	}
}

MRESReturn ReportUpgradePre(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	bool m_bPlayingMannVsMachine = view_as<bool>(GameRules_GetProp("m_bPlayingMannVsMachine"));
	if(!HasInfoPopulator && m_bPlayingMannVsMachine) {
		GameRules_SetProp("m_bPlayingMannVsMachine", 0);
		ReportUpgradeSetMVM = true;
	}
	return MRES_Ignored;
}

MRESReturn ReportUpgradePost(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if(ReportUpgradeSetMVM) {
		GameRules_SetProp("m_bPlayingMannVsMachine", 1);
		ReportUpgradeSetMVM = false;
	}
	return MRES_Ignored;
}

MRESReturn GameModeUsesUpgradesPre(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	hReturn.Value = 1;
	return MRES_Supercede;
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
	}
}

void StationCreated(int entity)
{
	g_UpgradeStation = entity;
	SDKHook(entity, SDKHook_StartTouch, UpgradeStartTouch);
	SDKHook(entity, SDKHook_EndTouch, UpgradeEndTouch);
}

void PopulatorCreated(int entity)
{
	HasInfoPopulator = true;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "func_upgradestation")) {
		StationCreated(entity);
	} else if(StrEqual(classname, "info_populator")) {
		PopulatorCreated(entity);
	}
}

#if defined SENDPROXY_PER_PLAYER
Action IsMVM(const char[] cPropName, int &iValue, const int iElement, const int iClient)
#else
Action IsMVM(const char[] cPropName, int &iValue, const int iElement)
#endif
{
	iValue = 0;
	return Plugin_Changed;
}

public void OnMapStart()
{
	if(g_bLateLoaded) {
		int ent = FindEntityByClassname(-1, "func_upgradestation");
		if(ent != -1) {
			StationCreated(ent);
		}
		ent = FindEntityByClassname(-1, "info_populator");
		if(ent != -1) {
			PopulatorCreated(ent);
		}
	}
}
#include <sourcemod>
#include <sdktools>
#include <dhooks>

static bool set_as_mvm = false;
static bool map_started = false;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int length)
{
	RegPluginLibrary("ruleshook");
	return APLRes_Success;
}

public void OnPluginStart()
{
	GameData gamedata = new GameData("ruleshooks");

	DynamicDetour tmp_detour = DynamicDetour.FromConf(gamedata, "CTFGameRules::GameModeUsesUpgrades");
	tmp_detour.Enable(Hook_Post, CTFGameRules_GameModeUsesUpgrades);

	tmp_detour = DynamicDetour.FromConf(gamedata, "CUpgrades::ReportUpgrade");
	tmp_detour.Enable(Hook_Pre, CUpgrades_ReportUpgrade_pre);
	tmp_detour.Enable(Hook_Post, CUpgrades_ReportUpgrade_post);

	delete gamedata;
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

static MRESReturn CTFGameRules_GameModeUsesUpgrades(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if(hReturn.Value == 1) {
		return MRES_Ignored;
	}

	hReturn.Value = gamemode_uses_upgrades_no_mvm();
	return MRES_Supercede;
}

static bool gamemode_uses_upgrades()
{
	return true;
}

static bool gamemode_uses_upgrades_no_mvm()
{
	if(!set_as_mvm && (map_started && GameRules_GetProp("m_bPlayingMannVsMachine") == 1)) {
		return false;
	}

	return gamemode_uses_upgrades();
}

public void OnMapStart()
{
	map_started = true;
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

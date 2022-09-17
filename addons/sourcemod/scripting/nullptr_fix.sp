#include <sourcemod>
#include <dhooks>

public void OnPluginStart()
{
	GameData gamedata = new GameData("nullptr_fix");
	if(gamedata == null) {
		SetFailState("Gamedata not found.");
		return;
	}

	DynamicDetour tmp = DynamicDetour.FromConf(gamedata, "EconItemInterface_OnOwnerKillEaterEvent_Batched");
	if(!tmp || !tmp.Enable(Hook_Pre, EconItemInterface_OnOwnerKillEaterEvent_Batched_detour)) {
		SetFailState("Failed to enable pre detour for EconItemInterface_OnOwnerKillEaterEvent_Batched");
		delete gamedata;
		return;
	}

	tmp = DynamicDetour.FromConf(gamedata, "CObjectSentrygun::GetEnemyAimPosition");
	if(!tmp || !tmp.Enable(Hook_Pre, CObjectSentrygun_GetEnemyAimPosition_detour)) {
		SetFailState("Failed to enable pre detour for CObjectSentrygun::GetEnemyAimPosition");
		delete gamedata;
		return;
	}

	delete gamedata;
}

static MRESReturn CObjectSentrygun_GetEnemyAimPosition_detour(int pThis, DHookReturn hReturn, DHookParam hParams)
{
	if(hParams.IsNull(1) || hParams.GetAddress(1) == Address_Null || hParams.Get(1) == -1) {
		hReturn.SetVector(view_as<float>({0.0, 0.0, 0.0}));
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

static MRESReturn EconItemInterface_OnOwnerKillEaterEvent_Batched_detour(DHookParam hParams)
{
	if(hParams.IsNull(2) || hParams.GetAddress(2) == Address_Null || hParams.Get(2) == -1) {
		return MRES_Supercede;
	}

	return MRES_Ignored;
}
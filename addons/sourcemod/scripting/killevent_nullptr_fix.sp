#include <sourcemod>
#include <dhooks>

public void OnPluginStart()
{
	GameData gamedata = new GameData("killevent_nullptr_fix");
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

	delete gamedata;
}

static MRESReturn EconItemInterface_OnOwnerKillEaterEvent_Batched_detour(DHookParam hParams)
{
	Address addr = hParams.GetAddress(2);
	if(addr == Address_Null) {
		return MRES_Supercede;
	}

	int ent = hParams.Get(2);
	if(ent == -1) {
		return MRES_Supercede;
	}

	return MRES_Ignored;
}
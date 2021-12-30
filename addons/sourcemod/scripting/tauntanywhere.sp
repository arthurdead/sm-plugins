#include <sourcemod>
#include <dhooks>

static ConVar tf_allow_sliding_taunt = null;
static ConVar tf_allow_taunt_switch = null;
static ConVar tf_allow_all_team_partner_taunt = null;

static int tempgroundent;
static int tempwaterlevel;

public void OnPluginStart()
{
	tf_allow_sliding_taunt = FindConVar("tf_allow_sliding_taunt");
	tf_allow_taunt_switch = FindConVar("tf_allow_taunt_switch");
	tf_allow_all_team_partner_taunt = FindConVar("tf_allow_all_team_partner_taunt");

	GameData gamedata = new GameData("tauntanywhere");
	if(gamedata == null) {
		SetFailState("Gamedata not found.");
		return;
	}

	DynamicDetour tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::IsAllowedToTaunt");
	if(!tmp || !tmp.Enable(Hook_Pre, IsAllowedToTaunt)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::IsAllowedToTaunt");
		delete gamedata;
		return;
	}
	if(!tmp.Enable(Hook_Post, IsAllowedToTaunt_post)) {
		SetFailState("Failed to enable post detour for CTFPlayer::IsAllowedToTaunt");
		delete gamedata;
		return;
	}

	tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::ShouldStopTaunting");
	if(!tmp || !tmp.Enable(Hook_Pre, ShouldStopTaunting)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::ShouldStopTaunting");
		delete gamedata;
		return;
	}

	delete gamedata;
}

public void OnConfigsExecuted()
{
	tf_allow_sliding_taunt.BoolValue = true;
	tf_allow_taunt_switch.IntValue = 2;
	tf_allow_all_team_partner_taunt.BoolValue = true;
}

static MRESReturn IsAllowedToTaunt(int pThis, DHookReturn hReturn)
{
	tempgroundent = GetEntPropEnt(pThis, Prop_Send, "m_hGroundEntity");
	tempwaterlevel = GetEntProp(pThis, Prop_Send, "m_nWaterLevel");
	SetEntPropEnt(pThis, Prop_Send, "m_hGroundEntity", 0);
	SetEntProp(pThis, Prop_Send, "m_nWaterLevel", 0);
	return MRES_Ignored;
}

static MRESReturn IsAllowedToTaunt_post(int pThis, DHookReturn hReturn)
{
	SetEntPropEnt(pThis, Prop_Send, "m_hGroundEntity", tempgroundent);
	SetEntProp(pThis, Prop_Send, "m_nWaterLevel", tempwaterlevel);
	return MRES_Ignored;
}

static MRESReturn ShouldStopTaunting(int pThis, DHookReturn hReturn)
{
	hReturn.Value = false;
	return MRES_Supercede;
}
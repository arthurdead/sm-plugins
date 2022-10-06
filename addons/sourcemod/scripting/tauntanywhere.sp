#include <sourcemod>
#include <dhooks>
#include <tf2>
#include <tf2_stocks>

#define TAUNT_LONG 3

static ConVar tf_allow_sliding_taunt = null;
static ConVar tf_allow_taunt_switch = null;
static ConVar tf_allow_all_team_partner_taunt = null;

static int tempgroundent;
static int tempwaterlevel;

static int m_flNextAllowTauntRemapInputTime_offset = -1;

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

	m_flNextAllowTauntRemapInputTime_offset = FindSendPropInfo("CTFPlayer", "m_iSpawnCounter");
	m_flNextAllowTauntRemapInputTime_offset -= gamedata.GetOffset("CTFPlayer::m_flNextAllowTauntRemapInputTime");

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

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(TF2_IsPlayerInCondition(client, TFCond_Taunting)) {
		int m_iTauntIndex = GetEntProp(client, Prop_Send, "m_iTauntIndex");
		if(m_iTauntIndex == TAUNT_LONG) {
			int m_iTauntItemDefIndex = GetEntProp(client, Prop_Send, "m_iTauntItemDefIndex");
			if(m_iTauntItemDefIndex == 1196 ||
				m_iTauntItemDefIndex == 31291) {
				return Plugin_Continue;
			}
			if(TF2_IsPlayerInCondition(client, TFCond_HalloweenKart)) {
				return Plugin_Continue;
			}
			SetEntDataFloat(client, m_flNextAllowTauntRemapInputTime_offset, GetGameTime() - 1.0);
		}
	}
	return Plugin_Continue;
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
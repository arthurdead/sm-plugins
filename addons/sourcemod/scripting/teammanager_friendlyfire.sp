#include <sourcemod>
#include <teammanager>
#include <dhooks>
#include <sdkhooks>

//TODO!!! pipes, sentries, diguises, taunt attacks

Handle dhCanCollideWithTeammates = null;
Handle dhGetCollideWithTeammatesDelay = null;
int m_bCanCollideWithTeammatesOffset = -1;

ConVar mp_friendlyfire = null;
ConVar mp_enemyfire = null;
ConVar tf_avoidteammates = null;
ConVar tf_avoidteammates_pushaway = null;

void FriendlyFireChanged(ConVar cvar, const char[] oldvalue, const char[] newvalue)
{
	int value = StringToInt(newvalue);

	if(value == 1) {
		tf_avoidteammates.BoolValue = false;
		tf_avoidteammates_pushaway.BoolValue = false;
	} else {
		tf_avoidteammates.BoolValue = true;
		tf_avoidteammates_pushaway.BoolValue = true;
	}
}

public void OnPluginStart()
{
	mp_friendlyfire = FindConVar("mp_friendlyfire");
	tf_avoidteammates = FindConVar("tf_avoidteammates");
	tf_avoidteammates_pushaway = FindConVar("tf_avoidteammates_pushaway");

	mp_friendlyfire.AddChangeHook(FriendlyFireChanged);

	mp_enemyfire = CreateConVar("mp_enemyfire", "1");

	if(mp_friendlyfire.BoolValue) {
		tf_avoidteammates.BoolValue = false;
		tf_avoidteammates_pushaway.BoolValue = false;
	} else {
		tf_avoidteammates.BoolValue = true;
		tf_avoidteammates_pushaway.BoolValue = true;
	}

	GameData gamedata = new GameData("teammanager");

	dhCanCollideWithTeammates = DHookCreateFromConf(gamedata, "CBaseProjectile::CanCollideWithTeammates");
	dhGetCollideWithTeammatesDelay = DHookCreateFromConf(gamedata, "CBaseProjectile::GetCollideWithTeammatesDelay");

	delete gamedata;

	m_bCanCollideWithTeammatesOffset = FindSendPropInfo("CBaseProjectile", "m_hOriginalLauncher");
	m_bCanCollideWithTeammatesOffset -= 4;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrContains(classname, "tf_projectile") != -1) {
		SDKHook(entity, SDKHook_SpawnPost, OnProjectileSpawnPost);
	}
}

void OnProjectileSpawnPost(int entity)
{
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hLauncher");
	if(owner != -1) {
		char classname[64];
		GetEntityClassname(owner, classname, sizeof(classname));
		if(!StrEqual(classname, "tf_point_weapon_mimic")) {
			owner = GetEntPropEnt(owner, Prop_Send, "m_hOwner");
		} else {
			owner = -1;
		}
	} else {
		owner = -1;
	}

	if(owner != -1) {
		if(mp_friendlyfire.BoolValue) {
			DHookEntity(dhCanCollideWithTeammates, false, entity, INVALID_FUNCTION, CanCollideWithTeammatesPre);
			DHookEntity(dhGetCollideWithTeammatesDelay, false, entity, INVALID_FUNCTION, GetCollideWithTeammatesDelayPre);
		}
	}
}

MRESReturn CanCollideWithTeammatesPre(int pThis, Handle hReturn)
{
	DHookSetReturn(hReturn, 1);
	return MRES_Supercede;
}

MRESReturn GetCollideWithTeammatesDelayPre(int pThis, Handle hReturn)
{
	DHookSetReturn(hReturn, 0.0);
	return MRES_Supercede;
}

public Action TeamManager_CanHeal(int entity, int other, HealSource source)
{
	if(source == HEAL_SUPPLYCABINET ||
		entity == other) {
		return Plugin_Continue;
	}

	int team1 = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	int team2 = GetEntProp(other, Prop_Send, "m_iTeamNum");

	if(team1 == team2) {
		if(mp_friendlyfire.BoolValue) {
			return Plugin_Handled;
		}
	} else {
		if(!mp_enemyfire.BoolValue) {
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

public Action TeamManager_CanGetJarated(int attacker, int victim)
{
	int team1 = GetEntProp(attacker, Prop_Send, "m_iTeamNum");
	int team2 = GetEntProp(victim, Prop_Send, "m_iTeamNum");

	if(team1 == team2) {
		if(mp_friendlyfire.BoolValue) {
			return Plugin_Handled;
		}
	} else {
		if(!mp_enemyfire.BoolValue) {
			return Plugin_Stop;
		}
	}

	return Plugin_Continue;
}

public Action TeamManager_CanDamage(int entity, int other, DamageSource source)
{
	if(entity == other) {
		return Plugin_Continue;
	}

	int team1 = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	int team2 = GetEntProp(other, Prop_Send, "m_iTeamNum");

	if(team1 == team2) {
		if(mp_friendlyfire.BoolValue) {
			return Plugin_Changed;
		}
	} else {
		if(!mp_enemyfire.BoolValue) {
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action TeamManager_InSameTeam(int entity, int other)
{
	if(entity == other) {
		return Plugin_Continue;
	}

	int team1 = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	int team2 = GetEntProp(other, Prop_Send, "m_iTeamNum");

	if(team1 == team2) {
		if(mp_friendlyfire.BoolValue) {
			return Plugin_Handled;
		}
	} else {
		if(!mp_enemyfire.BoolValue) {
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

public Action TeamManager_CanAirblast(int entity, int other)
{
	int team1 = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	int team2 = GetEntProp(other, Prop_Send, "m_iTeamNum");

	if(team1 == team2) {
		if(mp_friendlyfire.BoolValue) {
			return Plugin_Changed;
		}
	} else {
		if(!mp_enemyfire.BoolValue) {
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action TeamManager_CanBackstab(int entity, int other)
{
	int team1 = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	int team2 = GetEntProp(other, Prop_Send, "m_iTeamNum");

	if(team1 == team2) {
		if(mp_friendlyfire.BoolValue) {
			return Plugin_Changed;
		}
	} else {
		if(!mp_enemyfire.BoolValue) {
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action TF2_OnPlayerTeleport(int client, int teleporter, bool &result)
{
	int builder = GetEntPropEnt(teleporter, Prop_Send, "m_hBuilder");

	if(client == builder) {
		return Plugin_Continue;
	}

	int team1 = GetEntProp(client, Prop_Send, "m_iTeamNum");
	int team2 = GetEntProp(teleporter, Prop_Send, "m_iTeamNum");

	if(team1 == team2) {
		if(mp_friendlyfire.BoolValue) {
			result = false;
			return Plugin_Changed;
		}
	} else {
		if(!mp_enemyfire.BoolValue) {
			result = true;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

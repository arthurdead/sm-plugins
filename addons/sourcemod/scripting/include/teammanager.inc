#if defined _teammanager_inc_
	#endinput
#endif
#define _teammanager_inc_

#include <sdktools_functions>

enum HealSource
{
	HEAL_MEDIGUN,
	HEAL_DISPENSER,
	HEAL_LUNCHBOX, //not implemented
	HEAL_SUPPLYCABINET, //not implemented
	HEAL_WRENCH,
	HEAL_PROJECTILE,
};

enum DamageSource
{
	DAMAGE_PLAYER,
	DAMAGE_PROJECTILE,
};

/*
unless otherwise specified

Plugin_Continue == ignore
Plugin_Changed == true
Plugin_Handled/Stop == false
*/

/*
HEAL_MEDIGUN, entity = weapon, other = entity
HEAL_DISPENSER, entity = building, other = entity
HEAL_WRENCH, entity = weapon, other = building
HEAL_PROJECTILE, entity = player, other = player
*/
forward Action TeamManager_CanHeal(int entity, int other, HealSource source);

/*
DAMAGE_PLAYER, attacker = entity, victim = player
DAMAGE_PROJECTILE, attacker = projectile, victim = player
*/
forward Action TeamManager_CanDamage(int attacker, int victim, DamageSource source);

//entity = player, other = building
forward Action TeamManager_CanPickupBuilding(int entity, int other);

forward Action TeamManager_InSameTeam(int entity, int other);

forward Action TeamManager_CanChangeTeam(int entity, int team);

forward Action TeamManager_CanChangeClass(int entity, int class);

forward Action TeamManager_CanAirblast(int weapon, int owner, int other);

//not implemented
forward Action TeamManager_CanPush(int weapon, int other);

forward Action TeamManager_CanBackstab(int weapon, int other);

/*
Plugin_Continue == ignore
Plugin_Changed == extinguish
Plugin_Handled == jarate
Plugin_Stop == nothing
*/
forward Action TeamManager_CanGetJarated(int attacker, int victim);

native int TeamManager_GetEntityTeam(int entity);

native void TeamManager_SetEntityTeam(int entity, int team, bool raw);

stock int GetTeamIndex(const char[] name)
{
	if(StrEqual(name, "red") ||
		StrEqual(name, "2")) {
		return 2;
	} else if(StrEqual(name, "blu") ||
				StrEqual(name, "blue") ||
				StrEqual(name, "3")) {
		return 3;
	} else if(StrEqual(name, "spectate") ||
				StrEqual(name, "spec") ||
				StrEqual(name, "spectator") ||
				StrEqual(name, "1")) {
		return 1;
	} else {
		int count = GetTeamCount();

		char team[32];
		for(int i = 0; i < count; i++) {
			GetTeamName(i, team, sizeof(team));

			if(StrEqual(name, team)) {
				return i;
			}
		}

		return -1;
	}
}

public SharedPlugin __pl_teammanager =
{
	name = "teammanager",
	file = "teammanager.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_teammanager_SetNTVOptional()
{
	MarkNativeAsOptional("TeamManager_GetEntityFakeTeam");
	MarkNativeAsOptional("TeamManager_GetEntityTeam");
	MarkNativeAsOptional("TeamManager_SetEntityFakeTeam");
	MarkNativeAsOptional("TeamManager_SetEntityTeam");
}
#endif
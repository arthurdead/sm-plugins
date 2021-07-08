#if defined _teammanager_inc_
	#endinput
#endif
#define _teammanager_inc_

enum HealSource
{
	HEAL_MEDIGUN,
	HEAL_DISPENSER,
	HEAL_LUNCHBOX, //not implemented
	HEAL_SUPPLYCABINET, //not implemented
	HEAL_WRENCH,
	HEAL_PROJECTILE,
	//HEAL_AIRBLAST, //not implemented
};

/*
Plugin_Continue == ignore
Plugin_Changed == true
Plugin_Handled/Stop == false
*/

//if source is dispenser,medigun,airblast entity will be the owner
//if source is wrench,projectile both entity and other will be owner
forward Action TeamManager_CanHeal(int entity, int other, HealSource source);
forward Action TeamManager_CanDamage(int entity, int other);
forward Action TeamManager_CanPickupBuilding(int entity, int other);
forward Action TeamManager_InSameTeam(int entity, int other);
forward Action TeamManager_CanChangeTeam(int entity, int team);
forward Action TeamManager_CanChangeClass(int entity, int class);
//forward Action TeamManager_CanAirblast(int entity, int other);
//forward Action TeamManager_CanBackstab(int entity, int other);

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
public __pl_teammanager_SetNTVOptional()
{
	MarkNativeAsOptional("TeamManager_GetEntityFakeTeam");
	MarkNativeAsOptional("TeamManager_GetEntityTeam");
	MarkNativeAsOptional("TeamManager_SetEntityFakeTeam");
	MarkNativeAsOptional("TeamManager_SetEntityTeam");
}
#endif
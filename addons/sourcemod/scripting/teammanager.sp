#include <sdktools>
#include <dhooks>
#include <tf2>
#include <tf2_stocks>
#include <teammanager>
#include <sdkhooks>

#undef REQUIRE_EXTENSIONS
#tryinclude <collisionhook>
#define REQUIRE_EXTENSIONS

#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

Handle hAddPlayer = null;
Handle hRemovePlayer = null;
#if defined _collisionhook_included
bool bCollisionHook = false;
#endif

#include "teammanager/stocks.inc"

GlobalForward fwCanHeal = null;
GlobalForward fwCanDamage = null;
GlobalForward fwInSameTeam = null;
GlobalForward fwCanPickupBuilding = null;
GlobalForward fwCanChangeTeam = null;
GlobalForward fwCanChangeClass = null;
GlobalForward fwCanBackstab = null;
GlobalForward fwCanAirblast = null;

#include "teammanager/AllowedToHealTarget.sp"
#include "teammanager/CouldHealTarget.sp"
#include "teammanager/Smack.sp"
#include "teammanager/InSameTeam.sp"
#include "teammanager/StrikeTarget.sp"
#include "teammanager/TryToPickupBuilding.sp"
#include "teammanager/FPlayerCanTakeDamage.sp"
#include "teammanager/PlayerRelationship.sp"
#include "teammanager/ShouldCollide.sp"
#include "teammanager/CanPerformBackstabAgainstTarget.sp"
#include "teammanager/JarExplode.sp"
#include "teammanager/DeflectProjectiles.sp"

bool g_bLateLoaded = false;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int length)
{
	fwCanHeal = new GlobalForward("TeamManager_CanHeal", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
	fwCanDamage = new GlobalForward("TeamManager_CanDamage", ET_Hook, Param_Cell, Param_Cell);
	fwInSameTeam = new GlobalForward("TeamManager_InSameTeam", ET_Hook, Param_Cell, Param_Cell);
	fwCanPickupBuilding = new GlobalForward("TeamManager_CanPickupBuilding", ET_Hook, Param_Cell, Param_Cell);
	fwCanChangeTeam = new GlobalForward("TeamManager_CanChangeTeam", ET_Hook, Param_Cell, Param_Cell);
	fwCanChangeClass = new GlobalForward("TeamManager_CanChangeClass", ET_Hook, Param_Cell, Param_Cell);
	fwCanBackstab = new GlobalForward("TeamManager_CanBackstab", ET_Hook, Param_Cell, Param_Cell);
	fwCanAirblast = new GlobalForward("TeamManager_CanAirblast", ET_Hook, Param_Cell, Param_Cell);

	CreateNative("TeamManager_GetEntityTeam", Native_TeamManager_GetEntityTeam);
	CreateNative("TeamManager_SetEntityTeam", Native_TeamManager_SetEntityTeam);

	RegPluginLibrary("teammanager");

#if defined _collisionhook_included
	if(LibraryExists("collisionhook")) {
		bCollisionHook = true;
	} else {
		if(GetExtensionFileStatus("collisionhook.ext") == 1) {
			bCollisionHook = true;
		}
	}
#endif

	g_bLateLoaded = late;

	return APLRes_Success;
}

public void OnLibraryAdded(const char[] name)
{
#if defined _collisionhook_included
	if(StrEqual(name, "collisionhook")) {
		bCollisionHook = true;
	}
#endif
}

public void OnLibraryRemoved(const char[] name)
{
#if defined _collisionhook_included
	if(StrEqual(name, "collisionhook")) {
		bCollisionHook = false;
	}
#endif
}

public void OnPluginStart()
{
	GameData gamedata = new GameData("teammanager");

	AllowedToHealTargetCreate(gamedata);
	InSameTeamCreate(gamedata);
	SmackCreate(gamedata);
	CouldHealTargetCreate(gamedata);
	StrikeTargetCreate(gamedata);
	TryToPickupBuildingCreate(gamedata);
	FPlayerCanTakeDamageCreate(gamedata);
	PlayerRelationshipCreate(gamedata);
	ShouldCollideCreate(gamedata);
	JarExplodeCreate(gamedata);
	CanPerformBackstabAgainstTargetCreate(gamedata);
	DeflectProjectilesCreate(gamedata);

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CTeam::AddPlayer");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	hAddPlayer = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CTeam::RemovePlayer");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	hRemovePlayer = EndPrepSDKCall();

	delete gamedata;

	AddCommandListener(ConCommand_JoinTeam, "changeteam");
	AddCommandListener(ConCommand_JoinTeam, "jointeam");
	AddCommandListener(ConCommand_JoinTeam, "jointeam_nomenus");
	AddCommandListener(ConCommand_JoinTeam, "join_team");

	AddCommandListener(ConCommand_JoinClass, "changeclass");
	AddCommandListener(ConCommand_JoinClass, "joinclass");
	AddCommandListener(ConCommand_JoinClass, "join_class");

	HookEvent("player_death", Event_Death, EventHookMode_Post);

	if(g_bLateLoaded) {
		for(int i = 1; i <= MaxClients; ++i) {
			if(IsClientInGame(i)) {
				OnClientPutInServer(i);
			}
		}

		int entity = -1;
		char classname[64];
		while((entity = FindEntityByClassname(entity, "*")) != -1) {
			GetEntityClassname(entity, classname, sizeof(classname));
			OnEntityCreated(entity, classname);
		}
	}
}

public void OnPluginEnd()
{
	for(int i = 1; i < MaxClients; i++) {
		if(IsClientInGame(i)) {
			OnClientDisconnect(i);
		}
	}
}

int Native_TeamManager_GetEntityTeam(Handle plugin, int params)
{
	int entity = GetNativeCell(1);
	return GetEntityTeam(entity);
}

int Native_TeamManager_SetEntityTeam(Handle plugin, int params)
{
	int entity = GetNativeCell(1);
	int team = GetNativeCell(2);
	bool raw = GetNativeCell(3);

	SetEntityTeam(entity, team, raw);

	return 1;
}

public void OnClientPutInServer(int client)
{
	
}

Action ConCommand_JoinTeam(int client, const char[] command, int args)
{
	char arg[32];
	if(args >= 1) {
		GetCmdArg(1, arg, sizeof(arg));
	}

	Call_StartForward(fwCanChangeTeam);
	Call_PushCell(client);
	Call_PushCell(GetTeamIndex(arg));

	Action result = Plugin_Continue;
	Call_Finish(result);

	if(result == Plugin_Changed) {
		result = Plugin_Continue;
	}

	return result;
}

Action ConCommand_JoinClass(int client, const char[] command, int args)
{
	char arg[32];
	if(args >= 1) {
		GetCmdArg(1, arg, sizeof(arg));
	}

	Call_StartForward(fwCanChangeClass);
	Call_PushCell(client);
	Call_PushCell(TF2_GetClass(arg));

	Action result = Plugin_Continue;
	Call_Finish(result);

	if(result == Plugin_Changed) {
		result = Plugin_Continue;
	}

	return result;
}

public void OnMapStart()
{
#if defined DEBUG
	Precache();
#endif

	FPlayerCanTakeDamageMapStart();
	PlayerRelationshipMapStart();
}

public void OnEntityCreated(int entity, const char[] classname)
{
	ShouldCollideEntityCreated(entity, classname);
	JarExplodeEntityCreated(entity, classname);
	CanPerformBackstabAgainstTargetEntityCreated(entity, classname);
	DeflectProjectilesEntityCreated(entity, classname);
}

public void OnEntityDestroyed(int entity)
{
	if(entity == -1) {
		return;
	}

	TryToPickupBuildingDestroyed(entity);
}

Action Event_Death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int flags = event.GetInt("death_flags");

	TryToPickupBuildingDisconnect(client);

	return Plugin_Continue;
}

public void OnClientDisconnect(int client)
{
	TryToPickupBuildingDisconnect(client);
}

#include <sdktools>
#include <dhooks>
#include <tf2>
#include <tf2_stocks>
#include <teammanager>
#include <sdkhooks>
#include <bit>
#include <rulestools>
#include <tf2utils>

#undef REQUIRE_EXTENSIONS
#tryinclude <collisionhook>
#define REQUIRE_EXTENSIONS

#pragma semicolon 1
#pragma newdecls required

//#define DEBUG

#define HALLOWEEN_SCENARIO_LAKESIDE 3
#define HALLOWEEN_SCENARIO_HIGHTOWER 4

Handle hAddPlayer = null;
Handle hRemovePlayer = null;
Handle hTeamAddObject = null;
Handle hTeamRemoveObject = null;
Handle hTeamMgr = null;
Handle hCreateTeam = null;
Handle hChangeTeam = null;

#if defined _collisionhook_included
bool bCollisionHook = false;
#endif

static int CTFTeam_m_TeamColor_offset = -1;
bool truce_is_active;
bool ignore_team_override;

#include "teammanager/stocks.inc"

GlobalForward fwCanHeal = null;
GlobalForward fwCanDamage = null;
GlobalForward fwInSameTeam = null;
GlobalForward fwCanPickupBuilding = null;
GlobalForward fwCanChangeTeam = null;
GlobalForward fwCanChangeClass = null;
GlobalForward fwCanBackstab = null;
GlobalForward fwCanAirblast = null;
GlobalForward fwCanGetJarated = null;
GlobalForward fwCreateTeams = null;
GlobalForward fwFindTeams = null;
GlobalForward fwGetTeamAssignmentOverride = null;

Handle dhGetTeamAssignmentOverride = null;

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
#include "teammanager/Explode.sp"
#include "teammanager/DeflectProjectiles.sp"

bool g_bLateLoaded = false;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int length)
{
	fwCanHeal = new GlobalForward("TeamManager_CanHeal", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
	fwCanDamage = new GlobalForward("TeamManager_CanDamage", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
	fwInSameTeam = new GlobalForward("TeamManager_InSameTeam", ET_Hook, Param_Cell, Param_Cell);
	fwCanPickupBuilding = new GlobalForward("TeamManager_CanPickupBuilding", ET_Hook, Param_Cell, Param_Cell);
	fwCanChangeTeam = new GlobalForward("TeamManager_CanChangeTeam", ET_Hook, Param_Cell, Param_Cell);
	fwCanChangeClass = new GlobalForward("TeamManager_CanChangeClass", ET_Hook, Param_Cell, Param_Cell);
	fwCanBackstab = new GlobalForward("TeamManager_CanBackstab", ET_Hook, Param_Cell, Param_Cell);
	fwCanAirblast = new GlobalForward("TeamManager_CanAirblast", ET_Hook, Param_Cell, Param_Cell, Param_Cell);
	fwCanGetJarated = new GlobalForward("TeamManager_CanGetJarated", ET_Hook, Param_Cell, Param_Cell);
	fwCreateTeams = new GlobalForward("TeamManager_CreateTeams", ET_Ignore);
	fwFindTeams = new GlobalForward("TeamManager_FindTeams", ET_Ignore);
	fwGetTeamAssignmentOverride = new GlobalForward("TeamManager_GetTeamAssignmentOverride", ET_Hook, Param_Cell, Param_CellByRef);

	CreateNative("TeamManager_GetEntityTeam", Native_TeamManager_GetEntityTeam);
	CreateNative("TeamManager_SetEntityTeam", Native_TeamManager_SetEntityTeam);

	CreateNative("TeamManager_CreateTeam", Native_TeamManager_CreateTeam);
	CreateNative("TeamManager_RemoveTeam", Native_TeamManager_RemoveTeam);
	CreateNative("TeamManager_FindTeam", Native_TeamManager_FindTeam);
	CreateNative("TeamManager_AreTeamsEnemies", Native_TeamManager_AreTeamsEnemies);
	CreateNative("TeamManager_AreTeamsFriends", Native_TeamManager_AreTeamsFriends);

	CreateNative("TeamManager_IsTruceActive", Native_TeamManager_IsTruceActive);

	RegPluginLibrary("teammanager");

	g_bLateLoaded = late;

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
#if defined _collisionhook_included
	bCollisionHook = LibraryExists("collisionhook");
#endif
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
	ExplodeCreate(gamedata);
	CanPerformBackstabAgainstTargetCreate(gamedata);
	DeflectProjectilesCreate(gamedata);

	dhGetTeamAssignmentOverride = DHookCreateFromConf(gamedata, "CTFGameRules::GetTeamAssignmentOverride");
	DHookEnableDetour(dhGetTeamAssignmentOverride, false, GetTeamAssignmentOverride);

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CTeam::AddPlayer");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	hAddPlayer = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CTeam::RemovePlayer");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	hRemovePlayer = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFTeam::AddObject");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	hTeamAddObject = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFTeam::RemoveObject");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	hTeamRemoveObject = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFTeamManager::Create");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hCreateTeam = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "TFTeamMgr");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	hTeamMgr = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CBaseEntity::ChangeTeam");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	hChangeTeam = EndPrepSDKCall();

	delete gamedata;

	AddCommandListener(ConCommand_JoinTeam, "changeteam");
	AddCommandListener(ConCommand_JoinTeam, "jointeam");
	AddCommandListener(ConCommand_JoinTeam, "jointeam_nomenus");
	AddCommandListener(ConCommand_JoinTeam, "join_team");

	AddCommandListener(ConCommand_JoinClass, "changeclass");
	AddCommandListener(ConCommand_JoinClass, "joinclass");
	AddCommandListener(ConCommand_JoinClass, "join_class");

	HookEvent("player_death", Event_Death, EventHookMode_Post);

	CTFTeam_m_TeamColor_offset = FindSendPropInfo("CTeam", "m_iTeamNum");
	CTFTeam_m_TeamColor_offset += 4;

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

	RegAdminCmd("sm_dumpteams", sm_dumpteams, ADMFLAG_ROOT);
	RegAdminCmd("sm_setmyteam", sm_setmyteam, ADMFLAG_ROOT);
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

MRESReturn GetTeamAssignmentOverride(int pThis, Handle hReturn, Handle hParams)
{
	if(ignore_team_override) {
		int team = DHookGetParam(hParams, 2);
		DHookSetReturn(hReturn, team);
		return MRES_Supercede;
	}

	if(fwGetTeamAssignmentOverride.FunctionCount > 0) {
		Call_StartForward(fwGetTeamAssignmentOverride);
		int client = DHookGetParam(hParams, 1);
		int team = DHookGetParam(hParams, 2);
		Call_PushCell(client);
		Call_PushCellRef(team);
		Action res = Plugin_Continue;
		Call_Finish(res);

		if(res == Plugin_Continue) {
			return MRES_Ignored;
		} else if(res == Plugin_Changed) {
			DHookSetReturn(hReturn, team);
			return MRES_Supercede;
		}
	}

	return MRES_Ignored;
}

int Native_TeamManager_SetEntityTeam(Handle plugin, int params)
{
	int entity = GetNativeCell(1);
	int team = GetNativeCell(2);
	bool raw = GetNativeCell(3);

	SetEntityTeam(entity, team, raw);

	return 1;
}

static bool creating_internal_teams;
static bool created_internal_teams;

int Native_TeamManager_CreateTeam(Handle plugin, int params)
{
	int len;
	GetNativeStringLength(1, len);
	char[] name = new char[++len];
	GetNativeString(1, name, len);

	char temp_name[MAX_TEAM_NAME_LENGTH];

	int color[4];
	GetNativeArray(2, color, 4);

	int color32 = pack_4_ints(color[0], color[1], color[2], color[3]);

	int entity = -1;
	while((entity = FindEntityByClassname(entity, "tf_team")) != -1) {
		GetEntPropString(entity, Prop_Send, "m_szTeamname", temp_name, MAX_TEAM_NAME_LENGTH);

		if(StrEqual(name, temp_name)) {
			SetEntData(entity, CTFTeam_m_TeamColor_offset, color32, 4, false);

			return GetEntProp(entity, Prop_Send, "m_iTeamNum");
		}
	}

	int team = SDKCall(hCreateTeam, SDKCall(hTeamMgr), name, color32);

	if(!created_internal_teams && !creating_internal_teams) {
		if(team <= TF_TEAM_HALLOWEEN) {
			return ThrowNativeError(SP_ERROR_NATIVE, "internal game teams have not been created yet");
		}
	}

	return team;
}

int Native_TeamManager_RemoveTeam(Handle plugin, int params)
{
	int len;
	GetNativeStringLength(1, len);
	char[] name = new char[++len];
	GetNativeString(1, name, len);

	char temp_name[MAX_TEAM_NAME_LENGTH];

	int entity = -1;
	while((entity = FindEntityByClassname(entity, "tf_team")) != -1) {
		GetEntPropString(entity, Prop_Send, "m_szTeamname", temp_name, MAX_TEAM_NAME_LENGTH);

		if(StrEqual(name, temp_name)) {
			int team = GetEntProp(entity, Prop_Send, "m_iTeamNum");

			FormatEx(temp_name, MAX_TEAM_NAME_LENGTH, "__deleted_team_%i__", team);

			SetEntData(entity, CTFTeam_m_TeamColor_offset, 0, 4, false);
			SetEntPropString(entity, Prop_Send, "m_szTeamname", temp_name);
			break;
		}
	}

	return 0;
}

int Native_TeamManager_FindTeam(Handle plugin, int params)
{
	int len;
	GetNativeStringLength(1, len);
	char[] name = new char[++len];
	GetNativeString(1, name, len);

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

		char temp_name[MAX_TEAM_NAME_LENGTH];
		for(int i = 0; i < count; i++) {
			GetTeamName(i, temp_name, MAX_TEAM_NAME_LENGTH);

			if(StrEqual(name, temp_name)) {
				return i;
			}
		}
	}

	return -1;
}

int Native_TeamManager_AreTeamsEnemies(Handle plugin, int params)
{
	int team1 = GetNativeCell(1);
	int team2 = GetNativeCell(2);

	if(truce_is_active) {
		return false;
	}

	if(IsMannVsMachineMode()) {
		if((team1 == 3 || team1 == 4) &&
			(team2 == 3 || team2 == 4)) {
			return false;
		}
	}

	return (team1 != team2);
}

int Native_TeamManager_AreTeamsFriends(Handle plugin, int params)
{
	int team1 = GetNativeCell(1);
	int team2 = GetNativeCell(2);

	if(truce_is_active) {
		return true;
	}

	if(IsMannVsMachineMode()) {
		if((team1 == 3 || team1 == 4) &&
			(team2 == 3 || team2 == 4)) {
			return true;
		}
	}

	return (team1 == team2);
}

int Native_TeamManager_IsTruceActive(Handle plugin, int params)
{
	return truce_is_active;
}

public void OnClientPutInServer(int client)
{
	
}

Action ConCommand_JoinTeam(int client, const char[] command, int args)
{
	if(fwCanChangeTeam.FunctionCount == 0) {
		return Plugin_Continue;
	}

	char arg[32];
	if(args >= 1) {
		GetCmdArg(1, arg, sizeof(arg));
	}

	int team = TeamManager_FindTeam(arg);
	if(team == -1 || team > 3) {
		team = 2;
	}

	Call_StartForward(fwCanChangeTeam);
	Call_PushCell(client);
	Call_PushCell(team);

	Action result = Plugin_Continue;
	Call_Finish(result);

	if(result == Plugin_Changed) {
		result = Plugin_Continue;
	}

	return result;
}

Action ConCommand_JoinClass(int client, const char[] command, int args)
{
	if(fwCanChangeClass.FunctionCount == 0) {
		return Plugin_Continue;
	}

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

static Action sm_dumpteams(int client, int args)
{
	char temp_name[MAX_TEAM_NAME_LENGTH];

	int entity = -1;
	while((entity = FindEntityByClassname(entity, "tf_team")) != -1) {
		GetEntPropString(entity, Prop_Send, "m_szTeamname", temp_name, MAX_TEAM_NAME_LENGTH);

		int team = GetEntProp(entity, Prop_Send, "m_iTeamNum");

		int color32 = GetEntData(entity, CTFTeam_m_TeamColor_offset, 4);

		int r; int g; int b; int a;
		unpack_4_ints(color32, r, g, b, a);

		PrintToServer("%i - %i - %s - [%i, %i, %i, %i]", entity, team, temp_name, r, g, b, a);
	}

	return Plugin_Handled;
}

static Action sm_setmyteam(int client, int args)
{
	int team = GetCmdArgInt(1);

	SetEntityTeam(client, team, false);

	return Plugin_Handled;
}

static void ouput_truce_start(const char[] output, int caller, int activator, float delay)
{
	truce_is_active = true;
}

static void ouput_truce_end(const char[] output, int caller, int activator, float delay)
{
	truce_is_active = false;
}

public void OnMapStart()
{
#if defined DEBUG
	Precache();
#endif

	creating_internal_teams = true;

	if(IsMannVsMachineMode()) {
		int unused_team = TeamManager_CreateTeam("Giant Robots", {0, 0, 255, 0});
		if(unused_team != TF_TEAM_PVE_INVADERS_GIANTS) {
			LogError("expected unused team to be %i but got %i instead", TF_TEAM_PVE_INVADERS_GIANTS, unused_team);
		}
	} else {
		int unused_team = TeamManager_CreateTeam("__unused_team__", {0, 0, 0, 0});
		if(unused_team != TF_TEAM_COUNT) {
			LogError("expected unused team to be %i but got %i instead", TF_TEAM_COUNT, unused_team);
		}
	}

	int halloween_color[4];
	halloween_color[3] = 0;

	int halloween_scenario = GameRules_GetProp("m_halloweenScenario");
	if(halloween_scenario == HALLOWEEN_SCENARIO_LAKESIDE ||
		halloween_scenario == HALLOWEEN_SCENARIO_HIGHTOWER) {
		halloween_color[0] = 112;
		halloween_color[1] = 176;
		halloween_color[2] = 74;
	} else {
		halloween_color[0] = 134;
		halloween_color[1] = 80;
		halloween_color[2] = 172;
	}

	int halloween_team = TeamManager_CreateTeam("Halloween", halloween_color);
	if(halloween_team != TF_TEAM_HALLOWEEN) {
		LogError("expected halloween team to be %i but got %i instead", TF_TEAM_HALLOWEEN, halloween_team);
	}

	creating_internal_teams = false;
	created_internal_teams = true;

	if(fwCreateTeams.FunctionCount > 0) {
		Call_StartForward(fwCreateTeams);
		Call_Finish();
	}

	if(fwFindTeams.FunctionCount > 0) {
		Call_StartForward(fwFindTeams);
		Call_Finish();
	}

	int gamerules = FindEntityByClassname(-1, "tf_gamerules");

	HookSingleEntityOutput(gamerules, "OnTruceStart", ouput_truce_start);
	HookSingleEntityOutput(gamerules, "OnTruceEnd", ouput_truce_end);

	FPlayerCanTakeDamageMapStart();
	PlayerRelationshipMapStart();
}

public void OnMapEnd()
{
	created_internal_teams = false;
}

public void OnEntityCreated(int entity, const char[] classname)
{
#if defined DEBUG && 0
	PrintToServer("%s", classname);
#endif

	ShouldCollideEntityCreated(entity);

	int len = strlen(classname);

	if(len > 14 && classname[2] == '_' && classname[3] == 'p' && classname[13] == '_') {
		switch(classname[14]) {
			case 'j','c': {
				JarExplodeEntityCreated(entity);
			}
			case 's': {
				if(classname[15] == 'p') {
					JarExplodeEntityCreated(entity);
				}
			}
			case 'r','f','a','h','g': {
				ExplodeEntityCreated(entity);
			}
			case 'e': {
				switch(classname[21]) {
					case 'b': {
						ExplodeEntityCreated(entity);
					}
				}
			}
		}
	} else if(len > 9 && classname[2] == '_' && classname[3] == 'w' && classname[9] == '_') {
		switch(classname[10]) {
			case 'k': {
				if(classname[11] == 'n') {
					CanPerformBackstabAgainstTargetEntityCreated(entity);
				}
			}
			case 'f': {
				if(classname[13] == 'm') {
					DeflectProjectilesEntityCreated(entity);
				}
			}
		}
	}
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

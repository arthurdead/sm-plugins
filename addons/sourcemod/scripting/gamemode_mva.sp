#include <sourcemod>
#include <tf_econ_data>
#include <tf2items>
#include <teammanager>
#include <popspawner>
#include <proxysend>
#include <rulestools>
#include <tf2utils>
#include <playermodel2>
#include <clsobj_hack>
#include <vgui_watcher>

#define TF2_MAXPLAYERS 33

#define LOADOUT_POSITION_MELEE 2

#define DAMAGE_YES 2
#define DAMAGE_EVENTS_ONLY 1

static int TF_TEAM_PVE_DEFENDERS_DEAD = -1;

static int classes_melee_weapons[10] = {65535, ...};

static Handle dummy_item_view;

static TFPlayerClassData TF_CLASS_SKELETON;

static TFClassType player_alive_class[TF2_MAXPLAYERS+1] = {TFClass_Unknown, ...};

static ConVar tf_gamemode_mvm;
static ConVar tf_mvm_preallocate_bots;
static ConVar mp_tournament;

static int info_populator = INVALID_ENT_REFERENCE;

static bool game_ended;

static bool late_loaded;

static ConVar mp_tournament_blueteamname;
static ConVar mp_tournament_redteamname;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int length)
{
	late_loaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	tf_gamemode_mvm = FindConVar("tf_gamemode_mvm");

	tf_mvm_preallocate_bots = FindConVar("tf_mvm_preallocate_bots");
	tf_mvm_preallocate_bots.BoolValue = false;

	dummy_item_view = TF2Items_CreateItem(OVERRIDE_ALL);
	TF2Items_SetClassname(dummy_item_view, "");
	TF2Items_SetItemIndex(dummy_item_view, 65535);
	TF2Items_SetQuality(dummy_item_view, 0);
	TF2Items_SetLevel(dummy_item_view, 0);
	TF2Items_SetNumAttributes(dummy_item_view, 0);

	HookEvent("player_death", player_death);
	HookEvent("player_spawn", player_spawn);
	HookEvent("post_inventory_application", post_inventory_application);

	HookEvent("teamplay_round_start", teamplay_round_start);

	HookEvent("mvm_wave_complete", mvm_wave_complete);

	mp_tournament = FindConVar("mp_tournament");

	mp_tournament_blueteamname = FindConVar("mp_tournament_blueteamname");
	mp_tournament_blueteamname.Flags &= ~FCVAR_NOTIFY;

	mp_tournament_redteamname = FindConVar("mp_tournament_redteamname");
	mp_tournament_redteamname.Flags &= ~FCVAR_NOTIFY;
}

static bool filter_class_base_melee(int itemdef, TFClassType class)
{
	if(!TF2Econ_IsItemInBaseSet(itemdef)) {
		return false;
	}

	if(TF2Econ_GetItemLoadoutSlot(itemdef, class) != LOADOUT_POSITION_MELEE) {
		return false;
	}

	classes_melee_weapons[class] = itemdef;
	return false;
}

public void OnAllPluginsLoaded()
{
	for(int i = 1; i <= 9; ++i) {
		delete TF2Econ_GetItemList(filter_class_base_melee, i);
	}

	TF_CLASS_SKELETON = TFPlayerClassData.Find("Skeleton");
}

static void mvm_wave_complete(Event event, const char[] name, bool dontBroadcast)
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			IsClientSourceTV(i) ||
			IsClientReplay(i)) {
			continue;
		}

		int team = GetClientTeam(i);
		if(team != TF_TEAM_PVE_DEFENDERS_DEAD &&
			team != TF_TEAM_PVE_DEFENDERS) {
			continue;
		}

		if(team == TF_TEAM_PVE_DEFENDERS_DEAD) {
			TeamManager_SetEntityTeam(i, TF_TEAM_PVE_DEFENDERS, false);
			setup_alive_player(i);
			TF2_RespawnPlayer(i);
		} else if(team == TF_TEAM_PVE_DEFENDERS && !IsPlayerAlive(i)) {
			TF2_RespawnPlayer(i);
		}
	}
}

public Action should_cleanup_entity(int entity, bool &should)
{
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));

	if(StrEqual(classname, "tf_logic_mann_vs_machine")) {
		should = true;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public Action should_create_entity(const char[] classname, bool &should)
{
	if(StrEqual(classname, "tf_logic_mann_vs_machine")) {
		should = false;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public Action TeamManager_CanChangeTeam(int entity, int team)
{
	if(GetClientTeam(entity) == TF_TEAM_PVE_DEFENDERS_DEAD) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action TeamManager_CanChangeClass(int entity, int team)
{
	if(GetClientTeam(entity) == TF_TEAM_PVE_DEFENDERS_DEAD) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void OnClientDisconnect(int client)
{
	player_alive_class[client] = TFClass_Unknown;
}

static Action proxysend_mvm(int entity, const char[] prop, bool &value, int element, int client)
{
#if 0
	if(player_current_vgui(client) == player_vgui_class) {
		value = false;
		return Plugin_Changed;
	}
#endif

	value = true;
	return Plugin_Changed;
}

static Action proxysend_roundstate(int entity, const char[] prop, RoundState &value, int element, int client)
{
	if(game_ended) {
		value = GR_STATE_GAME_OVER;
		return Plugin_Changed;
	}

	if(value != GR_STATE_BETWEEN_RNDS &&
		value != GR_STATE_TEAM_WIN &&
		value != GR_STATE_GAME_OVER) {
		value = GR_STATE_BETWEEN_RNDS;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public void OnConfigsExecuted()
{
	tf_gamemode_mvm.BoolValue = false;

	FindConVar("tf_populator_debug").BoolValue = false;
}

static void teamplay_round_start(Event event, const char[] name, bool dontBroadcast)
{
	game_ended = false;

	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			IsClientSourceTV(i) ||
			IsClientReplay(i)) {
			continue;
		}

		int team = GetClientTeam(i);
		if(team != TF_TEAM_PVE_DEFENDERS_DEAD) {
			continue;
		}

		TeamManager_SetEntityTeam(i, TF_TEAM_PVE_DEFENDERS, false);
		setup_alive_player(i);
		TF2_RespawnPlayer(i);
	}

	init_pop();
}

public Action gamemode_uses_upgrades(bool &uses)
{
	uses = true;
	return Plugin_Changed;
}

public Action TeamManager_GetTeamAssignmentOverride(int entity, int &team)
{
	if(team == TF_TEAM_PVE_INVADERS || team == TF_TEAM_PVE_INVADERS_GIANTS) {
		team = TF_TEAM_PVE_DEFENDERS;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

#define WINPANEL_HOLD_TIME 14.0

static Action timer_endgame(Handle timer, any data)
{
	int populator = EntRefToEntIndex(info_populator);
	if(populator != -1) {
		RemoveEntity(populator);
	}

	mp_tournament.BoolValue = false;

	EndGame();

	return Plugin_Continue;
}

static Action timer_sendwinpanel(Handle timer, any data)
{
	SetWinningTeam(TF_TEAM_PVE_INVADERS, WINREASON_OPPONENTS_DEAD, true, false, WINPANEL_ARENA);

	CreateTimer(WINPANEL_HOLD_TIME, timer_endgame, 0, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}

public void OnGameFrame()
{
	if(!GameRules_GetProp("m_bInWaitingForPlayers") && GameRules_GetRoundState() == GR_STATE_RND_RUNNING) {
		int num_connected = 0;
		int num_alive = 0;
		for(int i = 1; i <= MaxClients; ++i) {
			if(!IsClientInGame(i) ||
				IsClientSourceTV(i) ||
				IsClientReplay(i)) {
				continue;
			}

			int team = GetClientTeam(i);
			if(team != TF_TEAM_PVE_DEFENDERS &&
				team != TF_TEAM_PVE_DEFENDERS_DEAD) {
				continue;
			}

			++num_connected;

			if(team == TF_TEAM_PVE_DEFENDERS) {
				if(IsPlayerAlive(i)) {
					++num_alive;
				}
			}
		}
		if(num_connected > 0 && num_alive == 0) {
			game_ended = true;

			//mp_tournament_blueteamname.SetString("?????");
			//mp_tournament_redteamname.SetString("MANNCO");

			float networktime = 0.3;

			BfWrite bitbuf = view_as<BfWrite>(StartMessageAll("MVMServerKickTimeUpdate"));
			bitbuf.WriteByte(RoundToFloor(networktime + WINPANEL_HOLD_TIME));
			EndMessage();

			CreateTimer(networktime, timer_sendwinpanel, 0, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public void OnMapStart()
{
	int gamerules = FindEntityByClassname(-1, "tf_gamerules");

	int logic = FindEntityByClassname(-1, "tf_logic_mann_vs_machine");
	if(logic != -1) {
		RemoveEntity(logic);
	}

	int populator = FindEntityByClassname(-1, "info_populator");
	if(populator == -1) {
		populator = CreateEntityByName("info_populator");
	}

	info_populator = EntIndexToEntRef(populator);

	set_pop_filename("mva.pop");

	GameRules_SetProp("m_bPlayingMannVsMachine", 1);

	proxysend_hook(gamerules, "m_bPlayingMannVsMachine", proxysend_mvm, true);
	proxysend_hook(gamerules, "m_iRoundState", proxysend_roundstate, false);

	GameRules_SetProp("m_nGameType", TF_GAMETYPE_UNDEFINED);
	SetHUDType(TF_HUDTYPE_UNDEFINED);
}

public void OnMapEnd()
{
	info_populator = INVALID_ENT_REFERENCE;

	game_ended = false;
}

public void TeamManager_CreateTeams()
{
	TF_TEAM_PVE_DEFENDERS_DEAD = TeamManager_CreateTeam("Defenders Dead", {255, 0, 0, 0});
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "teammanager")) {
		if(late_loaded) {
			TeamManager_CreateTeams();
		}
	}
}

static void setup_alive_player(int client)
{
	int flags = GetEntityFlags(client);
	flags &= ~FL_NOTARGET;
	SetEntityFlags(client, flags);
	SetEntProp(client, Prop_Data, "m_takedamage", DAMAGE_YES);
	TF2_RemoveCondition(client, TFCond_UberchargedOnTakeDamage);
	SetEntProp(client, Prop_Send, "m_nForceTauntCam", 0);
	SetEntPropFloat(client, Prop_Send, "m_flModelScale", 1.0);
	TFClassType class = player_alive_class[client];
	TF2_SetPlayerClass(client, class);
}

static void setup_dead_player(int client)
{
	TF2_SetPlayerClass(client, TF_CLASS_SKELETON.Index);
	int flags = GetEntityFlags(client);
	flags |= FL_NOTARGET;
	SetEntityFlags(client, flags);
	SetEntProp(client, Prop_Data, "m_takedamage", DAMAGE_EVENTS_ONLY);
	TF2_AddCondition(client, TFCond_UberchargedOnTakeDamage, TFCondDuration_Infinite);
	SetEntProp(client, Prop_Send, "m_nForceTauntCam", 1);
	SetEntPropFloat(client, Prop_Send, "m_flModelScale", 0.5);
}

static void player_death_frame(int client)
{
	client = GetClientOfUserId(client);
	if(client == 0) {
		return;
	}

	int team = GetClientTeam(client);

	if(team == TF_TEAM_PVE_DEFENDERS) {
		if(GameRules_GetRoundState() != GR_STATE_RND_RUNNING) {
			return;
		}

		player_alive_class[client] = TF2_GetPlayerClass(client);
		TeamManager_SetEntityTeam(client, TF_TEAM_PVE_DEFENDERS_DEAD, false);
		TF2_RespawnPlayer(client);
	}
}

static void player_death(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	if(client == 0) {
		return;
	}

	if(event.GetInt("death_flags") & TF_DEATHFLAG_DEADRINGER) {
		return;
	}

	int team = GetClientTeam(client);
	if(team != TF_TEAM_PVE_DEFENDERS &&
		team != TF_TEAM_PVE_DEFENDERS_DEAD) {
		return;
	}

	RequestFrame(player_death_frame, userid);
}

static void post_inventory_application_frame(int userid)
{
	int client = GetClientOfUserId(userid);
	if(client == 0) {
		return;
	}

	int team = GetClientTeam(client);
	if(team == TF_TEAM_PVE_DEFENDERS_DEAD) {
		TF2_RemoveAllWeapons(client);

		TF2Items_SetClassname(dummy_item_view, "tf_weapon_club");
		TF2Items_SetItemIndex(dummy_item_view, 3);

		int weapon = TF2Items_GiveNamedItem(client, dummy_item_view);
		EquipPlayerWeapon(client, weapon);
	} else {
		return;

		TF2_RemoveAllWeapons(client);

		TFClassType class = TF2_GetPlayerClass(client);
		int melee_itemdef = classes_melee_weapons[class];

		if(melee_itemdef != 65535) {
			char classname[64];
			TF2Econ_GetItemClassName(melee_itemdef, classname, sizeof(classname));

			TF2Items_SetClassname(dummy_item_view, classname);
			TF2Items_SetItemIndex(dummy_item_view, melee_itemdef);

			int weapon = TF2Items_GiveNamedItem(client, dummy_item_view);
			EquipPlayerWeapon(client, weapon);
		}
	}
}

static void player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	int team = GetClientTeam(client);
	TFClassType class = TF2_GetPlayerClass(client);
	if(class == TFClass_Unknown ||
		team < 2) {
		return;
	}

	if(team == TF_TEAM_PVE_DEFENDERS) {
		player_alive_class[client] = class;
	} else if(team == TF_TEAM_PVE_DEFENDERS_DEAD) {
		setup_dead_player(client);
	}
}

static void post_inventory_application(Event event, const char[] name, bool dontBroadcast)
{
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);

	int team = GetClientTeam(client);
	if(team != TF_TEAM_PVE_DEFENDERS &&
		team != TF_TEAM_PVE_DEFENDERS_DEAD) {
		return;
	}

	RequestFrame(post_inventory_application_frame, userid);
}

//TODO!!!!!! all the other callbacks
public Action TeamManager_InSameTeam(int entity, int other)
{
	int team1 = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	int team2 = GetEntProp(other, Prop_Send, "m_iTeamNum");

	if((team1 == TF_TEAM_PVE_DEFENDERS || team1 == TF_TEAM_PVE_DEFENDERS_DEAD) &&
		(team2 == TF_TEAM_PVE_DEFENDERS || team2 == TF_TEAM_PVE_DEFENDERS_DEAD)) {
		return Plugin_Changed;
	}

	return Plugin_Continue;
}
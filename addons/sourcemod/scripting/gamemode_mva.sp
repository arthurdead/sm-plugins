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
#include <cwx>

#define TF2_MAXPLAYERS 33

#define LOADOUT_POSITION_MELEE 2

#define DAMAGE_YES 2
#define DAMAGE_EVENTS_ONLY 1

static int TF_TEAM_PVE_DEFENDERS_DEAD = -1;

static int classes_melee_weapons[10] = {65535, ...};

static Handle dummy_item_view;

static ConVar sm_cwx_enable_menus;
static ConVar sm_cwx_enable_cookies;

static TFPlayerClassData TF_CLASS_SKELETON;

static float player_death_pos[TF2_MAXPLAYERS+1][3];
static TFClassType player_alive_class[TF2_MAXPLAYERS+1] = {TFClass_Unknown, ...};

static ConVar tf_gamemode_mvm;
static ConVar tf_mvm_preallocate_bots;
static ConVar mp_tournament;

static int info_populator = INVALID_ENT_REFERENCE;
static int tf_gamerules = INVALID_ENT_REFERENCE;
static int tf_logic_mann_vs_machine = INVALID_ENT_REFERENCE;

static int m_nLastEventFiredTime = -1;

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

	RegConsoleCmd("sm_mva", sm_mva);
}

static Action sm_mva(int client, int args)
{
	CWX_SetPlayerLoadoutItem(client, TF2_GetPlayerClass(client), "magic_sniper", LOADOUT_FLAG_ATTEMPT_REGEN);
	return Plugin_Handled;
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
	sm_cwx_enable_menus = FindConVar("sm_cwx_enable_menus");
	sm_cwx_enable_cookies = FindConVar("sm_cwx_enable_cookies");

	for(int i = 1; i <= 9; ++i) {
		delete TF2Econ_GetItemList(filter_class_base_melee, i);
	}

	TF_CLASS_SKELETON = TFPlayerClassData.Find("Skeleton");

	if(late_loaded) {
		CWX_ItemsLoaded();
	}
}

public void CWX_ItemsLoaded()
{
	
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
	} else if(StrEqual(classname, "prop_dynamic") ||
				StrEqual(classname, "prop_dynamic_override") ||
				StrEqual(classname, "dynamic_prop")) {
		char model[PLATFORM_MAX_PATH];
		GetEntPropString(entity, Prop_Data, "m_ModelName", model, PLATFORM_MAX_PATH);
		if(StrEqual(model, "models/props_mvm/robot_hologram.mdl") ||
			StrEqual(model, "models/bots/boss_bot/carrier_parts.mdl") ||
			StrEqual(model, "models/bots/boss_bot/static_boss_tank.mdl")) {
			should = true;
			return Plugin_Changed;
		}
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

	player_death_pos[client][0] = 0.0;
	player_death_pos[client][1] = 0.0;
	player_death_pos[client][2] = 0.0;
}

public void pop_entity_spawned(IPopulator populator, IPopulationSpawner spawner, SpawnLocation location, int entity)
{
	SetEntProp(entity, Prop_Send, "m_bGlowEnabled", 1);
}

static Action proxysend_mvm(int entity, const char[] prop, bool &value, int element, int client)
{
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

static Action proxysend_countdown(int entity, const char[] prop, float &value, int element, int client)
{
	value = -1.0;
	return Plugin_Changed;
}

public void OnConfigsExecuted()
{
	tf_gamemode_mvm.BoolValue = false;

	sm_cwx_enable_menus.BoolValue = false;
	sm_cwx_enable_cookies.BoolValue = false;

	FindConVar("tf_populator_debug").BoolValue = false;
}

public void OnPluginEnd()
{
	sm_cwx_enable_menus.BoolValue = true;
	sm_cwx_enable_cookies.BoolValue = true;
}

static void teamplay_round_start(Event event, const char[] name, bool dontBroadcast)
{
	game_ended = false;
	m_nLastEventFiredTime = -1;

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

	int logic = EntRefToEntIndex(tf_logic_mann_vs_machine);
	if(logic == -1) {
		init_pop();
	}
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

public void OnGameFrame()
{
	RoundState round = GameRules_GetRoundState();

	if(round == GR_STATE_BETWEEN_RNDS) {
		float m_flRestartRoundTime = GameRules_GetPropFloat("m_flRestartRoundTime");
		if(m_flRestartRoundTime != -1.0) {
			int time = RoundToCeil(m_flRestartRoundTime - GetGameTime());
			if(m_nLastEventFiredTime != time) {
				m_nLastEventFiredTime = time;

				int num_clients = 0;
				int clients[TF2_MAXPLAYERS];

				for(int i = 1; i <= MaxClients; ++i) {
					if(!IsClientInGame(i) ||
						IsClientReplay(i) ||
						IsClientSourceTV(i)) {
						continue;
					}

					int team = GetClientTeam(i);
					if(team != TF_TEAM_PVE_DEFENDERS &&
						team != TF_TEAM_PVE_DEFENDERS_DEAD) {
						continue;
					}

					clients[num_clients++] = i;
				}

				int max_wave = GetMannVsMachineMaxWaveCount();
				int mid_wave = (max_wave / 2);
				int curr_wave = GetMannVsMachineWaveCount();

				switch(time) {
					case 10: {
						if(curr_wave == max_wave) {
							EmitGameSound(clients, num_clients, "Announcer.MVM_Final_Wave_Start");
						} else if(curr_wave <= 1) {
							EmitGameSound(clients, num_clients, "Announcer.MVM_First_Wave_Start");
						} else {
							EmitGameSound(clients, num_clients, "Announcer.MVM_Wave_Start");
						}

						if(curr_wave == max_wave) {
							EmitSound(clients, num_clients, "music/mva/start_wave.mp3");
						} else if(curr_wave >= mid_wave) {
							EmitSound(clients, num_clients, "music/mva/start_wave.mp3");
						} else {
							EmitSound(clients, num_clients, "music/mva/start_wave.mp3");
						}
					}
					case 5: {
						EmitGameSound(clients, num_clients, "Announcer.RoundBegins5Seconds");
					}
					case 4: {
						EmitGameSound(clients, num_clients, "Announcer.RoundBegins4Seconds");
					}
					case 3: {
						EmitGameSound(clients, num_clients, "Announcer.RoundBegins3Seconds");
					}
					case 2: {
						EmitGameSound(clients, num_clients, "Announcer.RoundBegins2Seconds");
					}
					case 1: {
						EmitGameSound(clients, num_clients, "Announcer.RoundBegins1Seconds");
					}
				}
			}
		}
	}

	if(!GameRules_GetProp("m_bInWaitingForPlayers") && round == GR_STATE_RND_RUNNING) {
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

			BfWrite bitbuf = view_as<BfWrite>(StartMessageAll("MVMServerKickTimeUpdate"));
			bitbuf.WriteByte(RoundToFloor(WINPANEL_HOLD_TIME));
			EndMessage();

			SetWinningTeam(TF_TEAM_PVE_INVADERS, WINREASON_OPPONENTS_DEAD, true, false, WINPANEL_ARENA);

			CreateTimer(WINPANEL_HOLD_TIME, timer_endgame, 0, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

static void prop_spawn(int entity)
{
	char model[PLATFORM_MAX_PATH];
	GetEntPropString(entity, Prop_Data, "m_ModelName", model, PLATFORM_MAX_PATH);

	if(StrEqual(model, "models/props_mvm/robot_hologram.mdl") ||
		StrEqual(model, "models/bots/boss_bot/carrier_parts.mdl") ||
		StrEqual(model, "models/bots/boss_bot/static_boss_tank.mdl")) {
		RemoveEntity(entity);
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "prop_dynamic") ||
		StrEqual(classname, "prop_dynamic_override") ||
		StrEqual(classname, "dynamic_prop")) {
		SDKHook(entity, SDKHook_Spawn, prop_spawn);
	}
}

static void between_rounds(const char[] output, int caller, int activator, float delay)
{
	m_nLastEventFiredTime = -1;

	mp_tournament_blueteamname.SetString("Aliens");
	mp_tournament_redteamname.SetString("Mercs");
}

public void OnMapStart()
{
	PrecacheScriptSound("Announcer.RoundBegins1Seconds");
	PrecacheScriptSound("Announcer.RoundBegins2Seconds");
	PrecacheScriptSound("Announcer.RoundBegins3Seconds");
	PrecacheScriptSound("Announcer.RoundBegins4Seconds");
	PrecacheScriptSound("Announcer.RoundBegins5Seconds");

	PrecacheScriptSound("Announcer.MVM_Wave_Start");
	PrecacheScriptSound("Announcer.MVM_First_Wave_Start");
	PrecacheScriptSound("Announcer.MVM_Final_Wave_Start");

	PrecacheSound("music/mva/start_wave.mp3");

	int gamerules = FindEntityByClassname(-1, "tf_gamerules");
	tf_gamerules = EntIndexToEntRef(gamerules);

	int logic = FindEntityByClassname(-1, "tf_logic_mann_vs_machine");
	if(logic != -1) {
		tf_logic_mann_vs_machine = EntIndexToEntRef(logic);
	}

	HookSingleEntityOutput(gamerules, "OnStateEnterBetweenRounds", between_rounds);

	proxysend_hook(gamerules, "m_bPlayingMannVsMachine", proxysend_mvm, true);
	proxysend_hook(gamerules, "m_iRoundState", proxysend_roundstate, false);
	proxysend_hook(gamerules, "m_flRestartRoundTime", proxysend_countdown, false);

	GameRules_SetProp("m_nGameType", TF_GAMETYPE_UNDEFINED);
	SetHUDType(TF_HUDTYPE_UNDEFINED);

	int populator = FindEntityByClassname(-1, "info_populator");
	if(populator == -1) {
		populator = CreateEntityByName("info_populator");
	}

	info_populator = EntIndexToEntRef(populator);

	set_pop_filename("mva.pop");

	GameRules_SetProp("m_bPlayingMannVsMachine", 1);
}

public void OnMapEnd()
{
	info_populator = INVALID_ENT_REFERENCE;
	tf_gamerules = INVALID_ENT_REFERENCE;
	tf_logic_mann_vs_machine = INVALID_ENT_REFERENCE;

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

	GetClientAbsOrigin(client, player_death_pos[client]);

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

		TeleportEntity(client, player_death_pos[client]);
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
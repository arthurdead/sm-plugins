#include <sourcemod>
#include <sdktools>
#include <vtable>
#include <stocksoup/memory>
#include <dhooks>
#include <proxysend>
#include <vgui_watcher>
#include <rulestools>
#include <nextbot>
#include <popspawner>
#include <tf2>
#include <tf2_stocks>
#include <listen>
#include <bit>

#define DEBUG

#define TF2_MAXPLAYERS 33

#define TEAM_UNASSIGNED 0
#define TEAM_SPECTATOR 1
#define TF_TEAM_PVE_DEFENDERS 2
#define TF_TEAM_PVE_INVADERS 3
#define TF_TEAM_PVE_INVADERS_GIANTS 4
#define TF_TEAM_HALLOWEEN 5

static Handle CPopulationManager_SetPopulationFilename;
static Handle CPopulationManager_Initialize;

static Address g_pPopulationManager;

static int info_populator = INVALID_ENT_REFERENCE;
static int tf_logic_mann_vs_machine = INVALID_ENT_REFERENCE;
static int tf_gamerules = INVALID_ENT_REFERENCE;

static ConVar tf_gamemode_mvm;

static ConVar mp_tournament_blueteamname;
static ConVar mp_tournament_redteamname;

static ConVar npc_deathnotice_eventtime;

static ConVar mve_pop_file;

static bool game_ended;

static ArrayList last_killed_data;

static void mve_pop_file_changed(ConVar convar, const char[] oldValue, const char[] newValue)
{
	update_pop_path(newValue);
}

public void OnPluginStart()
{
	GameData gamedata = new GameData("gamemode_mve");

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CPopulationManager::SetPopulationFilename");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	CPopulationManager_SetPopulationFilename = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CPopulationManager::Initialize");
	CPopulationManager_Initialize = EndPrepSDKCall();

	DynamicDetour tmp_detour = DynamicDetour.FromConf(gamedata, "CPopulationManager::AllocateBots");
	tmp_detour.Enable(Hook_Pre, CPopulationManagerAllocateBots);

	g_pPopulationManager = gamedata.GetMemSig("g_pPopulationManager");

	delete gamedata;

	tf_gamemode_mvm = FindConVar("tf_gamemode_mvm");

	mp_tournament_blueteamname = FindConVar("mp_tournament_blueteamname");
	mp_tournament_blueteamname.Flags &= ~FCVAR_NOTIFY;

	mp_tournament_redteamname = FindConVar("mp_tournament_redteamname");
	mp_tournament_redteamname.Flags &= ~FCVAR_NOTIFY;

	npc_deathnotice_eventtime = FindConVar("npc_deathnotice_eventtime");

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}

	last_killed_data = new ArrayList(2);

	HookEvent("teamplay_round_start", teamplay_round_start);

	mve_pop_file = CreateConVar("mve_pop_file", "");
	mve_pop_file.AddChangeHook(mve_pop_file_changed);

	RegConsoleCmd("sm_mtest", sm_mtest);
}

static Action sm_mtest(int client, int args)
{
	PrecacheModel("models/impulse/riskofrain/human/containers/chest_small.mdl");

	int len = GetNavAreaVectorCount();
	for(int i = 0; i < 5; ++i) {
		CNavArea area = GetNavAreaFromVector(GetRandomInt(0, len-1));

		for(int j = 0; j < 3; ++j) {
			float pos[3];
			area.GetRandomPoint(pos);

			if(!IsSpaceToSpawnHere(pos)) {
				continue;
			}

			float ang[3];
			ang[1] = GetRandomFloat(0.0, 360.0);

			int entity = CreateEntityByName("prop_dynamic");
			DispatchKeyValue(entity, "model", "models/impulse/riskofrain/human/containers/chest_small.mdl");
			TeleportEntity(entity, pos, ang);
			DispatchSpawn(entity);

			int glow = CreateEntityByName("tf_glow");
			SetVariantString("!activator");
			AcceptEntityInput(glow, "SetParent", entity);
			SetEntProp(glow, Prop_Send, "m_glowColor", pack_4_ints(255, 255, 255, 255));
			SetEntProp(glow, Prop_Send, "m_iMode", 2);
			SetEntProp(glow, Prop_Send, "m_bDisabled", 0);
			SetEntPropEnt(glow, Prop_Send, "m_hTarget", entity);

			NDebugOverlay_Box(pos, VEC_HULL_MINS, VEC_HULL_MAXS, 255, 0, 0, 255, 10.0);

			break;
		}
	}

	return Plugin_Handled;
}

static MRESReturn CPopulationManagerAllocateBots(int pThis)
{
	return MRES_Supercede;
}

static void teamplay_round_start(Event event, const char[] name, bool dontBroadcast)
{
	game_ended = false;

#if 0
	char model[PLATFORM_MAX_PATH];
	int entity = -1;
	while((entity = FindEntityByClassname(entity, "prop_dynamic")) != -1) {
		GetEntPropString(entity, Prop_Data, "m_ModelName", model, PLATFORM_MAX_PATH);
		if(StrEqual(model, "models/props_mvm/robot_hologram.mdl")) {
			RemoveEntity(entity);
		}
	}
#endif

	int logic = EntRefToEntIndex(tf_logic_mann_vs_machine);
	if(logic == -1) {
		int populator = EntRefToEntIndex(info_populator);
		if(populator != -1) {
			SDKCall(CPopulationManager_Initialize, populator);
		} else {
			LogError("missing info_populator");
		}
	}
}

static void frame_currency_spawn(int entity)
{
	entity = EntRefToEntIndex(entity);
	if(entity == -1) {
		return;
	}

	SetEntityNextThink(entity, TIME_NEVER_THINK, "PowerupRemoveThink");

	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if(owner != -1) {
		int idx = last_killed_data.FindValue(EntIndexToEntRef(owner));
		if(idx != -1) {
			int attacker = GetClientOfUserId(last_killed_data.Get(idx, 1));
			if(attacker != 0) {
				float pos[3];
				GetClientAbsOrigin(attacker, pos);
				TeleportEntity(entity, pos);
			}
		}
	}
}

static void currency_spawn(int entity)
{
	RequestFrame(frame_currency_spawn, EntIndexToEntRef(entity));
}

static Action pop_entity_killed(int entity, CTakeDamageInfo info)
{
	int attacker = info.m_hAttacker;
	if(attacker < 1 || attacker > MaxClients) {
		return Plugin_Continue;
	}

	int userid = GetClientUserId(attacker);

	int ref = EntIndexToEntRef(entity);
	int idx = last_killed_data.FindValue(ref);
	if(idx == -1) {
		idx = last_killed_data.Push(ref);
	}

	last_killed_data.Set(idx, userid, 1);

	return Plugin_Continue;
}

public void pop_entity_spawned(IPopulator populator, IPopulationSpawner spawner, SpawnLocation location, int entity)
{
	HookEntityKilled(entity, pop_entity_killed, true);
}

public void OnEntityDestroyed(int entity)
{
	if(entity == -1) {
		return;
	}

	if(entity & (1 << 31)) {
		entity = EntRefToEntIndex(entity);
	}

	int idx = last_killed_data.FindValue(EntIndexToEntRef(entity));
	if(idx != -1) {
		last_killed_data.Erase(idx);
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "item_currencypack_large") ||
		StrEqual(classname, "item_currencypack_medium") ||
		StrEqual(classname, "item_currencypack_small") ||
		StrEqual(classname, "item_currencypack_custom")) {
		SDKHook(entity, SDKHook_SpawnPost, currency_spawn);
	}
}

static Action timer_endgame(Handle timer, any data)
{
	InsertServerCommand("tf_mvm_nextmission");
	ServerExecute();

	return Plugin_Continue;
}

#define WINPANEL_HOLD_TIME 14.0

static Action proxysend_roundstate(int entity, const char[] prop, RoundState &value, int element, int client)
{
	if(game_ended) {
		value = GR_STATE_GAME_OVER;
		return Plugin_Changed;
	} else if(value != GR_STATE_BETWEEN_RNDS) {
		value = GR_STATE_BETWEEN_RNDS;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

static Action timer_sendwinpanel(Handle timer, any data)
{
	SetWinningTeam(TF_TEAM_PVE_INVADERS, WINREASON_OPPONENTS_DEAD, true, false, WINPANEL_ARENA);

	CreateTimer(WINPANEL_HOLD_TIME, timer_endgame);

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

			if(GetClientTeam(i) != TF_TEAM_PVE_DEFENDERS) {
				continue;
			}

			++num_connected;

			if(IsPlayerAlive(i)) {
				++num_alive;
			}
		}
		if(num_connected > 0 && num_alive == 0) {
			game_ended = true;

			mp_tournament_blueteamname.SetString("?????");
			mp_tournament_redteamname.SetString("MANNCO");

			float networktime = 0.3;

			BfWrite bitbuf = view_as<BfWrite>(StartMessageAll("MVMServerKickTimeUpdate"));
			bitbuf.WriteByte(RoundToFloor(networktime + WINPANEL_HOLD_TIME));
			EndMessage();

			CreateTimer(networktime, timer_sendwinpanel);
		}
	}
}

public Action should_cleanup_entity(int entity, bool &should)
{
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));

#if 0
	if(is_gamemode_entity(classname)) {
		should = true;
		return Plugin_Changed;
	}
#endif

#if 0
	if(StrEqual(classname, "prop_dynamic")) {
		char model[PLATFORM_MAX_PATH];
		GetEntPropString(entity, Prop_Data, "m_ModelName", model, PLATFORM_MAX_PATH);
		if(StrEqual(model, "models/props_mvm/robot_hologram.mdl")) {
			should = true;
			return Plugin_Changed;
		}
	}
#endif

	return Plugin_Continue;
}

public Action should_create_entity(const char[] classname, bool &should)
{
#if 0
	if(is_gamemode_entity(classname)) {
		should = false;
		return Plugin_Changed;
	}
#endif

	return Plugin_Continue;
}

public void OnConfigsExecuted()
{
#if 0
	FindConVar("tf_populator_debug").BoolValue = true;
	FindConVar("tf_debug_placement_failure").BoolValue = false;
#endif
	FindConVar("tf_mvm_min_players_to_start").IntValue = 1;

	FindConVar("mve_pop_file").SetString("test");

	update_pop_path();

	tf_gamemode_mvm.BoolValue = true;
}

static void update_pop_path(const char[] name = NULL_STRING)
{
	char pop_file_path[PLATFORM_MAX_PATH];
	if(IsNullString(name) || name[0] == '\0') {
		mve_pop_file.GetString(pop_file_path, PLATFORM_MAX_PATH);
	}

	int len = strlen(pop_file_path);
	if(StrContains(pop_file_path, ".pop") != (len-4)) {
		StrCat(pop_file_path, PLATFORM_MAX_PATH, ".pop");
	}

	int populator = EntRefToEntIndex(info_populator);
	if(populator == -1) {
		return;
	}

	PrintToServer("SetPopulationFilename %s", pop_file_path);
	SDKCall(CPopulationManager_SetPopulationFilename, populator, pop_file_path);
}

public void OnMapStart()
{
	//clear_all_gamemodes();

	int gamerules = FindEntityByClassname(-1, "tf_gamerules");
#if 0
	proxysend_hook(gamerules, "m_iRoundState", proxysend_roundstate, false);
#endif
	tf_gamerules =  EntIndexToEntRef(gamerules);

	int logic = FindEntityByClassname(-1, "tf_logic_mann_vs_machine");
	if(logic != -1) {
		tf_logic_mann_vs_machine = EntIndexToEntRef(logic);
	}

	int stats = FindEntityByClassname(-1, "tf_mann_vs_machine_stats");
	if(stats == -1) {
		stats = CreateEntityByName("tf_mann_vs_machine_stats");
	}

	int populator = FindEntityByClassname(-1, "info_populator");
	if(populator == -1) {
		populator = CreateEntityByName("info_populator");
	}
	info_populator = EntIndexToEntRef(populator);

	update_pop_path();

	GameRules_SetProp("m_bPlayingMannVsMachine", 1);
}

public void OnMapEnd()
{
	game_ended = false;

	tf_gamerules = INVALID_ENT_REFERENCE;
	info_populator = INVALID_ENT_REFERENCE;
	tf_logic_mann_vs_machine = INVALID_ENT_REFERENCE;
}

public void OnClientPutInServer(int client)
{
	
}
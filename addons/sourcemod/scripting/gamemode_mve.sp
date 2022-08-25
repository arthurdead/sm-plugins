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

#define TF_TEAM_PVE_DEFENDERS 2
#define TF_TEAM_PVE_INVADERS 3

#define LIFE_ALIVE 2
#define EFL_KILLME (1 << 0)

static Handle CPopulationManager_SetPopulationFilename;
static Handle CPopulationManager_Initialize;

static Address g_pPopulationManager;

static int info_populator = INVALID_ENT_REFERENCE;
static int tf_gamerules = INVALID_ENT_REFERENCE;

static ConVar tf_gamemode_mvm;

static ConVar tf_populator_active_buffer_range;

static ConVar mve_pop_file;

static ArrayList last_ambush_areas;
static float next_ambush_calc;
static ArrayList entity_seen_time;

static float next_teleport_calc;
static float next_playercount_calc;

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

	tf_populator_active_buffer_range = FindConVar("tf_populator_active_buffer_range");

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}

	last_ambush_areas = new ArrayList();
	entity_seen_time = new ArrayList(3);

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
	collect_ambush_areas();

	int populator = EntRefToEntIndex(info_populator);
	if(populator != -1) {
		SDKCall(CPopulationManager_Initialize, populator);
	} else {
		LogError("missing info_populator");
	}
}

static void collect_ambush_areas()
{
	last_ambush_areas.Clear();

	ArrayList tmp_ambush_areas = new ArrayList();

	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			!IsPlayerAlive(i) ||
			GetClientTeam(i) < 2 ||
			TF2_GetPlayerClass(i) == TFClass_Unknown) {
			continue;
		}

		if(IsFakeClient(i)) {
			continue;
		}

		CNavArea start_area = GetEntityLastKnownArea(i);
		if(start_area == CNavArea_Null) {
			continue;
		}

		CollectSurroundingAreas(tmp_ambush_areas, start_area, tf_populator_active_buffer_range.FloatValue, STEP_HEIGHT, STEP_HEIGHT);

		int len = tmp_ambush_areas.Length;
		for(int j = 0; j < len; ++j) {
			CTFNavArea area = tmp_ambush_areas.Get(j);

			if(!area.ValidForWanderingPopulation) {
				continue;
			}

			if(area.IsPotentiallyVisibleToTeam(TF_TEAM_PVE_DEFENDERS)) {
				continue;
			}

			if(last_ambush_areas.FindValue(area) == -1) {
				last_ambush_areas.Push(area);
			}
		}
	}

	delete tmp_ambush_areas;

	next_ambush_calc = GetGameTime() + 1.0;
}

static bool get_random_ambush(float pos[3])
{
	int len = last_ambush_areas.Length;
	if(len == 0) {
		return false;
	}

	for(int i = 0; i < 5; ++i) {
		int idx = GetRandomInt(0, len-1);
		CNavArea area = last_ambush_areas.Get(idx);

		for(int j = 0; j < 3; ++j) {
			area.GetRandomPoint(pos);

			if(IsSpaceToSpawnHere(pos)) {
				return true;
			}
		}
	}

	return false;
}

public Action find_spawn_location(float pos[3])
{
	return get_random_ambush(pos) ? Plugin_Changed : Plugin_Handled;
}

public void OnGameFrame()
{
	if(next_ambush_calc < GetGameTime()) {
		collect_ambush_areas();
	}

	if(next_playercount_calc < GetGameTime()) {
		if(!GameRules_GetProp("m_bInWaitingForPlayers") && GameRules_GetRoundState() == GR_STATE_RND_RUNNING) {
			int num_alive = 0;
			for(int i = 1; i <= MaxClients; ++i) {
				if(!IsClientInGame(i) ||
					IsFakeClient(i)) {
					continue;
				}
				if(IsPlayerAlive(i)) {
					++num_alive;
				}
			}
			if(num_alive == 0) {
				SetWinningTeam(TF_TEAM_PVE_INVADERS, WINREASON_OPPONENTS_DEAD, true, false, WINPANEL_ARENA);
			}
		}

		next_playercount_calc = GetGameTime() + 0.2;
	}

	if(next_teleport_calc < GetGameTime()) {
		int entity = -1;
		while((entity = FindEntityByClassname(entity, "*")) != -1) {
			if(entity & (1 << 31)) {
				entity = EntRefToEntIndex(entity);
			}

			INextBot bot = INextBot(entity);
			if(bot == INextBot_Null) {
				continue;
			}

			if(entity >= 1 && entity <= MaxClients) {
				if(!IsFakeClient(entity)) {
					continue;
				}
			}

			if(GetEntProp(entity, Prop_Send, "m_iTeamNum") == TF_TEAM_PVE_DEFENDERS) {
				continue;
			}

			bool remove = false;

			if(GetEntProp(entity, Prop_Data, "m_lifeState") != LIFE_ALIVE ||
				GetEntProp(entity, Prop_Data, "m_iEFlags") & EFL_KILLME) {
				remove = true;
			}

			int ref = EntIndexToEntRef(entity);

			int idx = entity_seen_time.FindValue(ref);

			if(remove) {
				if(idx != -1) {
					entity_seen_time.Erase(idx);
				}
				continue;
			}

			if(idx == -1) {
				idx = entity_seen_time.Push(ref);
				entity_seen_time.Set(idx, 0.0, 1);
			}

			IVision vision = bot.VisionInterface;

			for(int i = 1; i <= MaxClients; ++i) {
				if(!IsClientInGame(i) ||
					IsFakeClient(i)) {
					continue;
				}

				if(CombatCharacterIsAbleToSeeEnt(i, entity, USE_FOV) ||
					vision.IsAbleToSeeEntity(i, DISREGARD_FOV)) {
					entity_seen_time.Set(idx, GetGameTime(), 1);
					break;
				}
			}

			float last_seen = entity_seen_time.Get(idx, 1);

			if((GetGameTime() - last_seen) > 5.0) {
				float pos[3];
				if(get_random_ambush(pos)) {
					TeleportEntity(entity, pos);
				}
			}
		}

		int len = entity_seen_time.Length;
		for(int i = 0; i < len;) {
			int ref = entity_seen_time.Get(i);
			entity = EntRefToEntIndex(ref);
			if(entity != -1) {
				if(GetEntProp(entity, Prop_Data, "m_lifeState") != LIFE_ALIVE ||
					GetEntProp(entity, Prop_Data, "m_iEFlags") & EFL_KILLME) {
					entity = -1;
				}
			}
			if(entity == -1) {
				entity_seen_time.Erase(i);
				--len;
				continue;
			}
			++i;
		}

		next_teleport_calc = GetGameTime() + 0.5;
	}
}

public Action should_cleanup_entity(int entity, bool &should)
{
	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));

	if(is_gamemode_entity(classname)) {
		should = true;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public Action should_create_entity(const char[] classname, bool &should)
{
	if(is_gamemode_entity(classname)) {
		should = false;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public void OnConfigsExecuted()
{
	FindConVar("tf_populator_debug").BoolValue = true;
	FindConVar("tf_debug_placement_failure").BoolValue = false;
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
		if(pop_file_path[0] != '\0') {
			BuildPath(Path_SM, pop_file_path, PLATFORM_MAX_PATH, "configs/mve/%s.pop", pop_file_path);
		}
	} else {
		BuildPath(Path_SM, pop_file_path, PLATFORM_MAX_PATH, "configs/mve/%s.pop", name);
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
	clear_all_gamemodes();

	next_ambush_calc = 0.0;

	int gamerules = FindEntityByClassname(-1, "tf_gamerules");
	tf_gamerules =  EntIndexToEntRef(gamerules);

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
	tf_gamerules = INVALID_ENT_REFERENCE;
	info_populator = INVALID_ENT_REFERENCE;
}

public void OnClientPutInServer(int client)
{
	
}
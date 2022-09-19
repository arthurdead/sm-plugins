#if defined __rulestools_inc
	#endinput
#endif
#define __rulestools_inc

#include <sdktools>

#define MVM_CLASS_TYPES_PER_WAVE_MAX 24

#define MVM_CLASS_FLAG_NONE            0
#define MVM_CLASS_FLAG_NORMAL          (1 << 0)
#define MVM_CLASS_FLAG_SUPPORT         (1 << 1)
#define MVM_CLASS_FLAG_MISSION         (1 << 2)
#define MVM_CLASS_FLAG_MINIBOSS        (1 << 3)
#define MVM_CLASS_FLAG_ALWAYSCRIT      (1 << 4)
#define MVM_CLASS_FLAG_SUPPORT_LIMITED (1 << 5)

enum HalloweenScenarioType
{
	HALLOWEEN_SCENARIO_NONE = 0,
	HALLOWEEN_SCENARIO_MANN_MANOR,
	HALLOWEEN_SCENARIO_VIADUCT,
	HALLOWEEN_SCENARIO_LAKESIDE,
	HALLOWEEN_SCENARIO_HIGHTOWER,
	HALLOWEEN_SCENARIO_DOOMSDAY,
};

enum ETFGameType
{
	TF_GAMETYPE_UNDEFINED = 0,
	TF_GAMETYPE_CTF,
	TF_GAMETYPE_CP,
	TF_GAMETYPE_ESCORT,
	TF_GAMETYPE_ARENA,
	TF_GAMETYPE_MVM,
	TF_GAMETYPE_RD,
	TF_GAMETYPE_PASSTIME,
	TF_GAMETYPE_PD,
	TF_GAMETYPE_COUNT
};

enum
{
	TF_HUDTYPE_UNDEFINED = 0,
	TF_HUDTYPE_CTF,
	TF_HUDTYPE_CP,
	TF_HUDTYPE_ESCORT,
	TF_HUDTYPE_ARENA,
	TF_HUDTYPE_TRAINING
};

enum
{
	WINREASON_NONE =0,
	WINREASON_ALL_POINTS_CAPTURED,
	WINREASON_OPPONENTS_DEAD,
	WINREASON_FLAG_CAPTURE_LIMIT,
	WINREASON_DEFEND_UNTIL_TIME_LIMIT,
	WINREASON_STALEMATE,
	WINREASON_TIMELIMIT,
	WINREASON_WINLIMIT,
	WINREASON_WINDIFFLIMIT,
	WINREASON_RD_REACTOR_CAPTURED,
	WINREASON_RD_CORES_COLLECTED,
	WINREASON_RD_REACTOR_RETURNED,
	WINREASON_PD_POINTS,
	WINREASON_SCORED,
	WINREASON_STOPWATCH_WATCHING_ROUNDS,
	WINREASON_STOPWATCH_WATCHING_FINAL_ROUND,
	WINREASON_STOPWATCH_PLAYING_ROUNDS,
};

#define GR_STATE_INIT RoundState_Init
#define GR_STATE_PREGAME RoundState_Pregame
#define GR_STATE_STARTGAME RoundState_StartGame
#define GR_STATE_PREROUND RoundState_Preround
#define GR_STATE_RND_RUNNING RoundState_RoundRunning
#define GR_STATE_TEAM_WIN RoundState_TeamWin
#define GR_STATE_RESTART RoundState_Restart
#define GR_STATE_STALEMATE RoundState_Stalemate
#define GR_STATE_GAME_OVER RoundState_GameOver
#define GR_STATE_BONUS RoundState_Bonus
#define GR_STATE_BETWEEN_RNDS RoundState_BetweenRounds

native void clear_all_gamemodes();

native bool is_gamemode_entity(const char[] classname);

native int get_objective_entity();
native int get_gamerules_proxy();

native bool IsMannVsMachineMode();

stock void SetHUDType(int type)
{
	GameRules_SetProp("m_nHudType", type);

	int proxy = get_gamerules_proxy();
	if(proxy != -1) {
		SetEntProp(proxy, Prop_Data, "m_nHudType", type);
	}
}

enum
{
	WINPANEL_DEFAULT,
	WINPANEL_NORMAL,
	WINPANEL_ARENA,
	WINPANEL_MVM
};

stock void SetWinningTeam(int team, int iWinReason, bool bForceMapReset = false, bool bSwitchTeams = false, int winpanel = WINPANEL_DEFAULT)
{
	int entity = CreateEntityByName("game_round_win");
	SetEntProp(entity, Prop_Data, "m_iWinReason", iWinReason);
	SetEntProp(entity, Prop_Data, "m_bForceMapReset", bForceMapReset);
	SetEntProp(entity, Prop_Data, "m_bSwitchTeamsOnWin", bSwitchTeams);
	bool was_mvm = GameRules_GetProp("m_bPlayingMannVsMachine") != 0;
	int old_gametype = GameRules_GetProp("m_nGameType");
	switch(winpanel) {
		case WINPANEL_NORMAL: {
			if(old_gametype == WINPANEL_ARENA) {
				GameRules_SetProp("m_nGameType", TF_GAMETYPE_CP);
			}
			GameRules_SetProp("m_bPlayingMannVsMachine", 0);
		}
		case WINPANEL_ARENA: {
			GameRules_SetProp("m_nGameType", TF_GAMETYPE_ARENA);
			GameRules_SetProp("m_bPlayingMannVsMachine", 0);
		}
		case WINPANEL_MVM: {
			GameRules_SetProp("m_nGameType", TF_GAMETYPE_MVM);
			GameRules_SetProp("m_bPlayingMannVsMachine", 1);
		}
	}
	SetEntProp(entity, Prop_Data, "m_iTeamNum", team);
	AcceptEntityInput(entity, "RoundWin");
	RemoveEntity(entity);
	GameRules_SetProp("m_nGameType", old_gametype);
	GameRules_SetProp("m_bPlayingMannVsMachine", was_mvm);
}

stock void SetMannVsMachineMaxWaveCount(int nCount)
{
	int objective = get_objective_entity();
	if(objective == -1) {
		return;
	}

	SetEntProp(objective, Prop_Send, "m_nMannVsMachineMaxWaveCount", nCount);
}

stock int GetMannVsMachineMaxWaveCount()
{
	int objective = get_objective_entity();
	if(objective == -1) {
		return 0;
	}

	return GetEntProp(objective, Prop_Send, "m_nMannVsMachineMaxWaveCount");
}

stock void SetMannVsMachineWaveCount(int nCount)
{
	int objective = get_objective_entity();
	if(objective == -1) {
		return;
	}

	SetEntProp(objective, Prop_Send, "m_nMannVsMachineWaveCount", nCount);
}

stock int GetMannVsMachineWaveCount()
{
	int objective = get_objective_entity();
	if(objective == -1) {
		return 0;
	}

	return GetEntProp(objective, Prop_Send, "m_nMannVsMachineWaveCount");
}

stock void SetMannVsMachineWaveEnemyCount(int nCount)
{
	int objective = get_objective_entity();
	if(objective == -1) {
		return;
	}

	SetEntProp(objective, Prop_Send, "m_nMannVsMachineWaveEnemyCount", nCount);
}

stock int GetMannVsMachineWaveEnemyCount()
{
	int objective = get_objective_entity();
	if(objective == -1) {
		return 0;
	}

	return GetEntProp(objective, Prop_Send, "m_nMannVsMachineWaveEnemyCount");
}

stock void SetMannVsMachineBetweenWaves(bool bVal)
{
	int objective = get_objective_entity();
	if(objective == -1) {
		return;
	}

	SetEntProp(objective, Prop_Send, "m_bMannVsMachineBetweenWaves", bVal);
}

stock bool GetMannVsMachineBetweenWaves()
{
	int objective = get_objective_entity();
	if(objective == -1) {
		return false;
	}

	return GetEntProp(objective, Prop_Send, "m_bMannVsMachineBetweenWaves") != 0;
}

native void SetMannVsMachineWaveClassName(int nIndex, const char[] iszClassIconName);
native void GetMannVsMachineWaveClassName(int nIndex, char[] iszClassIconName, int length);

native void SetMannVsMachineWaveClassCount(int nIndex, int nCount);
native int GetMannVsMachineWaveClassCount(int nIndex);

native void SetMannVsMachineWaveClassActive(int nIndex, bool bActive = true);
native bool GetMannVsMachineWaveClassActive(int nIndex);

native void SetMannVsMachineWaveClassFlags(int nIndex, int iFlags);
native int GetMannVsMachineWaveClassFlags(int nIndex);

native void CleanUpMap();
forward Action should_cleanup_entity(int entity, bool &should);
forward Action should_create_entity(const char[] classname, bool &should);

forward Action gamemode_uses_upgrades(bool &uses);

stock void ResetMannVsMachineWaveInfo()
{
	SetMannVsMachineMaxWaveCount(0);
	SetMannVsMachineWaveCount(0);
	SetMannVsMachineWaveEnemyCount(0);
	SetMannVsMachineBetweenWaves(false);

	for(int i = 0; i < MVM_CLASS_TYPES_PER_WAVE_MAX; ++i) {
		SetMannVsMachineWaveClassName(i, "");
		SetMannVsMachineWaveClassCount(i, 0);
		SetMannVsMachineWaveClassActive(i, false);
		SetMannVsMachineWaveClassFlags(i, MVM_CLASS_FLAG_NONE);
	}
}

public SharedPlugin __pl_rulestools =
{
	name = "rulestools",
	file = "rulestools.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_rulestools_SetNTVOptional()
{
	
}
#endif
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

native int get_objective_entity();

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
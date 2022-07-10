#include <sourcemod>
#include <sdktools>

#define NEXT_MAP_VOTE_OPTIONS 3

enum
{
	NEXT_MAP_VOTE_STATE_NONE,
	NEXT_MAP_VOTE_STATE_WAITING_FOR_USERS_TO_VOTE,
	NEXT_MAP_VOTE_STATE_MAP_CHOSEN_PAUSE,
};

enum
{
	USER_NEXT_MAP_VOTE_MAP_0 = 0,
	USER_NEXT_MAP_VOTE_MAP_1,
	USER_NEXT_MAP_VOTE_MAP_2,
	USER_NEXT_MAP_VOTE_UNDECIDED,

	NUM_VOTE_STATES
};

static ConVar tf_mm_next_map_vote_time;
static char maps[PLATFORM_MAX_PATH][NEXT_MAP_VOTE_OPTIONS];

public void OnPluginStart()
{
	tf_mm_next_map_vote_time = FindConVar("tf_mm_next_map_vote_time");

	AddCommandListener(next_map_vote, "next_map_vote");

	RegAdminCmd("sm_cmvotetest", sm_cmvotetest, ADMFLAG_ROOT);
}

static Action timer_votetimefinished(Handle timer, any data)
{
	int nvotes[NUM_VOTE_STATES];

	int numplayers = 0;
	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientConnected(i) || IsFakeClient(i)) {
			continue;
		}

		++numplayers;
		++nvotes[GameRules_GetProp("m_ePlayerWantsRematch", _, i)];
	}

	int winningvote = USER_NEXT_MAP_VOTE_MAP_0;
	if(nvotes[USER_NEXT_MAP_VOTE_UNDECIDED] == numplayers) {
		winningvote = USER_NEXT_MAP_VOTE_UNDECIDED;
	} else {
		for(int i = 0; i < NEXT_MAP_VOTE_OPTIONS; ++i) {
			winningvote = ((nvotes[i] >= nvotes[winningvote]) ? i : winningvote);
		}
	}

	if(winningvote == USER_NEXT_MAP_VOTE_UNDECIDED) {
		PrintToServer("stay");
	} else {
		int idx = GameRules_GetProp("m_nNextMapVoteOptions", _, winningvote);

		//maps[idx]

		PrintToServer("change to %i", idx);
	}

	return Plugin_Handled;
}

static Action sm_cmvotetest(int client, int args)
{
	GameRules_SetProp("m_iRoundState", RoundState_GameOver);
	GameRules_SetProp("m_eRematchState", NEXT_MAP_VOTE_STATE_WAITING_FOR_USERS_TO_VOTE);

	for(int i = 0; i < NEXT_MAP_VOTE_OPTIONS; ++i) {
		GameRules_SetProp("m_nNextMapVoteOptions", 1, _, i);
	}

	Event event = CreateEvent("vote_maps_changed", true);
	event.Fire();

	CreateTimer(float(tf_mm_next_map_vote_time.IntValue), timer_votetimefinished);

	return Plugin_Handled;
}

static Action next_map_vote(int client, const char[] command, int argc)
{
	int vote = GetCmdArgInt(1);

	if(GameRules_GetProp("m_eRematchState") != NEXT_MAP_VOTE_STATE_WAITING_FOR_USERS_TO_VOTE) {
		return Plugin_Handled;
	}

	GameRules_SetProp("m_ePlayerWantsRematch", vote, _, client);

	Event event = CreateEvent("player_next_map_vote_change", true);
	event.SetInt("map_index", vote);
	event.SetInt("vote", vote);
	event.Fire();

	return Plugin_Continue;
}

public void OnMapStart()
{
	GameRules_SetProp("m_eRematchState", NEXT_MAP_VOTE_STATE_NONE);

	for(int i = 1; i <= MaxClients; ++i) {
		GameRules_SetProp("m_ePlayerWantsRematch", USER_NEXT_MAP_VOTE_UNDECIDED, _, i);
	}

	for(int i = 0; i < NEXT_MAP_VOTE_OPTIONS; ++i) {
		GameRules_SetProp("m_nNextMapVoteOptions", 0, _, i);
	}

	Event event = CreateEvent("vote_maps_changed", true);
	event.Fire();
}
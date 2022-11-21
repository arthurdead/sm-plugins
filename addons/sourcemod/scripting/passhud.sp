#include <sourcemod>
#include <datamaps>
#include <sdktools>
#include <passhud>
#include <proxysend>
#include <sdkhooks>

#define TF2_MAXPLAYERS 33

static int player_reticle[TF2_MAXPLAYERS+1] = {-1, ...};

enum struct ReticleInfo
{
	int ref;
	passhud_reticle_type_t type;
	int ball;
	ArrayList goals;
}

static int passhud_logic = INVALID_ENT_REFERENCE;
static ArrayList reticles;
static ArrayList reticles_balls;
static ArrayList reticles_goals;
static bool removing_entities;
static bool removing_goals;
static bool logic_recreation_queued;
static Handle logic_creation_timer;

public void OnPluginStart()
{
	reticles = new ArrayList(sizeof(ReticleInfo));
	reticles_balls = new ArrayList();
	reticles_goals = new ArrayList();

	CustomEntityFactory factory = EntityFactoryDictionary.register_based("passhud_logic", "handle_test");
	CustomSendtable table = CustomSendtable.from_factory(factory, "CBaseEntity");
	table.set_shared_name("PasshudLogic");
	table.set_client_class_id("CTFPasstimeLogic");
	table.add_prop_ehandle("m_hBall");

	factory = EntityFactoryDictionary.register_based("passhud_ball", "prop_dynamic_override");
	table = CustomSendtable.from_factory(factory, "CBaseAnimating");
	table.set_shared_name("PasshudBall");
	table.set_client_class_id("CPasstimeBall");
	table.add_prop_ehandle("m_hHomingTarget");
	table.add_prop_ehandle("m_hCarrier");
	table.add_prop_ehandle("m_hPrevCarrier");

	factory = EntityFactoryDictionary.register_based("passhud_goal", "handle_test");
	table = CustomSendtable.from_factory(factory, "CBaseEntity");
	table.set_shared_name("PasshudGoal");
	table.set_client_class_id("CFuncPasstimeGoal");
	table.add_prop_bool("m_bTriggerDisabled");
	table.add_prop_int("m_iGoalType", 4);

	RegAdminCmd("sm_passhudinfo", sm_passhudinfo, ADMFLAG_ROOT);
}

static Action sm_passhudinfo(int client, int args)
{
	PrintToServer("reticle == %i", player_reticle[client]);

	int logic = EntRefToEntIndex(passhud_logic);
	PrintToServer("logic == %i", logic);
	if(logic != -1) {
		PrintToServer("  ball == %i", GetEntPropEnt(logic, Prop_Send, "m_hBall"));
	}

	int len = reticles.Length;
	PrintToServer("reticles == %i", len);
	for(int i = 0; i < len; ++i) {
		int reticle = EntRefToEntIndex(reticles.Get(i, ReticleInfo::ref));
		passhud_reticle_type_t type = reticles.Get(i, ReticleInfo::type);
		PrintToServer("  %i == %i", i, reticle);
		PrintToServer("    type == %i", type);
		if(reticle != -1) {
			PrintToServer("    team == %i", GetEntProp(reticle, Prop_Send, "m_iTeamNum"));
			switch(type) {
				case passhud_reticle_ball: {
					PrintToServer("    carrier == %i", GetEntPropEnt(reticle, Prop_Send, "m_hCarrier"));
				}
				case passhud_reticle_goal: {
					PrintToServer("    disabled == %i", GetEntProp(reticle, Prop_Send, "m_bTriggerDisabled"));
					PrintToServer("    goal type == %i", GetEntProp(reticle, Prop_Send, "m_iGoalType"));
				}
			}
		}
	}

	return Plugin_Handled;
}

static Action proxysend_ball(int entity, const char[] prop, int &value, int element, int client)
{
	int idx = player_reticle[client];
	if(idx >= 0 && idx < reticles.Length) {
		passhud_reticle_type_t type = reticles.Get(idx, ReticleInfo::type);
		if(type == passhud_reticle_goal) {
			int ball = reticles.Get(idx, ReticleInfo::ball);
			if(ball < 0 || ball >= reticles.Length) {
				value = -1;
				return Plugin_Changed;
			}
			idx = ball;
		}

		int ball_entity = EntRefToEntIndex(reticles.Get(idx, ReticleInfo::ref));
		if(ball_entity != -1) {
			value = ball_entity;
			return Plugin_Changed;
		}
	}

	value = -1;
	return Plugin_Changed;
}

static Action proxysend_carrier(int entity, const char[] prop, int &value, int element, int client)
{
	int idx = player_reticle[client];
	if(idx >= 0 && idx < reticles.Length) {
		passhud_reticle_type_t type = reticles.Get(idx, ReticleInfo::type);
		if(type == passhud_reticle_goal) {
			int ball = reticles.Get(idx, ReticleInfo::ball);
			if(ball < 0 || ball >= reticles.Length) {
				value = -1;
				return Plugin_Changed;
			}
			idx = ball;
		}

		if(EntRefToEntIndex(reticles.Get(idx, ReticleInfo::ref)) == entity) {
			ArrayList goals = reticles.Get(idx, ReticleInfo::goals);
			if(goals != null && goals.Length > 0) {
				value = client;
				return Plugin_Changed;
			}
		}
	}

	value = -1;
	return Plugin_Changed;
}

static Action proxysend_goal_team(int entity, const char[] prop, int &value, int element, int client)
{
	int idx = player_reticle[client];
	if(idx >= 0 && idx < reticles.Length) {
		passhud_reticle_type_t type = reticles.Get(idx, ReticleInfo::type);
		switch(type) {
			case passhud_reticle_ball: {
				ArrayList goals = reticles.Get(idx, ReticleInfo::goals);
				if(goals != null && goals.Length > 0) {
					int idx2 = reticles.FindValue(EntIndexToEntRef(entity), ReticleInfo::ref);
					if(idx2 != -1) {
						idx2 = goals.FindValue(idx2);
						if(idx2 != -1) {
							value = GetClientTeam(client);
							return Plugin_Changed;
						}
					}
				}
			}
			case passhud_reticle_goal: {
				int ball = reticles.Get(idx, ReticleInfo::ball);
				if(ball >= 0 && ball < reticles.Length) {
					if(EntRefToEntIndex(reticles.Get(ball, ReticleInfo::ref)) != -1) {
						value = GetClientTeam(client);
						return Plugin_Changed;
					}
				}
			}
		}
	}

	value = 0;
	return Plugin_Changed;
}

static Action proxysend_ball_team(int entity, const char[] prop, int &value, int element, int client)
{
	return Plugin_Continue;
}

static Action transmit_always(int entity, int client)
{
	int flags = GetEdictFlags(entity);
	flags |= FL_EDICT_ALWAYS;
	SetEdictFlags(entity, flags);
	return Plugin_Changed;
}

static int create_logic()
{
	int logic = CreateEntityByName("passhud_logic");
	DispatchKeyValue(logic, "model", "materials/sprites/dot.vmt");
	DispatchKeyValue(logic, "rendermode", "1");
	DispatchKeyValue(logic, "rendercolor", "0 0 0");
	DispatchKeyValue(logic, "renderamt", "0");
	DispatchSpawn(logic);
	proxysend_hook(logic, "m_hBall", proxysend_ball, true);
	SDKHook(logic, SDKHook_SetTransmit, transmit_always);
	int ball = -1;
	int idx = reticles.FindValue(passhud_reticle_ball, ReticleInfo::type);
	if(idx != -1) {
		ball = EntRefToEntIndex(reticles.Get(idx, ReticleInfo::ref));
	}
	SetEntPropEnt(logic, Prop_Send, "m_hBall", ball);
	passhud_logic = EntIndexToEntRef(logic);
	return logic;
}

static int create_ball()
{
	int ball = CreateEntityByName("passhud_ball");
	DispatchKeyValue(ball, "model", "models/empty.mdl");
	DispatchKeyValue(ball, "rendermode", "1");
	DispatchKeyValue(ball, "rendercolor", "0 0 0");
	DispatchKeyValue(ball, "renderamt", "0");
	DispatchSpawn(ball);
	SDKHook(ball, SDKHook_SetTransmit, transmit_always);
	//proxysend_hook(ball, "m_iTeamNum", proxysend_ball_team, true);
	proxysend_hook(ball, "m_hCarrier", proxysend_carrier, true);
	int logic = EntRefToEntIndex(passhud_logic);
	if(logic != -1) {
		if(GetEntPropEnt(logic, Prop_Send, "m_hBall") == -1) {
			SetEntPropEnt(logic, Prop_Send, "m_hBall", ball);
		}
	}
	ReticleInfo info;
	info.ref = EntIndexToEntRef(ball);
	info.type = passhud_reticle_ball;
	info.ball = -1;
	info.goals = null;
	int idx = reticles.PushArray(info, sizeof(ReticleInfo));
	reticles_balls.Push(idx);
	return ball;
}

static int create_goal()
{
	int goal = CreateEntityByName("passhud_goal");
	DispatchKeyValue(goal, "model", "materials/sprites/dot.vmt");
	DispatchKeyValue(goal, "rendermode", "1");
	DispatchKeyValue(goal, "rendercolor", "0 0 0");
	DispatchKeyValue(goal, "renderamt", "0");
	DispatchSpawn(goal);
	SDKHook(goal, SDKHook_SetTransmit, transmit_always);
	proxysend_hook(goal, "m_iTeamNum", proxysend_goal_team, true);
	ReticleInfo info;
	info.ref = EntIndexToEntRef(goal);
	info.type = passhud_reticle_goal;
	info.ball = -1;
	info.goals = null;
	int idx = reticles.PushArray(info, sizeof(ReticleInfo));
	reticles_goals.Push(idx);
	return goal;
}

static void queue_logic_recreation()
{
	int logic = EntRefToEntIndex(passhud_logic);
	if(logic != -1) {
		passhud_logic = INVALID_ENT_REFERENCE;
		RemoveEntity(logic);
	}

	logic_recreation_queued = true;

	if(logic_creation_timer) {
		KillTimer(logic_creation_timer);
	}

	logic_creation_timer = CreateTimer(0.3, timer_create_logic);
}

static Action timer_create_logic(Handle timer, any data)
{
	create_logic();

	logic_recreation_queued = false;
	logic_creation_timer = null;

	return Plugin_Continue;
}

static any native_passhud_create_reticle(Handle plugin, int params)
{
	passhud_reticle_type_t type = GetNativeCell(1);

	int reticle = -1;

	switch(type) {
		case passhud_reticle_ball: {
			reticle = create_ball();

			if(EntRefToEntIndex(passhud_logic) == -1) {
				if(!logic_recreation_queued) {
					create_logic();
				}
			}
		}
		case passhud_reticle_goal: {
			reticle = create_goal();

			queue_logic_recreation();
		}
	}

	return reticle;
}

static any native_passhud_num_reticles(Handle plugin, int params)
{
	return reticles.Length;
}

static any native_passhud_get_reticle_entity(Handle plugin, int params)
{
	int i = GetNativeCell(1);
	if(i < 0 || i >= reticles.Length) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid index %i", i);
	}

	return EntRefToEntIndex(reticles.Get(i, ReticleInfo::ref));
}

static any native_passhud_add_goal(Handle plugin, int params)
{
	int ball = GetNativeCell(1);
	int ball_idx = reticles.FindValue(EntIndexToEntRef(ball), ReticleInfo::ref);
	if(ball_idx == -1) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid ball entity %i", ball);
	}

	int goal = GetNativeCell(2);
	int goal_idx = reticles.FindValue(EntIndexToEntRef(goal), ReticleInfo::ref);
	if(goal_idx == -1) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid goal entity %i", goal);
	}

	if(reticles.Get(ball_idx, ReticleInfo::type) != passhud_reticle_ball) {
		return ThrowNativeError(SP_ERROR_NATIVE, "reticle index %i is not a ball", ball_idx);
	}

	if(reticles.Get(goal_idx, ReticleInfo::type) != passhud_reticle_goal) {
		return ThrowNativeError(SP_ERROR_NATIVE, "reticle index %i is not a goal", goal_idx);
	}

	ArrayList goals = reticles.Get(ball_idx, ReticleInfo::goals);
	if(goals == null) {
		goals = new ArrayList();
		reticles.Set(ball_idx, goals, ReticleInfo::goals);
	}

	goals.Push(goal_idx);

	reticles.Set(goal_idx, ball_idx, ReticleInfo::ball);

	int logic = EntRefToEntIndex(passhud_logic);
	if(logic != -1) {
		ChangeEdictState(logic);
	}

	ChangeEdictState(ball);
	ChangeEdictState(goal);

	return 0;
}

static any native_passhud_get_ball_entity(Handle plugin, int params)
{
	int reticle = GetNativeCell(1);

	int reticle_idx = reticles.FindValue(EntIndexToEntRef(reticle), ReticleInfo::ref);
	if(reticle_idx == -1) {
		return ThrowNativeError(SP_ERROR_NATIVE, "invalid reticle entity %i", reticle);
	}

	passhud_reticle_type_t type = reticles.Get(reticle_idx, ReticleInfo::type);
	switch(type) {
		case passhud_reticle_ball: {
			return reticle;
		}
		case passhud_reticle_goal: {
			int ball_idx = reticles.Get(reticle_idx, ReticleInfo::ball);
			if(ball_idx >= 0 && ball_idx < reticles.Length) {
				return EntRefToEntIndex(reticles.Get(ball_idx, ReticleInfo::ref));
			}
		}
	}

	return -1;
}

static any native_passhud_set_reticle(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	int reticle = GetNativeCell(2);
	if(reticle == -1) {
		remove_carrier(client);
		player_reticle[client] = -1;
	} else {
		int reticle_idx = reticles.FindValue(EntIndexToEntRef(reticle), ReticleInfo::ref);
		if(reticle_idx == -1) {
			return ThrowNativeError(SP_ERROR_NATIVE, "invalid reticle entity %i", reticle);
		}

		int ball_entity = reticle;

		passhud_reticle_type_t type = reticles.Get(reticle_idx, ReticleInfo::type);
		switch(type) {
			case passhud_reticle_goal: {
				int ball_idx = reticles.Get(reticle_idx, ReticleInfo::ball);
				if(ball_idx < 0 || ball_idx >= reticles.Length) {
					return ThrowNativeError(SP_ERROR_NATIVE, "goal reticle %i has no ball assigned %i", reticle);
				}
				reticle_idx = ball_idx;
				ball_entity = EntRefToEntIndex(reticles.Get(ball_idx, ReticleInfo::ref));
			}
		}

		player_reticle[client] = reticle_idx;

		ArrayList goals = reticles.Get(reticle_idx, ReticleInfo::goals);
		if(goals) {
			int len = goals.Length;
			int reticle_len = reticles.Length;
			int team = GetClientTeam(client);
			for(int i = 0; i < len; ++i) {
				int idx2 = goals.Get(i);
				if(idx2 >= 0 && idx2 < reticle_len) {
					int goal = EntRefToEntIndex(reticles.Get(idx2, ReticleInfo::ref));
					if(goal != -1) {
						SetEntProp(goal, Prop_Send, "m_iTeamNum", team);
					}
				}
			}
			if(ball_entity != -1) {
				if(len > 0) {
					if(GetEntPropEnt(ball_entity, Prop_Send, "m_hCarrier") == -1) {
						SetEntPropEnt(ball_entity, Prop_Send, "m_hCarrier", client);
					}
				}
			}
		}

		if(type == passhud_reticle_goal) {
			if(ball_entity != -1) {
				ChangeEdictState(ball_entity);
			}
		}

		ChangeEdictState(reticle);
	}

	int logic = EntRefToEntIndex(passhud_logic);
	if(logic != -1) {
		ChangeEdictState(logic);
	}

	return 0;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("passhud");
	CreateNative("passhud_num_reticles", native_passhud_num_reticles);
	CreateNative("passhud_get_reticle_entity", native_passhud_get_reticle_entity);
	CreateNative("passhud_create_reticle", native_passhud_create_reticle);
	CreateNative("passhud_add_goal", native_passhud_add_goal);
	CreateNative("passhud_get_ball_entity", native_passhud_get_ball_entity);
	CreateNative("passhud_set_reticle", native_passhud_set_reticle);
	return APLRes_Success;
}

public void OnMapStart()
{
	PrecacheModel("materials/sprites/dot.vmt");
	PrecacheModel("models/error.mdl");
	PrecacheModel("models/empty.mdl");
}

static void remove_carrier(int client)
{
	int old_reticle = player_reticle[client];
	if(old_reticle >= 0 && old_reticle < reticles.Length) {
		int ball_entity = -1;
		passhud_reticle_type_t type = reticles.Get(old_reticle, ReticleInfo::type);
		switch(type) {
			case passhud_reticle_ball: {
				ball_entity = EntRefToEntIndex(reticles.Get(old_reticle, ReticleInfo::ref));
			}
			case passhud_reticle_goal: {
				int ball_idx = reticles.Get(old_reticle, ReticleInfo::ball);
				if(ball_idx >= 0 && ball_idx < reticles.Length) {
					ball_entity = EntRefToEntIndex(reticles.Get(ball_idx, ReticleInfo::ref));
				}
			}
		}
		if(ball_entity != -1) {
			if(GetEntPropEnt(ball_entity, Prop_Send, "m_hCarrier") == client) {
				SetEntPropEnt(ball_entity, Prop_Send, "m_hCarrier", -1);
			}
		}
	}
}

public void OnClientDisconnect(int client)
{
	remove_carrier(client);
	player_reticle[client] = -1;
}

public void OnEntityDestroyed(int entity)
{
	if(removing_entities ||
		removing_goals) {
		return;
	}

	if(entity == -1) {
		return;
	}

	if(entity & (1 << 31)) {
		entity = EntRefToEntIndex(entity);
	}

	int ref = EntIndexToEntRef(entity);

	bool check_logic = false;
	bool recreate_logic = false;

	if(ref == passhud_logic) {
		passhud_logic = INVALID_ENT_REFERENCE;
	} else {
		int idx = reticles.FindValue(ref, ReticleInfo::ref);
		if(idx != -1) {
			passhud_reticle_type_t type = reticles.Get(idx, ReticleInfo::type);
			for(int i = 1; i <= MaxClients; ++i) {
				if(!IsClientInGame(i) ||
					IsFakeClient(i) ||
					IsClientSourceTV(i) ||
					IsClientReplay(i)) {
					continue;
				}
				if(player_reticle[i] == idx) {
					if(type == passhud_reticle_ball) {
						if(GetEntPropEnt(entity, Prop_Send, "m_hCarrier") == i) {
							SetEntPropEnt(entity, Prop_Send, "m_hCarrier", -1);
						}
					}
					player_reticle[i] = -1;
				}
			}
			check_logic = true;
			switch(type) {
				case passhud_reticle_ball: {
					int idx2 = reticles_balls.FindValue(idx);
					if(idx2 != -1) {
						reticles_balls.Erase(idx2);
					}
					ArrayList goals = reticles.Get(idx, ReticleInfo::goals);
					if(goals != null) {
						int len = goals.Length;
						removing_goals = true;
						for(int i = 0; i < len; ++i) {
							int goal = goals.Get(i);
							if(goal < 0 || goal >= reticles.Length) {
								continue;
							}
							int goal_entity = EntRefToEntIndex(reticles.Get(goal, ReticleInfo::ref));
							if(goal_entity != -1) {
								RemoveEntity(goal_entity);
							}
							idx2 = reticles_goals.FindValue(goal);
							if(idx2 != -1) {
								reticles_goals.Erase(idx2);
							}
							reticles.Erase(goal);
						}
						removing_goals = false;
						delete goals;
						if(reticles_goals.Length > 0) {
							recreate_logic = true;
						}
					}
				}
				case passhud_reticle_goal: {
					int idx2 = reticles_goals.FindValue(idx);
					if(idx2 != -1) {
						reticles_goals.Erase(idx2);
					}
					if(reticles_goals.Length > 0) {
						recreate_logic = true;
					}
					int ball = reticles.Get(idx, ReticleInfo::ball);
					if(ball >= 0 && ball < reticles.Length) {
						ArrayList goals = reticles.Get(ball, ReticleInfo::goals);
						if(goals != null) {
							idx2 = goals.FindValue(idx);
							if(idx2 != -1) {
								goals.Erase(idx2);
							}
						}
						int ball_entity = EntRefToEntIndex(reticles.Get(ball, ReticleInfo::ref));
						if(ball_entity != -1) {
							ChangeEdictState(ball_entity);
						}
					}
				}
			}
			reticles.Erase(idx);
			if(!recreate_logic) {
				int logic = EntRefToEntIndex(passhud_logic);
				if(logic != -1) {
					int ball = GetEntPropEnt(logic, Prop_Send, "m_hBall");
					if(ball == entity) {
						int idx2 = reticles.FindValue(passhud_reticle_ball, ReticleInfo::type);
						if(idx2 != -1) {
							ball = EntRefToEntIndex(reticles.Get(idx2, ReticleInfo::ref));
						} else {
							ball = -1;
						}
						SetEntPropEnt(logic, Prop_Send, "m_hBall", ball);
					}
					ChangeEdictState(logic);
				}
			}
		}
	}

	if(check_logic && !recreate_logic) {
		int logic = EntRefToEntIndex(passhud_logic);
		if(logic != -1) {
			if(reticles.Length == 0) {
				passhud_logic = INVALID_ENT_REFERENCE;
				RemoveEntity(logic);
			}
		}
	} else if(recreate_logic) {
		queue_logic_recreation();
	}
}

public void OnMapEnd()
{
	removing_entities = true;

	int logic = EntRefToEntIndex(passhud_logic);
	if(logic != -1) {
		passhud_logic = INVALID_ENT_REFERENCE;
		RemoveEntity(logic);
	}

	int len = reticles.Length;
	for(int i = 0; i < len; ++i) {
		int reticle = EntRefToEntIndex(reticles.Get(i, ReticleInfo::ref));
		if(reticle != -1) {
			RemoveEntity(reticle);
		}
		ArrayList goals = reticles.Get(i, ReticleInfo::goals);
		if(goals != null) {
			delete goals;
		}
	}
	reticles.Clear();

	reticles_balls.Clear();
	reticles_goals.Clear();

	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			IsFakeClient(i) ||
			IsClientSourceTV(i) ||
			IsClientReplay(i)) {
			continue;
		}

		player_reticle[i] = -1;
	}

	removing_entities = false;
}

public void OnPluginEnd()
{
	OnMapEnd();
}
#if defined __passhud_inc
	#endinput
#endif
#define __passhud_inc

enum passhud_reticle_type_t
{
	passhud_reticle_ball,
	passhud_reticle_goal
};

enum passhud_goal_type_t
{
	passhud_goal_hoop,
	passhud_goal_endzone,
	passhud_goal_tower
};

native int passhud_num_reticles();
native int passhud_get_reticle_entity(int i);
native void passhud_add_goal(int ball, int goal);
//native void passhud_remove_goal(int ball, int goal);
native int passhud_get_ball_entity(int goal);
native int passhud_create_reticle(passhud_reticle_type_t type);

native void passhud_set_reticle(int client, int reticle);

public SharedPlugin __pl_passhud =
{
	name = "passhud",
	file = "passhud.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_passhud_SetNTVOptional()
{
	
}
#endif
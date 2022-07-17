#if defined __animstate_inc
	#endinput
#endif
#define __animstate_inc

enum PlayerAnimEvent_t
{
	PLAYERANIMEVENT_ATTACK_PRIMARY,
	PLAYERANIMEVENT_ATTACK_SECONDARY,
	PLAYERANIMEVENT_ATTACK_GRENADE,
	PLAYERANIMEVENT_RELOAD,
	PLAYERANIMEVENT_RELOAD_LOOP,
	PLAYERANIMEVENT_RELOAD_END,
	PLAYERANIMEVENT_JUMP,
	PLAYERANIMEVENT_SWIM,
	PLAYERANIMEVENT_DIE,
	PLAYERANIMEVENT_FLINCH_CHEST,
	PLAYERANIMEVENT_FLINCH_HEAD,
	PLAYERANIMEVENT_FLINCH_LEFTARM,
	PLAYERANIMEVENT_FLINCH_RIGHTARM,
	PLAYERANIMEVENT_FLINCH_LEFTLEG,
	PLAYERANIMEVENT_FLINCH_RIGHTLEG,
	PLAYERANIMEVENT_DOUBLEJUMP,

	PLAYERANIMEVENT_CANCEL,
	PLAYERANIMEVENT_SPAWN,

	PLAYERANIMEVENT_SNAP_YAW,

	PLAYERANIMEVENT_CUSTOM,
	PLAYERANIMEVENT_CUSTOM_GESTURE,
	PLAYERANIMEVENT_CUSTOM_SEQUENCE,
	PLAYERANIMEVENT_CUSTOM_GESTURE_SEQUENCE,

	PLAYERANIMEVENT_ATTACK_PRE,
	PLAYERANIMEVENT_ATTACK_POST,
	PLAYERANIMEVENT_GRENADE1_DRAW,
	PLAYERANIMEVENT_GRENADE2_DRAW,
	PLAYERANIMEVENT_GRENADE1_THROW,
	PLAYERANIMEVENT_GRENADE2_THROW,
	PLAYERANIMEVENT_VOICE_COMMAND_GESTURE,
	PLAYERANIMEVENT_DOUBLEJUMP_CROUCH,
	PLAYERANIMEVENT_STUN_BEGIN,
	PLAYERANIMEVENT_STUN_MIDDLE,
	PLAYERANIMEVENT_STUN_END,
	PLAYERANIMEVENT_PASSTIME_THROW_BEGIN,
	PLAYERANIMEVENT_PASSTIME_THROW_MIDDLE,
	PLAYERANIMEVENT_PASSTIME_THROW_END,
	PLAYERANIMEVENT_PASSTIME_THROW_CANCEL,

	PLAYERANIMEVENT_ATTACK_PRIMARY_SUPER,

	PLAYERANIMEVENT_COUNT
};

enum
{
	TAUNT_BASE_WEAPON,
	TAUNT_MISC_ITEM,
	TAUNT_SHOW_ITEM,
	TAUNT_LONG,
	TAUNT_SPECIAL
};

native void animstate_is_allowed_to_taunt(int client);
native void animstate_cancel_taunt(int client);
native void animstate_set_taunt_state(int client, float duration, int index, int concept);
native bool animstate_play_taunt_from_item(int client, int itemdef);

native void animstate_do_event(int client, PlayerAnimEvent_t event, int data);
native bool animstate_play_sequence(int client, const char[] name);
native bool animstate_play_gesture(int client, const char[] name);

native bool animstate_play_taunt_activity(int client, const char[] name, bool long = false);
native bool animstate_play_taunt_activity_3_stage(int client, const char[] intro, const char[] idle, const char[] outro);

public SharedPlugin __pl_animstate =
{
	name = "animstate",
	file = "animstate.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_animstate_SetNTVOptional()
{
	
}
#endif
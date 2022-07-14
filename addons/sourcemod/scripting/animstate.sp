#include <sourcemod>
#include <sdktools>
#include <tf2items>
#include <dhooks>
#include <animstate>
#include <animhelpers>

#define TF2_MAXPLAYERS 33

#define INVALID_ITEM_ID_LOW 4294967295
#define INVALID_ITEM_ID_HIGH 4294967295

#define INVALID_ITEM_DEF_INDEX 65535

enum TauntStage_t
{
	TAUNT_NONE = 0,
	TAUNT_INTRO,
	TAUNT_OUTRO
};

static int CTFPlayer_m_TauntStage_offset = -1;
static int CTFPlayer_m_bAllowedToRemoveTaunt_offset = -1;
static int CTFPlayer_m_flTauntStartTime_offset = -1;
static int CTFPlayer_m_flTauntRemoveTime_offset = -1;
static int CTFPlayer_m_flTauntOutroTime_offset = -1;
static int CTFPlayer_m_vecTauntStartPosition_offset = -1;
static int CTFPlayer_m_angTauntCamera_offset = -1;
static int CTFPlayer_m_flPrevTauntYaw_offset = -1;
static int CTFPlayer_m_hTauntItem_offset = -1;
static int CTFPlayer_m_bTauntMimic_offset = -1;
static int CTFPlayer_m_bInitTaunt_offset = -1;
static int CTFPlayer_m_flNextAllowTauntRemapInputTime_offset = -1;

static int CEconEntity_m_Item_offset = -1;

static Handle CTFPlayer_PlayGesture;
static Handle CTFPlayer_PlaySpecificSequence;
static Handle CTFPlayer_DoAnimationEvent;
static Handle CTFPlayer_CancelTaunt;
static Handle CTFPlayer_PlayTauntSceneFromItem;
static Handle CTFPlayer_IsAllowedToTaunt;

static Handle dummy_item_view;

static Handle player_anim_idle_timer[TF2_MAXPLAYERS+1];
static Handle player_anim_intro_timer[TF2_MAXPLAYERS+1];

public void OnPluginStart()
{
	GameData gamedata = new GameData("animstate");
	if(gamedata == null) {
		SetFailState("Gamedata not found.");
		return;
	}

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayer::DoAnimationEvent");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	CTFPlayer_DoAnimationEvent = EndPrepSDKCall();
	if(CTFPlayer_DoAnimationEvent == null) {
		SetFailState("Failed to create SDKCall for CTFPlayer::DoAnimationEvent.");
		delete gamedata;
		return;
	}

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayer::PlaySpecificSequence");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	CTFPlayer_PlaySpecificSequence = EndPrepSDKCall();
	if(CTFPlayer_PlaySpecificSequence == null) {
		SetFailState("Failed to create SDKCall for CTFPlayer::PlaySpecificSequence.");
		delete gamedata;
		return;
	}

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayer::PlayGesture");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	CTFPlayer_PlayGesture = EndPrepSDKCall();
	if(CTFPlayer_PlayGesture == null) {
		SetFailState("Failed to create SDKCall for CTFPlayer::PlayGesture.");
		delete gamedata;
		return;
	}

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayer::CancelTaunt");
	CTFPlayer_CancelTaunt = EndPrepSDKCall();
	if(CTFPlayer_CancelTaunt == null) {
		SetFailState("Failed to create SDKCall for CTFPlayer::CancelTaunt.");
		delete gamedata;
		return;
	}

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayer::PlayTauntSceneFromItem");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	CTFPlayer_PlayTauntSceneFromItem = EndPrepSDKCall();
	if(CTFPlayer_PlayTauntSceneFromItem == null) {
		SetFailState("Failed to create SDKCall for CTFPlayer::PlayTauntSceneFromItem.");
		delete gamedata;
		return;
	}

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayer::IsAllowedToTaunt");
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	CTFPlayer_IsAllowedToTaunt = EndPrepSDKCall();
	if(CTFPlayer_IsAllowedToTaunt == null) {
		SetFailState("Failed to create SDKCall for CTFPlayer::IsAllowedToTaunt.");
		delete gamedata;
		return;
	}

	CEconEntity_m_Item_offset = FindSendPropInfo("CEconEntity", "m_Item");

	int offset = FindSendPropInfo("CTFPlayer", "m_iSpawnCounter");
	CTFPlayer_m_TauntStage_offset = offset - gamedata.GetOffset("CTFPlayer::m_TauntStage");
	CTFPlayer_m_bAllowedToRemoveTaunt_offset = offset - gamedata.GetOffset("CTFPlayer::m_bAllowedToRemoveTaunt");
	CTFPlayer_m_flTauntStartTime_offset = offset - gamedata.GetOffset("CTFPlayer::m_flTauntStartTime");
	CTFPlayer_m_flTauntRemoveTime_offset = offset - gamedata.GetOffset("CTFPlayer::m_flTauntRemoveTime");
	CTFPlayer_m_flTauntOutroTime_offset = offset - gamedata.GetOffset("CTFPlayer::m_flTauntOutroTime");
	CTFPlayer_m_vecTauntStartPosition_offset = offset - gamedata.GetOffset("CTFPlayer::m_vecTauntStartPosition");
	CTFPlayer_m_flNextAllowTauntRemapInputTime_offset = offset - gamedata.GetOffset("CTFPlayer::m_flNextAllowTauntRemapInputTime");

	offset = FindSendPropInfo("CTFPlayer", "m_bAllowMoveDuringTaunt");
	CTFPlayer_m_angTauntCamera_offset = offset - gamedata.GetOffset("CTFPlayer::m_angTauntCamera");
	CTFPlayer_m_hTauntItem_offset = offset - gamedata.GetOffset("CTFPlayer:: m_hTauntItem");

	offset = FindSendPropInfo("CTFPlayer", "m_flVehicleReverseTime");
	CTFPlayer_m_flPrevTauntYaw_offset = offset + gamedata.GetOffset("CTFPlayer::m_flPrevTauntYaw");
	CTFPlayer_m_bTauntMimic_offset = offset + gamedata.GetOffset("CTFPlayer::m_bTauntMimic");
	CTFPlayer_m_bInitTaunt_offset = offset + gamedata.GetOffset("CTFPlayer::m_bInitTaunt");

	delete gamedata;

	dummy_item_view = TF2Items_CreateItem(OVERRIDE_ALL|PRESERVE_ATTRIBUTES|FORCE_GENERATION);
	TF2Items_SetClassname(dummy_item_view, "tf_wearable_vm");
	TF2Items_SetItemIndex(dummy_item_view, 65535);
	TF2Items_SetQuality(dummy_item_view, 0);
	TF2Items_SetLevel(dummy_item_view, 0);
	TF2Items_SetNumAttributes(dummy_item_view, 0);
}

static int native_animstate_play_sequence(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	int length = 0;
	GetNativeStringLength(2, length);
	char[] name = new char[++length];
	GetNativeString(2, name, length);

	return SDKCall(CTFPlayer_PlaySpecificSequence, client, name);
}

static int native_animstate_play_gesture(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	int length = 0;
	GetNativeStringLength(2, length);
	char[] name = new char[++length];
	GetNativeString(2, name, length);

	return SDKCall(CTFPlayer_PlayGesture, client, name);
}

static int native_animstate_do_event(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	int event = GetNativeCell(2);
	int data = GetNativeCell(3);

	SDKCall(CTFPlayer_DoAnimationEvent, client, event, data);
	return 0;
}

static void set_taunt_yaw(int client, float yaw)
{
	float m_flTauntYaw = GetEntPropFloat(client, Prop_Send, "m_flTauntYaw");
	SetEntDataFloat(client, CTFPlayer_m_flPrevTauntYaw_offset, m_flTauntYaw);
	SetEntPropFloat(client, Prop_Send, "m_flTauntYaw", yaw);

	float angles[3];
	GetEntPropVector(client, Prop_Data, "m_angRotation", angles);
	angles[1] = yaw;

	//TODO!!! SetLocalAngles
	SetEntPropVector(client, Prop_Data, "m_angRotation", angles);
}

static int native_animstate_set_taunt_state(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	float duration = GetNativeCell(2);
	int index = GetNativeCell(3);
	int concept = GetNativeCell(4);

	#define INF_DURATION 99999999.0

#if 0
	if(duration != TFCondDuration_Infinite) {
		duration += 0.2;
	}
#endif

	SetEntData(client, CTFPlayer_m_hTauntItem_offset, 0xFFFFFFFF, 4);

	SetEntData(client, CTFPlayer_m_bTauntMimic_offset, 0, 1);

	SetEntData(client, CTFPlayer_m_bInitTaunt_offset, 1, 1);

	SetEntProp(client, Prop_Send, "m_iTauntIndex", index);
	SetEntProp(client, Prop_Send, "m_iTauntConcept", concept);

	SetEntData(client, CTFPlayer_m_TauntStage_offset, TAUNT_INTRO, 4);

	SetEntDataFloat(client, CTFPlayer_m_flTauntStartTime_offset, GetGameTime());
	SetEntDataFloat(client, CTFPlayer_m_flTauntOutroTime_offset, 0.0);

	SetEntProp(client, Prop_Send, "m_unTauntSourceItemID_Low", INVALID_ITEM_ID_LOW);
	SetEntProp(client, Prop_Send, "m_unTauntSourceItemID_High", INVALID_ITEM_ID_HIGH);

	SetEntProp(client, Prop_Send, "m_iTauntItemDefIndex", INVALID_ITEM_DEF_INDEX);

	float angles[3];
	GetClientAbsAngles(client, angles);

	if(index == TAUNT_LONG) {
		TF2_AddCondition(client, TFCond_Taunting, TFCondDuration_Infinite);

		SetEntDataFloat(client, CTFPlayer_m_flTauntRemoveTime_offset, GetGameTime());
		SetEntData(client, CTFPlayer_m_bAllowedToRemoveTaunt_offset, 0, 1);

		if(duration != TFCondDuration_Infinite) {
			SetEntDataFloat(client, CTFPlayer_m_flNextAllowTauntRemapInputTime_offset, GetGameTime() + duration);
		} else {
			SetEntDataFloat(client, CTFPlayer_m_flNextAllowTauntRemapInputTime_offset, GetGameTime() + INF_DURATION);
		}
	} else {
		TF2_AddCondition(client, TFCond_Taunting, duration);

		if(duration != TFCondDuration_Infinite) {
			SetEntDataFloat(client, CTFPlayer_m_flTauntRemoveTime_offset, GetGameTime() + duration);
		} else {
			SetEntDataFloat(client, CTFPlayer_m_flTauntRemoveTime_offset, GetGameTime() + INF_DURATION);
		}
		SetEntData(client, CTFPlayer_m_bAllowedToRemoveTaunt_offset, 0, 1);

		SetEntDataFloat(client, CTFPlayer_m_flNextAllowTauntRemapInputTime_offset, -1.0);
	}

	float eye[3];
	GetClientEyeAngles(client, eye);
	SetEntDataVector(client, CTFPlayer_m_angTauntCamera_offset, eye);

	float zero[3];
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, zero);

	set_taunt_yaw(client, angles[1]);

	float pos[3];
	GetClientAbsOrigin(client, pos);
	SetEntDataVector(client, CTFPlayer_m_vecTauntStartPosition_offset, pos);

	return 0;
}

static int native_animstate_is_allowed_to_taunt(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	return SDKCall(CTFPlayer_IsAllowedToTaunt, client);
}

static int native_animstate_cancel_taunt(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	SDKCall(CTFPlayer_CancelTaunt, client);
	TF2_RemoveCondition(client, TFCond_Taunting);
	return 0;
}

static int native_animstate_play_taunt_from_item(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	int itemdef = GetNativeCell(2);

	TF2Items_SetItemIndex(dummy_item_view, itemdef);
	int entity = TF2Items_GiveNamedItem(client, dummy_item_view);
	Address item_view = (GetEntityAddress(entity) + view_as<Address>(CEconEntity_m_Item_offset));
	bool played = SDKCall(CTFPlayer_PlayTauntSceneFromItem, client, item_view);
	RemoveEntity(entity);

	return played;
}

public void OnClientDisconnect(int client)
{
	if(player_anim_idle_timer[client] != null) {
		KillTimer(player_anim_idle_timer[client]);
		player_anim_idle_timer[client] = null;
	}

	if(player_anim_intro_timer[client] != null) {
		KillTimer(player_anim_intro_timer[client]);
		player_anim_intro_timer[client] = null;
	}
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	if(condition == TFCond_Taunting) {
		OnClientDisconnect(client);
		animstate_do_event(client, PLAYERANIMEVENT_CUSTOM_SEQUENCE, -1);
	}
}

#define IDLE_ANIM_DURATION_OFF 0.1
#define INTRO_ANIM_DURATION_OFF 0.1

static Action timer_idle_anim(Handle plugin, DataPack data)
{
	data.Reset();

	int client = GetClientOfUserId(data.ReadCell());
	if(client == 0) {
		return Plugin_Stop;
	}

	int sequence = data.ReadCell();
	animstate_do_event(client, PLAYERANIMEVENT_CUSTOM_SEQUENCE, sequence);

	return Plugin_Continue;
}

static int native_animstate_play_taunt_activity(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	int length = 0;
	GetNativeStringLength(2, length);
	char[] name = new char[++length];
	GetNativeString(2, name, length);

	bool long = GetNativeCell(3);

	Activity activity = view_as<BaseAnimating>(client).LookupActivity(name);
	if(activity == ACT_INVALID) {
		return 0;
	}

	int sequence = view_as<BaseAnimating>(client).SelectWeightedSequence(activity);
	if(sequence == -1) {
		return 0;
	}

	float duration = view_as<BaseAnimating>(client).SequenceDuration(sequence);
	if(duration == 0.0) {
		return 0;
	}

	animstate_set_taunt_state(client, long ? TFCondDuration_Infinite : duration, long ? TAUNT_LONG : TAUNT_SPECIAL, -1);
	animstate_do_event(client, PLAYERANIMEVENT_CUSTOM_SEQUENCE, sequence);

	if(long) {
		if(player_anim_idle_timer[client] != null) {
			KillTimer(player_anim_idle_timer[client]);
		}

		DataPack data;
		player_anim_idle_timer[client] = CreateDataTimer(duration-IDLE_ANIM_DURATION_OFF, timer_idle_anim, data, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		data.WriteCell(GetClientUserId(client));
		data.WriteCell(sequence);
	}

	return 1;
}

static Action timer_intro_anim(Handle timer, DataPack data)
{
	data.Reset();

	int client = GetClientOfUserId(data.ReadCell());
	if(client == 0) {
		return Plugin_Stop;
	}

	int sequence = data.ReadCell();
	float duration = data.ReadFloat();

	animstate_do_event(client, PLAYERANIMEVENT_CUSTOM_SEQUENCE, sequence);

	if(player_anim_idle_timer[client] != null) {
		KillTimer(player_anim_idle_timer[client]);
	}

	player_anim_idle_timer[client] = CreateDataTimer(duration-IDLE_ANIM_DURATION_OFF, timer_idle_anim, data, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	data.WriteCell(GetClientUserId(client));
	data.WriteCell(sequence);

	player_anim_intro_timer[client] = null;
	return Plugin_Continue;
}

static int native_animstate_play_taunt_activity_3_stage(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	int length = 0;
	GetNativeStringLength(2, length);
	char[] intro = new char[++length];
	GetNativeString(2, intro, length);

	length = 0;
	GetNativeStringLength(3, length);
	char[] idle = new char[++length];
	GetNativeString(3, idle, length);

	length = 0;
	GetNativeStringLength(4, length);
	char[] outro = new char[++length];
	GetNativeString(4, outro, length);

	Activity intro_activity = view_as<BaseAnimating>(client).LookupActivity(intro);
	Activity idle_activity = view_as<BaseAnimating>(client).LookupActivity(idle);
	Activity outro_activity = view_as<BaseAnimating>(client).LookupActivity(outro);
	if(intro_activity == ACT_INVALID ||
		idle_activity == ACT_INVALID ||
		outro_activity == ACT_INVALID) {
		return 0;
	}

	int intro_sequence = view_as<BaseAnimating>(client).SelectWeightedSequence(intro_activity);
	int idle_sequence = view_as<BaseAnimating>(client).SelectWeightedSequence(idle_activity);
	int outro_sequence = view_as<BaseAnimating>(client).SelectWeightedSequence(outro_activity);
	if(intro_sequence == -1 ||
		idle_sequence == -1 ||
		outro_sequence == -1) {
		return 0;
	}

	float intro_duration = view_as<BaseAnimating>(client).SequenceDuration(intro_sequence);
	float idle_duration = view_as<BaseAnimating>(client).SequenceDuration(idle_sequence);
	float outro_duration = view_as<BaseAnimating>(client).SequenceDuration(outro_sequence);
	if(intro_duration == 0.0 ||
		idle_duration == 0.0 ||
		outro_duration == 0.0) {
		return 0;
	}

	animstate_set_taunt_state(client, TFCondDuration_Infinite, TAUNT_LONG, -1);
	animstate_do_event(client, PLAYERANIMEVENT_CUSTOM_SEQUENCE, intro_sequence);

	if(player_anim_intro_timer[client] != null) {
		KillTimer(player_anim_intro_timer[client]);
	}

	DataPack data;
	player_anim_intro_timer[client] = CreateDataTimer(intro_duration-INTRO_ANIM_DURATION_OFF, timer_intro_anim, data, TIMER_FLAG_NO_MAPCHANGE);
	data.WriteCell(GetClientUserId(client));
	data.WriteCell(idle_sequence);
	data.WriteFloat(idle_duration);

	return 1;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("animstate");
	CreateNative("animstate_do_event", native_animstate_do_event);
	CreateNative("animstate_play_sequence", native_animstate_play_sequence);
	CreateNative("animstate_play_gesture", native_animstate_play_gesture);
	CreateNative("animstate_set_taunt_state", native_animstate_set_taunt_state);
	CreateNative("animstate_is_allowed_to_taunt", native_animstate_is_allowed_to_taunt);
	CreateNative("animstate_cancel_taunt", native_animstate_cancel_taunt);
	CreateNative("animstate_play_taunt_from_item", native_animstate_play_taunt_from_item);
	CreateNative("animstate_play_taunt_activity", native_animstate_play_taunt_activity);
	CreateNative("animstate_play_taunt_activity_3_stage", native_animstate_play_taunt_activity_3_stage);
	return APLRes_Success;
}
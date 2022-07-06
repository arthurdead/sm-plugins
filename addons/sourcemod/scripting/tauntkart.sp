#include <sourcemod>
#include <tf2>
#include <proxysend>
#include <dhooks>
#include <tf2_stocks>
#include <tf2items>
#include <tf_econ_data>
#include <bit>
#include <morecolors>
#include <stocksoup/memory>
#include <sdkhooks>
#include <svb-game-translations>

#define DEBUG

#define TKART_CON_PREFIX "[TKART] "
#define TKART_CHAT_PREFIX "{dodgerblue}[TKART]{default} "

#define TF2_MAXPLAYERS 33

#define PLAYERANIMEVENT_CUSTOM_GESTURE 20

#define ACT_KART_ACTION_DASH 1860

#define TAUNT_M2_REMAP_IDX 1162

static int tauntkart[TF2_MAXPLAYERS+1] = {-1, ...};

static Handle dummy_item_view;
static int CEconEntity_m_Item_offset = -1;

static Handle CTFPlayer_IsAllowedToTaunt;
static Handle CTFPlayer_CancelTaunt;
static Handle CTFPlayer_PlayTauntSceneFromItem;

static int CTFPlayer_m_Shared_offset = -1;

static StringMap taunt_name_map;
static Menu tauntkart_menu;

public void OnPluginStart()
{
	GameData gamedata = new GameData("tauntkart");
	if(gamedata == null) {
		SetFailState("Gamedata not found.");
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

	DynamicDetour tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::IsAllowedToTaunt");
	if(!tmp || !tmp.Enable(Hook_Pre, CTFPlayer_IsAllowedToTaunt_detour)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::IsAllowedToTaunt");
		delete gamedata;
		return;
	}
	if(!tmp.Enable(Hook_Post, CTFPlayer_IsAllowedToTaunt_detour_post)) {
		SetFailState("Failed to enable post detour for CTFPlayer::IsAllowedToTaunt");
		delete gamedata;
		return;
	}

	tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::ShouldStopTaunting");
	if(!tmp || !tmp.Enable(Hook_Pre, CTFPlayer_ShouldStopTaunting_detour)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::ShouldStopTaunting");
		delete gamedata;
		return;
	}

	tmp = DynamicDetour.FromConf(gamedata, "CTFPlayerShared::StunPlayer");
	if(!tmp || !tmp.Enable(Hook_Pre, CTFPlayerShared_StunPlayer_detour)) {
		SetFailState("Failed to enable pre detour for CTFPlayerShared::StunPlayer");
		delete gamedata;
		return;
	}
	if(!tmp.Enable(Hook_Post, CTFPlayerShared_StunPlayer_detour_post)) {
		SetFailState("Failed to enable pre detour for CTFPlayerShared::StunPlayer");
		delete gamedata;
		return;
	}

	tmp = DynamicDetour.FromConf(gamedata, "CTFPlayer::StopTaunt");
	if(!tmp || !tmp.Enable(Hook_Pre, CTFPlayer_StopTaunt_detour)) {
		SetFailState("Failed to enable pre detour for CTFPlayer::StopTaunt");
		delete gamedata;
		return;
	}

	delete gamedata;

	CEconEntity_m_Item_offset = FindSendPropInfo("CEconEntity", "m_Item");

	CTFPlayer_m_Shared_offset = FindSendPropInfo("CTFPlayer", "m_Shared");

	dummy_item_view = TF2Items_CreateItem(OVERRIDE_ALL|PRESERVE_ATTRIBUTES|FORCE_GENERATION);
	TF2Items_SetClassname(dummy_item_view, "tf_wearable_vm");
	TF2Items_SetItemIndex(dummy_item_view, 65535);
	TF2Items_SetQuality(dummy_item_view, 0);
	TF2Items_SetLevel(dummy_item_view, 0);
	TF2Items_SetNumAttributes(dummy_item_view, 0);

	AddTempEntHook("PlayerAnimEvent", PlayerAnimEvent);

	RegConsoleCmd("sm_tkart", sm_tkart);
	RegConsoleCmd("sm_tauntkart", sm_tkart);

	taunt_name_map = new StringMap();

	tauntkart_menu = new Menu(menuhandler_tauntkart);
	tauntkart_menu.SetTitle("Tauntkart");

	add_taunt_to_menu(1157);
	add_taunt_to_menu(1162);
	add_taunt_to_menu(1168);
	add_taunt_to_menu(1172);
	add_taunt_to_menu(1174);
	add_taunt_to_menu(1175);
	add_taunt_to_menu(1196);
	add_taunt_to_menu(1197);
	add_taunt_to_menu(30671);
	add_taunt_to_menu(30672);
	add_taunt_to_menu(30763);
	add_taunt_to_menu(30840);
	add_taunt_to_menu(30845);
	add_taunt_to_menu(30919);
	add_taunt_to_menu(30920);
	add_taunt_to_menu(31155);
	add_taunt_to_menu(31156);
	add_taunt_to_menu(31160);
	add_taunt_to_menu(31203);
	add_taunt_to_menu(31239);
}

static char tmp_taunt_name[512];

static void add_taunt_to_menu(int defidx)
{
	if(!TF2Econ_GetLocalizedItemName(defidx, tmp_taunt_name, sizeof(tmp_taunt_name))) {
		return;
	}

	SVBGameTranslations_GetTranslation(tmp_taunt_name, "english", tmp_taunt_name, sizeof(tmp_taunt_name));

	ReplaceStringEx(tmp_taunt_name, sizeof(tmp_taunt_name), "Taunt: ", "");
	ReplaceStringEx(tmp_taunt_name, sizeof(tmp_taunt_name), "The ", "");

	char str[5];
	pack_int_in_str(defidx, str);

	taunt_name_map.SetString(str, tmp_taunt_name);

	tauntkart_menu.AddItem(str, tmp_taunt_name);
}

static void get_taunt_name(int defidx, char[] name, int len)
{
	char str[5];
	pack_int_in_str(defidx, str);

	taunt_name_map.GetString(str, name, len);
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			remove_tauntkart(i);
		}
	}
}

static bool in_stun_call = false;

static MRESReturn CTFPlayerShared_StunPlayer_detour(Address pThis, DHookParam hParams)
{
	in_stun_call = true;

	Address player_addr = (view_as<Address>(view_as<int>(pThis) - CTFPlayer_m_Shared_offset));
	int client = GetEntityFromAddress(player_addr);

	if(tauntkart[client] != -1) {
		int iStunFlags = hParams.Get(3);
		iStunFlags &= ~(TF_STUNFLAG_THIRDPERSON|TF_STUNFLAG_BONKSTUCK);
		hParams.Set(3, iStunFlags);
		return MRES_ChangedHandled;
	}

	return MRES_Ignored;
}

static MRESReturn CTFPlayerShared_StunPlayer_detour_post(Address pThis, DHookParam hParams)
{
	in_stun_call = false;
	return MRES_Ignored;
}

static MRESReturn CTFPlayer_StopTaunt_detour(int pThis)
{
	if(in_stun_call) {
		if(tauntkart[pThis] != -1) {
			return MRES_Supercede;
		}
	}
	return MRES_Ignored;
}

static int tempgroundent = 0;
static int tempwaterlevel = 0;

static MRESReturn CTFPlayer_IsAllowedToTaunt_detour(int pThis, DHookReturn hReturn)
{
	if(tauntkart[pThis] != -1) {
		tempgroundent = GetEntPropEnt(pThis, Prop_Send, "m_hGroundEntity");
		tempwaterlevel = GetEntProp(pThis, Prop_Send, "m_nWaterLevel");
		SetEntPropEnt(pThis, Prop_Send, "m_hGroundEntity", 0);
		SetEntProp(pThis, Prop_Send, "m_nWaterLevel", 0);
	}
	return MRES_Ignored;
}

static MRESReturn CTFPlayer_IsAllowedToTaunt_detour_post(int pThis, DHookReturn hReturn)
{
	if(tauntkart[pThis] != -1) {
		SetEntPropEnt(pThis, Prop_Send, "m_hGroundEntity", tempgroundent);
		SetEntProp(pThis, Prop_Send, "m_nWaterLevel", tempwaterlevel);
	}
	return MRES_Ignored;
}

static MRESReturn CTFPlayer_ShouldStopTaunting_detour(int pThis, DHookReturn hReturn)
{
	if(tauntkart[pThis] != -1) {
		hReturn.Value = false;
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

public void OnMapStart()
{
	PrecacheModel("models/player/items/taunts/bumpercar/parts/bumpercar.mdl");
	PrecacheModel("models/props_halloween/bumpercar_cage.mdl");

	PrecacheScriptSound("BumperCar.Spawn");
	PrecacheScriptSound("BumperCar.SpawnFromLava");
	PrecacheScriptSound("BumperCar.GoLoop");
	PrecacheScriptSound("BumperCar.Screech");
	PrecacheScriptSound("BumperCar.HitGhost");
	PrecacheScriptSound("BumperCar.Bump");
	PrecacheScriptSound("BumperCar.BumpHard");
	PrecacheScriptSound("BumperCar.BumpIntoAir");
	PrecacheScriptSound("BumperCar.SpeedBoostStart");
	PrecacheScriptSound("BumperCar.SpeedBoostStop");
	PrecacheScriptSound("BumperCar.Jump");
	PrecacheScriptSound("BumperCar.JumpLand");

	PrecacheScriptSound("sf14.Merasmus.DuckHunt.BonusDucks");

	//PrecacheParticleSystem("kartimpacttrail");
	//PrecacheParticleSystem("kart_dust_trail_red");
	//PrecacheParticleSystem("kart_dust_trail_blue");
	//PrecacheParticleSystem("kartdamage_4");
}

static Action proxysend_kartcond(int entity, const char[] prop, int &value, int element, int client)
{
	value &= ~get_bit_for_cond(TFCond_HalloweenKart);
	return Plugin_Changed;
}

static Action proxysend_kartdashcond(int entity, const char[] prop, int &value, int element, int client)
{
	value &= ~get_bit_for_cond(TFCond_HalloweenKartDash);
	return Plugin_Changed;
}

static Action proxysend_tauntdef(int entity, const char[] prop, int &value, int element, int client)
{
	value = TAUNT_M2_REMAP_IDX;
	return Plugin_Changed;
}

static void tauntkart_removed(int client)
{
	proxysend_unhook(client, "m_iTauntItemDefIndex", proxysend_tauntdef);
	proxysend_unhook_cond(client, TFCond_HalloweenKart, proxysend_kartcond);
	proxysend_unhook_cond(client, TFCond_HalloweenKartDash, proxysend_kartdashcond);
	SetEntProp(client, Prop_Send, "m_bAllowMoveDuringTaunt", 0);
	tauntkart[client] = -1;
}

static void remove_tauntkart(int client)
{
	if(tauntkart[client] != -1) {
		tauntkart_removed(client);
		SDKCall(CTFPlayer_CancelTaunt, client);
		TF2_RemoveCondition(client, TFCond_HalloweenKart);
	}
}

public void OnClientDisconnect(int client)
{
	tauntkart[client] = -1;
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	if(tauntkart[client] != -1) {
		switch(condition) {
			case TFCond_Taunting: {
				tauntkart_removed(client);
				TF2_RemoveCondition(client, TFCond_HalloweenKart);
			}
			case TFCond_HalloweenKart: {
				tauntkart_removed(client);
				SDKCall(CTFPlayer_CancelTaunt, client);
			}
		}
	}
}

static Action PlayerAnimEvent(const char[] te_name, const int[] Players, int numClients, float delay)
{
	int m_iPlayerIndex = TE_ReadNum("m_iPlayerIndex");
	int m_iEvent = TE_ReadNum("m_iEvent");
	int m_nData = TE_ReadNum("m_nData");

	if(tauntkart[m_iPlayerIndex] != -1) {
		if(m_iEvent == PLAYERANIMEVENT_CUSTOM_GESTURE) {
			if(m_nData == ACT_KART_ACTION_DASH) {
				return Plugin_Stop;
			}
		}
	}

	return Plugin_Continue;
}

static bool play_taunt(int client, int defidx)
{
	TF2Items_SetItemIndex(dummy_item_view, defidx);
	int entity = TF2Items_GiveNamedItem(client, dummy_item_view);
	Address item_view = (GetEntityAddress(entity) + view_as<Address>(CEconEntity_m_Item_offset));
	bool played = SDKCall(CTFPlayer_PlayTauntSceneFromItem, client, item_view);
	RemoveEntity(entity);
	return played;
}

static bool taunt_has_m2_remap(int defidx)
{
	switch(defidx) {
		case 1162, 30919, 30920, 31156, 31239: {
			return true;
		}
	}

	return false;
}

static bool taunt_needs_move(int defidx)
{
	switch(defidx) {
		case 1168, 30763: {
			return true;
		}
	}

	return false;
}

static bool set_tauntkart(int client, int defidx)
{
	if(tauntkart[client] != -1 ||
		TF2_IsPlayerInCondition(client, TFCond_HalloweenKart) ||
		TF2_IsPlayerInCondition(client, TFCond_Taunting) ||
		!SDKCall(CTFPlayer_IsAllowedToTaunt, client)) {
		return false;
	}

	if(!play_taunt(client, defidx)) {
		return false;
	}

	tauntkart[client] = defidx;

	if(taunt_needs_move(defidx)) {
		SetEntProp(client, Prop_Send, "m_bAllowMoveDuringTaunt", 1);
	}
	if(!taunt_has_m2_remap(defidx)) {
		proxysend_hook(client, "m_iTauntItemDefIndex", proxysend_tauntdef, false);
	}

	proxysend_hook_cond(client, TFCond_HalloweenKart, proxysend_kartcond, false);
	proxysend_hook_cond(client, TFCond_HalloweenKartDash, proxysend_kartdashcond, false);

	SetEntProp(client, Prop_Send, "m_iKartHealth", GetEntProp(client, Prop_Data, "m_iHealth"));
	TF2_AddCondition(client, TFCond_HalloweenKart);

	return true;
}

static int menuhandler_tauntkart(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		char str[5];
		menu.GetItem(param2, str, sizeof(str));

		int defidx = unpack_int_in_str(str);

		if(!set_tauntkart(param1, defidx)) {
			get_taunt_name(defidx, tmp_taunt_name, sizeof(tmp_taunt_name));

			CPrintToChat(param1, TKART_CHAT_PREFIX ... "Failed to start taunt: %s", tmp_taunt_name);
		}
	}

	return 0;
}

static Action sm_tkart(int client, int args)
{
	if(tauntkart[client] != -1) {
		remove_tauntkart(client);
	} else {
		tauntkart_menu.Display(client, MENU_TIME_FOREVER);
	}

	return Plugin_Handled;
}
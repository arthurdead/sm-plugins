#include <sourcemod>
#include <economy>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <playermodel2>

#define TF2_MAXPLAYERS 33

static int CTFPlayerShared_m_bPhaseFXOn_offset = -1;
static int CTFPlayer_m_Shared_offset = -1;

static Handle CTFPlayerShared_AddPhaseEffects;
static Handle CTFPlayerShared_RemovePhaseEffects;

static ArrayList player_trails[TF2_MAXPLAYERS+1];

static bool player_has_trail[TF2_MAXPLAYERS+1];

static bool late_loaded;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	late_loaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	GameData gamedata = new GameData("economy_trail");
	if(gamedata == null) {
		SetFailState("Gamedata not found.");
		return;
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayerShared::AddPhaseEffects");
	CTFPlayerShared_AddPhaseEffects = EndPrepSDKCall();
	if(CTFPlayerShared_AddPhaseEffects == null) {
		SetFailState("Failed to create SDKCall for CTFPlayerShared::AddPhaseEffects.");
		delete gamedata;
		return;
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayerShared::RemovePhaseEffects");
	CTFPlayerShared_RemovePhaseEffects = EndPrepSDKCall();
	if(CTFPlayerShared_RemovePhaseEffects == null) {
		SetFailState("Failed to create SDKCall for CTFPlayerShared::RemovePhaseEffects.");
		delete gamedata;
		return;
	}

	int offset = FindSendPropInfo("CTFPlayerShared", "m_nNumHealers");
	CTFPlayerShared_m_bPhaseFXOn_offset = offset - gamedata.GetOffset("CTFPlayerShared::m_bPhaseFXOn");

	delete gamedata;

	CTFPlayer_m_Shared_offset = FindSendPropInfo("CTFPlayer", "m_Shared");

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void econ_cache_item(const char[] classname, int item_idx, StringMap settings)
{
	
}

public Action econ_items_conflict(const char[] classname1, int item1_idx, const char[] classname2, int item2_idx)
{
	return StrEqual(classname1, classname2) ? Plugin_Handled : Plugin_Continue;
}

static Action trail_transmit(int entity, int client)
{
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hAttachedToEntity");

	if(client == owner) {
		if(!pm2_is_thirdperson(client)) {
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

static void frame_trail_spawn(int entity)
{
	entity = EntRefToEntIndex(entity);
	if(entity == -1) {
		return;
	}

	int owner = GetEntPropEnt(entity, Prop_Send, "m_hAttachedToEntity");
	if(owner >= 1 && owner <= MaxClients) {
		//SDKHook(entity, SDKHook_SetTransmit, trail_transmit);
		player_trails[owner].Push(EntIndexToEntRef(entity));
	}
}

static void trail_spawn(int entity)
{
	RequestFrame(frame_trail_spawn, EntIndexToEntRef(entity));
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "env_spritetrail")) {
		SDKHook(entity, SDKHook_SpawnPost, trail_spawn);
	}
}

static void toggle_trail(int client, bool on)
{
	Address player_addr = GetEntityAddress(client);
	Address m_Shared = (player_addr + view_as<Address>(CTFPlayer_m_Shared_offset));
	Address m_bPhaseFXOn_addr = (m_Shared + view_as<Address>(CTFPlayerShared_m_bPhaseFXOn_offset));

	if(view_as<bool>(LoadFromAddress(m_bPhaseFXOn_addr, NumberType_Int8))) {
		SDKCall(CTFPlayerShared_RemovePhaseEffects, m_Shared);
	}

	remove_all_trails(client);

	if(on) {
		if(!view_as<bool>(LoadFromAddress(m_bPhaseFXOn_addr, NumberType_Int8))) {
			SDKCall(CTFPlayerShared_AddPhaseEffects, m_Shared);
		}
	}
}

public void OnPluginEnd()
{
	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			toggle_trail(i, false);
		}
	}
}

public void OnClientPutInServer(int client)
{
	player_trails[client] = new ArrayList();
}

static void remove_all_trails(int client)
{
	if(player_trails[client]) {
		int len = player_trails[client].Length;
		for(int i = 0; i < len; ++i) {
			int ref = player_trails[client].Get(i);
			int ent = EntRefToEntIndex(ref);
			if(ent != -1) {
				RemoveEntity(ent);
			}
		}

		player_trails[client].Clear();
	}
}

public void OnClientDisconnect(int client)
{
	player_has_trail[client] = false;

	remove_all_trails(client);

	delete player_trails[client];
}

public void pm2_model_changed(int client)
{
	if(player_has_trail[client]) {
		toggle_trail(client, false);
		toggle_trail(client, true);
	}
}

public void econ_handle_item(int client, const char[] classname, int item_idx, int inv_idx, econ_item_action action)
{
	if(StrEqual(classname, "phase_trail")) {
		switch(action) {
			case econ_item_equip: {
				player_has_trail[client] = true;
				if(econ_player_state_valid(client)) {
					toggle_trail(client, false);
					toggle_trail(client, true);
				}
			}
			case econ_item_apply: {
				toggle_trail(client, false);
				toggle_trail(client, true);
			}
			case econ_item_remove: {
				if(IsClientInGame(client)) {
					toggle_trail(client, false);
				}
			}
			case econ_item_unequip: {
				player_has_trail[client] = false;
				if(IsClientInGame(client)) {
					toggle_trail(client, false);
				}
			}
		}
	}
}

static void plr_cat_registered(int idx, any data)
{
	{
		KeyValues item_kv = new KeyValues("");
		item_kv.SetString("name", "Phase");
		item_kv.SetString("classname", "phase_trail");
		item_kv.SetNum("price", 600);

		econ_get_or_register_item(idx, item_kv, INVALID_FUNCTION, 0);

		delete item_kv;
	}
}

static void trail_cat_registered(int idx, any data)
{
	econ_get_or_register_category("Player", idx, plr_cat_registered, 0);
}

public void econ_loaded()
{
	econ_get_or_register_category("Trails", ECON_INVALID_CATEGORY, trail_cat_registered, 0);
}

public void econ_register_item_classes()
{
	econ_register_item_class("phase_trail", true);
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "economy")) {
		if(late_loaded) {
			econ_register_item_classes();
		}
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "economy")) {
		
	}
}

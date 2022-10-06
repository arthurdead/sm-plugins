#include <sourcemod>
#include <tf_custom_attributes>
#include <proxysend>
#include <sdkhooks>
#include <sdktools>

static bool late_loaded;

enum struct WeaponProxysendInfo
{
	int ref;
	int itemdef;
	TFClassType class;
}

static ArrayList weapons_infos;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	late_loaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	weapons_infos = new ArrayList(sizeof(WeaponProxysendInfo));

	if(late_loaded) {
		int entity = -1;
		while((entity = FindEntityByClassname(entity, "*")) != -1) {
			if(HasEntProp(entity, Prop_Send, "m_iItemDefinitionIndex")) {
				frame_item_spawn(EntIndexToEntRef(entity));
			}
			if(entity >= 1 && entity <= MaxClients) {
				OnClientPutInServer(entity);
			}
		}
	}
}

static Action proxysend_itemdef(int entity, const char[] prop, int &value, int element, int client)
{
	int idx = weapons_infos.FindValue(EntIndexToEntRef(entity), WeaponProxysendInfo::ref);
	if(idx != -1) {
		int new_value = weapons_infos.Get(idx, WeaponProxysendInfo::itemdef);
		if(new_value != -1) {
			value = new_value;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

static Action proxysend_class(int entity, const char[] prop, TFClassType &value, int element, int client)
{
	if(client != entity) {
		return Plugin_Continue;
	}
	int weapon = GetEntPropEnt(entity, Prop_Send, "m_hActiveWeapon");
	if(weapon == -1) {
		return Plugin_Continue;
	}
	int idx = weapons_infos.FindValue(EntIndexToEntRef(weapon), WeaponProxysendInfo::ref);
	if(idx != -1) {
		TFClassType new_value = weapons_infos.Get(idx, WeaponProxysendInfo::class);
		if(new_value != TFClass_Unknown) {
			value = new_value;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	proxysend_hook(client, "m_iClass", proxysend_class, true);
}

static void frame_item_spawn(int entity)
{
	entity = EntRefToEntIndex(entity);
	if(entity == -1) {
		return;
	}

	WeaponProxysendInfo info;
	info.ref = EntIndexToEntRef(entity);
	info.itemdef = TF2CustAttr_GetInt(entity, "proxysend_itemdef", -1);
	info.class = view_as<TFClassType>(TF2CustAttr_GetInt(entity, "proxysend_class", view_as<int>(TFClass_Unknown)));

	if(info.itemdef == -1 &&
		info.class == TFClass_Unknown) {
		return;
	}

	weapons_infos.PushArray(info, sizeof(WeaponProxysendInfo));

	if(info.itemdef != -1) {
		proxysend_hook(entity, "m_iItemDefinitionIndex", proxysend_itemdef, false);
	}
}

static void item_spawn(int entity)
{
	RequestFrame(frame_item_spawn, EntIndexToEntRef(entity));
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(HasEntProp(entity, Prop_Send, "m_iItemDefinitionIndex")) {
		SDKHook(entity, SDKHook_SpawnPost, item_spawn);
	}
}

public void OnEntityDestroyed(int entity)
{
	if(entity == -1) {
		return;
	}

	if(entity & (1 << 31)) {
		entity = EntRefToEntIndex(entity);
	}

	int idx = weapons_infos.FindValue(EntIndexToEntRef(entity), WeaponProxysendInfo::ref);
	if(idx != -1) {
		weapons_infos.Erase(idx);
	}
}

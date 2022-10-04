#include <sourcemod>
#include <tf_custom_attributes>
#include <proxysend>
#include <sdkhooks>
#include <sdktools>

static bool late_loaded;

static ArrayList itemdefs;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	late_loaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	itemdefs = new ArrayList(2);

	if(late_loaded) {
		int entity = -1;
		while((entity = FindEntityByClassname(entity, "*")) != -1) {
			if(HasEntProp(entity, Prop_Send, "m_iItemDefinitionIndex")) {
				frame_item_spawn(EntIndexToEntRef(entity));
			}
		}
	}
}

static Action proxysend_itemdef(int entity, const char[] prop, int &value, int element, int client)
{
	int idx = itemdefs.FindValue(EntIndexToEntRef(entity));
	if(idx != -1) {
		value = itemdefs.Get(idx, 1);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

static void frame_item_spawn(int entity)
{
	entity = EntRefToEntIndex(entity);
	if(entity == -1) {
		return;
	}

	int itemdef = TF2CustAttr_GetInt(entity, "proxysend_itemdef", -1);
	if(itemdef != -1) {
		int idx = itemdefs.Push(EntIndexToEntRef(entity));
		itemdefs.Set(idx, itemdef, 1);
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

	int idx = itemdefs.FindValue(EntIndexToEntRef(entity));
	if(idx != -1) {
		itemdefs.Erase(idx);
	}
}

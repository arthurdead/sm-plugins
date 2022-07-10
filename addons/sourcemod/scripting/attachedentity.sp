#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

static bool late_loaded;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int length)
{
	late_loaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	if(late_loaded) {
		char classname[64];

		int entity = -1;
		while((entity = FindEntityByClassname(entity, "*")) != -1) {
			GetEntityClassname(entity, classname, sizeof(classname));
			OnEntityCreated(entity, classname);
		}
	}
}

static void spawn_post(int entity)
{
	SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", 1);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(HasEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity")) {
		SDKHook(entity, SDKHook_SpawnPost, spawn_post);
	}
}
#include <sourcemod>
#include <sdkhooks>
#include <teammanager>
#include <teammanager_gameplay>
#tryinclude <sendproxy>

//#define DEBUG

#define Gameplay_Default view_as<GameplayGroupType>(-1)
#define Gameplay_Mismatch view_as<GameplayGroupType>(-2)

enum struct GameplayInfo
{
	GameplayGroupType type;
	ArrayList players;
}

static ArrayList gameplaygroups;
static ArrayList playergameplaygroups[MAXPLAYERS+1];
static ArrayStack freeslots;
static ArrayList pluginmap;

static void remove_gameplaygroup(int idx)
{
	int len = gameplaygroups.Length;
	if(idx < 0 || idx >= len) {
		return;
	}
	GameplayInfo info;
	gameplaygroups.GetArray(idx, info, sizeof(GameplayInfo));
	if(idx == len-1) {
		delete info.players;
		gameplaygroups.Erase(idx);
	} else {
		while(info.players.Length) {
			info.players.Erase(0);
		}
		freeslots.Push(idx);
	}
}

public void OnNotifyPluginUnloaded(Handle plugin)
{
	int idx = pluginmap.FindValue(plugin);
	if(idx != -1) {
		ArrayList list = pluginmap.Get(idx);
		pluginmap.Erase(idx);
		int len = list.Length;
		for(int i = 0; i < len; ++i) {
			idx = list.Get(i);
			remove_gameplaygroup(idx);
		}
		delete list;
	}
}

int native_TeamManager_NewGameplayGroup(Handle plugin, int params)
{
	GameplayInfo info;
	info.type = GetNativeCell(1);
	info.players = new ArrayList();
	int idx = -1;
	if(freeslots.Empty) {
		idx = gameplaygroups.PushArray(info, sizeof(GameplayInfo));
	} else {
		idx = freeslots.Pop();
		gameplaygroups.SetArray(idx, info, sizeof(GameplayInfo));
	}
	int plidx = pluginmap.FindValue(plugin);
	ArrayList list = null;
	if(plidx == -1) {
		list = new ArrayList();
	} else {
		list = pluginmap.Get(plidx);
	}
	list.Push(idx);
	return idx;
}

int native_TeamManager_RemoveGameplayGroup(Handle plugin, int params)
{
	int idx = GetNativeCell(1);
	remove_gameplaygroup(idx);
	return 0;
}

int native_TeamManager_AddPlayerToGameplayGroup(Handle plugin, int params)
{
	int client = GetNativeCell(1);

	int idx = GetNativeCell(2);
	if(idx < 0 || idx >= gameplaygroups.Length) {
		return ThrowNativeError(SP_ERROR_PARAM, "invalid gameplay group %i", idx);
	}

	GameplayInfo info;
	gameplaygroups.GetArray(idx, info, sizeof(GameplayInfo));

	int usrid = GetClientUserId(client);

	if(info.players.FindValue(usrid) == -1) {
		info.players.Push(usrid);
		playergameplaygroups[client].Push(idx);
	}

	return 0;
}

int native_TeamManager_RemovePlayerFromGameplayGroup(Handle plugin, int params)
{
	int client = GetNativeCell(1);
	int idx = GetNativeCell(2);
	if(idx < 0 || idx >= gameplaygroups.Length) {
		return 0;
	}

	GameplayInfo info;
	gameplaygroups.GetArray(idx, info, sizeof(GameplayInfo));

	idx = playergameplaygroups[client].FindValue(idx);
	if(idx != -1) {
		playergameplaygroups[client].Erase(idx);
	}

	int usrid = GetClientUserId(client);

	idx = info.players.FindValue(usrid);
	if(idx != -1) {
		info.players.Erase(idx);
	}

	return 0;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gameplaygroups = new ArrayList(sizeof(GameplayInfo));
	freeslots = new ArrayStack();
	pluginmap = new ArrayList();
	RegPluginLibrary("teammanager_gameplay");
	CreateNative("TeamManager_NewGameplayGroup", native_TeamManager_NewGameplayGroup);
	CreateNative("TeamManager_RemoveGameplayGroup", native_TeamManager_RemoveGameplayGroup);
	CreateNative("TeamManager_AddPlayerToGameplayGroup", native_TeamManager_AddPlayerToGameplayGroup);
	CreateNative("TeamManager_RemovePlayerFromGameplayGroup", native_TeamManager_RemovePlayerFromGameplayGroup);
	return APLRes_Success;
}

public void OnPluginStart()
{
#if defined DEBUG
	GameplayInfo tmpinfo;
	tmpinfo.type = Gameplay_Normal;
	tmpinfo.players = new ArrayList();
	gameplaygroups.PushArray(tmpinfo, sizeof(GameplayInfo));

	RegAdminCmd("sm_tg", sm_tg, ADMFLAG_ROOT);
#endif

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

#if defined DEBUG
static Action sm_tg(int client, int args)
{
	GameplayInfo info;
	gameplaygroups.GetArray(0, info, sizeof(GameplayInfo));

	int usrid = GetClientUserId(client);

	int idx = info.players.FindValue(usrid);
	if(idx == -1) {
		info.players.Push(usrid);
		PrintToChat(client, "added to gameplay group");
	} else {
		info.players.Erase(idx);
		PrintToChat(client, "removed to gameplay group");
	}

	return Plugin_Continue;
}
#endif

public void OnClientPutInServer(int client)
{
	playergameplaygroups[client] = new ArrayList();

	SDKHook(client, SDKHook_PostThinkPost, player_postthinkpost);
}

static void player_postthinkpost(int client)
{
	
}

public void OnClientDisconnect(int client)
{
	if(playergameplaygroups[client] != null) {
		int len = playergameplaygroups[client].Length;

		GameplayInfo info;

		for(int i = 0; i < len; ++i) {
			int idx = playergameplaygroups[client].Get(i);

			gameplaygroups.GetArray(idx, info, sizeof(GameplayInfo));

			int usrid = GetClientUserId(client);

			idx = info.players.FindValue(usrid);
			if(idx != -1) {
				info.players.Erase(idx);
			}
		}
		delete playergameplaygroups[client];
	}
}

static int get_building_owner(int entity)
{
	return GetEntPropEnt(entity, Prop_Send, "m_hBuilder");
}

static int get_weapon_owner(int entity)
{
	return GetEntPropEnt(entity, Prop_Send, "m_hOwner");
}

static int get_projectile_owner(int entity)
{
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hLauncher");
	if(owner != -1) {
		owner = get_weapon_owner(owner);
	}
	return owner;
}

static int get_entity_owner(int other)
{
	int other_owner = -1;

	if(other >= 1 && other <= MaxClients) {
		other_owner = other;
	} else {
		char classname[32];
		GetEntityClassname(other, classname, sizeof(classname));

		if(StrContains(classname, "obj_") != -1) {
			other_owner = get_building_owner(other);
		} else if(StrContains(classname, "tf_projectile") != -1) {
			other_owner = get_projectile_owner(other);
		} else if(StrContains(classname, "tf_weapon") != -1) {
			other_owner = get_weapon_owner(other);
		}
	}

	return other_owner;
}

static GameplayGroupType get_equal_group(int player1, int player2)
{
	int len1 = (playergameplaygroups[player1] == null ? 0 : playergameplaygroups[player1].Length);
	int len2 = (playergameplaygroups[player2] == null ? 0 : playergameplaygroups[player2].Length);

	if(len1 == 0 && len2 == 0) {
		return Gameplay_Default;
	}

	GameplayInfo info;

	for(int i = 0; i < len1; ++i) {
		int idx = playergameplaygroups[player1].Get(i);

		if(playergameplaygroups[player2].FindValue(idx) != -1) {
			gameplaygroups.GetArray(idx, info, sizeof(GameplayInfo));
			return info.type;
		}
	}

	return Gameplay_Mismatch;
}

public Action TeamManager_CanHeal(int entity, int other, HealSource source)
{
	int owner = -1;
	int other_owner = get_entity_owner(other);

	switch(source) {
		case HEAL_MEDIGUN, HEAL_WRENCH: {
			owner = get_weapon_owner(entity);
		}
		case HEAL_DISPENSER: {
			owner = get_building_owner(entity);
		}
		case HEAL_PROJECTILE: {
			owner = get_projectile_owner(entity);
		}
	}

	if(owner != -1 && other_owner != -1) {
		GameplayGroupType type = get_equal_group(owner, other_owner);

	#if defined DEBUG
		PrintToServer("TeamManager_CanHeal %i", type);
	#endif

		switch(type) {
			case Gameplay_Friendly: {
				return Plugin_Changed;
			}
			case Gameplay_FriendlyFire: {
				return Plugin_Handled;
			}
			case Gameplay_Mismatch: {
				return Plugin_Handled;
			}
		}
	}

	return Plugin_Continue;
}

public Action TeamManager_CanDamage(int attacker, int victim, DamageSource source)
{
	int owner = -1;
	int other_owner = -1;

	switch(source) {
		case DAMAGE_PLAYER: {
			owner = get_entity_owner(attacker);
			other_owner = victim;
		}
		case DAMAGE_PROJECTILE: {
			owner = get_projectile_owner(attacker);
			other_owner = get_entity_owner(victim);
		}
	}

	if(owner == other_owner) {
		return Plugin_Continue;
	}

	if(owner != -1 && other_owner != -1) {
		GameplayGroupType type = get_equal_group(owner, other_owner);

	#if defined DEBUG
		PrintToServer("TeamManager_CanDamage %i", type);
	#endif

		switch(type) {
			case Gameplay_Friendly: {
				return Plugin_Handled;
			}
			case Gameplay_FriendlyFire: {
				return Plugin_Changed;
			}
			case Gameplay_Mismatch: {
				return Plugin_Handled;
			}
		}
	}

	return Plugin_Continue;
}

public Action TeamManager_CanGetJarated(int attacker, int victim)
{
	GameplayGroupType type = get_equal_group(attacker, victim);

#if defined DEBUG
	PrintToServer("TeamManager_CanGetJarated %i", type);
#endif

	switch(type) {
		case Gameplay_Friendly: {
			return Plugin_Changed;
		}
		case Gameplay_FriendlyFire: {
			return Plugin_Handled;
		}
		case Gameplay_Mismatch: {
			return Plugin_Stop;
		}
	}

	return Plugin_Continue;
}

public Action TeamManager_InSameTeam(int entity, int other)
{
	int owner = get_entity_owner(entity);
	int other_owner = get_entity_owner(other);

	if(owner != -1 && other_owner != -1) {
		GameplayGroupType type = get_equal_group(owner, other_owner);

	#if defined DEBUG && 0
		PrintToServer("TeamManager_InSameTeam %i %i %i", type, owner, other_owner);
	#endif

		switch(type) {
			case Gameplay_Friendly: {
				return Plugin_Changed;
			}
			case Gameplay_FriendlyFire: {
				return Plugin_Handled;
			}
			case Gameplay_Mismatch: {
				return Plugin_Changed;
			}
		}
	}

	return Plugin_Continue;
}

public Action TeamManager_CanAirblast(int weapon, int owner, int other)
{
	int other_owner = get_entity_owner(other);

	if(other_owner != -1) {
		GameplayGroupType type = get_equal_group(owner, other_owner);

	#if defined DEBUG
		PrintToServer("TeamManager_CanAirblast %i %i %i", type, owner, other_owner);
	#endif

		switch(type) {
			case Gameplay_Friendly: {
				return Plugin_Changed;
			}
			case Gameplay_FriendlyFire: {
				return Plugin_Changed;
			}
			case Gameplay_Mismatch: {
				return Plugin_Handled;
			}
		}
	}

	return Plugin_Continue;
}

public Action TeamManager_CanBackstab(int weapon, int other)
{
	int owner = get_weapon_owner(weapon);
	int other_owner = get_entity_owner(other);

	if(other_owner != -1) {
		GameplayGroupType type = get_equal_group(owner, other_owner);

	#if defined DEBUG
		PrintToServer("TeamManager_CanBackstab %i", type);
	#endif

		switch(type) {
			case Gameplay_Friendly: {
				return Plugin_Handled;
			}
			case Gameplay_FriendlyFire: {
				return Plugin_Changed;
			}
			case Gameplay_Mismatch: {
				return Plugin_Handled;
			}
		}
	}

	return Plugin_Continue;
}
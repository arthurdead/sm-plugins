#include <sourcemod>
#include <bit>
#include <economy>

#include <morecolors>
#undef COLOR_GREEN
#if 1
	#include <ccc>
#else
enum CCC_ColorType
{
	CCC_TagColor,
	CCC_NameColor,
	CCC_ChatColor
};

static void CCC_SetTag(int client, const char[] tag) {}
static void CCC_ResetTag(int client) {}

static void CCC_SetColor(int client, CCC_ColorType type, int value, bool alpha) {}
static void CCC_ResetColor(int client, CCC_ColorType type) {}
#endif

#define TF2_MAXPLAYERS 33

#define INVALID_COLOR -1

static char player_tag[TF2_MAXPLAYERS+1][MAX_NAME_LENGTH];
static int player_chat_colors[TF2_MAXPLAYERS+1][3];

static bool late_loaded;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	late_loaded = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	
}

public void econ_cache_item(const char[] classname, int item_idx, StringMap settings)
{
	
}

public Action econ_items_conflict(const char[] classname1, int item1_idx, const char[] classname2, int item2_idx)
{
	return StrEqual(classname1, classname2) ? Plugin_Handled : Plugin_Continue;
}

static int get_color_item_value(int item_idx)
{
	char name[ECON_MAX_ITEM_NAME];
	econ_get_item_name(item_idx, name, ECON_MAX_ITEM_NAME);

	return get_color_value(name);
}

static int get_color_value(const char[] name)
{
	CCheckTrie();

	int value;
	GetTrieValue(CTrie, name, value);

	return value;
}

public void OnClientDisconnect(int client)
{
	player_tag[client][0] = '\0';

	player_chat_colors[client][CCC_TagColor] = INVALID_COLOR;
	player_chat_colors[client][CCC_NameColor] = INVALID_COLOR;
	player_chat_colors[client][CCC_ChatColor] = INVALID_COLOR;
}

public void econ_handle_item(int client, const char[] classname, int item_idx, int inv_idx, econ_item_action action)
{
	if(StrEqual(classname, "chat_tag")) {
		switch(action) {
			case econ_item_apply: {
				if(player_tag[client][0] != '\0') {
					CCC_SetTag(client, player_tag[client]);
				} else {
					CCC_ResetTag(client);
				}
			}
			case econ_item_equip: {
				char name[ECON_MAX_ITEM_NAME];
				econ_get_item_name(item_idx, name, ECON_MAX_ITEM_NAME);
				StrCat(name, ECON_MAX_ITEM_NAME, " ");

				strcopy(player_tag[client], MAX_NAME_LENGTH, name);

				if(IsClientInGame(client)) {
					CCC_SetTag(client, name);
				}
			}
			case econ_item_unequip: {
				player_tag[client][0] = '\0';
				if(IsClientInGame(client)) {
					CCC_ResetTag(client);
				}
			}
		}
	} else {
		CCC_ColorType color = view_as<CCC_ColorType>(INVALID_COLOR);

		if(StrEqual(classname, "chat_color_tag")) {
			color = CCC_TagColor;
		} else if(StrEqual(classname, "chat_color")) {
			color = CCC_ChatColor;
		} else if(StrEqual(classname, "chat_color_name")) {
			color = CCC_NameColor;
		} else {
			return;
		}

		switch(action) {
			case econ_item_apply: {
				if(player_chat_colors[client][color] != INVALID_COLOR) {
					CCC_SetColor(client, color, player_chat_colors[client][color], false);
				} else {
					CCC_ResetColor(client, color);
				}
			}
			case econ_item_equip: {
				player_chat_colors[client][color] = get_color_item_value(item_idx);

				if(IsClientInGame(client)) {
					CCC_SetColor(client, color, player_chat_colors[client][color], false);
				}
			}
			case econ_item_unequip: {
				if(IsClientInGame(client)) {
					CCC_ResetColor(client, color);
				}
				player_chat_colors[client][color] = INVALID_COLOR;
			}
		}
	}
}

static void chat_clr_item_registered(int idx, int cat_idx)
{
	econ_add_item_to_category(idx, cat_idx);
}

static void chat_clr_cat_registered(int cat, int type)
{
	CCheckTrie();

	char name[ECON_MAX_ITEM_NAME];

	Handle snap = CreateTrieSnapshot(CTrie);

	KeyValues item_kv = new KeyValues("");

	int len = GetTrieSize(CTrie);
	for(int i = 0; i < len; ++i) {
		GetTrieSnapshotKey(snap, i, name, sizeof(name));

		int value;
		GetTrieValue(CTrie, name, value);

		if(econ_find_item(cat, name) != ECON_INVALID_ITEM) {
			continue;
		}

		item_kv.SetString("name", name);

		switch(type) {
			case 0: {
				item_kv.SetString("classname", "chat_color_tag");
				item_kv.SetNum("price", 50);
				econ_register_item(item_kv, chat_clr_item_registered, cat);
			}
			case 1: {
				item_kv.SetString("classname", "chat_color");
				item_kv.SetNum("price", 100);
				econ_register_item(item_kv, chat_clr_item_registered, cat);
			}
			case 2: {
				item_kv.SetString("classname", "chat_color_name");
				item_kv.SetNum("price", 150);
				econ_register_item(item_kv, chat_clr_item_registered, cat);
			}
		}
	}

	delete item_kv;

	CloseHandle(snap);
}

static void chat_clrs_cat_registered(int cat, any data)
{
	econ_get_or_register_category("Tag", cat, chat_clr_cat_registered, 0);
	econ_get_or_register_category("Chat", cat, chat_clr_cat_registered, 1);
	econ_get_or_register_category("Name", cat, chat_clr_cat_registered, 2);
}

static void chat_cat_registered(int cat, any data)
{
	econ_get_or_register_category("Tag", cat, INVALID_FUNCTION, 0);
	econ_get_or_register_category("Colors", cat, chat_clrs_cat_registered, 0);
}

public void econ_loaded()
{
	econ_get_or_register_category("Chat", ECON_INVALID_CATEGORY, chat_cat_registered, 0);
}

public void econ_register_item_classes()
{
	econ_register_item_class("chat_tag", true);
	econ_register_item_class("chat_color_tag", true);
	econ_register_item_class("chat_color_name", true);
	econ_register_item_class("chat_color", true);
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
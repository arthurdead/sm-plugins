#include <sourcemod>
#include <regex>
#include <morecolors>
#include <nativevotes>
#include <aliasrandom>
#include <SteamWorks>
#include <sdktools>
#include <mapchooser_extended>
#include <gamemode_manager>
#include <mapcycle_manager>

#define TF2_MAXPLAYERS 33

//#define DEBUG

#define GAMEMODE_NAME_MAX 64

#define CMD_STR_MAX 128
#define INT_STR_MAX 4

#define GMM_CON_PREFIX "[GMM] "
#define GMM_CHAT_PREFIX "{dodgerblue}[GMM]{default} "

enum struct StateChangeInfo
{
	char cfg[PLATFORM_MAX_PATH];
	ArrayList commands;
}

enum struct GamemodePluginInfo
{
	char path[PLATFORM_MAX_PATH];
	Handle plugin;
	Function handle_fwd;
	Function map_fwd;
}

enum struct GamemodeInfo
{
	char name[GAMEMODE_NAME_MAX];
	float weight;
	float time;
	GamemodePluginInfo gamemode_plugin;
	ArrayList plugins;
	ArrayList plugins_disable;
	StateChangeInfo enabled;
	StateChangeInfo disabled;
	ArrayList mapcycle;
}

static ArrayList gamemodes;
static StringMap gamemode_idx_map;
static StringMap gamemode_map_map;

static ArrayList gamemode_history;

static int current_gamemode = -1;
static int next_gamemode = -1;
static int default_gamemode = -1;
static int start_gamemode = -1;

static ConVar gmm_start_gamemode;
static ConVar gmm_default_gamemode;
static ConVar gmm_multimod;

static ConVar rtg_needed;
static ConVar rtg_minplayers;
static ConVar rtg_initialdelay;
static ConVar rtg_interval;

static bool can_rtg;
static bool rtg_allowed;
static int votes;
static int voters;
static bool voted[TF2_MAXPLAYERS+1];
static int rtg_time;
static int votes_needed;

static char current_map[PLATFORM_MAX_PATH];

static bool reset_next_map;

static bool late_loaded;
static Handle change_gamemode_timer;

static Handle ff2_plugin;

static void unload_gamemodes()
{
	unload_current_gamemode();

	next_gamemode = -1;

	GamemodeInfo modeinfo;

	int len = gamemodes.Length;
	for(int i = 0; i < len; ++i) {
		gamemodes.GetArray(i, modeinfo, sizeof(GamemodeInfo));

		delete modeinfo.plugins;
		delete modeinfo.plugins_disable;
		delete modeinfo.disabled.commands;
		delete modeinfo.enabled.commands;
		delete modeinfo.mapcycle;
	}

	char map[PLATFORM_MAX_PATH];

	StringMapSnapshot snap = gamemode_map_map.Snapshot();
	len = snap.Length;
	for(int i = 0; i < len; ++i) {
		snap.GetKey(i, map, PLATFORM_MAX_PATH);

		ArrayList modes;
		if(gamemode_map_map.GetValue(map, modes)) {
			delete modes;
		}
	}
	delete snap;

	delete gamemodes;
	delete gamemode_idx_map;
	delete gamemode_map_map;
}

static void kv_handle_str_array(KeyValues kv, const char[] name, ArrayList &arr, char[] str, int size)
{
	if(kv.JumpToKey(name)) {
		if(kv.GotoFirstSubKey(false)) {
			arr = new ArrayList(ByteCountToCells(size));

			do {
				kv.GetString(NULL_STRING, str, size);

				arr.PushString(str);
			} while(kv.GotoNextKey(false));

			kv.GoBack();
		} else {
			arr = null;
		}

		kv.GoBack();
	} else {
		arr = null;
	}
}

static void kv_handle_state_changed(KeyValues kv, const char[] name, char cmd_str[CMD_STR_MAX], StateChangeInfo info)
{
	if(kv.JumpToKey(name)) {
		kv.GetString("cfg", info.cfg, PLATFORM_MAX_PATH);
		kv_handle_str_array(kv, "commands", info.commands, cmd_str, CMD_STR_MAX);
		kv.GoBack();
	}
}

static void add_plugin_to_gamemode(ArrayList plugins, const char[] path, const char[] plugins_folder_path)
{
	char disabled_plugin_path[PLATFORM_MAX_PATH];

	int i = strlen(path)-1;
	while(i > 0 && path[--i] != '/') {}

	int j = 0;
	for(; j < i; ++j) {
		disabled_plugin_path[j] = path[j];
	}
	disabled_plugin_path[j] = '\0';

	Format(disabled_plugin_path, PLATFORM_MAX_PATH, "%s/disabled/%s", plugins_folder_path, disabled_plugin_path);

	CreateDirectory(disabled_plugin_path, FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC);

	plugins.PushString(path);
}

static void kv_handle_plugins(KeyValues kv, ArrayList &arr, const char[] name, const char[] plugins_folder_path)
{
	if(kv.JumpToKey(name)) {
		if(kv.GotoFirstSubKey(false)) {
			arr = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

			char any_file_path[PLATFORM_MAX_PATH];

			do {
				kv.GetString(NULL_STRING, any_file_path, PLATFORM_MAX_PATH);

				add_plugin_to_gamemode(arr, any_file_path, plugins_folder_path);
			} while(kv.GotoNextKey(false));

			kv.GoBack();
		} else {
			arr = null;
		}

		kv.GoBack();
	} else {
		arr = null;
	}
}

static void load_gamemodes()
{
	char gamemodes_file_path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, gamemodes_file_path, PLATFORM_MAX_PATH, "configs/gmm/gamemodes.txt");

	if(FileExists(gamemodes_file_path)) {
		KeyValues kv = new KeyValues("Gamemodes");
		kv.ImportFromFile(gamemodes_file_path);

		GamemodeInfo info;

		if(kv.GotoFirstSubKey()) {
			gamemodes = new ArrayList(sizeof(GamemodeInfo));
			gamemode_idx_map = new StringMap();
			gamemode_map_map = new StringMap();

			char cmd_str[CMD_STR_MAX];

			char plugins_folder_path[PLATFORM_MAX_PATH];
			BuildPath(Path_SM, plugins_folder_path, PLATFORM_MAX_PATH, "plugins");

			do {
				kv.GetSectionName(info.name, GAMEMODE_NAME_MAX);

				kv_handle_plugins(kv, info.plugins, "plugins", plugins_folder_path);
				kv_handle_plugins(kv, info.plugins_disable, "plugins_disable", plugins_folder_path);

				info.gamemode_plugin.handle_fwd = INVALID_FUNCTION;
				info.gamemode_plugin.map_fwd = INVALID_FUNCTION;

				kv.GetString("gamemode_plugin", info.gamemode_plugin.path, PLATFORM_MAX_PATH);
				if(info.gamemode_plugin.path[0] != '\0') {
					if(!info.plugins) {
						info.plugins = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
					}

					add_plugin_to_gamemode(info.plugins, info.gamemode_plugin.path, plugins_folder_path);
				}

				info.weight = kv.GetFloat("weight", 50.0);
				info.time = kv.GetFloat("time", 30.0);

				kv_handle_state_changed(kv, "enabled", cmd_str, info.enabled);
				kv_handle_state_changed(kv, "disabled", cmd_str, info.disabled);

				info.mapcycle = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

				int idx = gamemodes.PushArray(info, sizeof(GamemodeInfo));

				gamemode_idx_map.SetValue(info.name, idx);
			} while(kv.GotoNextKey());

			kv.GoBack();
		}
	}
}

public void OnNotifyPluginUnloaded(Handle plugin)
{
	if(ff2_plugin != null && plugin == ff2_plugin) {
		//toggle_ff2_folder(false);
		ff2_plugin = null;
		return;
	}

	if(gamemodes != null) {
		GamemodeInfo info;

		int len = gamemodes.Length;
		for(int i = 0; i < len; ++i) {
			gamemodes.GetArray(i, info, sizeof(GamemodeInfo));

			if(info.gamemode_plugin.plugin == plugin) {
				gamemode_plugin_unloaded(i, info);

				if(current_gamemode == i) {
					unload_current_gamemode();
					load_gamemode_for_map(current_map, i);
				}
			}
		}
	}
}

static void toggle_ff2_folder(bool value)
{
	static char ff2_folder_enabled_path[PLATFORM_MAX_PATH];
	if(ff2_folder_enabled_path[0] == '\0') {
		BuildPath(Path_SM, ff2_folder_enabled_path, PLATFORM_MAX_PATH, "plugins/freaks");
	}
	static char ff2_folder_disabled_path[PLATFORM_MAX_PATH];
	if(ff2_folder_disabled_path[0] == '\0') {
		BuildPath(Path_SM, ff2_folder_disabled_path, PLATFORM_MAX_PATH, "plugins/disabled/freaks");
	}

	if(value) {
		RenameFile(ff2_folder_enabled_path, ff2_folder_disabled_path);
	}

	DirectoryListing ff2_folder_enabled = OpenDirectory(ff2_folder_enabled_path);
	if(ff2_folder_enabled != null) {
		char plugin_filename[PLATFORM_MAX_PATH];
		char plugin_path_smx_enabled[PLATFORM_MAX_PATH];
		char plugin_path_ff2_enabled[PLATFORM_MAX_PATH];

		FileType filetype;
		while(ff2_folder_enabled.GetNext(plugin_filename, PLATFORM_MAX_PATH, filetype)) {
			if(filetype != FileType_File) {
				continue;
			}

			int ext = StrContains(plugin_filename, ".ff2");
			if(ext == -1) {
				ext = StrContains(plugin_filename, ".smx");
			}
			if(ext == -1) {
				continue;
			}

			if((strlen(plugin_filename)-ext) != 4) {
				continue;
			}

			plugin_filename[ext] = '\0';

			Format(plugin_path_smx_enabled, PLATFORM_MAX_PATH, "%s/%s", ff2_folder_enabled_path, plugin_filename);
			StrCat(plugin_path_smx_enabled, PLATFORM_MAX_PATH, ".smx");

			Format(plugin_path_ff2_enabled, PLATFORM_MAX_PATH, "%s/%s", ff2_folder_enabled_path, plugin_filename);
			StrCat(plugin_path_ff2_enabled, PLATFORM_MAX_PATH, ".ff2");

			if(!value) {
				if(FileExists(plugin_path_smx_enabled)) {
					InsertServerCommand("sm plugins unload \"freaks/%s\"", plugin_filename);
				}
				//RenameFile(plugin_path_ff2_enabled, plugin_path_smx_enabled);
			} else {
				RenameFile(plugin_path_smx_enabled, plugin_path_ff2_enabled);
				/*if(FileExists(plugin_path_smx_enabled)) {
					InsertServerCommand("sm plugins load \"freaks/%s\"", plugin_filename);
				}*/
			}
		}
		delete ff2_folder_enabled;

		ServerExecute();
	}

	if(!value) {
		RenameFile(ff2_folder_disabled_path, ff2_folder_enabled_path);
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("gamemode_manager");
	late_loaded = late;
	toggle_ff2_folder(false);
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	gamemode_history = new ArrayList();

	rtg_needed = CreateConVar("rtg_needed", "0.60", "Percentage of players needed to rockthevote (Def 60%)", 0, true, 0.05, true, 1.0);
	rtg_minplayers = CreateConVar("rtg_minplayers", "0", "Number of players required before RTG will be enabled.", 0, true, 0.0, true, float(TF2_MAXPLAYERS));
	rtg_initialdelay = CreateConVar("rtg_initialdelay", "30.0", "Time (in seconds) before first RTG can be held", 0, true, 0.00);
	rtg_interval = CreateConVar("rtg_interval", "240.0", "Time (in seconds) after a failed RTG before another can be held", 0, true, 0.00);

	gmm_start_gamemode = CreateConVar("gmm_start_gamemode", "");
	gmm_default_gamemode = CreateConVar("gmm_default_gamemode", "");

	gmm_multimod = CreateConVar("gmm_multimod", "0");

	RegAdminCmd("sm_rgmm", sm_rgmm, ADMFLAG_ROOT);
	RegAdminCmd("sm_fgm", sm_fgm, ADMFLAG_ROOT);

	RegConsoleCmd("sm_rtg", sm_rtg);
	RegAdminCmd("sm_forcertg", sm_fgmv, ADMFLAG_ROOT);

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientConnected(i)) {
			OnClientConnected(i);
		}
	}
}

static void gamemode_plugin_unloaded(int idx, GamemodeInfo info)
{
	info.gamemode_plugin.plugin = null;

	info.gamemode_plugin.handle_fwd = INVALID_FUNCTION;
	info.gamemode_plugin.map_fwd = INVALID_FUNCTION;

	gamemodes.SetArray(idx, info, sizeof(GamemodeInfo));

#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "%s plugin unloaded", info.name);
#endif
}

static void gamemode_plugin_loaded(int idx, GamemodeInfo info)
{
	if(info.gamemode_plugin.handle_fwd == INVALID_FUNCTION) {
		info.gamemode_plugin.handle_fwd = GetFunctionByName(info.gamemode_plugin.plugin, "gmm_handle_gamemode");
	}

	if(info.gamemode_plugin.map_fwd == INVALID_FUNCTION) {
		info.gamemode_plugin.map_fwd = GetFunctionByName(info.gamemode_plugin.plugin, "gmm_map_valid_for_gamemode");
	}

	gamemodes.SetArray(idx, info, sizeof(GamemodeInfo));

#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "added %s functions", info.name);
#endif
}

static int get_filename_pos(const char[] path)
{
	int i = strlen(path)
	for(; i; --i) {
		if(path[i] == '/' || path[i] == '\\') {
			++i;
			break;
		}
	}
	return i;
}

stock Handle FindPluginByFilename(const char[] filename)
{
	int targetpos = get_filename_pos(filename);

	char buffer[256];

	Handle iter = GetPluginIterator();
	Handle pl;

	while (MorePlugins(iter))
	{
		pl = ReadPlugin(iter);

		GetPluginFilename(pl, buffer, sizeof(buffer));

		int sourcepos = get_filename_pos(buffer);

		if (strcmp(buffer[sourcepos], filename[targetpos], false) == 0)
		{
			CloseHandle(iter);
			return pl;
		}
	}

	CloseHandle(iter);

	return INVALID_HANDLE;
}

static void frame_gamemode_plugin_loaded(DataPack data)
{
	data.Reset();

	int idx = data.ReadCell();

	GamemodeInfo info;
	data.ReadCellArray(info, sizeof(GamemodeInfo));

	char path[PLATFORM_MAX_PATH];
	data.ReadString(path, PLATFORM_MAX_PATH);

	Function on_loaded = data.ReadFunction();

	DataPack on_loaded_data = data.ReadCell();

	delete data;

	info.gamemode_plugin.plugin = FindPluginByFile(path);
	if(info.gamemode_plugin.plugin == null) {
		LogError("Gamemode \"%s\" plugin \"%s\" was not found.", info.name, path);
	}

	if(info.gamemode_plugin.plugin != null) {
		gamemode_plugin_loaded(idx, info);
	}

	gamemodes.SetArray(idx, info, sizeof(GamemodeInfo));

	if(on_loaded != INVALID_FUNCTION) {
		Call_StartFunction(null, on_loaded);
		Call_PushCell(on_loaded_data);
		Call_Finish();
	}
}

static void load_gamemode_plugin(int idx, GamemodeInfo info, const char[] path, Function on_loaded = INVALID_FUNCTION, DataPack on_loaded_data = null)
{
	InsertServerCommand("sm plugins load \"%s\"", path);
	ServerExecute();

	DataPack data = new DataPack();
	data.WriteCell(idx);
	data.WriteCellArray(info, sizeof(GamemodeInfo));
	data.WriteString(path);
	data.WriteFunction(on_loaded);
	data.WriteCell(on_loaded_data);
	RequestFrame(frame_gamemode_plugin_loaded, data);
}

static void find_gamemode_plugin(int idx, GamemodeInfo info, const char[] path, bool load, Function on_loaded = INVALID_FUNCTION, DataPack on_loaded_data = null)
{
	info.gamemode_plugin.plugin = FindPluginByFile(path);
	if(info.gamemode_plugin.plugin == null) {
		if(load) {
			load_gamemode_plugin(idx, info, path, on_loaded, on_loaded_data);
			return;
		}
	}

	if(info.gamemode_plugin.plugin != null) {
		gamemode_plugin_loaded(idx, info);
	}

	gamemodes.SetArray(idx, info, sizeof(GamemodeInfo));

	if(on_loaded != INVALID_FUNCTION) {
		Call_StartFunction(null, on_loaded);
		Call_PushCell(on_loaded_data);
		Call_Finish();
	}
}

static Action call_gamemode_map_filter(int idx, GamemodeInfo info, const char[] map)
{
	if(info.gamemode_plugin.plugin == null) {
		find_gamemode_plugin(idx, info, info.gamemode_plugin.path, true);
	}

	if(info.gamemode_plugin.plugin == null) {
		LogError("Gamemode \"%s\" plugin \"%s\" is not loaded.", info.name, info.gamemode_plugin.path);
	} else if(info.gamemode_plugin.map_fwd != INVALID_FUNCTION) {
		Call_StartFunction(info.gamemode_plugin.plugin, info.gamemode_plugin.map_fwd);
		Call_PushString(info.name);
		Call_PushString(map);
		Action ret = Plugin_Continue;
		Call_Finish(ret);
		if(ret == Plugin_Changed) {
			return Plugin_Changed;
		} else if(ret > Plugin_Changed) {
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

static void call_gamemode_handle(int idx, GamemodeInfo info, gmm_gamemode_action action)
{
	if(info.gamemode_plugin.plugin == null) {
		find_gamemode_plugin(idx, info, info.gamemode_plugin.path, (action == gmm_gamemode_start));
	}

	if(info.gamemode_plugin.plugin == null) {
		if(action != gmm_gamemode_end) {
			LogError("Gamemode \"%s\" plugin \"%s\" is not loaded", info.name, info.gamemode_plugin.path);
		}
	} else if(info.gamemode_plugin.handle_fwd == INVALID_FUNCTION) {
		LogError("Gamemode \"%s\" plugin \"%s\" has no handle function", info.name, info.gamemode_plugin.path);
	} else {
		Call_StartFunction(info.gamemode_plugin.plugin, info.gamemode_plugin.handle_fwd);
		Call_PushString(info.name);
		Call_PushCell(action);
		Call_Finish();
	}
}

public void OnAllPluginsLoaded()
{
	load_gamemodes();

#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "plugin loaded unloading all gamemodes");
#endif

	GamemodeInfo info;

	int len = gamemodes.Length;
	for(int i = 0; i < len; ++i) {
		unload_gamemode(i);

		gamemodes.GetArray(i, info, sizeof(GamemodeInfo));

		if(info.gamemode_plugin.path[0] != '\0') {
			if(info.gamemode_plugin.plugin == null) {
				find_gamemode_plugin(i, info, info.gamemode_plugin.path, true);
			}
		}
	}
}

static Action sm_rtg(int client, int args)
{
	if(!client || !can_rtg) {
		return Plugin_Handled;
	}

	attempt_rtg(client);

	return Plugin_Handled;
}

static void attempt_rtg(int client)
{
	if(!rtg_allowed) {
		CPrintToChat(client, GMM_CHAT_PREFIX ... "Rock the Gamemode is not allowed yet.");
		return;
	}

	if(GetClientCount(true) < rtg_minplayers.IntValue) {
		CPrintToChat(client, GMM_CHAT_PREFIX ... "The minimal number of players required has not been met.");
		return;
	}

	if(voted[client]) {
		CPrintToChat(client, GMM_CHAT_PREFIX ... "You have already voted to Rock the Gamemode. (%i votes, %i required)", votes, votes_needed);
		return;
	}

	++votes;
	voted[client] = true;

	CPrintToChatAll(GMM_CHAT_PREFIX ... "%N wants to rock the vote. (%i votes, %i required)", client, votes, votes_needed);

	if(votes >= votes_needed) {
		start_gamemode_vote();
	}
}

static Action sm_fgmv(int client, int args)
{
	start_gamemode_vote();
	return Plugin_Handled;
}

static Action sm_fgm(int client, int args)
{
	char name[GAMEMODE_NAME_MAX];
	if(args >= 1) {
		GetCmdArg(1, name, GAMEMODE_NAME_MAX);
	}

	if(name[0] != '\0') {
		if(StrEqual(name, "current_map")) {
			load_gamemode_for_map(current_map);
			return Plugin_Handled;
		} else {
			int mode = -1;

			if(StrEqual(name, "random")) {
				mode = get_random_gamemode_idx();
				if(mode == -1) {
					CReplyToCommand(client, GMM_CHAT_PREFIX ... "couldn't get random gamemode");
					return Plugin_Handled;
				}
			} else {
				if(!gamemode_idx_map.GetValue(name, mode)) {
					CReplyToCommand(client, GMM_CHAT_PREFIX ... "invalid gamemode name \"%s\"", name);
					return Plugin_Handled;
				}
			}

			if(mode != -1) {
				if(!is_gamemode_valid_for_map(mode, current_map)) {
					next_gamemode = mode;
					change_to_random_gamemode_map(mode);
				} else {
					if(current_gamemode != mode) {
						load_gamemode(mode);
					}
				}
			}
		}
	} else {
		unload_current_gamemode();
	}

	return Plugin_Handled;
}

static Action sm_rgmm(int client, int args)
{
	unload_gamemodes();
	load_gamemodes();
	return Plugin_Handled;
}

static Action timer_change_to_map(Handle timer, DataPack data)
{
	data.Reset();

	char map[PLATFORM_MAX_PATH];
	data.ReadString(map, PLATFORM_MAX_PATH);

	ForceChangeLevel(map, "GMM");
	return Plugin_Continue;
}

static void change_to_map(const char[] map)
{
	float time = 2.0;

	CPrintToChatAll(GMM_CHAT_PREFIX ... "Changing to map \"%s\".", map);

	CreateTimer(time * 0.8, timer_load_next_gamemode, 0, TIMER_FLAG_NO_MAPCHANGE);

	SetNextMap(map);

	DataPack data;
	CreateDataTimer(time, timer_change_to_map, data, TIMER_FLAG_NO_MAPCHANGE);
	data.WriteString(map);
}

static void change_to_random_gamemode_map(int mode)
{
	ArrayList mapcycle = gamemodes.Get(mode, GamemodeInfo::mapcycle);

	if(mapcycle == null) {
		load_gamemode(mode);
		next_gamemode = -1;
		return;
	}

	int map_idx = GetRandomInt(0, mapcycle.Length-1);

	char map[PLATFORM_MAX_PATH];
	mapcycle.GetString(map_idx, map, PLATFORM_MAX_PATH);

	change_to_map(map);
}

static Action timer_load_next_gamemode(Handle timer, any data)
{
	if(next_gamemode != -1) {
		load_gamemode(next_gamemode);
		next_gamemode = -1;
	}
	return Plugin_Continue;
}

static int votehandler_gamemode(NativeVote menu, MenuAction action, int param1, int param2)
{
	switch(action) {
		case MenuAction_VoteEnd: {
			char int_str[INT_STR_MAX];
			menu.GetItem(param1, int_str, INT_STR_MAX);
			int idx = StringToInt(int_str);
			if(idx == -1) {
				if(default_gamemode != -1) {
					idx = default_gamemode;
				}
			}
			if(idx != -1) {
				GamemodeInfo info;
				gamemodes.GetArray(idx, info, sizeof(GamemodeInfo));

				menu.DisplayPassEx(NativeVotesPass_ChgMission, "%s", info.name);
				CPrintToChatAll(GMM_CHAT_PREFIX ... "\"%s\" won the gamemode vote.", info.name);

				next_gamemode = idx;

				if(info.mapcycle != null) {
					if(info.mapcycle.Length == 1) {
						char next_map[PLATFORM_MAX_PATH];
						info.mapcycle.GetString(0, next_map, PLATFORM_MAX_PATH);

						change_to_map(next_map);
					} else {
						InitiateMapChooserVote(MapChange_RoundEnd, info.mapcycle);
					}
				} else {
					CreateTimer(2.0, timer_load_next_gamemode, 0, TIMER_FLAG_NO_MAPCHANGE);
				}
			} else {
				menu.DisplayPassEx(NativeVotesPass_ChgMission, "Team Fortress");
				CPrintToChatAll(GMM_CHAT_PREFIX ... "Unloading current gamemode.");
				unload_current_gamemode();
			}
		}
		case MenuAction_VoteCancel: {
			switch(param1) {
				case VoteCancel_Generic:
				{ menu.DisplayFail(NativeVotesFail_Generic); }
				case VoteCancel_NoVotes:
				{ menu.DisplayFail(NativeVotesFail_NotEnoughVotes); }
			}
			if(gmm_multimod.BoolValue) {
				CPrintToChatAll(GMM_CHAT_PREFIX ... "Gamemode vote failed starting the vote again.");

				change_gamemode_timer = CreateTimer(1.0, timer_change_gamemode, true);
			} else {
				if(current_gamemode != -1) {
					GamemodeInfo info;
					gamemodes.GetArray(current_gamemode, info, sizeof(GamemodeInfo));

					CPrintToChatAll(GMM_CHAT_PREFIX ... "Gamemode vote failed keeping current gamemode: \"%s\".", info.name);
				}
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}

	return 0;
}

static void start_gamemode_vote()
{
	NativeVote vote_menu = new NativeVote(votehandler_gamemode, NativeVotesType_Custom_Mult);
	vote_menu.SetTitle("Gamemodes");

	GamemodeInfo info;

	ArrayList weights = new ArrayList();
	ArrayList to_choose = new ArrayList();

	int modes_len = gamemodes.Length;
	for(int i = 0; i < modes_len; ++i) {
		gamemodes.GetArray(i, info, sizeof(GamemodeInfo));

		if(gamemode_history.FindValue(i) != -1 ||
			i == current_gamemode) {
		#if defined DEBUG
			PrintToServer(GMM_CON_PREFIX ... "skipped %s either in history or current", info.name);
		#endif
			continue;
		}

		if(!is_gamemode_valid(info)) {
		#if defined DEBUG
			PrintToServer(GMM_CON_PREFIX ... "skipped %s not valid", info.name);
		#endif
			continue;
		}

		if(info.gamemode_plugin.path[0] != '\0') {
			Action ret = call_gamemode_map_filter(i, info, current_map);
			if(ret == Plugin_Handled) {
			#if defined DEBUG
				PrintToServer(GMM_CON_PREFIX ... "skipped %s map not valid", info.name);
			#endif
				continue;
			}
		}

		weights.Push(info.weight);
		to_choose.Push(i);
	}

	ArrayList aliases = CreateAliasRandom(weights);

	char int_str[INT_STR_MAX];

	bool add_default_vote = (!gmm_multimod.BoolValue && (current_gamemode != default_gamemode));

	int max_votes = 5;
	if(add_default_vote) {
		--max_votes;
	}

	int to_choose_len = to_choose.Length;
	int num_votes = to_choose_len > max_votes ? max_votes : to_choose_len;
	for(int i = 0; i < num_votes; ++i) {
		int idx = GetAliasRandom(aliases);

		int mode = to_choose.Get(idx);
		gamemodes.GetArray(mode, info, sizeof(GamemodeInfo));

		weights.Erase(idx);

		delete aliases;
		aliases = CreateAliasRandom(weights);

		to_choose.Erase(idx);

		IntToString(mode, int_str, INT_STR_MAX);
		vote_menu.AddItem(int_str, info.name);
	}

	delete aliases;
	delete weights;
	delete to_choose;

	if(add_default_vote) {
		vote_menu.AddItem("-1", "Default Gamemode");
	}

	vote_menu.DisplayVoteToAll(20);

	reset_rtg();
	rtg_allowed = false;
	rtg_time = GetTime() + rtg_interval.IntValue;
	CreateTimer(rtg_interval.FloatValue, timer_delayrtg, _, TIMER_FLAG_NO_MAPCHANGE);
}

static void reset_rtg()
{
	votes = 0;
	for(int i = 1; i <= MaxClients; ++i) {
		voted[i] = false;
	}
}

public void OnClientConnected(int client)
{
	if(IsFakeClient(client) ||
		IsClientReplay(client) ||
		IsClientSourceTV(client)) {
		return;
	}

	voted[client] = false;

	++voters;
	votes_needed = RoundToCeil(float(voters) * rtg_needed.FloatValue);
}

public void OnClientDisconnect(int client)
{
	if(IsFakeClient(client) ||
		IsClientReplay(client) ||
		IsClientSourceTV(client)) {
		return;
	}

	if(voted[client]) {
		voted[client] = false;
		--votes;
	}

	--voters;
	votes_needed = RoundToCeil(float(voters) * rtg_needed.FloatValue);

	if(!can_rtg) {
		return;
	}

	if(votes > 0 && 
		voters > 0 && 
		votes >= votes_needed && 
		rtg_allowed)
	{
		start_gamemode_vote();
	}
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if(!client || !can_rtg || IsChatTrigger()) {
		return;
	}

	if(StrEqual(sArgs, "rtg") || StrEqual(sArgs, "rockthegame")) {
		ReplySource oldsrc = SetCmdReplySource(SM_REPLY_TO_CHAT);
		attempt_rtg(client);
		SetCmdReplySource(oldsrc);
	}
}

static void handle_gamemode_plugins(int idx, GamemodeInfo info, bool unload, bool force_plugin_unload = false)
{
	char pluginsfolder[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, pluginsfolder, PLATFORM_MAX_PATH, "plugins");

	char plugin_filename[PLATFORM_MAX_PATH];
	char plugin_disabled_path[PLATFORM_MAX_PATH];
	char plugin_enabled_path[PLATFORM_MAX_PATH];

	if(!unload) {
		if(info.plugins_disable != null) {
			for(int i = info.plugins_disable.Length-1; i >= 0; --i) {
				info.plugins_disable.GetString(i, plugin_filename, PLATFORM_MAX_PATH);

				Format(plugin_disabled_path, PLATFORM_MAX_PATH, "%s/disabled/%s", pluginsfolder, plugin_filename);
				Format(plugin_enabled_path, PLATFORM_MAX_PATH, "%s/%s", pluginsfolder, plugin_filename);

				if(FileExists(plugin_enabled_path)) {
					InsertServerCommand("sm plugins unload \"%s\"", plugin_filename);
				} else {
					//LogError("Gamemode \"%s\" plugin \"%s\" was not loaded.", info.name, plugin_filename);
				}
				RenameFile(plugin_disabled_path, plugin_enabled_path);
			}
		}
	} else {
		if(info.gamemode_plugin.path[0] != '\0') {
			call_gamemode_handle(idx, info, gmm_gamemode_end);
		}
	}

	if(info.plugins != null) {
		bool reverse = (unload);

		int i = 0;
		if(reverse) {
			i = info.plugins.Length-1;
		}
		int len = 0;
		if(!reverse) {
			len = info.plugins.Length;
		}

		while(true) {
			if(reverse) {
				if(i < 0) {
					break;
				}
			} else {
				if(i >= len) {
					break;
				}
			}

			info.plugins.GetString(i, plugin_filename, PLATFORM_MAX_PATH);

			Format(plugin_disabled_path, PLATFORM_MAX_PATH, "%s/disabled/%s", pluginsfolder, plugin_filename);
			Format(plugin_enabled_path, PLATFORM_MAX_PATH, "%s/%s", pluginsfolder, plugin_filename);

			bool is_ff2 = StrEqual(plugin_filename[get_filename_pos(plugin_filename)], "freak_fortress_2");
			bool is_gamemode_plugin = StrEqual(plugin_filename, info.gamemode_plugin.path);

			if(unload) {
				if(!is_gamemode_plugin || force_plugin_unload) {
					if(is_ff2) {
						toggle_ff2_folder(false);
					}

					if(FileExists(plugin_enabled_path)) {
						InsertServerCommand("sm plugins unload \"%s\"", plugin_filename);
					} else {
						//LogError("Gamemode \"%s\" plugin \"%s\" was not loaded.", info.name, plugin_filename);
					}
					RenameFile(plugin_disabled_path, plugin_enabled_path);

					if(is_gamemode_plugin) {
						gamemode_plugin_unloaded(idx, info);
					} else if(is_ff2) {
						ff2_plugin = null;
					}
				}
			} else {
				if(is_ff2) {
					toggle_ff2_folder(true);
				}

				RenameFile(plugin_enabled_path, plugin_disabled_path);
				if(FileExists(plugin_enabled_path)) {
					InsertServerCommand("sm plugins load \"%s\"", plugin_filename);
				} else {
					LogError("Gamemode \"%s\" plugin \"%s\" does not exist.", info.name, plugin_filename);
				}

				if(is_ff2) {
					if(ff2_plugin == null) {
						ServerExecute();

						DataPack data = new DataPack();
						data.WriteString(plugin_filename);
						RequestFrame(frame_ff2_loaded, data);
					}
				}
			}

			if(reverse) {
				--i;
			} else {
				++i;
			}
		}
	}

	if(unload) {
		if(info.plugins_disable != null) {
			int len = info.plugins_disable.Length;
			for(int i = 0; i < len; ++i) {
				info.plugins_disable.GetString(i, plugin_filename, PLATFORM_MAX_PATH);

				Format(plugin_disabled_path, PLATFORM_MAX_PATH, "%s/disabled/%s", pluginsfolder, plugin_filename);
				Format(plugin_enabled_path, PLATFORM_MAX_PATH, "%s/%s", pluginsfolder, plugin_filename);

				RenameFile(plugin_enabled_path, plugin_disabled_path);
				if(FileExists(plugin_enabled_path)) {
					InsertServerCommand("sm plugins load \"%s\"", plugin_filename);
				} else {
					LogError("Gamemode \"%s\" plugin \"%s\" does not exist.", info.name, plugin_filename);
				}
			}
		}
	}

	ServerExecute();

	if(!unload) {
		if(info.gamemode_plugin.path[0] != '\0') {
			DataPack data = new DataPack();
			data.WriteCell(idx);
			data.WriteCellArray(info, sizeof(GamemodeInfo));
			data.WriteCell(gmm_gamemode_start);
			RequestFrame(frame_call_gamemode_handle, data);
		}
	}
}

static void frame_ff2_loaded(DataPack data)
{
	data.Reset();

	char plugin_filename[PLATFORM_MAX_PATH];
	data.ReadString(plugin_filename, PLATFORM_MAX_PATH);

	delete data;

	ff2_plugin = FindPluginByFile(plugin_filename);
}

static void frame_call_gamemode_handle(DataPack data)
{
	data.Reset();

	int idx = data.ReadCell();

	GamemodeInfo info;
	data.ReadCellArray(info, sizeof(GamemodeInfo));

	gmm_gamemode_action action = data.ReadCell();

	delete data;

	call_gamemode_handle(idx, info, action);
}

static void handle_gamemode_state(StateChangeInfo info)
{
	if(info.cfg[0] != '\0') {
		InsertServerCommand("exec %s", info.cfg);
	}

	if(info.commands != null) {
		char cmd_str[CMD_STR_MAX];

		int len = info.commands.Length;
		for(int i = 0; i < len; ++i) {
			info.commands.GetString(i, cmd_str, CMD_STR_MAX);

			InsertServerCommand("%s", cmd_str);
		}
	}

	ServerExecute();
}

static void add_to_gamemode_history(int idx)
{
	if(gamemode_history.FindValue(idx) != -1) {
		return;
	}

	gamemode_history.Push(idx);

	int len = gamemodes.Length;
	int max = len > 5 ? 5 : len-1;

	if(gamemode_history.Length > max) {
		gamemode_history.Erase(0);
	}
}

static void unload_gamemode(int idx, bool force_plugin_unload = false)
{
	GamemodeInfo info;
	gamemodes.GetArray(idx, info, sizeof(GamemodeInfo));

#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "unloaded %s", info.name);
#endif

	handle_gamemode_state(info.disabled);
	handle_gamemode_plugins(idx, info, true, force_plugin_unload);
}

static void unload_current_gamemode(bool force_plugin_unload = false)
{
	if(current_gamemode == -1) {
		return;
	}

	if(change_gamemode_timer != null) {
		KillTimer(change_gamemode_timer);
		change_gamemode_timer = null;
	}

#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "unloading current gamemode");
#endif

	unload_gamemode(current_gamemode, force_plugin_unload);
	current_gamemode = -1;

	mcm_set_config(NULL_STRING);

	SteamWorks_SetGameDescription("Team Fortress");
}

static Action timer_change_gamemode(Handle timer, bool data)
{
	if(current_gamemode != -1 && !data) {
		GamemodeInfo info;
		gamemodes.GetArray(current_gamemode, info, sizeof(GamemodeInfo));

		CPrintToChatAll(GMM_CHAT_PREFIX ... "Gamemode \"%s\" time ended.", info.name);
	}

	if(gmm_multimod.BoolValue) {
		start_gamemode_vote();
	} else {
		load_gamemode_for_map(current_map, current_gamemode);
	}

	change_gamemode_timer = null;
	return Plugin_Continue;
}

static void load_gamemode(int idx)
{
	if(current_gamemode == idx) {
		return;
	}

	GamemodeInfo info;
	gamemodes.GetArray(idx, info, sizeof(GamemodeInfo));

#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "unloading current gamemode to load %s instead", info.name);
#endif

	unload_current_gamemode();

	current_gamemode = idx;

#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "loaded %s", info.name);
#endif

	add_to_gamemode_history(idx);

	SteamWorks_SetGameDescription(info.name);

	handle_gamemode_plugins(idx, info, false);
	handle_gamemode_state(info.enabled);

	mcm_set_config(info.name);

	change_gamemode_timer = CreateTimer(info.time * 60, timer_change_gamemode);
}

public void OnPluginEnd()
{
#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "plugin unloaded unloading current gamemode");
#endif
	unload_current_gamemode(true);
}

static int get_random_gamemode_idx()
{
	ArrayList weights = new ArrayList();
	ArrayList to_choose = new ArrayList();

	GamemodeInfo info;

	int len = gamemodes.Length;
	for(int i = 0; i < len; ++i) {
		if(gamemode_history.FindValue(i) != -1 ||
			i == current_gamemode) {
			continue;
		}

		gamemodes.GetArray(i, info, sizeof(GamemodeInfo));

		if(!is_gamemode_valid(info)) {
			continue;
		}

		weights.Push(info.weight);
		to_choose.Push(i);
	}

	ArrayList aliases = CreateAliasRandom(weights);

	int idx = GetAliasRandom(aliases);

	int mode = -1;
	if(idx != -1) {
		mode = to_choose.Get(idx);
	} else {
		LogError("Couldn't get a random gamemode.");
	}

	delete aliases;
	delete weights;
	delete to_choose;

	return mode;
}

static bool is_gamemode_valid(GamemodeInfo info)
{
	return true;
}

static bool is_gamemode_valid_for_map(int mode, const char[] map)
{
	GamemodeInfo info;
	gamemodes.GetArray(mode, info, sizeof(GamemodeInfo));

	if(!is_gamemode_valid(info)) {
		return false;
	}

	if(info.gamemode_plugin.path[0] != '\0') {
		Action ret = call_gamemode_map_filter(mode, info, map);
		if(ret == Plugin_Changed) {
			return true;
		} else if(ret == Plugin_Handled) {
			return false;
		}
	}

	return (info.mapcycle == null || (info.mapcycle != null && info.mapcycle.FindString(map) != -1));
}

public void OnConfigsExecuted()
{
	if(!late_loaded) {
		if(!reset_next_map) {
			SetNextMap("");
			reset_next_map = true;
		}
	}

	GamemodeInfo modeinfo;
	char map_path[PLATFORM_MAX_PATH];

	StringMapSnapshot snap = gamemode_map_map.Snapshot();
	int len = snap.Length;
	for(int i = 0; i < len; ++i) {
		snap.GetKey(i, map_path, PLATFORM_MAX_PATH);

		ArrayList modes;
		if(gamemode_map_map.GetValue(map_path, modes)) {
			modes.Clear();
		}
	}
	delete snap;

	len = gamemodes.Length;
	for(int i = 0; i < len; ++i) {
		gamemodes.GetArray(i, modeinfo, sizeof(GamemodeInfo));

		mcm_read_maps(modeinfo.name, modeinfo.mapcycle);

		int len2 = modeinfo.mapcycle.Length;
		for(int j = 0; j < len2; ++j) {
			modeinfo.mapcycle.GetString(j, map_path, PLATFORM_MAX_PATH);

			ArrayList modes;
			if(!gamemode_map_map.GetValue(map_path, modes)) {
				modes = new ArrayList();
				gamemode_map_map.SetValue(map_path, modes);
			}

			modes.Push(i);
		}
	}

	char gamemode_name[GAMEMODE_NAME_MAX];
	gmm_default_gamemode.GetString(gamemode_name, GAMEMODE_NAME_MAX);

	if(gamemode_name[0] != '\0') {
		int idx = -1;
		if(!gamemode_idx_map.GetValue(gamemode_name, idx)) {
			LogError(GMM_CON_PREFIX ... "invalid default gamemode '%s'", gamemode_name);
		}
		default_gamemode = idx;
	}

	if(start_gamemode == -1) {
		if(gamemode_name[0] == '\0') {
			gmm_start_gamemode.GetString(gamemode_name, GAMEMODE_NAME_MAX);
		}

		if(gamemode_name[0] != '\0') {
			int mode = -1;
			if(StrEqual(gamemode_name, "random")) {
				mode = get_random_gamemode_idx();
			} else {
				if(!gamemode_idx_map.GetValue(gamemode_name, mode)) {
					LogError(GMM_CON_PREFIX ... "invalid start gamemode '%s'", gamemode_name);
				}
			}
			start_gamemode = mode;

			if(start_gamemode != -1) {
				if(!late_loaded) {
					if(!is_gamemode_valid_for_map(start_gamemode, current_map)) {
						next_gamemode = start_gamemode;
						change_to_random_gamemode_map(start_gamemode);
					} else {
						if(current_gamemode != start_gamemode) {
							load_gamemode(start_gamemode);
						}
					}
				}
			}
		}
	}

	if(default_gamemode != -1) {
		if(current_gamemode == -1 && next_gamemode == -1) {
			if(!is_gamemode_valid_for_map(default_gamemode, current_map)) {
				next_gamemode = default_gamemode;
				change_to_random_gamemode_map(default_gamemode);
			} else {
				load_gamemode(default_gamemode);
			}
		}
	}

	can_rtg = true;
	rtg_allowed = false;
	rtg_time = GetTime() + rtg_initialdelay.IntValue;
	CreateTimer(rtg_initialdelay.FloatValue, timer_delayrtg, _, TIMER_FLAG_NO_MAPCHANGE);
}

static Action timer_delayrtg(Handle timer, any data)
{
	rtg_allowed = true;
	return Plugin_Continue;
}

static bool get_random_gamemode_for_map(const char[] map, int &idx, int except = -1)
{
	ArrayList modes;
	if(gamemode_map_map.GetValue(map, modes)) {
		ArrayList modes_clone = new ArrayList();

		GamemodeInfo info;

		int len = modes.Length;
		for(int i = 0; i < len; ++i) {
			int mode = modes.Get(i);

			if(mode == except || mode == current_gamemode) {
				continue;
			}

			gamemodes.GetArray(mode, info, sizeof(GamemodeInfo));

			if(!is_gamemode_valid(info)) {
				continue;
			}

			modes_clone.Push(mode);
		}

		len = modes_clone.Length;
		if(len == 0) {
			idx = -1;
		} else {
			idx = modes_clone.Get(GetRandomInt(0, len-1));
		}

		delete modes_clone;

		return (idx != -1);
	}
	return false;
}

static void load_gamemode_for_map(const char[] map, int except = -1)
{
#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "loading gamemode for map %s", map);
#endif

	if(current_gamemode != -1) {
		if((current_gamemode == except) || !is_gamemode_valid_for_map(current_gamemode, map)) {
			int idx = -1;
			if(get_random_gamemode_for_map(map, idx, except)) {
				load_gamemode(idx);
			} else if(default_gamemode != -1 && is_gamemode_valid_for_map(default_gamemode, map)) {
				load_gamemode(default_gamemode);
			} else {
				unload_current_gamemode();
			}
		}
	} else {
		int idx = -1;
		if(get_random_gamemode_for_map(map, idx, except)) {
			load_gamemode(idx);
		} else if(default_gamemode != -1 && is_gamemode_valid_for_map(default_gamemode, map)) {
			load_gamemode(default_gamemode);
		}
	}
}

public void OnMapEnd()
{
	can_rtg = false;
	rtg_allowed = false;
	voters = 0;
	votes = 0;
	votes_needed = 0;

	if(next_gamemode != -1) {
	#if defined DEBUG
		PrintToServer(GMM_CON_PREFIX ... "loading next gamemode");
	#endif
		load_gamemode(next_gamemode);
		next_gamemode = -1;
	}

#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "loading gamemode for next map");
#endif

	char next_map[PLATFORM_MAX_PATH];
	if(GetNextMap(next_map, PLATFORM_MAX_PATH)) {
		load_gamemode_for_map(next_map);
	}
}

public void OnMapStart()
{
	voters = 0;
	votes = 0;
	votes_needed = 0;

#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "loading gamemode for current map");
#endif
	GetCurrentMap(current_map, PLATFORM_MAX_PATH);
	load_gamemode_for_map(current_map);
}
#include <sourcemod>
#include <regex>
#include <morecolors>
#include <nativevotes>
#include <aliasrandom>
#include <SteamWorks>
#include <sdktools>
#include <mapchooser>

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

enum struct GamemodeInfo
{
	char name[GAMEMODE_NAME_MAX];
	float weight;
	float time;
	ArrayList plugins;
	ArrayList plugins_disable;
	bool maps_is_whitelist;
	ArrayList maps_regex;
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

static ConVar gmm_default_gamemode;

static char original_mapcyclefile_value[PLATFORM_MAX_PATH];
static ConVar mapcyclefile;
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

		if(modeinfo.maps_regex != null) {
			int len2 = modeinfo.maps_regex.Length;
			for(int j = 0; j < len2; ++j) {
				Regex rex = modeinfo.maps_regex.Get(j);
				delete rex;
			}
		}

		delete modeinfo.plugins;
		delete modeinfo.plugins_disable;
		delete modeinfo.maps_regex;
		delete modeinfo.mapcycle;
		delete modeinfo.disabled.commands;
		delete modeinfo.enabled.commands;
	}

	char map[PLATFORM_MAX_PATH];

	StringMapSnapshot snap = gamemode_map_map.Snapshot();
	len = snap.Length;
	for(int i = 0; i < len; ++i) {
		snap.GetKey(i, map, PLATFORM_MAX_PATH);

		ArrayList modes;
		gamemode_map_map.GetValue(map, modes);

		delete modes;
	}
	delete snap;

	delete gamemodes;
	delete gamemode_idx_map;
	delete gamemode_map_map;
}

static void build_mapcycle_filepath(char path[PLATFORM_MAX_PATH], char name[GAMEMODE_NAME_MAX])
{
	char name_copy[GAMEMODE_NAME_MAX];
	strcopy(name_copy, GAMEMODE_NAME_MAX, name);

	ReplaceString(name_copy, GAMEMODE_NAME_MAX, " ", "_");
	ReplaceString(name_copy, GAMEMODE_NAME_MAX, ":", "_");
	ReplaceString(name_copy, GAMEMODE_NAME_MAX, ".", "_");

	BuildPath(Path_SM, path, PLATFORM_MAX_PATH, "data/gmm/mapcycles/%s.txt", name_copy);
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

static void kv_handle_plugins(KeyValues kv, ArrayList &arr, const char[] name, const char[] plugins_folder_path)
{
	if(kv.JumpToKey(name)) {
		if(kv.GotoFirstSubKey(false)) {
			arr = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

			char disabled_plugin_path[PLATFORM_MAX_PATH];
			char any_file_path[PLATFORM_MAX_PATH];

			do {
				kv.GetString(NULL_STRING, any_file_path, PLATFORM_MAX_PATH);

				int i = strlen(any_file_path)-1;
				while(i > 0 && any_file_path[--i] != '/') {}

				int j = 0;
				for(; j < i; ++j) {
					disabled_plugin_path[j] = any_file_path[j];
				}
				disabled_plugin_path[j] = '\0';

				Format(disabled_plugin_path, PLATFORM_MAX_PATH, "%s/disabled/%s", plugins_folder_path, disabled_plugin_path);

				CreateDirectory(disabled_plugin_path, FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC);

				arr.PushString(any_file_path);
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
		char any_file_path[PLATFORM_MAX_PATH];

		if(kv.GotoFirstSubKey()) {
			gamemodes = new ArrayList(sizeof(GamemodeInfo));
			gamemode_idx_map = new StringMap();
			gamemode_map_map = new StringMap();

			char regex_str[128];
			char cmd_str[CMD_STR_MAX];

			char plugins_folder_path[PLATFORM_MAX_PATH];
			BuildPath(Path_SM, plugins_folder_path, PLATFORM_MAX_PATH, "plugins");

			do {
				kv.GetSectionName(info.name, GAMEMODE_NAME_MAX);

				kv_handle_plugins(kv, info.plugins, "plugins", plugins_folder_path);
				kv_handle_plugins(kv, info.plugins_disable, "plugins_disable", plugins_folder_path);

				int maps = -1;
				bool valid = true;
				info.maps_is_whitelist = false;

				if(kv.JumpToKey("maps_whitelist")) {
					if(kv.JumpToKey("maps_blacklist")) {
						LogError(GMM_CON_PREFIX ... " gamemode %s has both maps_whitelist and maps_blacklist", info.name);
						valid = false;
						kv.GoBack();
					}
					info.maps_is_whitelist = true;
					maps = 0;
				}

				if(kv.JumpToKey("maps_blacklist")) {
					if(kv.JumpToKey("maps_whitelist")) {
						LogError(GMM_CON_PREFIX ... " gamemode %s has both maps_blacklist and maps_whitelist", info.name);
						valid = false;
						kv.GoBack();
					}
					maps = 1;
				}

				if(!valid) {
					delete info.plugins;
					delete info.plugins_disable;
					continue;
				}

				if(maps != -1) {
					if(kv.GotoFirstSubKey(false)) {
						info.maps_regex = new ArrayList();

						do {
							kv.GetString(NULL_STRING, any_file_path, PLATFORM_MAX_PATH);

							RegexError regex_code;
							Regex regex = new Regex(any_file_path, PCRE_UTF8, regex_str, sizeof(regex_str), regex_code);
							if(regex_code != REGEX_ERROR_NONE) {
								delete regex;
								LogError(GMM_CON_PREFIX ... " gamemode %s has invalid map regex \"%s\": \"%s\" (%i)", info.name, any_file_path, regex_str, regex_code);
								valid = false;
								break;
							}

							info.maps_regex.Push(regex);
						} while(kv.GotoNextKey(false));

						kv.GoBack();
					} else {
						info.maps_regex = null;
					}

					kv.GoBack();
				} else {
					info.maps_regex = null;
				}

				if(!valid) {
					if(info.maps_regex != null) {
						int len = info.maps_regex.Length;
						for(int i = 0; i < len; ++i) {
							Regex regex = info.maps_regex.Get(i);
							delete regex;
						}
					}
					delete info.maps_regex;
					continue;
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

		DirectoryListing maps_dir = OpenDirectory("maps", true);
		FileType filetype;
		while(maps_dir.GetNext(any_file_path, PLATFORM_MAX_PATH, filetype)) {
			if(filetype != FileType_File) {
				continue;
			}

			int bsp = StrContains(any_file_path, ".bsp");
			if(bsp == -1) {
				continue;
			}

			if((strlen(any_file_path)-bsp) != 4) {
				continue;
			}

			any_file_path[bsp] = '\0';

			if(StrEqual(any_file_path, "background01") ||
				StrEqual(any_file_path, "itemtest") ||
				StrEqual(any_file_path, "cp_cloak") ||
				StrContains(any_file_path, "tr_") == 0) {
				continue;
			}

			ArrayList modes;
			if(!gamemode_map_map.GetValue(any_file_path, modes)) {
				modes = new ArrayList();
				gamemode_map_map.SetValue(any_file_path, modes);
			}

			bool unmatched = true;

			int modes_len = gamemodes.Length;
			for(int i = 0; i < modes_len; ++i) {
				gamemodes.GetArray(i, info, sizeof(GamemodeInfo));

				if(info.maps_regex == null) {
					continue;
				}

				int maps_regex_len = info.maps_regex.Length;
				for(int j = 0; j < maps_regex_len; ++j) {
					Regex regex = info.maps_regex.Get(j);

					if(info.maps_is_whitelist && regex.Match(any_file_path) < 1) {
						continue;
					} else if(!info.maps_is_whitelist && regex.Match(any_file_path) > 0) {
						continue;
					}

					if(modes.FindValue(i) == -1) {
						modes.Push(i);
						info.mapcycle.PushString(any_file_path);
						if(info.maps_is_whitelist) {
							unmatched = false;
						}
					}
				}
			}

			if(unmatched) {
				for(int i = 0; i < modes_len; ++i) {
					gamemodes.GetArray(i, info, sizeof(GamemodeInfo));

					if(info.maps_regex != null) {
						continue;
					}

					if(modes.FindValue(i) == -1) {
						modes.Push(i);
						info.mapcycle.PushString(any_file_path);
					}
				}
			}

			if(modes.Length == 0) {
				delete modes;
				gamemode_map_map.Remove(any_file_path);
			}
		}
		delete maps_dir;

	#if defined DEBUG
		for(int i = 0; i < gamemodes.Length; ++i) {
			gamemodes.GetArray(i, info, sizeof(GamemodeInfo));

			PrintToServer(GMM_CON_PREFIX ... "mode %s has maps:", info.name);

			char map[PLATFORM_MAX_PATH];

			for(int j = 0; j < info.mapcycle.Length; ++j) {
				info.mapcycle.GetString(j, map, PLATFORM_MAX_PATH);

				PrintToServer(GMM_CON_PREFIX ... "  %s", map);
			}
		}
	#endif

		BuildPath(Path_SM, any_file_path, PLATFORM_MAX_PATH, "data/gmm");
		CreateDirectory(any_file_path, FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC);

		BuildPath(Path_SM, any_file_path, PLATFORM_MAX_PATH, "data/gmm/mapcycles");
		CreateDirectory(any_file_path, FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC);

		int modes_len = gamemodes.Length;
		for(int i = 0; i < modes_len; ++i) {
			gamemodes.GetArray(i, info, sizeof(GamemodeInfo));

			build_mapcycle_filepath(any_file_path, info.name);
			File cycle_file = OpenFile(any_file_path, "w+");

			int mapcycle_len = info.mapcycle.Length;
			for(int j = 0; j < mapcycle_len; ++j) {
				info.mapcycle.GetString(j, any_file_path, PLATFORM_MAX_PATH);
				StrCat(any_file_path, PLATFORM_MAX_PATH, "\n");
				cycle_file.WriteString(any_file_path, true);
			}

			delete cycle_file;
		}
	}
}

public void OnNotifyPluginUnloaded(Handle plugin)
{
	if(ff2_plugin != null && plugin == ff2_plugin) {
		//toggle_ff2_folder(false);
		ff2_plugin = null;
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
	late_loaded = late;
	toggle_ff2_folder(false);
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	gamemode_history = new ArrayList();

	load_gamemodes();

#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "plugin loaded unloading all gamemodes");
#endif

	int len = gamemodes.Length;
	for(int i = 0; i < len; ++i) {
		unload_gamemode(i);
	}

	gmm_default_gamemode = CreateConVar("gmm_default_gamemode", "random");

	mapcyclefile = FindConVar("mapcyclefile");

	RegAdminCmd("sm_rgmm", sm_rgmm, ADMFLAG_ROOT);
	RegAdminCmd("sm_fgm", sm_fgm, ADMFLAG_ROOT);
	RegAdminCmd("sm_fgmv", sm_fgmv, ADMFLAG_ROOT);

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

static Action sm_fgmv(int client, int args)
{
	if(change_gamemode_timer != null) {
		KillTimer(change_gamemode_timer);
	}
	change_gamemode_timer = CreateTimer(0.1, timer_change_gamemode);
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
			} else {
				int idx = -1;
				if(gamemode_idx_map.GetValue(name, idx)) {
					mode = idx;
				} else {
					CReplyToCommand(client, GMM_CHAT_PREFIX ... "invalid gamemode name %s", name);
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

	CPrintToChatAll(GMM_CHAT_PREFIX ... "Changing to map %s", map);

	CreateTimer(time * 0.8, timer_load_next_gamemode, 0, TIMER_FLAG_NO_MAPCHANGE);

	SetNextMap(map);

	DataPack data;
	CreateDataTimer(time, timer_change_to_map, data, TIMER_FLAG_NO_MAPCHANGE);
	data.WriteString(map);
}

static void change_to_random_gamemode_map(int mode)
{
	GamemodeInfo info;
	gamemodes.GetArray(mode, info, sizeof(GamemodeInfo));

	int map_idx = GetRandomInt(0, info.mapcycle.Length-1);

	char map[PLATFORM_MAX_PATH];
	info.mapcycle.GetString(map_idx, map, PLATFORM_MAX_PATH);

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

			GamemodeInfo info;
			gamemodes.GetArray(idx, info, sizeof(GamemodeInfo));

			menu.DisplayPassEx(NativeVotesPass_ChgMission, "%s", info.name);
			CPrintToChatAll(GMM_CHAT_PREFIX ... "%s won the gamemode vote", info.name);

			next_gamemode = idx;

			if(info.mapcycle.Length == 1) {
				char next_map[PLATFORM_MAX_PATH];
				info.mapcycle.GetString(0, next_map, PLATFORM_MAX_PATH);

				change_to_map(next_map);
			} else {
				InitiateMapChooserVote(MapChange_RoundEnd, info.mapcycle);
			}
		}
		case MenuAction_VoteCancel: {
			switch(param1) {
				case VoteCancel_Generic:
				{ menu.DisplayFail(NativeVotesFail_Generic); }
				case VoteCancel_NoVotes:
				{ menu.DisplayFail(NativeVotesFail_NotEnoughVotes); }
			}
			change_gamemode_timer = CreateTimer(1.0, timer_change_gamemode);
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
			continue;
		}
		weights.Push(info.weight);
		to_choose.Push(i);
	}

	ArrayList aliases = CreateAliasRandom(weights);

	char int_str[INT_STR_MAX];

	int to_choose_len = to_choose.Length;
	int max = to_choose_len > 5 ? 5 : to_choose_len;
	for(int i = 0; i < max; ++i) {
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

	vote_menu.DisplayVoteToAll(20);
}

public void OnClientPutInServer(int client)
{
	if(IsFakeClient(client) ||
		IsClientReplay(client) ||
		IsClientSourceTV(client)) {
		return;
	}

	
}

public void OnClientDisconnect(int client)
{
	if(IsFakeClient(client) ||
		IsClientReplay(client) ||
		IsClientSourceTV(client)) {
		return;
	}

	bool any_human = false;
	for(int i = 1; i <= MaxClients; ++i) {
		if(i == client) {
			continue;
		}

		if(IsClientInGame(i) && !(
			IsFakeClient(i) ||
			IsClientReplay(i) ||
			IsClientSourceTV(i)
		)) {
			any_human = true;
		}
	}

	
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if(IsChatTrigger()) {
		return;
	}

	if(StrEqual(sArgs, "rtg")) {
		ReplySource oldsrc = SetCmdReplySource(SM_REPLY_TO_CHAT);
		
		SetCmdReplySource(oldsrc);
	}
}

static void handle_gamemode_plugins(GamemodeInfo info, bool unload)
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
				}
				RenameFile(plugin_disabled_path, plugin_enabled_path);
			}
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

			bool is_ff2 = (StrContains(plugin_filename, "freak_fortress_2") != -1);
			if(is_ff2) {
				toggle_ff2_folder(!unload);
				if(unload) {
					ff2_plugin = null;
				}
			}

			if(unload) {
				if(FileExists(plugin_enabled_path)) {
					InsertServerCommand("sm plugins unload \"%s\"", plugin_filename);
				}
				RenameFile(plugin_disabled_path, plugin_enabled_path);
			} else {
				RenameFile(plugin_enabled_path, plugin_disabled_path);
				if(FileExists(plugin_enabled_path)) {
					InsertServerCommand("sm plugins load \"%s\"", plugin_filename);
				}
			}

			if(is_ff2 && !unload) {
				ff2_plugin = FindPluginByFile("freak_fortress_2.smx");
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
				}
			}
		}
	}

	ServerExecute();
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

static void unload_gamemode(int idx)
{
	GamemodeInfo info;
	gamemodes.GetArray(idx, info, sizeof(GamemodeInfo));

#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "unloaded %s", info.name);
#endif

	handle_gamemode_state(info.disabled);
	handle_gamemode_plugins(info, true);

	SteamWorks_SetGameDescription("Team Fortress");
}

static void unload_current_gamemode()
{
	if(current_gamemode == -1) {
		return;
	}

	mapcyclefile.SetString(original_mapcyclefile_value);

	if(change_gamemode_timer != null) {
		KillTimer(change_gamemode_timer);
		change_gamemode_timer = null;
	}

#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "unloading current gamemode");
#endif

	unload_gamemode(current_gamemode);
	current_gamemode = -1;
}

static Action timer_change_gamemode(Handle timer, any data)
{
	if(NativeVotes_IsVoteInProgress()) {
		NativeVotes_Cancel();
	}

	start_gamemode_vote();

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

	handle_gamemode_plugins(info, false);
	handle_gamemode_state(info.enabled);

	char cycle_path[PLATFORM_MAX_PATH];
	build_mapcycle_filepath(cycle_path, info.name);

	mapcyclefile.SetString(cycle_path);

	change_gamemode_timer = CreateTimer(info.time * 60, timer_change_gamemode);
}

public void OnPluginEnd()
{
#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "plugin unloaded unloading current gamemode");
#endif
	unload_current_gamemode();
}

static int get_random_gamemode_idx()
{
	GamemodeInfo info;

	ArrayList weights = new ArrayList();
	ArrayList to_choose = new ArrayList();

	int len = gamemodes.Length;
	for(int i = 0; i < len; ++i) {
		gamemodes.GetArray(i, info, sizeof(GamemodeInfo));
		if(gamemode_history.FindValue(i) != -1 ||
			i == current_gamemode) {
			continue;
		}
		weights.Push(info.weight);
		to_choose.Push(i);
	}

	ArrayList aliases = CreateAliasRandom(weights);

	int idx = GetAliasRandom(aliases);
	int mode = to_choose.Get(idx);

	delete aliases;
	delete weights;
	delete to_choose;

	return mode;
}

static bool is_gamemode_valid_for_map(int mode, const char[] map)
{
	ArrayList modes;
	if(gamemode_map_map.GetValue(map, modes)) {
		return (modes.FindValue(mode) != -1);
	}
	return false;
}

public void OnConfigsExecuted()
{
	if(!late_loaded) {
		if(!reset_next_map) {
			SetNextMap("");
			reset_next_map = true;
		}
	}

	if(original_mapcyclefile_value[0] == '\0') {
		mapcyclefile.GetString(original_mapcyclefile_value, PLATFORM_MAX_PATH);
	}

	if(default_gamemode == -1) {
		char gamemode_name[GAMEMODE_NAME_MAX];
		gmm_default_gamemode.GetString(gamemode_name, GAMEMODE_NAME_MAX);

		if(gamemode_name[0] != '\0') {
			if(StrEqual(gamemode_name, "random")) {
				default_gamemode = get_random_gamemode_idx();
			} else {
				int idx = -1;
				if(gamemode_idx_map.GetValue(gamemode_name, idx)) {
					default_gamemode = idx;
				} else {
					LogError(GMM_CON_PREFIX ... "invalid default gamemode %s", gamemode_name);
				}
			}

			if(default_gamemode != -1) {
				if(!late_loaded) {
					if(!is_gamemode_valid_for_map(default_gamemode, current_map)) {
						next_gamemode = default_gamemode;
						change_to_random_gamemode_map(default_gamemode);
					} else {
						if(current_gamemode != default_gamemode) {
							load_gamemode(default_gamemode);
						}
					}
				}
			}
		}
	}

	if(current_gamemode != -1) {
		GamemodeInfo info;
		gamemodes.GetArray(current_gamemode, info, sizeof(GamemodeInfo));

		char cycle_path[PLATFORM_MAX_PATH];
		build_mapcycle_filepath(cycle_path, info.name);

		mapcyclefile.SetString(cycle_path);
	}
}

static void load_gamemode_for_map(const char[] map)
{
#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "loading gamemode for map %s", map);
#endif

	if(current_gamemode != -1) {
		ArrayList modes;
		if(gamemode_map_map.GetValue(map, modes)) {
			if(modes.FindValue(current_gamemode) == -1) {
				int idx = modes.Get(GetRandomInt(0, modes.Length-1));
				load_gamemode(idx);
			}
		} else {
			unload_current_gamemode();
		}
	} else {
		ArrayList modes;
		if(gamemode_map_map.GetValue(map, modes)) {
			int idx = modes.Get(GetRandomInt(0, modes.Length-1));
			load_gamemode(idx);
		}
	}
}

public void OnMapEnd()
{
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
#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "loading gamemode for current map");
#endif
	GetCurrentMap(current_map, PLATFORM_MAX_PATH);
	load_gamemode_for_map(current_map);
}
#include <sourcemod>
#include <regex>
#include <morecolors>

//#define DEBUG

#define GAMEMODE_NAME_MAX 64

#define GAMEMODE_BREATHE_TIME 0.5

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
	ArrayList plugins;
	bool maps_is_whitelist;
	ArrayList maps_regex;
	StateChangeInfo enabled;
	StateChangeInfo disabled;
	ArrayList mapcycle;
	Menu cyclemenu;
}

static ArrayList gamemodes;
static StringMap gamemodeidmap;
static StringMap gamemodemapmap;
static int currentgamemode = -1;
static int nextgamemode = -1;
static int num_voters;
static int num_votes;
static int votes_needed;
static bool voted[MAXPLAYERS+1];
static ConVar gmm_votes_needed;
static ConVar gmm_default;
static ConVar gmm_initial_delay;
static ConVar gmm_fail_delay;
static ConVar gmm_map_time;
static Menu gamemodemenu;
static bool votes_allowed;
static char currentmap[PLATFORM_MAX_PATH];

static void handle_str_array(KeyValues kvModes, const char[] name, ArrayList &arr, char[] str, int size)
{
	if(kvModes.JumpToKey(name)) {
		if(kvModes.GotoFirstSubKey(false)) {
		#if defined DEBUG
			PrintToServer(GMM_CON_PREFIX ... "  %s", name);
		#endif

			arr = new ArrayList(ByteCountToCells(size));

			do {
				kvModes.GetString(NULL_STRING, str, size);
			#if defined DEBUG
				PrintToServer(GMM_CON_PREFIX ... "    %s", str);
			#endif

				arr.PushString(str);
			} while(kvModes.GotoNextKey(false));

			kvModes.GoBack();
		} else {
			arr = null;
		}

		kvModes.GoBack();
	} else {
		arr = null;
	}
}

static void unload_gamemodes()
{
	unload_currentgamemode();

	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			IsFakeClient(i)) {
			continue;
		}

		voted[i] = false;
	}

	num_votes = 0;
	votes_allowed = true;

	nextgamemode = -1;

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
		delete modeinfo.maps_regex;
		delete modeinfo.mapcycle;
		delete modeinfo.cyclemenu;
		delete modeinfo.disabled.commands;
		delete modeinfo.enabled.commands;
	}

	char map[PLATFORM_MAX_PATH];

	StringMapSnapshot snap = gamemodemapmap.Snapshot();
	len = snap.Length;
	for(int i = 0; i < len; ++i) {
		snap.GetKey(i, map, PLATFORM_MAX_PATH);

		ArrayList modes = null;
		gamemodemapmap.GetValue(map, modes);

		delete modes;
	}
	delete snap;

	delete gamemodes;
	delete gamemodeidmap;
	delete gamemodemapmap;
	delete gamemodemenu;
}

static void handle_state_changed(KeyValues kvModes, const char[] name, char cmdstr[CMD_STR_MAX], StateChangeInfo stateinfo)
{
	if(kvModes.JumpToKey(name)) {
		kvModes.GetString("cfg", stateinfo.cfg, PLATFORM_MAX_PATH);
		handle_str_array(kvModes, "commands", stateinfo.commands, cmdstr, CMD_STR_MAX);
		kvModes.GoBack();
	}
}

static int menuhandler_maps(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action) {
		case MenuAction_DrawItem: {
			char menumap[PLATFORM_MAX_PATH];
			menu.GetItem(param1, menumap, PLATFORM_MAX_PATH);

			if(StrEqual(currentmap, menumap)) {
				return ITEMDRAW_IGNORE;
			} else {
				return ITEMDRAW_DEFAULT;
			}
		}
		case MenuAction_DisplayItem: {
			char menumap[PLATFORM_MAX_PATH];
			menu.GetItem(param1, menumap, PLATFORM_MAX_PATH);

			if(StrEqual(currentmap, menumap)) {
				return RedrawMenuItem("");
			} else {
				return 0;
			}
		}
		case MenuAction_VoteEnd: {
			char menumap[PLATFORM_MAX_PATH];
			menu.GetItem(param1, menumap, PLATFORM_MAX_PATH);

			CPrintToChatAll(GMM_CHAT_PREFIX ... "%s won the map vote", menumap);

			votes_allowed = false;

			CreateTimer(gmm_map_time.FloatValue-GAMEMODE_BREATHE_TIME, timer_unloadgamemode, 0, TIMER_FLAG_NO_MAPCHANGE);

			DataPack data = null;
			CreateDataTimer(gmm_map_time.FloatValue, timer_changemap, data, TIMER_FLAG_NO_MAPCHANGE);
			data.WriteString(menumap);

			num_votes = 0;
			for(int j = 1; j <= MaxClients; ++j) {
				if(!IsClientInGame(j) ||
					IsFakeClient(j)) {
					continue;
				}
				voted[j] = false;
			}
		}
		case MenuAction_VoteCancel: {
			votes_allowed = false;
			num_votes = 0;
			for(int j = 1; j <= MaxClients; ++j) {
				if(!IsClientInGame(j) ||
					IsFakeClient(j)) {
					continue;
				}
				voted[j] = false;
			}
			CreateTimer(gmm_fail_delay.FloatValue, timer_allowvotes);
		}
	}

	return 0;
}

static int menuhandler_gamemodes(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action) {
		case MenuAction_DrawItem: {
			char intstr[INT_STR_MAX];
			menu.GetItem(param1, intstr, INT_STR_MAX);
			int idx = StringToInt(intstr);

			if(idx == currentgamemode) {
				return ITEMDRAW_IGNORE;
			} else {
				return ITEMDRAW_DEFAULT;
			}
		}
		case MenuAction_DisplayItem: {
			char intstr[INT_STR_MAX];
			menu.GetItem(param1, intstr, INT_STR_MAX);
			int idx = StringToInt(intstr);

			if(idx == currentgamemode) {
				return RedrawMenuItem("");
			} else {
				return 0;
			}
		}
		case MenuAction_VoteEnd: {
			char intstr[INT_STR_MAX];
			menu.GetItem(param1, intstr, INT_STR_MAX);
			int idx = StringToInt(intstr);

			GamemodeInfo modeinfo;
			gamemodes.GetArray(idx, modeinfo, sizeof(GamemodeInfo));

			nextgamemode = idx;

			CPrintToChatAll(GMM_CHAT_PREFIX ... "%s won the gamemode vote", modeinfo.name);

			votes_allowed = false;

			modeinfo.cyclemenu.DisplayVoteToAll(MENU_TIME_FOREVER);

			num_votes = 0;
			for(int j = 1; j <= MaxClients; ++j) {
				if(!IsClientInGame(j) ||
					IsFakeClient(j)) {
					continue;
				}
				voted[j] = false;
			}
		}
		case MenuAction_VoteCancel: {
			nextgamemode = -1;
			votes_allowed = false;
			num_votes = 0;
			for(int j = 1; j <= MaxClients; ++j) {
				if(!IsClientInGame(j) ||
					IsFakeClient(j)) {
					continue;
				}
				voted[j] = false;
			}
			CreateTimer(gmm_fail_delay.FloatValue, timer_allowvotes);
		}
	}

	return 0;
}

static Action timer_unloadgamemode(Handle timer, any data)
{
	unload_currentgamemode();
	if(nextgamemode != -1) {
		load_gamemode(nextgamemode);
	}
	return Plugin_Continue;
}

static Action timer_changemap(Handle timer, DataPack data)
{
	data.Reset();

	char map[PLATFORM_MAX_PATH];
	data.ReadString(map, PLATFORM_MAX_PATH);

	ForceChangeLevel(map, "GMM");

	return Plugin_Continue;
}

static void load_gamemodes()
{
	char gamemodefile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, gamemodefile, PLATFORM_MAX_PATH, "configs/gmm/gamemodes.txt");

	if(FileExists(gamemodefile)) {
		KeyValues kvModes = new KeyValues("Gamemodes");
		kvModes.ImportFromFile(gamemodefile);

		GamemodeInfo modeinfo;
		char anyfilepath[PLATFORM_MAX_PATH];

		if(kvModes.GotoFirstSubKey()) {
			gamemodes = new ArrayList(sizeof(GamemodeInfo));
			gamemodeidmap = new StringMap();
			gamemodemapmap = new StringMap();
			gamemodemenu = new Menu(menuhandler_gamemodes, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem|MenuAction_DisplayItem);
			gamemodemenu.SetTitle("Gamemodes");
			gamemodemenu.ExitButton = false;

			char rexerrstr[128];
			char cmdstr[CMD_STR_MAX];
			char intstr[INT_STR_MAX];

			char pluginsfolder[PLATFORM_MAX_PATH];
			BuildPath(Path_SM, pluginsfolder, PLATFORM_MAX_PATH, "plugins");

			char disabledpath[PLATFORM_MAX_PATH];

			static const int folderflags = (
				FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC
			);

			do {
				kvModes.GetSectionName(modeinfo.name, GAMEMODE_NAME_MAX);
			#if defined DEBUG
				PrintToServer(GMM_CON_PREFIX ... "%s", modeinfo.name);
			#endif

				if(kvModes.JumpToKey("plugins")) {
					if(kvModes.GotoFirstSubKey(false)) {
					#if defined DEBUG
						PrintToServer(GMM_CON_PREFIX ... "  plugins");
					#endif

						modeinfo.plugins = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

						do {
							kvModes.GetString(NULL_STRING, anyfilepath, PLATFORM_MAX_PATH);
						#if defined DEBUG
							PrintToServer(GMM_CON_PREFIX ... "    %s", anyfilepath);
						#endif

							int i = strlen(anyfilepath)-1;
							while(i > 0 && anyfilepath[--i] != '/') {}

							int j = 0;
							for(; j < i; ++j) {
								disabledpath[j] = anyfilepath[j];
							}
							disabledpath[j] = '\0';

							Format(disabledpath, PLATFORM_MAX_PATH, "%s/disabled/%s", pluginsfolder, disabledpath);

							CreateDirectory(disabledpath, folderflags);

							modeinfo.plugins.PushString(anyfilepath);
						} while(kvModes.GotoNextKey(false));

						kvModes.GoBack();
					} else {
						modeinfo.plugins = null;
					}

					kvModes.GoBack();
				} else {
					modeinfo.plugins = null;
				}

				int maps = -1;

				bool valid = true;

				modeinfo.maps_is_whitelist = false;

				if(kvModes.JumpToKey("maps_whitelist")) {
					if(kvModes.JumpToKey("maps_blacklist")) {
						LogError(GMM_CON_PREFIX ... " gamemode %s has both maps_whitelist and maps_blacklist", modeinfo.name);
						valid = false;
						kvModes.GoBack();
					}
					modeinfo.maps_is_whitelist = true;
					maps = 0;
				}

				if(kvModes.JumpToKey("maps_blacklist")) {
					if(kvModes.JumpToKey("maps_whitelist")) {
						LogError(GMM_CON_PREFIX ... " gamemode %s has both maps_blacklist and maps_whitelist", modeinfo.name);
						valid = false;
						kvModes.GoBack();
					}
					maps = 1;
				}

				if(!valid) {
					delete modeinfo.plugins;
					continue;
				}

				if(maps != -1) {
					if(kvModes.GotoFirstSubKey(false)) {
					#if defined DEBUG
						if(maps == 0) {
							PrintToServer(GMM_CON_PREFIX ... "  maps_whitelist");
						} else {
							PrintToServer(GMM_CON_PREFIX ... "  maps_blacklist");
						}
					#endif

						modeinfo.maps_regex = new ArrayList();

						do {
							kvModes.GetString(NULL_STRING, anyfilepath, PLATFORM_MAX_PATH);

						#if defined DEBUG
							PrintToServer(GMM_CON_PREFIX ... "    %s", anyfilepath);
						#endif

							RegexError rexerrcode;
							Regex rex = new Regex(anyfilepath, PCRE_UTF8, rexerrstr, sizeof(rexerrstr), rexerrcode);
							if(rexerrcode != REGEX_ERROR_NONE) {
								delete rex;
								LogError(GMM_CON_PREFIX ... " gamemode %s has invalid map regex \"%s\": \"%s\" (%i)", modeinfo.name, anyfilepath, rexerrstr, rexerrcode);
								valid = false;
								break;
							}

							modeinfo.maps_regex.Push(rex);
						} while(kvModes.GotoNextKey(false));

						kvModes.GoBack();
					} else {
						modeinfo.maps_regex = null;
					}

					kvModes.GoBack();
				} else {
					modeinfo.maps_regex = null;
				}

				if(!valid) {
					if(modeinfo.maps_regex != null) {
						int len = modeinfo.maps_regex.Length;
						for(int i = 0; i < len; ++i) {
							Regex rex = modeinfo.maps_regex.Get(i);
							delete rex;
						}
					}
					delete modeinfo.maps_regex;
					continue;
				}

				handle_state_changed(kvModes, "enabled", cmdstr, modeinfo.enabled);

				modeinfo.mapcycle = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

				modeinfo.cyclemenu = new Menu(menuhandler_maps, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem|MenuAction_DisplayItem);
				modeinfo.cyclemenu.SetTitle("Maps");
				modeinfo.cyclemenu.ExitButton = false;

				int idx = gamemodes.PushArray(modeinfo, sizeof(GamemodeInfo));

				gamemodeidmap.SetValue(modeinfo.name, idx);

				IntToString(idx, intstr, INT_STR_MAX);
				gamemodemenu.AddItem(intstr, modeinfo.name);
			} while(kvModes.GotoNextKey());

			kvModes.GoBack();
		}

	#if defined DEBUG
		PrintToServer(GMM_CON_PREFIX ... "maps:", anyfilepath);
	#endif

		DirectoryListing mapsdir = OpenDirectory("maps", true);
		FileType filetype;
		while(mapsdir.GetNext(anyfilepath, PLATFORM_MAX_PATH, filetype)) {
			if(filetype != FileType_File) {
				continue;
			}

			int bsp = StrContains(anyfilepath, ".bsp");
			if(bsp == -1) {
				continue;
			}

			int pathlen = strlen(anyfilepath);
			if((pathlen-bsp) != 4) {
				continue;
			}

			anyfilepath[bsp] = '\0';

			ArrayList modes;
			if(!gamemodemapmap.GetValue(anyfilepath, modes)) {
				modes = new ArrayList();
				gamemodemapmap.SetValue(anyfilepath, modes);
			}

			bool unmatched = true;

			int len = gamemodes.Length;
			for(int i = 0; i < len; ++i) {
				gamemodes.GetArray(i, modeinfo, sizeof(GamemodeInfo));

				if(modeinfo.maps_regex == null) {
					continue;
				}

				int len2 = modeinfo.maps_regex.Length;
				for(int j = 0; j < len2; ++j) {
					Regex rex = modeinfo.maps_regex.Get(j);

					if(modeinfo.maps_is_whitelist && rex.Match(anyfilepath) < 1) {
						continue;
					} else if(!modeinfo.maps_is_whitelist && rex.Match(anyfilepath) > 0) {
						continue;
					}

					if(modes.FindValue(i) == -1) {
						modes.Push(i);
						modeinfo.mapcycle.PushString(anyfilepath);
						modeinfo.cyclemenu.AddItem(anyfilepath, anyfilepath);
						if(modeinfo.maps_is_whitelist) {
							unmatched = false;
						}
					}
				}
			}

			if(unmatched) {
				for(int i = 0; i < len; ++i) {
					gamemodes.GetArray(i, modeinfo, sizeof(GamemodeInfo));

					if(modeinfo.maps_regex != null) {
						continue;
					}

					if(modes.FindValue(i) == -1) {
						modes.Push(i);
						modeinfo.mapcycle.PushString(anyfilepath);
						modeinfo.cyclemenu.AddItem(anyfilepath, anyfilepath);
					}
				}
			}

			if(modes.Length == 0) {
				delete modes;
				gamemodemapmap.Remove(anyfilepath);
			}

		#if defined DEBUG && 0
			if(modes != null) {
				PrintToServer(GMM_CON_PREFIX ... "  %s", anyfilepath);

				len = modes.Length;
				for(int i = 0; i < len; ++i) {
					int idx = modes.Get(i);

					gamemodes.GetArray(idx, modeinfo, sizeof(GamemodeInfo));

					PrintToServer(GMM_CON_PREFIX ... "    %s", modeinfo.name);
				}
			}
		#endif
		}
		delete mapsdir;
	}
}

public void OnPluginStart()
{
	load_gamemodes();

	int len = gamemodes.Length;
	for(int i = 0; i < len; ++i) {
		unload_gamemode(i);
	}

	gmm_votes_needed = CreateConVar("gmm_votes_needed", "0.60");
	gmm_default = CreateConVar("gmm_default", "");
	gmm_initial_delay = CreateConVar("gmm_initial_delay", "45.0");
	gmm_fail_delay = CreateConVar("gmm_fail_delay", "240.0");
	gmm_map_time = CreateConVar("gmm_map_time", "10.0");

	RegConsoleCmd("sm_rtg", sm_rtg);

	RegAdminCmd("sm_frtg", sm_frtg, ADMFLAG_ROOT);
	RegAdminCmd("sm_rgmm", sm_rgmm, ADMFLAG_ROOT);

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

static Action sm_rgmm(int client, int args)
{
	unload_gamemodes();
	load_gamemodes();
	return Plugin_Handled;
}

public void OnClientPutInServer(int client)
{
	if(IsFakeClient(client)) {
		return;
	}

	++num_voters;

	votes_needed = RoundToCeil(float(num_voters) * gmm_votes_needed.FloatValue);
}

public void OnClientDisconnect(int client)
{
	if(IsFakeClient(client)) {
		return;
	}

	if(voted[client]) {
		--num_votes;
	}
	voted[client] = false;
	--num_voters;

	votes_needed = RoundToCeil(float(num_voters) * gmm_votes_needed.FloatValue);

	if(num_votes >= votes_needed) {
		if(votes_allowed) {
			gamemodemenu.DisplayVoteToAll(MENU_TIME_FOREVER);
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
		sm_rtg(client, 0);
		SetCmdReplySource(oldsrc);
	}
}

static Action sm_frtg(int client, int args)
{
	gamemodemenu.DisplayVoteToAll(MENU_TIME_FOREVER);
	return Plugin_Handled;
}

static Action sm_rtg(int client, int args)
{
	if(voted[client]) {
		CReplyToCommand(client, GMM_CHAT_PREFIX ... "you already voted");
		return Plugin_Handled;
	}

	if(!votes_allowed) {
		CReplyToCommand(client, GMM_CHAT_PREFIX ... "votes are not allowed at this time");
		return Plugin_Handled;
	}

	voted[client] = true;
	++num_votes;

	if(num_votes >= votes_needed) {
		gamemodemenu.DisplayVoteToAll(MENU_TIME_FOREVER);
	}

	CPrintToChatAll(GMM_CHAT_PREFIX ... "%N wants to change gamemode %i more votes needed", client, (votes_needed-num_votes));

	return Plugin_Handled;
}

static void do_plugins(GamemodeInfo modeinfo, bool unload)
{
	if(modeinfo.plugins != null) {
		char pluginsfolder[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, pluginsfolder, PLATFORM_MAX_PATH, "plugins");

		char pluginpath1[PLATFORM_MAX_PATH];
		char pluginpath2[PLATFORM_MAX_PATH];
		char pluginpath3[PLATFORM_MAX_PATH];

		int i = 0;
		if(unload) {
			i = modeinfo.plugins.Length-1;
		}
		int len = 0;
		if(!unload) {
			len = modeinfo.plugins.Length;
		}

		bool oldautoreload = true;

		ConVar autoreload = FindConVar("sm_autoreload_enable");
		if(autoreload != null) {
			oldautoreload = autoreload.BoolValue;
			autoreload.BoolValue = false;
		}

		while(true) {
			if(unload) {
				if(i < 0) {
					break;
				}
			} else {
				if(i >= len) {
					break;
				}
			}

			modeinfo.plugins.GetString(i, pluginpath1, PLATFORM_MAX_PATH);

			Format(pluginpath2, PLATFORM_MAX_PATH, "%s/disabled/%s", pluginsfolder, pluginpath1);
			Format(pluginpath3, PLATFORM_MAX_PATH, "%s/%s", pluginsfolder, pluginpath1);

			if(unload) {
			#if defined DEBUG
				PrintToServer(GMM_CON_PREFIX ... "%s -> %s", pluginpath3, pluginpath2);
			#endif
				if(FileExists(pluginpath3)) {
					ServerCommand("sm plugins unload \"%s\"", pluginpath1);
				}
				RenameFile(pluginpath2, pluginpath3);
			} else {
			#if defined DEBUG
				PrintToServer(GMM_CON_PREFIX ... "%s -> %s", pluginpath2, pluginpath3);
			#endif
				RenameFile(pluginpath3, pluginpath2);
				if(FileExists(pluginpath3)) {
					ServerCommand("sm plugins load \"%s\"", pluginpath1);
				}
			}

			if(unload) {
				--i;
			} else {
				++i;
			}
		}

		if(autoreload != null) {
			autoreload.BoolValue = oldautoreload;
		}
	}
}

static void do_state(StateChangeInfo state)
{
	if(state.cfg[0] != '\0') {
		ServerCommand("exec %s", state.cfg);
	}

	if(state.commands != null) {
		char cmdstr[CMD_STR_MAX];

		int len = state.commands.Length;
		for(int i = 0; i < len; ++i) {
			state.commands.GetString(i, cmdstr, CMD_STR_MAX);

			ServerCommand("%s", cmdstr);
		}
	}
}

static void unload_gamemode(int idx)
{
	GamemodeInfo modeinfo;
	gamemodes.GetArray(idx, modeinfo, sizeof(GamemodeInfo));

	do_state(modeinfo.disabled);
	do_plugins(modeinfo, true);
}

static void load_gamemode(int idx)
{
	if(currentgamemode == idx) {
		return;
	}

	currentgamemode = idx;

	GamemodeInfo modeinfo;
	gamemodes.GetArray(currentgamemode, modeinfo, sizeof(GamemodeInfo));

	do_state(modeinfo.enabled);
	do_plugins(modeinfo, false);

	char map[PLATFORM_MAX_PATH];

	File cycle = OpenFile("cfg/mapcycle.txt", "w+", true);
	int len = modeinfo.mapcycle.Length;
	for(int i = 0; i < len; ++i) {
		modeinfo.mapcycle.GetString(i, map, PLATFORM_MAX_PATH);
		StrCat(map, PLATFORM_MAX_PATH, "\n");
		cycle.WriteString(map, true);
	}
	delete cycle;
}

static void unload_currentgamemode()
{
	if(currentgamemode == -1) {
		return;
	}

	unload_gamemode(currentgamemode);
	currentgamemode = -1;
}

public void OnPluginEnd()
{
	unload_currentgamemode();
}

public void OnMapEnd()
{
	num_votes = 0;
	for(int j = 1; j <= MaxClients; ++j) {
		if(!IsClientInGame(j) ||
			IsFakeClient(j)) {
			continue;
		}
		voted[j] = false;
	}
	votes_allowed = false;

	if(nextgamemode == -1 || nextgamemode != currentgamemode) {
		unload_currentgamemode();
	}

	if(nextgamemode != -1) {
		load_gamemode(nextgamemode);
	}
}

public void OnMapStart()
{
	GetCurrentMap(currentmap, PLATFORM_MAX_PATH);

	if(nextgamemode == -1) {
		ArrayList modes;
		if(gamemodemapmap.GetValue(currentmap, modes)) {
			int idx = modes.Get(GetRandomInt(0, modes.Length-1));
			load_gamemode(idx);
		}
	} else {
		nextgamemode = -1;
	}

	CreateTimer(gmm_initial_delay.FloatValue, timer_allowvotes, 0, TIMER_FLAG_NO_MAPCHANGE);
}

static Action timer_allowvotes(Handle timer, any data)
{
	votes_allowed = true;
	return Plugin_Continue;
}
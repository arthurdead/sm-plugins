#include <sourcemod>
#include <regex>
#include <morecolors>
#include <nativevotes>

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
	ArrayList plugins;
	bool maps_is_whitelist;
	ArrayList maps_regex;
	StateChangeInfo enabled;
	StateChangeInfo disabled;
	ArrayList mapcycle;
	ArrayList maphistory;
}

static ArrayList gamemodehistory;
static ArrayList gamemodes;
static StringMap gamemodeidmap;
static StringMap gamemodemapmap;
static int currentgamemode = -1;
static int nextgamemode = -1;
static int defaultgamemode = -1;
static int num_voters;
static int num_votes;
static int votes_needed;
static bool voted[MAXPLAYERS+1];
static ConVar gmm_votes_needed;
static ConVar gmm_default;
static ConVar gmm_initial_delay;
static ConVar gmm_fail_delay;
static ConVar gmm_map_time;
static ConVar mapcyclefile;
static bool votes_allowed;
static char currentmap[PLATFORM_MAX_PATH];
static bool lateloaded;

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

	reset_voting();

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
		delete modeinfo.maphistory;
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
}

static void handle_state_changed(KeyValues kvModes, const char[] name, char cmdstr[CMD_STR_MAX], StateChangeInfo stateinfo)
{
	if(kvModes.JumpToKey(name)) {
		kvModes.GetString("cfg", stateinfo.cfg, PLATFORM_MAX_PATH);
		handle_str_array(kvModes, "commands", stateinfo.commands, cmdstr, CMD_STR_MAX);
		kvModes.GoBack();
	}
}

static void build_mapcyclefilename(char path[PLATFORM_MAX_PATH], char name[GAMEMODE_NAME_MAX])
{
	char namecopy[GAMEMODE_NAME_MAX];
	strcopy(namecopy, GAMEMODE_NAME_MAX, name);

	ReplaceString(namecopy, GAMEMODE_NAME_MAX, " ", "_");
	ReplaceString(namecopy, GAMEMODE_NAME_MAX, ":", "_");
	ReplaceString(namecopy, GAMEMODE_NAME_MAX, ".", "_");

	BuildPath(Path_SM, path, PLATFORM_MAX_PATH, "data/gmm/mapcycles/%s.txt", namecopy);
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

			char rexerrstr[128];
			char cmdstr[CMD_STR_MAX];

			char pluginsfolder[PLATFORM_MAX_PATH];
			BuildPath(Path_SM, pluginsfolder, PLATFORM_MAX_PATH, "plugins");

			char disabledpath[PLATFORM_MAX_PATH];

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

							CreateDirectory(disabledpath, FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC);

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

				modeinfo.maphistory = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

				int idx = gamemodes.PushArray(modeinfo, sizeof(GamemodeInfo));

				gamemodeidmap.SetValue(modeinfo.name, idx);
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

			if(StrEqual(anyfilepath, "background01") ||
				StrEqual(anyfilepath, "itemtest") ||
				StrEqual(anyfilepath, "cp_cloak") ||
				(anyfilepath[0] == 't' &&
				anyfilepath[1] == 'r' &&
				anyfilepath[2] == '_')) {
				continue;
			}

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

		BuildPath(Path_SM, anyfilepath, PLATFORM_MAX_PATH, "data/gmm");
		CreateDirectory(anyfilepath, FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC);
		BuildPath(Path_SM, anyfilepath, PLATFORM_MAX_PATH, "data/gmm/mapcycles");
		CreateDirectory(anyfilepath, FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC);

		int len = gamemodes.Length;
		for(int i = 0; i < len; ++i) {
			gamemodes.GetArray(i, modeinfo, sizeof(GamemodeInfo));

			build_mapcyclefilename(anyfilepath, modeinfo.name);
			File cycle = OpenFile(anyfilepath, "w+");

			int len2 = modeinfo.mapcycle.Length;
			for(int j = 0; j < len2; ++j) {
				modeinfo.mapcycle.GetString(j, anyfilepath, PLATFORM_MAX_PATH);
				StrCat(anyfilepath, PLATFORM_MAX_PATH, "\n");
				cycle.WriteString(anyfilepath, true);
			}

			delete cycle;
		}
	}
}

static void toggle_ff2_folder(bool value)
{
	static char ff2path1[PLATFORM_MAX_PATH];
	if(ff2path1[0] == '\0') {
		BuildPath(Path_SM, ff2path1, PLATFORM_MAX_PATH, "plugins/freaks");
	}
	static char ff2path2[PLATFORM_MAX_PATH];
	if(ff2path2[0] == '\0') {
		BuildPath(Path_SM, ff2path2, PLATFORM_MAX_PATH, "plugins/disabled/freaks");
	}

	if(!value) {
		DirectoryListing ff2dir = OpenDirectory(ff2path1);
		if(ff2dir != null) {
			char pluginfile[PLATFORM_MAX_PATH];

			FileType filetype;
			while(ff2dir.GetNext(pluginfile, PLATFORM_MAX_PATH, filetype)) {
				if(filetype != FileType_File) {
					continue;
				}

				int smx = StrContains(pluginfile, ".smx");
				if(smx == -1) {
					continue;
				}

				int pathlen = strlen(pluginfile);
				if((pathlen-smx) != 4) {
					continue;
				}

				pluginfile[smx] = '\0';

				ServerCommand("sm plugins unload \"%s\"", pluginfile);
			}
			delete ff2dir;
		}

		RenameFile(ff2path2, ff2path1);
	} else {
		RenameFile(ff2path1, ff2path2);
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	lateloaded = late;
#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "lateloaded: %i", late);
#endif
	toggle_ff2_folder(false);
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");

	gamemodehistory = new ArrayList();

	load_gamemodes();

	int len = gamemodes.Length;
	for(int i = 0; i < len; ++i) {
		unload_gamemode(i);
	}

	gmm_votes_needed = CreateConVar("gmm_votes_needed", "0.60");
	gmm_default = CreateConVar("gmm_default", "");
	gmm_initial_delay = CreateConVar("gmm_initial_delay", "45.0");
	gmm_fail_delay = CreateConVar("gmm_fail_delay", "240.0");
	gmm_map_time = CreateConVar("gmm_map_time", "5.0");

	mapcyclefile = FindConVar("mapcyclefile");

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

static void increment_voters()
{
	++num_voters;
	votes_needed = RoundToCeil(float(num_voters) * gmm_votes_needed.FloatValue);
}

static void decrement_voters(int client)
{
	if(voted[client]) {
		--num_votes;
	}
	voted[client] = false;
	--num_voters;
	votes_needed = RoundToCeil(float(num_voters) * gmm_votes_needed.FloatValue);
}

static int menuhandler_maps(NativeVote menu, MenuAction action, int param1, int param2)
{
	switch(action) {
		case MenuAction_VoteEnd: {
			char map[PLATFORM_MAX_PATH];
			menu.GetItem(param1, map, PLATFORM_MAX_PATH);

			CPrintToChatAll(GMM_CHAT_PREFIX ... "%s won the map vote", map);

			float mapchangetime = gmm_map_time.FloatValue;
			float unloadtime = mapchangetime * 0.8;

			CreateTimer(unloadtime, timer_unloadgamemode, 0, TIMER_FLAG_NO_MAPCHANGE);

			SetNextMap(map);
			CreateTimer(mapchangetime, timer_changemap, 0, TIMER_FLAG_NO_MAPCHANGE);

			menu.DisplayPassEx(NativeVotesPass_NextLevel, "%s", map);
		}
		case MenuAction_VoteCancel: {
			nextgamemode = -1;
			reset_voting();
			CreateTimer(gmm_fail_delay.FloatValue, timer_allowvotes, 0, TIMER_FLAG_NO_MAPCHANGE);
			switch(param1) {
				case VoteCancel_Generic:
				{ menu.DisplayFail(NativeVotesFail_Generic); }
				case VoteCancel_NoVotes:
				{ menu.DisplayFail(NativeVotesFail_NotEnoughVotes); }
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}

	return 0;
}

static void mapvote(int mode)
{
	GamemodeInfo modeinfo;
	gamemodes.GetArray(mode, modeinfo, sizeof(GamemodeInfo));

	NativeVote cyclemenu = new NativeVote(menuhandler_maps, NativeVotesType_NextLevelMult);

	char title[GAMEMODE_NAME_MAX + 8];
	Format(title, sizeof(title), "%s - Maps", modeinfo.name);
	cyclemenu.SetTitle(title);

	char map[PLATFORM_MAX_PATH];

	ArrayList maps_tochoose = new ArrayList();

	int len = modeinfo.mapcycle.Length;
	for(int i = 0; i < len; ++i) {
		modeinfo.mapcycle.GetString(i, map, sizeof(map));

		if(modeinfo.maphistory.FindString(map) != -1) {
		#if defined DEBUG
			PrintToServer(GMM_CON_PREFIX ... "removed %s from %s map vote", map, modeinfo.name);
		#endif
			continue;
		}

	#if defined DEBUG
		PrintToServer(GMM_CON_PREFIX ... "added %s to %s map vote", map, modeinfo.name);
	#endif
		maps_tochoose.Push(i);
	}

	len = maps_tochoose.Length;
	len = len > 5 ? 5 : len;
	for(int i = 0; i < len; ++i) {
		int idx = GetRandomInt(0, maps_tochoose.Length-1);
		int mapidx = maps_tochoose.Get(idx);
		maps_tochoose.Erase(idx);

		modeinfo.mapcycle.GetString(mapidx, map, sizeof(map));

	#if defined DEBUG
		PrintToServer(GMM_CON_PREFIX ... "selected %s from %s map vote", map, modeinfo.name);
	#endif

		cyclemenu.AddItem(map, map);
	}

	delete maps_tochoose;

	cyclemenu.DisplayVoteToAll(20);
}

static Action timer_mapvote(Handle timer, int idx)
{
	mapvote(idx);
	return Plugin_Continue;
}

static int menuhandler_gamemodes(NativeVote menu, MenuAction action, int param1, int param2)
{
	switch(action) {
		case MenuAction_VoteEnd: {
			char intstr[INT_STR_MAX];
			menu.GetItem(param1, intstr, INT_STR_MAX);
			int idx = StringToInt(intstr);

			GamemodeInfo modeinfo;
			gamemodes.GetArray(idx, modeinfo, sizeof(GamemodeInfo));

			nextgamemode = idx;

			CPrintToChatAll(GMM_CHAT_PREFIX ... "%s won the gamemode vote", modeinfo.name);

			reset_voting();

			menu.DisplayPassEx(NativeVotesPass_ChgMission, "%s", modeinfo.name);

			float delay = float(NativeVotes_CheckVoteDelay()) * 0.1;
		#if defined DEBUG
			PrintToServer(GMM_CON_PREFIX ... "map vote in %f", delay);
		#endif
			CreateTimer(delay, timer_mapvote, idx, TIMER_FLAG_NO_MAPCHANGE);
		}
		case MenuAction_VoteCancel: {
			nextgamemode = -1;
			reset_voting();
			CreateTimer(gmm_fail_delay.FloatValue, timer_allowvotes, 0, TIMER_FLAG_NO_MAPCHANGE);
			switch(param1) {
				case VoteCancel_Generic:
				{ menu.DisplayFail(NativeVotesFail_Generic); }
				case VoteCancel_NoVotes:
				{ menu.DisplayFail(NativeVotesFail_NotEnoughVotes); }
			}
		}
		case MenuAction_End: {
			delete menu;
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

static Action timer_changemap(Handle timer, any data)
{
	char map[PLATFORM_MAX_PATH];
	if(GetNextMap(map, sizeof(map))) {
		ForceChangeLevel(map, "GMM");
	}
	return Plugin_Continue;
}

static void startvote()
{
#if defined DEBUG
	if(NativeVotes_IsVoteInProgress()) {
		NativeVotes_Cancel();
	}
#endif

	NativeVote gamemodemenu = new NativeVote(menuhandler_gamemodes, NativeVotesType_Custom_Mult);
	gamemodemenu.SetTitle("Gamemodes");

	GamemodeInfo modeinfo;

	ArrayList gamemodes_tochoose = new ArrayList();
	int len = gamemodes.Length;
	for(int i = 0; i < len; ++i) {
		if(gamemodehistory.FindValue(i) != -1) {
		#if defined DEBUG
			gamemodes.GetArray(i, modeinfo, sizeof(GamemodeInfo));
			PrintToServer(GMM_CON_PREFIX ... "removed %s from gamemode vote", modeinfo.name);
		#endif
			continue;
		}

	#if defined DEBUG
		gamemodes.GetArray(i, modeinfo, sizeof(GamemodeInfo));
		PrintToServer(GMM_CON_PREFIX ... "added %s to gamemode vote", modeinfo.name);
	#endif
		gamemodes_tochoose.Push(i);
	}

	char intstr[INT_STR_MAX];

	len = gamemodes_tochoose.Length;
	len = len > 5 ? 5 : len;
	for(int i = 0; i < len; ++i) {
		int idx = GetRandomInt(0, gamemodes_tochoose.Length-1);
		int mode = gamemodes_tochoose.Get(idx);
		gamemodes_tochoose.Erase(idx);

		gamemodes.GetArray(mode, modeinfo, sizeof(GamemodeInfo));

	#if defined DEBUG
		PrintToServer(GMM_CON_PREFIX ... "selected %s from gamemode vote", modeinfo.name);
	#endif

		IntToString(mode, intstr, INT_STR_MAX);
		gamemodemenu.AddItem(intstr, modeinfo.name);
	}

	delete gamemodes_tochoose;

	gamemodemenu.DisplayVoteToAll(20);
}

public void OnClientPutInServer(int client)
{
	if(IsFakeClient(client)) {
		return;
	}

	increment_voters();
}

public void OnClientDisconnect(int client)
{
	if(IsFakeClient(client)) {
		return;
	}

	decrement_voters(client);

	if(num_votes > 0 &&
		num_voters > 0 &&
		num_votes >= votes_needed &&
		NativeVotes_IsNewVoteAllowed()) {
		startvote();
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
	startvote();
	return Plugin_Handled;
}

static Action sm_rtg(int client, int args)
{
	if(voted[client]) {
		CReplyToCommand(client, GMM_CHAT_PREFIX ... "you already voted");
		return Plugin_Handled;
	}

	if(!votes_allowed || NativeVotes_IsNewVoteAllowed()) {
		CReplyToCommand(client, GMM_CHAT_PREFIX ... "votes are not allowed at this time");
		return Plugin_Handled;
	}

	voted[client] = true;
	++num_votes;

	CPrintToChatAll(GMM_CHAT_PREFIX ... "%N wants to change gamemode %i more votes needed", client, (votes_needed-num_votes));

	if(num_votes >= votes_needed) {
		startvote();
	}

	return Plugin_Handled;
}

static void do_plugins(GamemodeInfo modeinfo, bool unload)
{
	if(unload) {
		toggle_ff2_folder(false);
	}

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

			if(!unload && StrContains(pluginpath1, "freak_fortress_2") != -1) {
				toggle_ff2_folder(true);
			}

			Format(pluginpath2, PLATFORM_MAX_PATH, "%s/disabled/%s", pluginsfolder, pluginpath1);
			Format(pluginpath3, PLATFORM_MAX_PATH, "%s/%s", pluginsfolder, pluginpath1);

			if(unload) {
			#if defined DEBUG && 0
				PrintToServer(GMM_CON_PREFIX ... "%s -> %s", pluginpath3, pluginpath2);
			#endif
				if(FileExists(pluginpath3)) {
					ServerCommand("sm plugins unload \"%s\"", pluginpath1);
				}
				RenameFile(pluginpath2, pluginpath3);
			} else {
			#if defined DEBUG && 0
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

#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "unloaded %s", modeinfo.name);
#endif
}

static void addto_gamemodehistory(int mode)
{
	if(gamemodehistory.FindValue(mode) != -1) {
		return;
	}

	gamemodehistory.Push(mode);

	int len = gamemodes.Length;
	int max = len > 5 ? 5 : len-1;

	if(gamemodehistory.Length > max) {
		gamemodehistory.Erase(0);
	}
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

	addto_gamemodehistory(currentgamemode);

#if defined DEBUG
	PrintToServer(GMM_CON_PREFIX ... "loaded %s", modeinfo.name);
#endif
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

static void reset_voting()
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
}

static void addto_maphistory(GamemodeInfo modeinfo, char map[PLATFORM_MAX_PATH])
{
	if(modeinfo.maphistory.FindString(map)) {
		return;
	}

	modeinfo.maphistory.PushString(map);

	if(modeinfo.mapcycle.Length == 1) {
		return;
	}

	int len = modeinfo.mapcycle.Length;
	int max = len > 5 ? 5 : len-1;

	if(modeinfo.maphistory.Length > max) {
		modeinfo.maphistory.Erase(0);
	}
}

public void OnMapEnd()
{
	reset_voting();

	if(currentgamemode != -1) {
		GamemodeInfo modeinfo;
		gamemodes.GetArray(currentgamemode, modeinfo, sizeof(GamemodeInfo));

		addto_maphistory(modeinfo, currentmap);
	}

	if(nextgamemode == -1 || nextgamemode != currentgamemode) {
		unload_currentgamemode();
	}

	if(nextgamemode != -1) {
		load_gamemode(nextgamemode);
	}
}

public void OnConfigsExecuted()
{
	if(defaultgamemode == -1) {
		char gamemode[GAMEMODE_NAME_MAX];
		gmm_default.GetString(gamemode, GAMEMODE_NAME_MAX);

		if(gamemode[0] != '\0') {
			int idx = -1;
			if(gamemodeidmap.GetValue(gamemode, idx)) {
				defaultgamemode = idx;

				if(!lateloaded) {
					bool valid = false;

					ArrayList modes;
					if(gamemodemapmap.GetValue(currentmap, modes)) {
						int len = modes.Length;
						for(int i = 0; i < len; ++i) {
							idx = modes.Get(i);
							if(idx == defaultgamemode) {
								valid = true;
							}
						}
					}

					nextgamemode = defaultgamemode;

					if(!valid) {
						GamemodeInfo modeinfo;
						gamemodes.GetArray(defaultgamemode, modeinfo, sizeof(GamemodeInfo));

						int mapidx = GetRandomInt(0, modeinfo.mapcycle.Length-1);

						char newmap[PLATFORM_MAX_PATH];
						modeinfo.mapcycle.GetString(mapidx, newmap, PLATFORM_MAX_PATH);

						SetNextMap(newmap);

						CreateTimer(0.5, timer_unloadgamemode, 0, TIMER_FLAG_NO_MAPCHANGE);

						DataPack data = null;
						CreateDataTimer(1.0, timer_changemap, data, TIMER_FLAG_NO_MAPCHANGE);
						data.WriteString(newmap);

					#if defined DEBUG
						PrintToServer(GMM_CON_PREFIX ... "changing to default gamemode %s on map %s", modeinfo.name, newmap);
					#endif
					} else {
						if(currentgamemode != nextgamemode) {
							unload_currentgamemode();
							load_gamemode(nextgamemode);
						}
						nextgamemode = -1;

					#if defined DEBUG
						GamemodeInfo modeinfo;
						gamemodes.GetArray(defaultgamemode, modeinfo, sizeof(GamemodeInfo));

						PrintToServer(GMM_CON_PREFIX ... "default gamemode %s supports current map %s", modeinfo.name, currentmap);
					#endif
					}
				}
			#if defined DEBUG
				else {
					PrintToServer(GMM_CON_PREFIX ... "plugin was lateloaded not applying default gamemode");
				}
			#endif
			} else {
				LogError(GMM_CON_PREFIX ... "invalid default gamemode %s", gamemode);
			}
		}
	#if defined DEBUG
		else {
			PrintToServer(GMM_CON_PREFIX ... "default gamemode cvar was empty");
		}
	#endif
	}

	if(currentgamemode != -1) {
		GamemodeInfo modeinfo;
		gamemodes.GetArray(currentgamemode, modeinfo, sizeof(GamemodeInfo));

		char cyclefile[PLATFORM_MAX_PATH];
		build_mapcyclefilename(cyclefile, modeinfo.name);

		mapcyclefile.SetString(cyclefile);
	}

#if !defined DEBUG
	CreateTimer(gmm_initial_delay.FloatValue, timer_allowvotes, 0, TIMER_FLAG_NO_MAPCHANGE);
#else
	timer_allowvotes(null, 0);
#endif
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
}

static Action timer_allowvotes(Handle timer, any data)
{
	votes_allowed = true;
	return Plugin_Continue;
}
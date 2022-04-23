#include <sourcemod>
#include <regex>
#include <morecolors>
#include <nativevotes>
#include <aliasrandom>
#include <SteamWorks>

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
static ConVar gmm_startrounds;
static ConVar gmm_startfrags;
static ConVar gmm_voteduration;
static ConVar mapcyclefile;
static bool votes_allowed;
static char currentmap[PLATFORM_MAX_PATH];
static bool lateloaded;
static float voteblock_start;
static bool gamemodetimeelapsed;
static Handle changegamemode_timer;
static ConVar mp_maxrounds;
static ConVar mp_winlimit;
static ConVar mp_bonusroundtime;
static ConVar mp_fraglimit;
static int rounds;
static bool inround;
static Handle mapvotetimer;
static Handle gamemodevotetimer;

static void handle_str_array(KeyValues kvModes, const char[] name, ArrayList &arr, char[] str, int size)
{
	if(kvModes.JumpToKey(name)) {
		if(kvModes.GotoFirstSubKey(false)) {
			arr = new ArrayList(ByteCountToCells(size));

			do {
				kvModes.GetString(NULL_STRING, str, size);

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
		delete modeinfo.plugins_disable;
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

				if(kvModes.JumpToKey("plugins")) {
					if(kvModes.GotoFirstSubKey(false)) {
						modeinfo.plugins = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

						do {
							kvModes.GetString(NULL_STRING, anyfilepath, PLATFORM_MAX_PATH);

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

				if(kvModes.JumpToKey("plugins_disable")) {
					if(kvModes.GotoFirstSubKey(false)) {
						modeinfo.plugins_disable = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

						do {
							kvModes.GetString(NULL_STRING, anyfilepath, PLATFORM_MAX_PATH);

							int i = strlen(anyfilepath)-1;
							while(i > 0 && anyfilepath[--i] != '/') {}

							int j = 0;
							for(; j < i; ++j) {
								disabledpath[j] = anyfilepath[j];
							}
							disabledpath[j] = '\0';

							Format(disabledpath, PLATFORM_MAX_PATH, "%s/disabled/%s", pluginsfolder, disabledpath);

							CreateDirectory(disabledpath, FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC);

							modeinfo.plugins_disable.PushString(anyfilepath);
						} while(kvModes.GotoNextKey(false));

						kvModes.GoBack();
					} else {
						modeinfo.plugins_disable = null;
					}

					kvModes.GoBack();
				} else {
					modeinfo.plugins_disable = null;
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
						modeinfo.maps_regex = new ArrayList();

						do {
							kvModes.GetString(NULL_STRING, anyfilepath, PLATFORM_MAX_PATH);

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

				modeinfo.weight = kvModes.GetFloat("weight", 50.0);
				modeinfo.time = kvModes.GetFloat("time", 30.0);

				handle_state_changed(kvModes, "enabled", cmdstr, modeinfo.enabled);
				handle_state_changed(kvModes, "disabled", cmdstr, modeinfo.disabled);

				modeinfo.mapcycle = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

				modeinfo.maphistory = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

				int idx = gamemodes.PushArray(modeinfo, sizeof(GamemodeInfo));

				gamemodeidmap.SetValue(modeinfo.name, idx);
			} while(kvModes.GotoNextKey());

			kvModes.GoBack();
		}

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

static void load_ff2_folder()
{
	static char ff2path1[PLATFORM_MAX_PATH];
	if(ff2path1[0] == '\0') {
		BuildPath(Path_SM, ff2path1, PLATFORM_MAX_PATH, "plugins/freaks");
	}

	DirectoryListing ff2dir = OpenDirectory(ff2path1);
	if(ff2dir != null) {
		char pluginfile1[PLATFORM_MAX_PATH];
		char pluginfile2[PLATFORM_MAX_PATH];
		char pluginfile3[PLATFORM_MAX_PATH];

		FileType filetype;
		while(ff2dir.GetNext(pluginfile1, PLATFORM_MAX_PATH, filetype)) {
			if(filetype != FileType_File) {
				continue;
			}

			int smx = StrContains(pluginfile1, ".ff2");
			if(smx == -1) {
				continue;
			}

			int pathlen = strlen(pluginfile1);
			if((pathlen-smx) != 4) {
				continue;
			}

			pluginfile1[smx] = '\0';

			Format(pluginfile2, PLATFORM_MAX_PATH, "%s/%s", ff2path1, pluginfile1);
			StrCat(pluginfile2, PLATFORM_MAX_PATH, ".smx");

			Format(pluginfile3, PLATFORM_MAX_PATH, "%s/%s", ff2path1, pluginfile1);
			StrCat(pluginfile3, PLATFORM_MAX_PATH, ".ff2");

			RenameFile(pluginfile2, pluginfile3);

			ServerCommand("sm plugins load \"freaks/%s\"", pluginfile1);
		}
		delete ff2dir;
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
			char pluginfile1[PLATFORM_MAX_PATH];
			char pluginfile2[PLATFORM_MAX_PATH];
			char pluginfile3[PLATFORM_MAX_PATH];

			FileType filetype;
			while(ff2dir.GetNext(pluginfile1, PLATFORM_MAX_PATH, filetype)) {
				if(filetype != FileType_File) {
					continue;
				}

				int smx = StrContains(pluginfile1, ".smx");
				if(smx == -1) {
					continue;
				}

				int pathlen = strlen(pluginfile1);
				if((pathlen-smx) != 4) {
					continue;
				}

				pluginfile1[smx] = '\0';

				Format(pluginfile2, PLATFORM_MAX_PATH, "%s/%s", ff2path1, pluginfile1);
				StrCat(pluginfile2, PLATFORM_MAX_PATH, ".smx");

				Format(pluginfile3, PLATFORM_MAX_PATH, "%s/%s", ff2path1, pluginfile1);
				StrCat(pluginfile3, PLATFORM_MAX_PATH, ".ff2");

				ServerCommand("sm plugins unload \"freaks/%s\"", pluginfile1);

				//RenameFile(pluginfile3, pluginfile2);
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
	gmm_startrounds = CreateConVar("gmm_startrounds", "2.0");
	gmm_startfrags = CreateConVar("gmm_startfrags", "5.0");
	gmm_voteduration = CreateConVar("gmm_voteduration", "20.0");

	mapcyclefile = FindConVar("mapcyclefile");

	RegConsoleCmd("sm_rtg", sm_rtg);

	RegAdminCmd("sm_frtg", sm_frtg, ADMFLAG_ROOT);
	RegAdminCmd("sm_rgmm", sm_rgmm, ADMFLAG_ROOT);
	RegAdminCmd("sm_frg", sm_frg, ADMFLAG_ROOT);

	mp_winlimit = FindConVar("mp_winlimit");
	mp_maxrounds = FindConVar("mp_maxrounds");
	mp_fraglimit = FindConVar("mp_fraglimit");

	mp_bonusroundtime = FindConVar("mp_bonusroundtime");
	mp_bonusroundtime.SetBounds(ConVarBound_Upper, true, 30.0);

	HookEvent("teamplay_round_win", teamplay_round_win);
	HookEvent("teamplay_game_over", teamplay_round_win);
	HookEvent("tf_game_over", teamplay_round_win);

	HookEvent("teamplay_round_active", teamplay_round_active);
	HookEvent("arena_round_start", teamplay_round_active);

	HookEvent("teamplay_win_panel", teamplay_win_panel);
	HookEvent("arena_win_panel", teamplay_win_panel);

	HookEvent("teamplay_restart_round", teamplay_restart_round);

	HookEvent("player_death", player_death);

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

static void teamplay_round_win(Event event, const char[] name, bool dontBroadcast)
{
	inround = false;
}

static void teamplay_round_active(Event event, const char[] name, bool dontBroadcast)
{
	inround = true;
}

static void player_death(Event event, const char[] name, bool dontBroadcast)
{
	if(mp_fraglimit.IntValue <= 0) {
		return;
	}

	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if(attacker < 1 || attacker > MaxClients) {
		return;
	}

	if(GetClientFrags(attacker) >= (mp_fraglimit.IntValue - gmm_startfrags.IntValue)) {
		timer_mapvote(null, currentgamemode);
	}
}

static void teamplay_restart_round(Event event, const char[] name, bool dontBroadcast)
{
	inround = false;
	rounds = 0;
}

static void checkwin(int score)
{
	int winlimit = mp_winlimit.IntValue;
	if(winlimit > 0) {
		if(score >= (winlimit - gmm_startrounds.IntValue)) {
			timer_mapvote(null, currentgamemode);
		}
	}
}

static void teamplay_win_panel(Event event, const char[] name, bool dontBroadcast)
{
	inround = false;

	if(event.GetInt("round_complete") == 1) {
		++rounds;

		int maxrounds = mp_maxrounds.IntValue;
		if(maxrounds > 0) {
			if(rounds >= (maxrounds - gmm_startrounds.IntValue)) {
				timer_mapvote(null, currentgamemode);
			}
		}

		switch(event.GetInt("winning_team")) {
			case 3:
			{ checkwin(event.GetInt("blue_score")); }
			case 2:
			{ checkwin(event.GetInt("red_score")); }
		}
	}
}

static Action sm_frg(int client, int args)
{
	nextgamemode = randomgamemode();

	GamemodeInfo modeinfo;
	gamemodes.GetArray(nextgamemode, modeinfo, sizeof(GamemodeInfo));

	changerandommap(modeinfo);

	return Plugin_Handled;
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

static void changemap(const char[] map)
{
	float mapchangetime = gmm_map_time.FloatValue;
	float unloadtime = mapchangetime * 0.8;

	CreateTimer(unloadtime, timer_unloadgamemode, 0, TIMER_FLAG_NO_MAPCHANGE);

	SetNextMap(map);
	CreateTimer(mapchangetime, timer_changemap, 0, TIMER_FLAG_NO_MAPCHANGE);
}

static void changerandommap(GamemodeInfo modeinfo)
{
	int mapidx = GetRandomInt(0, modeinfo.mapcycle.Length-1);

	char newmap[PLATFORM_MAX_PATH];
	modeinfo.mapcycle.GetString(mapidx, newmap, PLATFORM_MAX_PATH);

	changemap(newmap);
}

static int menuhandler_maps(NativeVote menu, MenuAction action, int param1, int param2)
{
	switch(action) {
		case MenuAction_VoteEnd: {
			char map[PLATFORM_MAX_PATH];
			menu.GetItem(param1, map, PLATFORM_MAX_PATH);

			CPrintToChatAll(GMM_CHAT_PREFIX ... "%s won the map vote", map);

			changemap(map);

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
			if(gamemodetimeelapsed) {
				if(changegamemode_timer == null) {
					float delay = float(NativeVotes_CheckVoteDelay());
					changegamemode_timer = CreateTimer(delay, timer_changemode, 0, TIMER_FLAG_NO_MAPCHANGE);
				}
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}

	return 0;
}

static Action timer_mapvote(Handle timer, int mode)
{
	if(mapvotetimer != null && mapvotetimer != timer) {
		KillTimer(mapvotetimer);
	}

	if(!NativeVotes_IsNewVoteAllowed()) {
		float delay = float(NativeVotes_CheckVoteDelay());
		mapvotetimer = CreateTimer(delay, timer_mapvote, mode, TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Continue;
	}

	mapvote(mode);
	mapvotetimer = null;
	return Plugin_Continue;
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
			continue;
		}

		maps_tochoose.Push(i);
	}

	len = maps_tochoose.Length;
	len = len > 5 ? 5 : len;
	for(int i = 0; i < len; ++i) {
		int idx = GetRandomInt(0, maps_tochoose.Length-1);
		int mapidx = maps_tochoose.Get(idx);
		maps_tochoose.Erase(idx);

		modeinfo.mapcycle.GetString(mapidx, map, sizeof(map));

		cyclemenu.AddItem(map, map);
	}

	delete maps_tochoose;

	cyclemenu.DisplayVoteToAll(gmm_voteduration.IntValue);
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

			if(modeinfo.mapcycle.Length == 1) {
				char map[PLATFORM_MAX_PATH];
				modeinfo.mapcycle.GetString(0, map, sizeof(map));

				changemap(map);
			} else {
				if(mapvotetimer != null) {
					KillTimer(mapvotetimer);
				}
				timer_mapvote(null, nextgamemode);
			}
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
			if(gamemodetimeelapsed) {
				if(changegamemode_timer == null) {
					float delay = float(NativeVotes_CheckVoteDelay());
					changegamemode_timer = CreateTimer(delay, timer_changemode, 0, TIMER_FLAG_NO_MAPCHANGE);
				}
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

static Action timer_gamemodevote(Handle timer, any data)
{
	if(gamemodevotetimer != null && gamemodevotetimer != timer) {
		KillTimer(gamemodevotetimer);
	}

	if(!NativeVotes_IsNewVoteAllowed()) {
		float delay = float(NativeVotes_CheckVoteDelay());
		gamemodevotetimer = CreateTimer(delay, timer_gamemodevote, 0, TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Continue;
	}

	startvote();
	gamemodevotetimer = null;
	return Plugin_Continue;
}

static void startvote()
{
	if(!NativeVotes_IsNewVoteAllowed()) {
		LogError(GMM_CON_PREFIX ... "tried to start new gamemode vote while it wanst possible");
		return;
	}

	NativeVote gamemodemenu = new NativeVote(menuhandler_gamemodes, NativeVotesType_Custom_Mult);
	gamemodemenu.SetTitle("Gamemodes");

	GamemodeInfo modeinfo;

	ArrayList weights = new ArrayList();

	ArrayList gamemodes_tochoose = new ArrayList();
	int len = gamemodes.Length;
	for(int i = 0; i < len; ++i) {
		gamemodes.GetArray(i, modeinfo, sizeof(GamemodeInfo));
		if(gamemodehistory.FindValue(i) != -1) {
			continue;
		}
		if(i == currentgamemode) {
			continue;
		}
		weights.Push(modeinfo.weight);
		gamemodes_tochoose.Push(i);
	}

	ArrayList aliases = CreateAliasRandom(weights);

	char intstr[INT_STR_MAX];

	len = gamemodes_tochoose.Length;
	len = len > 5 ? 5 : len;
	for(int i = 0; i < len; ++i) {
		int idx = GetAliasRandom(aliases);

		int mode = gamemodes_tochoose.Get(idx);
		gamemodes.GetArray(mode, modeinfo, sizeof(GamemodeInfo));

		weights.Erase(idx);

		delete aliases;
		aliases = CreateAliasRandom(weights);

		gamemodes_tochoose.Erase(idx);

		IntToString(mode, intstr, INT_STR_MAX);
		gamemodemenu.AddItem(intstr, modeinfo.name);
	}

	delete aliases;
	delete weights;
	delete gamemodes_tochoose;

	gamemodemenu.DisplayVoteToAll(gmm_voteduration.IntValue);
}

public void OnClientPutInServer(int client)
{
	if(IsFakeClient(client) ||
		IsClientReplay(client) ||
		IsClientSourceTV(client)) {
		return;
	}

	increment_voters();
}

public void OnClientDisconnect(int client)
{
	if(IsFakeClient(client) ||
		IsClientReplay(client) ||
		IsClientSourceTV(client)) {
		return;
	}

	decrement_voters(client);

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

	if(any_human) {
		if(num_votes > 0 &&
			num_voters > 0 &&
			num_votes >= votes_needed &&
			(votes_allowed && NativeVotes_IsNewVoteAllowed())) {
			timer_gamemodevote(null, 0);
		}
	} else {
		if(gamemodetimeelapsed) {
			nextgamemode = randomgamemode();

			GamemodeInfo modeinfo;
			gamemodes.GetArray(nextgamemode, modeinfo, sizeof(GamemodeInfo));

			changerandommap(modeinfo);
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
	timer_gamemodevote(null, 0);
	return Plugin_Handled;
}

static Action sm_rtg(int client, int args)
{
	if(voted[client]) {
		CReplyToCommand(client, GMM_CHAT_PREFIX ... "you already voted");
		return Plugin_Handled;
	}

	if(!NativeVotes_IsNewVoteAllowed()) {
		CReplyToCommand(client, GMM_CHAT_PREFIX ... "votes are not allowed at this time");
		return Plugin_Handled;
	}

	if(!votes_allowed) {
		int seconds = RoundToFloor(gmm_initial_delay.FloatValue-(GetGameTime()-voteblock_start));
		CReplyToCommand(client, GMM_CHAT_PREFIX ... "votes are not allowed at this time. please wait %i seconds.", seconds);
		return Plugin_Handled;
	}

	voted[client] = true;
	++num_votes;

	int needed = (votes_needed-num_votes);
	if(needed > 0) {
		CPrintToChatAll(GMM_CHAT_PREFIX ... "%N wants to change gamemode %i more votes needed", client, needed);
	}

	if(num_votes >= votes_needed) {
		timer_gamemodevote(null, 0);
	}

	return Plugin_Handled;
}

static void do_plugins(GamemodeInfo modeinfo, bool unload)
{
	if(unload) {
		toggle_ff2_folder(false);
	}

	char pluginsfolder[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, pluginsfolder, PLATFORM_MAX_PATH, "plugins");

	char pluginpath1[PLATFORM_MAX_PATH];
	char pluginpath2[PLATFORM_MAX_PATH];
	char pluginpath3[PLATFORM_MAX_PATH];

	if(!unload) {
		if(modeinfo.plugins_disable != null) {
			for(int i = modeinfo.plugins_disable.Length-1; i >= 0; --i) {
				modeinfo.plugins_disable.GetString(i, pluginpath1, PLATFORM_MAX_PATH);

				Format(pluginpath2, PLATFORM_MAX_PATH, "%s/disabled/%s", pluginsfolder, pluginpath1);
				Format(pluginpath3, PLATFORM_MAX_PATH, "%s/%s", pluginsfolder, pluginpath1);

				if(FileExists(pluginpath3)) {
					ServerCommand("sm plugins unload \"%s\"", pluginpath1);
				}
				RenameFile(pluginpath2, pluginpath3);
			}
		}
	}

	if(modeinfo.plugins != null) {
		bool reverse = (unload);

		int i = 0;
		if(reverse) {
			i = modeinfo.plugins.Length-1;
		}
		int len = 0;
		if(!reverse) {
			len = modeinfo.plugins.Length;
		}

		bool ff2 = false;

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

			modeinfo.plugins.GetString(i, pluginpath1, PLATFORM_MAX_PATH);

			ff2 = (StrContains(pluginpath1, "freak_fortress_2") != -1);

			if(!unload && ff2) {
				toggle_ff2_folder(true);
			}

			Format(pluginpath2, PLATFORM_MAX_PATH, "%s/disabled/%s", pluginsfolder, pluginpath1);
			Format(pluginpath3, PLATFORM_MAX_PATH, "%s/%s", pluginsfolder, pluginpath1);

			if(unload) {
				if(FileExists(pluginpath3)) {
					ServerCommand("sm plugins unload \"%s\"", pluginpath1);
				}
				RenameFile(pluginpath2, pluginpath3);
			} else {
				RenameFile(pluginpath3, pluginpath2);
				if(FileExists(pluginpath3)) {
					ServerCommand("sm plugins load \"%s\"", pluginpath1);
				}
			}

			if(reverse) {
				--i;
			} else {
				++i;
			}
		}

		if(!unload && ff2) {
			load_ff2_folder();
		}
	}

	if(unload) {
		if(modeinfo.plugins_disable != null) {
			int len = modeinfo.plugins_disable.Length;
			for(int i = 0; i < len; ++i) {
				modeinfo.plugins_disable.GetString(i, pluginpath1, PLATFORM_MAX_PATH);

				Format(pluginpath2, PLATFORM_MAX_PATH, "%s/disabled/%s", pluginsfolder, pluginpath1);
				Format(pluginpath3, PLATFORM_MAX_PATH, "%s/%s", pluginsfolder, pluginpath1);

				RenameFile(pluginpath3, pluginpath2);
				if(FileExists(pluginpath3)) {
					ServerCommand("sm plugins load \"%s\"", pluginpath1);
				}
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

	SteamWorks_SetGameDescription("");
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

	SteamWorks_SetGameDescription(modeinfo.name);

	do_plugins(modeinfo, false);

	addto_gamemodehistory(currentgamemode);

	char cyclefile[PLATFORM_MAX_PATH];
	build_mapcyclefilename(cyclefile, modeinfo.name);

	mapcyclefile.SetString(cyclefile);
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
			IsFakeClient(j) ||
			IsClientReplay(j) ||
			IsClientSourceTV(j)) {
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
	changegamemode_timer = null;
	gamemodevotetimer = null;
	mapvotetimer = null;

	inround = false;
	rounds = 0;

	gamemodetimeelapsed = false;

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

static int randomgamemode()
{
	ArrayList weights = new ArrayList();

	GamemodeInfo modeinfo;

	ArrayList gamemodes_tochoose = new ArrayList();
	int len = gamemodes.Length;
	for(int i = 0; i < len; ++i) {
		gamemodes.GetArray(i, modeinfo, sizeof(GamemodeInfo));
		if(gamemodehistory.FindValue(i) != -1) {
			continue;
		}
		if(i == currentgamemode) {
			continue;
		}
		weights.Push(modeinfo.weight);
		gamemodes_tochoose.Push(i);
	}

	ArrayList aliases = CreateAliasRandom(weights);

	int idx = GetAliasRandom(aliases);

	int mode = gamemodes_tochoose.Get(idx);

	delete aliases;
	delete weights;
	delete gamemodes_tochoose;

	return mode;
}

public void OnConfigsExecuted()
{
	if(mp_bonusroundtime && !gmm_startrounds.IntValue) {
		if(mp_bonusroundtime.FloatValue <= gmm_voteduration.FloatValue) {
			LogError(GMM_CON_PREFIX ... "Warning - Bonus Round Time shorter than Vote Time. Votes during bonus round may not have time to complete");
		}
	}

	if(defaultgamemode == -1) {
		char gamemode[GAMEMODE_NAME_MAX];
		gmm_default.GetString(gamemode, GAMEMODE_NAME_MAX);

		if(gamemode[0] != '\0') {
			if(StrEqual(gamemode, "random")) {
				defaultgamemode = randomgamemode();
			} else {
				int idx = -1;
				if(gamemodeidmap.GetValue(gamemode, idx)) {
					defaultgamemode = idx;
				} else {
					LogError(GMM_CON_PREFIX ... "invalid default gamemode %s", gamemode);
				}
			}

			if(defaultgamemode != -1) {
				if(!lateloaded) {
					bool valid = false;

					ArrayList modes;
					if(gamemodemapmap.GetValue(currentmap, modes)) {
						int len = modes.Length;
						for(int i = 0; i < len; ++i) {
							int idx = modes.Get(i);
							if(idx == defaultgamemode) {
								valid = true;
							}
						}
					}

					nextgamemode = defaultgamemode;

					if(!valid) {
						GamemodeInfo modeinfo;
						gamemodes.GetArray(defaultgamemode, modeinfo, sizeof(GamemodeInfo));

						changerandommap(modeinfo);
					} else {
						if(currentgamemode != nextgamemode) {
							unload_currentgamemode();
							load_gamemode(nextgamemode);
						}
						nextgamemode = -1;
					}
				}
			}
		}
	}

	if(currentgamemode != -1) {
		GamemodeInfo modeinfo;
		gamemodes.GetArray(currentgamemode, modeinfo, sizeof(GamemodeInfo));

		char cyclefile[PLATFORM_MAX_PATH];
		build_mapcyclefilename(cyclefile, modeinfo.name);

		mapcyclefile.SetString(cyclefile);

		changegamemode_timer = CreateTimer(modeinfo.time * 60, timer_changemode);
	}

	voteblock_start = GetGameTime();
	CreateTimer(gmm_initial_delay.FloatValue, timer_allowvotes, 0, TIMER_FLAG_NO_MAPCHANGE);
}

static Action timer_changemode(Handle timer, any data)
{
	gamemodetimeelapsed = true;

	if(nextgamemode != -1 || inround) {
		changegamemode_timer = null;
		return Plugin_Continue;
	}

	bool any_human = false;
	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i) && !(
			IsFakeClient(i) ||
			IsClientReplay(i) ||
			IsClientSourceTV(i)
		)) {
			any_human = true;
		}
	}

	if(any_human) {
		if(!votes_allowed || !NativeVotes_IsNewVoteAllowed()) {
			float time = float(NativeVotes_CheckVoteDelay());
			changegamemode_timer = CreateTimer(time, timer_changemode, 0, TIMER_FLAG_NO_MAPCHANGE);
			return Plugin_Continue;
		}

		timer_gamemodevote(null, 0);
	} else {
		nextgamemode = randomgamemode();

		GamemodeInfo modeinfo;
		gamemodes.GetArray(nextgamemode, modeinfo, sizeof(GamemodeInfo));

		changerandommap(modeinfo);
	}

	changegamemode_timer = null;
	return Plugin_Continue;
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
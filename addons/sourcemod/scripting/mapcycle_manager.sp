#include <sourcemod>
#include <tf2>
#include <mapcycle_manager>

//#define DEBUG

#define TIME_STR_MAX 32

#define MCM_CON_PREFIX "[MCM] "

enum /*holiday_index*/
{
	holiday_none =            0,
	holiday_birthday =        1,
	holiday_halloween =       2,
	holiday_christmas =       3,
	holiday_endoftheline =    4,
	holiday_communityupdate = 5,
	holiday_valentinesday =   6,
	holiday_meetthepyro =     7,
	holiday_fullmoon =        8,
	holiday_aprilfools =      9,
	holiday_soldier =         10
};

#define NUM_HOLIDAYS 11
#define HOLIDAY_NAME_MAX 16

#define HOLIDAY_BIT(%1) view_as<holiday_flag>(1 << view_as<int>(%1))

enum holiday_flag
{
	holiday_flag_none =            0,
	holiday_flag_birthday =        (1 << holiday_birthday),
	holiday_flag_halloween =       (1 << holiday_halloween),
	holiday_flag_christmas =       (1 << holiday_christmas),
	holiday_flag_endoftheline =    (1 << holiday_endoftheline),
	holiday_flag_communityupdate = (1 << holiday_communityupdate),
	holiday_flag_valentinesday =   (1 << holiday_valentinesday),
	holiday_flag_meetthepyro =     (1 << holiday_meetthepyro),
	holiday_flag_fullmoon =        (1 << holiday_fullmoon),
	holiday_flag_aprilfools =      (1 << holiday_aprilfools),
	holiday_flag_soldier =         (1 << holiday_soldier)
};

enum struct ConfigMapInfo
{
	ArrayList paths;
	int holiday_path_idx[NUM_HOLIDAYS];
	holiday_flag holiday_alternates;
	holiday_flag holiday_restriction;
	float chance;
	int timelimit;
	int player_bounds[2];
	char time_start[TIME_STR_MAX];
	char time_end[TIME_STR_MAX];
	bool no_nominate;
}

static ArrayList config_maps;
static StringMap config_map_idx_map;

static ArrayList config_maps_with_playerchange;
static ArrayList config_maps_without_playerchange;

static char mapcyclefile_path[PLATFORM_MAX_PATH];
static ArrayList current_mapcycle;
static ArrayList current_mapcycle_maps;
static int mapcycle_playerchange_begin = -1;
static int mapcycle_playerchange_offset = -1;

static char mapcyclefile_nochance_path[PLATFORM_MAX_PATH];
static ArrayList current_mapcycle_nochance;
static ArrayList current_mapcycle_nochance_maps;
static int mapcycle_nochance_playerchange_begin = -1;
static int mapcycle_nochance_playerchange_offset = -1;

static bool initial_map_loaded;

static ConVar mapcyclefile;
static ConVar mp_timelimit;

static Handle mapchooser_plugin;
static Function mapchooser_configsexecuted = INVALID_FUNCTION;
static Function mapchooser_mcm_changed = INVALID_FUNCTION;

static Handle nominations_plugin;
static Function nominations_configsexecuted = INVALID_FUNCTION;
static Function nominations_mcm_changed = INVALID_FUNCTION;

static holiday_flag current_holiday_flags = holiday_flag_none;
static char current_map[PLATFORM_MAX_PATH];

static int num_players;
static bool ignore_playerchance = true;

static bool late_loaded;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("mapcycle_manager");
	late_loaded = late;
	return APLRes_Success;
}

static void load_config()
{
	char mapcycle_file_path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, mapcycle_file_path, PLATFORM_MAX_PATH, "configs/mcm/mapcycle.txt");

	if(FileExists(mapcycle_file_path)) {
		KeyValues kv = new KeyValues("Mapcycle");
		kv.ImportFromFile(mapcycle_file_path);

		if(kv.GotoFirstSubKey()) {
			config_maps = new ArrayList(sizeof(ConfigMapInfo));
			config_map_idx_map = new StringMap();

			ConfigMapInfo info;
			char holiday_name[HOLIDAY_NAME_MAX];
			char map_path_noholiday[PLATFORM_MAX_PATH];
			char map_path[PLATFORM_MAX_PATH];

			do {
				bool valid = true;

				info.paths = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

				kv.GetSectionName(map_path_noholiday, PLATFORM_MAX_PATH);
				int idx = info.paths.PushString(map_path_noholiday);
				info.holiday_path_idx[holiday_none] = idx;

				info.chance = kv.GetFloat("chance", 1.0);

				info.timelimit = kv.GetNum("timelimit", 60);
				if(info.timelimit < 0) {
					LogError(MCM_CON_PREFIX ... " invalid timelimit", info.timelimit);
					delete info.paths;
					continue;
				}

				info.player_bounds[0] = kv.GetNum("minplayers", -1);
				info.player_bounds[1] = kv.GetNum("maxplayers", -1);

				info.no_nominate = view_as<bool>(kv.GetNum("no_nominate", 0));

				info.holiday_alternates = holiday_flag_none;

				if(kv.JumpToKey("holiday_alternative")) {
					if(kv.GotoFirstSubKey(false)) {
						do {
							kv.GetSectionName(holiday_name, PLATFORM_MAX_PATH);

							if(StrEqual(holiday_name, "birthday")) {
								kv.GetString(NULL_STRING, map_path, PLATFORM_MAX_PATH);
								idx = info.paths.PushString(map_path);
								info.holiday_path_idx[holiday_birthday] = idx;
								info.holiday_alternates |= holiday_flag_birthday;
							} else if(StrEqual(holiday_name, "halloween")) {
								kv.GetString(NULL_STRING, map_path, PLATFORM_MAX_PATH);
								idx = info.paths.PushString(map_path);
								info.holiday_path_idx[holiday_halloween] = idx;
								info.holiday_alternates |= holiday_flag_halloween;
							} else if(StrEqual(holiday_name, "christmas")) {
								kv.GetString(NULL_STRING, map_path, PLATFORM_MAX_PATH);
								idx = info.paths.PushString(map_path);
								info.holiday_path_idx[holiday_christmas] = idx;
								info.holiday_alternates |= holiday_flag_christmas;
							} else if(StrEqual(holiday_name, "endoftheline")) {
								kv.GetString(NULL_STRING, map_path, PLATFORM_MAX_PATH);
								idx = info.paths.PushString(map_path);
								info.holiday_path_idx[holiday_endoftheline] = idx;
								info.holiday_alternates |= holiday_flag_endoftheline;
							} else if(StrEqual(holiday_name, "communityupdate")) {
								kv.GetString(NULL_STRING, map_path, PLATFORM_MAX_PATH);
								idx = info.paths.PushString(map_path);
								info.holiday_path_idx[holiday_communityupdate] = idx;
								info.holiday_alternates |= holiday_flag_communityupdate;
							} else if(StrEqual(holiday_name, "valentinesday")) {
								kv.GetString(NULL_STRING, map_path, PLATFORM_MAX_PATH);
								idx = info.paths.PushString(map_path);
								info.holiday_path_idx[holiday_valentinesday] = idx;
								info.holiday_alternates |= holiday_flag_valentinesday;
							} else if(StrEqual(holiday_name, "meetthepyro")) {
								kv.GetString(NULL_STRING, map_path, PLATFORM_MAX_PATH);
								idx = info.paths.PushString(map_path);
								info.holiday_path_idx[holiday_meetthepyro] = idx;
								info.holiday_alternates |= holiday_flag_meetthepyro;
							} else if(StrEqual(holiday_name, "fullmoon")) {
								kv.GetString(NULL_STRING, map_path, PLATFORM_MAX_PATH);
								idx = info.paths.PushString(map_path);
								info.holiday_path_idx[holiday_fullmoon] = idx;
								info.holiday_alternates |= holiday_flag_fullmoon;
							} else if(StrEqual(holiday_name, "aprilfools")) {
								kv.GetString(NULL_STRING, map_path, PLATFORM_MAX_PATH);
								idx = info.paths.PushString(map_path);
								info.holiday_path_idx[holiday_aprilfools] = idx;
								info.holiday_alternates |= holiday_flag_aprilfools;
							} else if(StrEqual(holiday_name, "soldier")) {
								kv.GetString(NULL_STRING, map_path, PLATFORM_MAX_PATH);
								idx = info.paths.PushString(map_path);
								info.holiday_path_idx[holiday_soldier] = idx;
								info.holiday_alternates |= holiday_flag_soldier;
							} else {
								LogError(MCM_CON_PREFIX ... " invalid holiday name", holiday_name);
								valid = false;
								break;
							}
						} while(kv.GotoNextKey(false));
						kv.GoBack();
					}
					kv.GoBack();
				}

				if(!valid) {
					delete info.paths;
					continue;
				}

				idx = config_maps.PushArray(info, sizeof(ConfigMapInfo));

				config_map_idx_map.SetValue(map_path_noholiday, idx);
			} while(kv.GotoNextKey());

			kv.GoBack();
		}
	}
}

static holiday_flag get_current_holidays()
{
	holiday_flag holiday_flags = holiday_flag_none;

	if(TF2_IsHolidayActive(TFHoliday_Birthday)) {
		holiday_flags |= holiday_flag_birthday;
	}
	if(TF2_IsHolidayActive(TFHoliday_Halloween)) {
		holiday_flags |= holiday_flag_halloween;
	}
	if(TF2_IsHolidayActive(TFHoliday_Christmas)) {
		holiday_flags |= holiday_flag_christmas;
	}
	if(TF2_IsHolidayActive(TFHoliday_EndOfTheLine)) {
		holiday_flags |= holiday_flag_endoftheline;
	}
	if(TF2_IsHolidayActive(TFHoliday_CommunityUpdate)) {
		holiday_flags |= holiday_flag_communityupdate;
	}
	if(TF2_IsHolidayActive(TFHoliday_ValentinesDay)) {
		holiday_flags |= holiday_flag_valentinesday;
	}
	if(TF2_IsHolidayActive(TFHoliday_MeetThePyro)) {
		holiday_flags |= holiday_flag_meetthepyro;
	}
	if(TF2_IsHolidayActive(TFHoliday_FullMoon)) {
		holiday_flags |= holiday_flag_fullmoon;
	}
	if(TF2_IsHolidayActive(TFHoliday_HalloweenOrFullMoon)) {
		holiday_flags |= (holiday_flag_halloween|holiday_flag_fullmoon);
	}
	if(TF2_IsHolidayActive(TFHoliday_HalloweenOrFullMoonOrValentines)) {
		holiday_flags |= (holiday_flag_halloween|holiday_flag_fullmoon|holiday_flag_valentinesday);
	}
	if(TF2_IsHolidayActive(TFHoliday_AprilFools)) {
		holiday_flags |= holiday_flag_aprilfools;
	}
	if(TF2_IsHolidayActive(TFHoliday_Soldier)) {
		holiday_flags |= holiday_flag_soldier;
	}

	return holiday_flags;
}

static void get_config_map_path(ConfigMapInfo info, char[] map, int size)
{
	ArrayList supported_holidays = new ArrayList();

	int holiday_mask = current_holiday_flags;
	for(int j = 0; holiday_mask; holiday_mask >>= 1, ++j) {
		if(holiday_mask & 1) {
			if(info.holiday_alternates & HOLIDAY_BIT(j)) {
				supported_holidays.Push(j);
			}
		}
	}

	int holiday = holiday_none;

	int len = supported_holidays.Length;
	if(len > 0) {
		holiday = supported_holidays.Get(GetRandomInt(0, len-1));
	}

	delete supported_holidays;

	int idx = info.holiday_path_idx[holiday];
	info.paths.GetString(idx, map, size);
}

static void add_to_mapcycle(ConfigMapInfo info, int idx)
{
	if(!info.no_nominate) {
		current_mapcycle_nochance.Push(idx);

		char map_name[PLATFORM_MAX_PATH];
		get_config_map_path(info, map_name, PLATFORM_MAX_PATH);

		current_mapcycle_nochance_maps.PushString(map_name);
	}

	if(info.chance != 1.0) {
		if(info.chance < GetRandomFloat(0.0, 1.0)) {
			return;
		}
	}

	current_mapcycle.Push(idx);

	char map_name[PLATFORM_MAX_PATH];
	get_config_map_path(info, map_name, PLATFORM_MAX_PATH);

	current_mapcycle_maps.PushString(map_name);
}

static void recompute_mapcycle_write_file(mcm_changed_from from, const char[] path, int begin, int &offset, ArrayList mapcycle)
{
	int size = 0;
	if(from == mcm_changed_player_count) {
		size = FileSize(path);
	#if defined DEBUG
		PrintToServer(MCM_CON_PREFIX ... "  file size = %i", size);
	#endif
	}

	File cycle_file;

	if(from == mcm_changed_initial) {
		cycle_file = OpenFile(path, "w+");
	} else {
		cycle_file = OpenFile(path, "r+");
		if(offset != -1) {
			cycle_file.Seek(offset, SEEK_SET);
			size -= offset
		#if defined DEBUG
			PrintToServer(MCM_CON_PREFIX ... "  write size = %i", size);
		#endif
			if(size > 0) {
				int[] nul = new int[ByteCountToCells(size)];
				cycle_file.Write(nul, size, 1);
				cycle_file.Seek(offset, SEEK_SET);
			}
		}
	}

#if defined DEBUG
	PrintToServer(MCM_CON_PREFIX ... "%s %i %i", path, from, offset);
#endif

	ConfigMapInfo info;

	char map_name[PLATFORM_MAX_PATH];

#if defined DEBUG
	PrintToServer(MCM_CON_PREFIX ... "  maps:");
#endif

	for(int i = ((from == mcm_changed_player_count) ? begin : 0); i < mapcycle.Length; ++i) {
		int idx = mapcycle.Get(i);

		config_maps.GetArray(idx, info, sizeof(ConfigMapInfo));

		get_config_map_path(info, map_name, PLATFORM_MAX_PATH);

		cycle_file.WriteString(map_name, false);
	#if defined DEBUG
		PrintToServer(MCM_CON_PREFIX ... "    %s", map_name);
	#endif
		cycle_file.WriteInt8('\n');

		if(from == mcm_changed_initial && i == (begin-1)) {
			cycle_file.Flush();
			offset = cycle_file.Position;
		}
	}

	delete cycle_file;
}

static void recompute_mapcycle_clean_playerchange(int begin, ArrayList mapcycle, ArrayList mapcycle_maps)
{
#if defined DEBUG
	PrintToServer(MCM_CON_PREFIX ... "%i %i", begin, mapcycle.Length);
#endif

	if(begin != -1) {
		if(begin >= mapcycle.Length) {
			return;
		}

		for(int i = begin; i < mapcycle.Length;) {
		#if defined DEBUG
			int idx = mapcycle.Get(i);
			ConfigMapInfo info;
			config_maps.GetArray(idx, info, sizeof(ConfigMapInfo));
			char map_name[PLATFORM_MAX_PATH];
			get_config_map_path(info, map_name, PLATFORM_MAX_PATH);
			PrintToServer(MCM_CON_PREFIX ... "removed %s %i %i", map_name, idx, i);
		#endif
			mapcycle.Erase(i);
			mapcycle_maps.Erase(i);
		}
	}
}

static void recompute_mapcycle(mcm_changed_from from)
{
	ConfigMapInfo info;

	if(from == mcm_changed_initial) {
		int len = config_maps_without_playerchange.Length;
		for(int i = 0; i < len; ++i) {
			int idx = config_maps_without_playerchange.Get(i);

			config_maps.GetArray(idx, info, sizeof(ConfigMapInfo));

			add_to_mapcycle(info, idx);
		}

		mapcycle_playerchange_begin = current_mapcycle.Length;
		mapcycle_nochance_playerchange_begin = current_mapcycle_nochance.Length;
	}

	recompute_mapcycle_clean_playerchange(mapcycle_playerchange_begin, current_mapcycle, current_mapcycle_maps);
	recompute_mapcycle_clean_playerchange(mapcycle_nochance_playerchange_begin, current_mapcycle_nochance, current_mapcycle_nochance_maps);

	int len = config_maps_with_playerchange.Length;
	for(int i = 0; i < len; ++i) {
		int idx = config_maps_with_playerchange.Get(i);

		config_maps.GetArray(idx, info, sizeof(ConfigMapInfo));

	#if defined DEBUG
		char map_name[PLATFORM_MAX_PATH];
		get_config_map_path(info, map_name, PLATFORM_MAX_PATH);

		PrintToServer(MCM_CON_PREFIX ... "%s - [%i, %i] - %i", map_name, info.player_bounds[0], info.player_bounds[1], num_players);
	#endif

		if(info.player_bounds[0] != -1) {
			if(num_players < info.player_bounds[0]) {
			#if defined DEBUG
				PrintToServer(MCM_CON_PREFIX ... "skipped %s minplayers did not match", map_name);
			#endif
				continue;
			}
		}

		if(info.player_bounds[1] != -1) {
			if(num_players >= info.player_bounds[1]) {
			#if defined DEBUG
				PrintToServer(MCM_CON_PREFIX ... "skipped %s maxplayers did not match", map_name);
			#endif
				continue;
			}
		}

		add_to_mapcycle(info, idx);
	}

	if(mapchooser_mcm_changed == INVALID_FUNCTION) {
		recompute_mapcycle_write_file(from, mapcyclefile_path, mapcycle_playerchange_begin, mapcycle_playerchange_offset, current_mapcycle);
	}

	if(nominations_mcm_changed == INVALID_FUNCTION) {
		recompute_mapcycle_write_file(from, mapcyclefile_nochance_path, mapcycle_nochance_playerchange_begin, mapcycle_nochance_playerchange_offset, current_mapcycle_nochance);
	}

	if(mapchooser_plugin != null) {
		if(mapchooser_mcm_changed != INVALID_FUNCTION) {
			Call_StartFunction(mapchooser_plugin, mapchooser_mcm_changed);
			Call_PushCell(current_mapcycle_maps);
			Call_PushCell(from);
			Call_Finish();
		} else if(mapchooser_configsexecuted != INVALID_FUNCTION) {
			mapcyclefile.SetString(mapcyclefile_path);
			Call_StartFunction(mapchooser_plugin, mapchooser_configsexecuted);
			Call_Finish();
		}
	}

	if(nominations_plugin != null) {
		if(nominations_mcm_changed != INVALID_FUNCTION) {
			Call_StartFunction(nominations_plugin, nominations_mcm_changed);
			Call_PushCell(current_mapcycle_nochance_maps);
			Call_PushCell(from);
			Call_Finish();
		} else if(nominations_configsexecuted != INVALID_FUNCTION) {
			mapcyclefile.SetString(mapcyclefile_nochance_path);
			Call_StartFunction(nominations_plugin, nominations_configsexecuted);
			Call_Finish();
		}
	}
}

public void OnPluginStart()
{
	BuildPath(Path_SM, mapcyclefile_path, PLATFORM_MAX_PATH, "data/mcm");
	CreateDirectory(mapcyclefile_path, FPERM_U_READ|FPERM_U_WRITE|FPERM_U_EXEC);
	BuildPath(Path_SM, mapcyclefile_path, PLATFORM_MAX_PATH, "data/mcm/mapcycle.txt");
	BuildPath(Path_SM, mapcyclefile_nochance_path, PLATFORM_MAX_PATH, "data/mcm/mapcycle_nochance.txt");

	config_maps_with_playerchange = new ArrayList();
	config_maps_without_playerchange = new ArrayList();
	current_mapcycle = new ArrayList();
	current_mapcycle_maps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	current_mapcycle_nochance = new ArrayList();
	current_mapcycle_nochance_maps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

	mapcyclefile = FindConVar("mapcyclefile");
	mp_timelimit = FindConVar("mp_timelimit");

	load_config();

#if defined DEBUG
	RegAdminCmd("sm_mcm_print1", sm_mcm_print1, ADMFLAG_ROOT);
	RegAdminCmd("sm_mcm_print2", sm_mcm_print2, ADMFLAG_ROOT);
#endif

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

#if defined DEBUG
static void print_mapcycle(int client, ArrayList mapcycle)
{
	int len = mapcycle.Length;

	int str_len = ((PLATFORM_MAX_PATH+1) * len);
	char[] str = new char[str_len];

	ConfigMapInfo info;

	char map_name[PLATFORM_MAX_PATH];

	for(int i = 0; i < len; ++i) {
		int idx = mapcycle.Get(i);
		config_maps.GetArray(idx, info, sizeof(ConfigMapInfo));

		get_config_map_path(info, map_name, PLATFORM_MAX_PATH);

		StrCat(str, str_len, MCM_CON_PREFIX);
		StrCat(str, str_len, " ");
		StrCat(str, str_len, map_name);
		StrCat(str, str_len, "\n");
	}

	PrintToConsole(client, "%s", str);
}

static Action sm_mcm_print1(int client, int args)
{
	print_mapcycle(client, current_mapcycle);
	return Plugin_Handled;
}

static Action sm_mcm_print2(int client, int args)
{
	print_mapcycle(client, current_mapcycle_nochance);
	return Plugin_Handled;
}
#endif

public void OnNotifyPluginUnloaded(Handle plugin)
{
	if(plugin == mapchooser_plugin) {
		mapchooser_unloaded();
	} else if(plugin == nominations_plugin) {
		nominations_unloaded();
	}
}

static void mapchooser_unloaded()
{
	mapchooser_plugin = null;
	mapchooser_configsexecuted = INVALID_FUNCTION;
	mapchooser_mcm_changed = INVALID_FUNCTION;
}

static void nominations_unloaded()
{
	nominations_plugin = null;
	nominations_configsexecuted = INVALID_FUNCTION;
	nominations_mcm_changed = INVALID_FUNCTION;
}

static void find_nominations()
{
	if(nominations_plugin != null &&
		nominations_configsexecuted != INVALID_FUNCTION) {
		return;
	}

	static const char nominations_paths[][PLATFORM_MAX_PATH] = {
		"thirdparty_edited/nominations_extended.smx",
		"thirdparty/nominations_extended.smx",
		"thirdparty/nativevotes_nominations.smx",
		"nominations_extended.smx",
		"nativevotes_nominations.smx",
		"nominations.smx"
	};

	for(int i = 0; i < sizeof(nominations_paths); ++i) {
		nominations_plugin = FindPluginByFile(nominations_paths[i]);
		if(nominations_plugin != null) {
			break;
		}
	}

	if(nominations_plugin == null) {
		char plugin_filename[PLATFORM_MAX_PATH];

		Handle iter = GetPluginIterator();
		while(MorePlugins(iter)) {
			Handle plugin = ReadPlugin(iter);

			GetPluginFilename(plugin, plugin_filename, PLATFORM_MAX_PATH);

			if(StrContains(plugin_filename, "nominations") != -1) {
				nominations_plugin = plugin;
				break;
			}
		}
		delete iter;
	}
	if(nominations_plugin != null) {
		nominations_configsexecuted = GetFunctionByName(nominations_plugin, "OnConfigsExecuted");
		nominations_mcm_changed = GetFunctionByName(nominations_plugin, "mcm_changed");
	}
#if defined DEBUG
	PrintToServer(MCM_CON_PREFIX ... "nominations plugin: %i", nominations_plugin != null ? 1 : 0);
	PrintToServer(MCM_CON_PREFIX ... "nominations OnConfigsExecuted: %i", nominations_configsexecuted != INVALID_FUNCTION ? 1 : 0);
	PrintToServer(MCM_CON_PREFIX ... "nominations mcm_changed: %i", nominations_mcm_changed != INVALID_FUNCTION ? 1 : 0);
#endif
}

static void find_mapchooser()
{
	if(mapchooser_plugin != null &&
		mapchooser_configsexecuted != INVALID_FUNCTION) {
		return;
	}

	static const char mapchooser_paths[][PLATFORM_MAX_PATH] = {
		"thirdparty_edited/mapchooser_extended.smx",
		"thirdparty/mapchooser_extended.smx",
		"thirdparty/nativevotes_mapchooser.smx",
		"mapchooser_extended.smx",
		"nativevotes_mapchooser.smx",
		"mapchooser.smx"
	};

	for(int i = 0; i < sizeof(mapchooser_paths); ++i) {
		mapchooser_plugin = FindPluginByFile(mapchooser_paths[i]);
		if(mapchooser_plugin != null) {
			break;
		}
	}

	if(mapchooser_plugin == null) {
		char plugin_filename[PLATFORM_MAX_PATH];

		Handle iter = GetPluginIterator();
		while(MorePlugins(iter)) {
			Handle plugin = ReadPlugin(iter);

			GetPluginFilename(plugin, plugin_filename, PLATFORM_MAX_PATH);

			if(StrContains(plugin_filename, "mapchooser") != -1) {
				mapchooser_plugin = plugin;
				break;
			}
		}
		delete iter;
	}
	if(mapchooser_plugin != null) {
		mapchooser_configsexecuted = GetFunctionByName(mapchooser_plugin, "OnConfigsExecuted");
		mapchooser_mcm_changed = GetFunctionByName(mapchooser_plugin, "mcm_changed");
	}
#if defined DEBUG
	PrintToServer(MCM_CON_PREFIX ... "mapchooser plugin: %i", mapchooser_plugin != null ? 1 : 0);
	PrintToServer(MCM_CON_PREFIX ... "mapchooser OnConfigsExecuted: %i", mapchooser_configsexecuted != INVALID_FUNCTION ? 1 : 0);
	PrintToServer(MCM_CON_PREFIX ... "mapchooser mcm_changed: %i", mapchooser_mcm_changed != INVALID_FUNCTION ? 1 : 0);
#endif
}

public void OnAllPluginsLoaded()
{
	find_mapchooser();
	find_nominations();
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "mapchooser")) {
		find_mapchooser();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "mapchooser")) {
		mapchooser_unloaded();
	}
}

public void OnConfigsExecuted()
{
	current_holiday_flags = get_current_holidays();

	ConfigMapInfo info;

	config_maps_with_playerchange.Clear();
	config_maps_without_playerchange.Clear();
	current_mapcycle.Clear();
	current_mapcycle_maps.Clear();
	current_mapcycle_nochance.Clear();
	current_mapcycle_nochance_maps.Clear();

	int len = config_maps.Length;
	for(int i = 0; i < len; ++i) {
		config_maps.GetArray(i, info, sizeof(ConfigMapInfo));

		/*if(!(info.holiday_restriction & current_holiday_flags)) {
			continue;
		}*/

	#if defined DEBUG
		char map_name[PLATFORM_MAX_PATH];
		get_config_map_path(info, map_name, PLATFORM_MAX_PATH);
	#endif

		if(info.player_bounds[0] != -1 ||
			info.player_bounds[1] != -1) {
		#if defined DEBUG
			PrintToServer(MCM_CON_PREFIX ... "%s - playerchange", map_name);
		#endif
			config_maps_with_playerchange.Push(i);
		} else {
		#if defined DEBUG
			PrintToServer(MCM_CON_PREFIX ... "%s - no playerchange", map_name);
		#endif
			config_maps_without_playerchange.Push(i);
		}
	}

	recompute_mapcycle(mcm_changed_initial);

	if(mapchooser_mcm_changed == INVALID_FUNCTION || nominations_mcm_changed == INVALID_FUNCTION) {
		mapcyclefile.SetString(mapcyclefile_path);
	}

	ignore_playerchance = false;

	if(!late_loaded) {
		if(!initial_map_loaded) {
			initial_map_loaded = true;
			if(FindCommandLineParam("+randommap")) {
				int i = GetRandomInt(0, current_mapcycle_nochance.Length-1);
				int idx = current_mapcycle_nochance.Get(i);
				config_maps.GetArray(idx, info, sizeof(ConfigMapInfo));
				char map_name[PLATFORM_MAX_PATH];
				get_config_map_path(info, map_name, PLATFORM_MAX_PATH);
				if(!StrEqual(map_name, current_map)) {
					SetNextMap(map_name);
					ForceChangeLevel(map_name, "MCM");
					return;
				}
			}
		}
	}

	int idx = -1;
	if(config_map_idx_map.GetValue(current_map, idx)) {
		config_maps.GetArray(idx, info, sizeof(ConfigMapInfo));

	#if defined DEBUG
		PrintToServer(MCM_CON_PREFIX ... "mp_timelimit: %i", mp_timelimit.IntValue);
		PrintToServer(MCM_CON_PREFIX ... "config timelimit: %i", info.timelimit);
	#endif

		int old_timelimit = mp_timelimit.IntValue;
		if(info.timelimit != old_timelimit) {
			int new_timelimit = old_timelimit;
			GetMapTimeLimit(new_timelimit);
		#if defined DEBUG
			PrintToServer(MCM_CON_PREFIX ... "timelimit before calc: %i", new_timelimit);
		#endif
			new_timelimit = -(new_timelimit - info.timelimit);
		#if defined DEBUG
			PrintToServer(MCM_CON_PREFIX ... "timelimit after calc: %i", new_timelimit);
		#endif
			ExtendMapTimeLimit(new_timelimit * 60);
		}
	}
}

public void OnClientPutInServer(int client)
{
#if !defined DEBUG
	if(IsFakeClient(client) ||
		IsClientSourceTV(client) ||
		IsClientReplay(client)) {
		return;
	}
#endif

	++num_players;

	if(!ignore_playerchance) {
		recompute_mapcycle(mcm_changed_player_count);
	}
}

public void OnClientDisconnect(int client)
{
#if !defined DEBUG
	if(IsFakeClient(client) ||
		IsClientSourceTV(client) ||
		IsClientReplay(client)) {
		return;
	}
#endif

	--num_players;

	if(!ignore_playerchance) {
		recompute_mapcycle(mcm_changed_player_count);
	}
}

public void OnMapStart()
{
	GetCurrentMap(current_map, PLATFORM_MAX_PATH);
}

public void OnMapEnd()
{
	ignore_playerchance = true;
}
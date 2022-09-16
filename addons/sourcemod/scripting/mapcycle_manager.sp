#include <sourcemod>
#include <tf2>
#include <mapcycle_manager>
#include <regex>
#include <system2>

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

#define HOLIDAY_BIT(%1) view_as<holiday_flag>(1 << view_as<int>(%1))

#define CONFIG_NAME_MAX 32
#define BUILDER_NAME_MAX 32

enum struct BuilderInfo
{
	char name[BUILDER_NAME_MAX];
	ArrayList whitelist_regexes;
	ArrayList blacklist_regexes;
	File file;
	int num_workshop_maps;
}

//TODO!!!!!!! support multiple paths for the same holiday
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

static char current_config_name[CONFIG_NAME_MAX];

static bool configs_executed;

static ConVar mcm_api_key;

static ArrayList config_maps;
static StringMap config_map_idx_map;
static int config_maps_raw_begin = -1;

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

static char original_mapcyclefile[PLATFORM_MAX_PATH];
static ConVar mapcyclefile;
static int original_timelimit;
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
static bool ignore_playerchange = true;

static bool late_loaded;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("mapcycle_manager");
	CreateNative("mcm_read_maps", native_mcm_read_maps);
	CreateNative("mcm_set_config", native_mcm_set_config);
	late_loaded = late;
	return APLRes_Success;
}

static int native_mcm_set_config(Handle plugin, int params)
{
	if(IsNativeParamNullString(1)) {
		current_config_name[0] = '\0';
		if(configs_executed) {
			reload_maps();
		}
	} else {
		int len;
		GetNativeStringLength(1, len);
		char[] name = new char[++len];
		GetNativeString(1, name, len);

		if(name[0] == '\0') {
			current_config_name[0] = '\0';
			if(configs_executed) {
				reload_maps();
			}
		} else {
			strcopy(current_config_name, CONFIG_NAME_MAX, name);
			if(configs_executed) {
				reload_maps();
			}
		}
	}

	return 0;
}

#define APIKEY_MAX 64
#define WORKSHOP_ID_MAX 15
#define WORKSHOP_CMD_MAX (22 + WORKSHOP_ID_MAX)

//#define WORKSHOP_USE_MAPNAME_IN_CYCLE

static ArrayList builders;

enum struct WorkshopRequestInfo
{
	char builder_name[BUILDER_NAME_MAX];
	bool only_download;
}

static int num_workshop_requests;
static int num_workshop_metadatas;
static ArrayList workshop_commands;
static ArrayList workshop_request_data;

#if defined WORKSHOP_USE_MAPNAME_IN_CYCLE
static void get_details(bool success, const char[] error, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method)
{
	BuilderInfo info;

	WorkshopRequestInfo req_info;
	int data_idx = request.Any;
	workshop_request_data.GetArray(data_idx, req_info, sizeof(WorkshopRequestInfo));

	int builders_len = builders.Length;

	bool found_builder = false;

	for(int i = 0; i < builders_len; ++i) {
		builders.GetArray(i, info, sizeof(BuilderInfo));

		if(StrEqual(req_info.builder_name, info.name)) {
			found_builder = true;
			break;
		}
	}

	if(success && found_builder && !req_info.only_download) {
		int len = response.ContentLength;
		char[] text = new char[++len];
		response.GetContent(text, len);

		KeyValues kv = new KeyValues("response");

		if(kv.ImportFromString(text, "response")) {
			if(kv.JumpToKey("publishedfiledetails") && kv.GotoFirstSubKey()) {
				char filename[PLATFORM_MAX_PATH];
				kv.GetString("metadata", filename, PLATFORM_MAX_PATH);

				int bsp = StrContains(filename, ".bsp");
				if(bsp != -1 && (strlen(filename)-bsp) == 4) {
					filename[bsp] = '\0';

					bool found = false;

					int rex_len = info.blacklist_regexes.Length;
					for(int j = 0; j < rex_len; ++j) {
						Regex rex = info.blacklist_regexes.Get(j);
						if(rex.Match(filename) > 0) {
							found = true;
						}
					}

					if(!found) {
						char workshop_id[WORKSHOP_ID_MAX];
						kv.GetString("publishedfileid", workshop_id, WORKSHOP_ID_MAX);
						if(workshop_id[0] != '\0') {
						#if defined WORKSHOP_USE_MAPNAME_IN_CYCLE
							Format(filename, PLATFORM_MAX_PATH, "workshop/%s.ugc%s", filename, workshop_id);
						#else
							FormatEx(filename, PLATFORM_MAX_PATH, "workshop/%s", workshop_id);
						#endif
						}
						info.file.WriteString(filename, false);
						info.file.WriteInt8('\n');
					}
				}
			}
		}

		delete kv;
	}

	if(--num_workshop_metadatas == 0) {
		for(int i = 0; i < builders_len; ++i) {
			builders.GetArray(i, info, sizeof(BuilderInfo));

			delete info.file;
			delete info.blacklist_regexes;
			delete info.whitelist_regexes;
		}

		delete builders;

		delete workshop_request_data;
	}
}
#endif

static void collection_details(bool success, const char[] error, System2HTTPRequest request, System2HTTPResponse response, HTTPRequestMethod method)
{
	char cmd_line[WORKSHOP_CMD_MAX];

	if(success) {
		int len = response.ContentLength;
		char[] text = new char[++len];
		response.GetContent(text, len);

		KeyValues kv = new KeyValues("response");
		if(kv.ImportFromString(text, "response")) {
			if(kv.JumpToKey("collectiondetails") && kv.GotoFirstSubKey()) {
				int result = kv.GetNum("result");

				char workshop_id[WORKSHOP_ID_MAX];

				WorkshopRequestInfo req_info;
				int data_idx = request.Any;
				workshop_request_data.GetArray(data_idx, req_info, sizeof(WorkshopRequestInfo));

			#if defined WORKSHOP_USE_MAPNAME_IN_CYCLE
				#define URL_FORMAT \
					"https://api.steampowered.com/IPublishedFileService/GetDetails/v1/?format=vdf" ... \
					"&key=%s" ... \
					"&publishedfileids[0]=%s" ... \
					"&includemetadata=true" ... \
					"&appid=440" ... \
					"&includetags=false" ... \
					"&includeadditionalpreviews=false" ... \
					"&includechildren=false" ... \
					"&includekvtags=false" ... \
					"&includevotes=false" ... \
					"&short_description=true" ... \
					"&includeforsaledata=false" ... \
					"&return_playtime_stats=0" ... \
					"&strip_description_bbcode=true" ... \
					"&includereactions=false"

				char api_key[APIKEY_MAX];
				mcm_api_key.GetString(api_key, APIKEY_MAX);
			#else
				BuilderInfo info;

				int builders_len = builders.Length;

				bool found_builder = false;

				for(int i = 0; i < builders_len; ++i) {
					builders.GetArray(i, info, sizeof(BuilderInfo));

					if(StrEqual(req_info.builder_name, info.name)) {
						found_builder = true;
						break;
					}
				}
			#endif

				switch(result) {
					case 1: {
						if(kv.JumpToKey("children")) {
							if(kv.GotoFirstSubKey()) {
								do {
									int filetype = kv.GetNum("filetype");
									if(filetype != 0) {
										continue;
									}

									kv.GetString("publishedfileid", workshop_id, WORKSHOP_ID_MAX);
									strcopy(cmd_line, WORKSHOP_CMD_MAX, "tf_workshop_map_sync ");
									StrCat(cmd_line, WORKSHOP_CMD_MAX, workshop_id);
									workshop_commands.PushString(cmd_line);

								#if defined WORKSHOP_USE_MAPNAME_IN_CYCLE
									if(!req_info.only_download && api_key[0] != '\0') {
										//TODO!!!!!!!!!!!!!!! only do a single request
										System2HTTPRequest post = new System2HTTPRequest(get_details, URL_FORMAT, api_key, workshop_id);
										post.Any = data_idx;
										post.GET();
										++num_workshop_metadatas;
									}
								#else
									if(found_builder) {
										info.file.WriteString("workshop/", false);
										info.file.WriteString(workshop_id, false);
										info.file.WriteInt8('\n');
									}
								#endif
								} while(kv.GotoNextKey());
								kv.GoBack();
							}
							kv.GoBack();
						}
					}
					case 9: {
						kv.GetString("publishedfileid", workshop_id, WORKSHOP_ID_MAX);
						strcopy(cmd_line, WORKSHOP_CMD_MAX, "tf_workshop_map_sync ");
						StrCat(cmd_line, WORKSHOP_CMD_MAX, workshop_id);
						workshop_commands.PushString(cmd_line);

					#if defined WORKSHOP_USE_MAPNAME_IN_CYCLE
						if(!req_info.only_download && api_key[0] != '\0') {
							//TODO!!!!!!!!!!!!!!! only do a single request
							System2HTTPRequest post = new System2HTTPRequest(get_details, URL_FORMAT, api_key, workshop_id);
							post.Any = data_idx;
							post.GET();
							++num_workshop_metadatas;
						}
					#else
						if(found_builder) {
							info.file.WriteString("workshop/", false);
							info.file.WriteString(workshop_id, false);
							info.file.WriteInt8('\n');
						}
					#endif
					}
				}
			}
		}

		delete kv;
	}

	if(--num_workshop_requests == 0) {
		int len = workshop_commands.Length;
		for(int i = 0; i < len; ++i) {
			workshop_commands.GetString(i, cmd_line, WORKSHOP_CMD_MAX);
			InsertServerCommand("%s", cmd_line);
		}
		delete workshop_commands;
		ServerExecute();

		if(num_workshop_metadatas == 0) {
			int builders_len = builders.Length;

			BuilderInfo info;

			for(int i = 0; i < builders_len; ++i) {
				builders.GetArray(i, info, sizeof(BuilderInfo));

				delete info.file;
				delete info.blacklist_regexes;
				delete info.whitelist_regexes;
			}

			delete builders;

			delete workshop_request_data;
		}
	}
}

static void load_builders()
{
	if(num_workshop_requests != 0 ||
		num_workshop_metadatas != 0 ||
		workshop_commands != null ||
		workshop_request_data != null ||
		builders != null) {
		SetFailState("should never happen");
	}

	builders = new ArrayList(sizeof(BuilderInfo));
	workshop_request_data = new ArrayList(sizeof(WorkshopRequestInfo));
	num_workshop_requests = 0;
	num_workshop_metadatas = 0;
	workshop_commands = new ArrayList(ByteCountToCells(WORKSHOP_CMD_MAX));

	char builders_dir_path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, builders_dir_path, PLATFORM_MAX_PATH, "configs/mcm/builders");

	BuilderInfo info;

	char filename[PLATFORM_MAX_PATH];

	char file_path[PLATFORM_MAX_PATH];

	DirectoryListing builders_dir = OpenDirectory(builders_dir_path);
	if(builders_dir) {
		char regex_str[128];
		char line[PLATFORM_MAX_PATH];
		FileType filetype;
		while(builders_dir.GetNext(filename, PLATFORM_MAX_PATH, filetype)) {
			if(filetype != FileType_File) {
				continue;
			}

			int txt = StrContains(filename, ".txt");
			if(txt == -1) {
				continue;
			}

			if((strlen(filename)-txt) != 4) {
				continue;
			}

			strcopy(info.name, BUILDER_NAME_MAX, filename);
			info.name[txt] = '\0';

			FormatEx(file_path, PLATFORM_MAX_PATH, "%s/%s", builders_dir_path, filename);

			File mapcycle = OpenFile(file_path, "r", false);
			if(mapcycle) {
				info.blacklist_regexes = new ArrayList();
				info.whitelist_regexes = new ArrayList();

				while(!mapcycle.EndOfFile()) {
					if(mapcycle.ReadLine(line, PLATFORM_MAX_PATH)) {
						ReplaceString(line, PLATFORM_MAX_PATH, "\n", "", false);
						ReplaceString(line, PLATFORM_MAX_PATH, "\r", "", false);
						ReplaceString(line, PLATFORM_MAX_PATH, "\t", "", false);
						ReplaceString(line, PLATFORM_MAX_PATH, " ", "", false);

						if(line[0] == '/' && line[1] == '/' || line[0] == '\0') {
							continue;
						}

						bool flag = (line[0] == '!');

						if(strcmp(line[flag ? 1 : 0], "workshop/") == 1) {
							++num_workshop_requests;
							++info.num_workshop_maps;
							//TODO!!!!!!!!!!!!!!! only do a single request
							System2HTTPRequest post = new System2HTTPRequest(collection_details, "https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/?format=vdf");
							post.SetData("collectioncount=1&publishedfileids[0]=%s", line[flag ? 10 : 9]);
							WorkshopRequestInfo req_info;
							strcopy(req_info.builder_name, BUILDER_NAME_MAX, info.name);
							req_info.only_download = flag;
							post.Any = workshop_request_data.PushArray(req_info, sizeof(WorkshopRequestInfo));
							post.POST();
							continue;
						} else {
							RegexError regex_code;
							Regex regex = new Regex(line[flag ? 1 : 0], PCRE_UTF8, regex_str, sizeof(regex_str), regex_code);
							if(regex_code != REGEX_ERROR_NONE) {
								delete regex;
								continue;
							}

							if(flag) {
								info.blacklist_regexes.Push(regex);
							} else {
								info.whitelist_regexes.Push(regex);
							}
						}
					}
				}
			}
			delete mapcycle;

			BuildPath(Path_SM, file_path, PLATFORM_MAX_PATH, "data/mcm/%s", filename);

			info.file = OpenFile(file_path, "w+", false);

			builders.PushArray(info, sizeof(BuilderInfo));
		}
		delete builders_dir;
	}

	if(num_workshop_requests == 0) {
		delete workshop_commands;
		delete workshop_request_data;
	}

	int builders_len = builders.Length;

	DirectoryListing maps_dir = OpenDirectory("maps", true);
	FileType filetype;
	while(maps_dir.GetNext(filename, PLATFORM_MAX_PATH, filetype)) {
		if(filetype != FileType_File) {
			continue;
		}

		int bsp = StrContains(filename, ".bsp");
		if(bsp == -1) {
			continue;
		}

		if((strlen(filename)-bsp) != 4) {
			continue;
		}

		filename[bsp] = '\0';

		for(int i = 0; i < builders_len; ++i) {
			builders.GetArray(i, info, sizeof(BuilderInfo));

			bool found = false;

			int rex_len = info.blacklist_regexes.Length;
			for(int j = 0; j < rex_len; ++j) {
				Regex rex = info.blacklist_regexes.Get(j);
				if(rex.Match(filename) > 0) {
					found = true;
				}
			}

			if(found) {
				continue;
			}

			rex_len = info.whitelist_regexes.Length;
			for(int j = 0; j < rex_len; ++j) {
				Regex rex = info.whitelist_regexes.Get(j);
				if(rex.Match(filename) > 0) {
					found = true;
				}
			}

			if(found) {
				info.file.WriteString(filename, false);
				info.file.WriteInt8('\n');
			}
		}
	}

	for(int i = 0; i < builders_len;) {
		builders.GetArray(i, info, sizeof(BuilderInfo));

		if(info.num_workshop_maps == 0) {
			delete info.file;
			delete info.blacklist_regexes;
			delete info.whitelist_regexes;

			--builders_len;
			builders.Erase(i);
			continue;
		}

		++i;
	}

	if(num_workshop_requests == 0) {
		delete builders;
	}
}

static int native_mcm_read_maps(Handle plugin, int params)
{
	int len;
	GetNativeStringLength(1, len);
	char[] name = new char[++len];
	GetNativeString(1, name, len);

	ArrayList maps = GetNativeCell(2);

	maps.Clear();

	char mapcycle_file_path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, mapcycle_file_path, PLATFORM_MAX_PATH, "configs/mcm/%s.txt", name);

	char map_path[PLATFORM_MAX_PATH];

	if(FileExists(mapcycle_file_path)) {
		KeyValues kv = new KeyValues("Mapcycle");
		if(kv.ImportFromFile(mapcycle_file_path)) {
			if(kv.GotoFirstSubKey()) {
				do {
					kv.GetSectionName(map_path, PLATFORM_MAX_PATH);
					maps.PushString(map_path);

					if(kv.JumpToKey("holiday_alternative")) {
						if(kv.GotoFirstSubKey(false)) {
							do {
								kv.GetString(NULL_STRING, map_path, PLATFORM_MAX_PATH);
								maps.PushString(map_path);
							} while(kv.GotoNextKey(false));
							kv.GoBack();
						}
						kv.GoBack();
					}
				} while(kv.GotoNextKey());
				kv.GoBack();
			}
		}
		delete kv;
	}

	BuildPath(Path_SM, mapcycle_file_path, PLATFORM_MAX_PATH, "data/mcm/%s.txt", name);

	File mapcycle = OpenFile(mapcycle_file_path, "r", true);
	if(mapcycle) {
		char line[PLATFORM_MAX_PATH];

		while(!mapcycle.EndOfFile()) {
			if(mapcycle.ReadLine(line, PLATFORM_MAX_PATH)) {
				ReplaceString(line, PLATFORM_MAX_PATH, "\n", "", false);
				ReplaceString(line, PLATFORM_MAX_PATH, "\r", "", false);
				ReplaceString(line, PLATFORM_MAX_PATH, "\t", "", false);
				ReplaceString(line, PLATFORM_MAX_PATH, " ", "", false);

				if(line[0] == '/' && line[1] == '/') {
					continue;
				}

				if(maps.FindString(line) != -1) {
					continue;
				}

				maps.PushString(line);
			}
		}
	}
	delete mapcycle;

	return 0;
}

static void load_config()
{
	ConfigMapInfo info;

	if(config_maps != null) {
		int len = config_maps.Length;
		for(int i = 0; i < len; ++i) {
			config_maps.GetArray(i, info, sizeof(ConfigMapInfo));
			delete info.paths;
		}
		config_maps.Clear();
	} else {
		config_maps = new ArrayList(sizeof(ConfigMapInfo));
	}

	if(config_map_idx_map != null) {
		config_map_idx_map.Clear();
	} else {
		config_map_idx_map = new StringMap();
	}

	char mapcycle_file_path[PLATFORM_MAX_PATH];
	if(current_config_name[0] == '\0') {
		BuildPath(Path_SM, mapcycle_file_path, PLATFORM_MAX_PATH, "configs/mcm/mapcycle.txt");
	} else {
		BuildPath(Path_SM, mapcycle_file_path, PLATFORM_MAX_PATH, "configs/mcm/%s.txt", current_config_name);
	}

	if(FileExists(mapcycle_file_path)) {
		KeyValues kv = new KeyValues("Mapcycle");
		if(kv.ImportFromFile(mapcycle_file_path)) {
			if(kv.GotoFirstSubKey()) {
				char holiday_name[HOLIDAY_NAME_MAX];
				char map_path[PLATFORM_MAX_PATH];

				do {
					bool valid = true;

					info.paths = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

					for(int i = 0; i < NUM_HOLIDAYS; ++i) {
						info.holiday_path_idx[i] = -1;
					}

					kv.GetSectionName(map_path, PLATFORM_MAX_PATH);
					int idx = info.paths.PushString(map_path);
					info.holiday_path_idx[holiday_none] = idx;

					info.chance = kv.GetFloat("chance", 1.0);

					info.timelimit = kv.GetNum("timelimit", original_timelimit);
					if(info.timelimit < 0) {
						LogError(MCM_CON_PREFIX ... " invalid timelimit", info.timelimit);
						delete info.paths;
						continue;
					}

					info.player_bounds[0] = kv.GetNum("minplayers", -1);
					info.player_bounds[1] = kv.GetNum("maxplayers", -1);

					info.no_nominate = view_as<bool>(kv.GetNum("no_nominate", 0));

					info.holiday_restriction = holiday_flag_none;

					info.holiday_alternates = holiday_flag_none;

					if(kv.JumpToKey("holiday_alternative")) {
						if(kv.GotoFirstSubKey(false)) {
							do {
								kv.GetSectionName(holiday_name, HOLIDAY_NAME_MAX);

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

					int len = info.paths.Length;
					for(int i = 0; i < len; ++i) {
						info.paths.GetString(i, map_path, PLATFORM_MAX_PATH);
						config_map_idx_map.SetValue(map_path, idx);
					}
				} while(kv.GotoNextKey());

				kv.GoBack();
			}
		}
		delete kv;
	}
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

	char tmp_mapcyclefile[PLATFORM_MAX_PATH];
	mapcyclefile.GetString(tmp_mapcyclefile, PLATFORM_MAX_PATH);

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
			mapcyclefile.SetString(tmp_mapcyclefile);
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
			mapcyclefile.SetString(tmp_mapcyclefile);
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

	mcm_api_key = CreateConVar("mcm_api_key", "");

	load_builders();

#if defined DEBUG || 1
	RegAdminCmd("sm_mcm_print1", sm_mcm_print1, ADMFLAG_ROOT);
	RegAdminCmd("sm_mcm_print2", sm_mcm_print2, ADMFLAG_ROOT);
#endif

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

#if defined DEBUG || 1
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

public void OnPluginEnd()
{
	mapcyclefile.SetString(original_mapcyclefile);
	mp_timelimit.IntValue = original_timelimit;
}

static void load_maps()
{
	load_config();

	config_maps_raw_begin = config_maps.Length;

	ConfigMapInfo info;
	char line[PLATFORM_MAX_PATH];

	char tmp_mapcyclefile_path[PLATFORM_MAX_PATH];
	if(current_config_name[0] == '\0') {
		strcopy(tmp_mapcyclefile_path, PLATFORM_MAX_PATH, original_mapcyclefile);
		if(!FileExists(tmp_mapcyclefile_path, true)) {
			Format(tmp_mapcyclefile_path, PLATFORM_MAX_PATH, "cfg/%s", tmp_mapcyclefile_path);
		}

		File mapcycle = OpenFile(tmp_mapcyclefile_path, "r", true);
		if(mapcycle) {
			while(!mapcycle.EndOfFile()) {
				if(mapcycle.ReadLine(line, PLATFORM_MAX_PATH)) {
					ReplaceString(line, PLATFORM_MAX_PATH, "\n", "", false);
					ReplaceString(line, PLATFORM_MAX_PATH, "\r", "", false);
					ReplaceString(line, PLATFORM_MAX_PATH, "\t", "", false);
					ReplaceString(line, PLATFORM_MAX_PATH, " ", "", false);

					if(line[0] == '/' && line[1] == '/') {
						continue;
					}

					if(config_map_idx_map.ContainsKey(line)) {
						continue;
					}

					info.paths = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
					for(int i = 0; i < NUM_HOLIDAYS; ++i) {
						info.holiday_path_idx[i] = -1;
					}

					int idx = info.paths.PushString(line);
					info.holiday_path_idx[holiday_none] = idx;

					info.holiday_alternates = holiday_flag_none;
					info.holiday_restriction = holiday_flag_none;
					info.chance = 1.0;
					info.timelimit = original_timelimit;
					info.player_bounds[0] = -1;
					info.player_bounds[1] = -1;
					info.no_nominate = false;

					idx = config_maps.PushArray(info, sizeof(ConfigMapInfo));
					config_map_idx_map.SetValue(line, idx);
				}
			}
		}
		delete mapcycle;
	}

	if(current_config_name[0] == '\0') {
		BuildPath(Path_SM, tmp_mapcyclefile_path, PLATFORM_MAX_PATH, "data/mcm/default.txt");
	} else {
		BuildPath(Path_SM, tmp_mapcyclefile_path, PLATFORM_MAX_PATH, "data/mcm/%s.txt", current_config_name);
	}

	File mapcycle = OpenFile(tmp_mapcyclefile_path, "r", true);
	if(mapcycle) {
		while(!mapcycle.EndOfFile()) {
			if(mapcycle.ReadLine(line, PLATFORM_MAX_PATH)) {
				ReplaceString(line, PLATFORM_MAX_PATH, "\n", "", false);
				ReplaceString(line, PLATFORM_MAX_PATH, "\r", "", false);
				ReplaceString(line, PLATFORM_MAX_PATH, "\t", "", false);
				ReplaceString(line, PLATFORM_MAX_PATH, " ", "", false);

				if(line[0] == '/' && line[1] == '/') {
					continue;
				}

				if(config_map_idx_map.ContainsKey(line)) {
					continue;
				}

				info.paths = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
				for(int i = 0; i < NUM_HOLIDAYS; ++i) {
					info.holiday_path_idx[i] = -1;
				}

				int idx = info.paths.PushString(line);
				info.holiday_path_idx[holiday_none] = idx;

				info.holiday_alternates = holiday_flag_none;
				info.holiday_restriction = holiday_flag_none;
				info.chance = 1.0;
				info.timelimit = original_timelimit;
				info.player_bounds[0] = -1;
				info.player_bounds[1] = -1;
				info.no_nominate = false;

				idx = config_maps.PushArray(info, sizeof(ConfigMapInfo));
				config_map_idx_map.SetValue(line, idx);
			}
		}
	}
	delete mapcycle;

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
}

static void reload_maps()
{
	remove_raw_maps();
	load_maps();
}

public void OnConfigsExecuted()
{
	mapcyclefile.GetString(original_mapcyclefile, PLATFORM_MAX_PATH);
	original_timelimit = mp_timelimit.IntValue;

	current_holiday_flags = get_current_holidays();

	load_maps();

	ignore_playerchange = false;

	ConfigMapInfo info;

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

	configs_executed = true;
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

	if(!ignore_playerchange) {
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

	if(!ignore_playerchange) {
		recompute_mapcycle(mcm_changed_player_count);
	}
}

public void OnMapStart()
{
	GetCurrentMap(current_map, PLATFORM_MAX_PATH);
}

static void remove_raw_maps()
{
	if(config_maps_raw_begin != -1) {
		if(config_maps_raw_begin >= config_maps.Length) {
			config_maps_raw_begin = -1;
			return;
		}

		ConfigMapInfo info;

		char path[PLATFORM_MAX_PATH];

		for(int i = config_maps_raw_begin; i < config_maps.Length;) {
			config_maps.GetArray(i, info, sizeof(ConfigMapInfo));

			int len = info.paths.Length;
			for(int j = 0; j < len; ++j) {
				info.paths.GetString(j, path, PLATFORM_MAX_PATH);

				config_map_idx_map.Remove(path);
			}

			config_maps.Erase(i);
		}
	}

	config_maps_raw_begin = -1;
}

public void OnMapEnd()
{
	ignore_playerchange = true;

	mapcyclefile.SetString(original_mapcyclefile);
	mp_timelimit.IntValue = original_timelimit;

	configs_executed = false;

	remove_raw_maps();
}
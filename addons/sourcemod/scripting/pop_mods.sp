#include <sourcemod>
#include <popspawner>

enum mod_type_t
{
	mod_merge,
	mod_merge_parent,
	mod_merge_root,
};

enum struct ModInfo
{
	KeyValues data;
	float min;
	float max;
	mod_type_t type;
}

static ArrayList manager_mods;
static ArrayList wave_mods;
static ArrayList wavespawn_mods;

public void OnPluginStart()
{
	manager_mods = new ArrayList(sizeof(ModInfo));
	wave_mods = new ArrayList(sizeof(ModInfo));
	wavespawn_mods = new ArrayList(sizeof(ModInfo));
}

static void parse_mod(const char[] path, ArrayList arr)
{
	mod_type_t type = mod_merge;

	int idx = StrContains(path, ".parent");
	if(idx != -1) {
		type = mod_merge_parent;
	} else {
		idx = StrContains(path, ".root");
		if(idx != -1) {
			type = mod_merge_root;
		}
	}

	KeyValues kv = new KeyValues("Population");
	if(kv.ImportFromFile(path)) {
		if(kv.GotoFirstSubKey()) {
			ModInfo mod;

			#define PERC_SIZE 10

			char name[PERC_SIZE + 1 + PERC_SIZE];

			do {
				kv.GetSectionName(name, sizeof(name));

				char min_str[PERC_SIZE];
				int max_start = BreakString(name, min_str, PERC_SIZE);

				char max_str[PERC_SIZE];
				strcopy(max_str, PERC_SIZE, name[max_start]);

				mod.data = new KeyValues("Population");
				mod.data.Import(kv);

				mod.min = StringToFloat(min_str);
				mod.max = StringToFloat(max_str);

				mod.type = type;

				arr.PushArray(mod, sizeof(ModInfo));
			} while(kv.GotoNextKey());
			kv.GoBack();
		}
	}
	delete kv;
}

static void loop_mod_folder(const char[] type, ArrayList arr, char[] mod_dir_path, char[] mod_file_path)
{
	BuildPath(Path_SM, mod_dir_path, PLATFORM_MAX_PATH, "configs/pop_mods/%s", type);
	DirectoryListing dir_it = OpenDirectory(mod_dir_path, true);
	if(dir_it != null) {
		FileType filetype;
		while(dir_it.GetNext(mod_file_path, PLATFORM_MAX_PATH, filetype)) {
			if(filetype != FileType_File) {
				continue;
			}

			int mod = StrContains(mod_file_path, ".mod");
			if(mod == -1) {
				continue;
			}

			if((strlen(mod_file_path)-mod) != 4) {
				continue;
			}

			Format(mod_file_path, PLATFORM_MAX_PATH, "%s/%s", mod_dir_path, mod_file_path);

			parse_mod(mod_file_path, arr);
		}
	}
	delete dir_it;
}

static void free_mods(ArrayList arr, ModInfo mod)
{
	int num_mods = arr.Length;
	for(int j = 0; j < num_mods; ++j) {
		arr.GetArray(j, mod, sizeof(ModInfo));
		delete mod.data;
	}

	arr.Clear();
}

public Action pop_parse(KeyValues data, bool &result)
{
	ModInfo mod;

	free_mods(manager_mods, mod);
	free_mods(wave_mods, mod);
	free_mods(wavespawn_mods, mod);

	char mod_file_path[PLATFORM_MAX_PATH];
	char mod_dir_path[PLATFORM_MAX_PATH];

	loop_mod_folder("wave", wave_mods, mod_dir_path, mod_file_path);
	loop_mod_folder("wavespawn", wavespawn_mods, mod_dir_path, mod_file_path);
	loop_mod_folder("manager", manager_mods, mod_dir_path, mod_file_path);

	int num_manager_mods = manager_mods.Length;

	for(int i = 0; i < num_manager_mods; ++i) {
		manager_mods.GetArray(i, mod, sizeof(ModInfo));

		if(!merge_pop(mod.data)) {
			result = false;
			return Plugin_Stop;
		}
	}

	int num_wave_mods = wave_mods.Length;
	int num_wavespawn_mods = wavespawn_mods.Length;

	char tmp_sec_name[64];

	int num_waves = wave_count();
	for(int i = 0; i < num_waves; ++i) {
		CWave wave = get_wave(i);

		float percent = (float(i+1) / float(num_waves));

		for(int j = 0; j < num_wave_mods; ++j) {
			wave_mods.GetArray(j, mod, sizeof(ModInfo));

			if(percent >= mod.min && percent <= mod.max) {
				switch(mod.type) {
					case mod_merge: {
						if(!wave.ParseAdditive(mod.data)) {
							result = false;
							return Plugin_Stop;
						}
					}
					case mod_merge_parent, mod_merge_root: {
						if(!merge_pop(mod.data)) {
							result = false;
							return Plugin_Stop;
						}
					}
				}
			}
		}

		int num_wavespawns = wave.WaveSpawnCount;
		for(int k = 0; k < num_wavespawns; ++k) {
			CWaveSpawnPopulator wavespawn = wave.GetWaveSpawn(k);

			for(int j = 0; j < num_wavespawn_mods; ++j) {
				wavespawn_mods.GetArray(j, mod, sizeof(ModInfo));

				if(percent >= mod.min && percent <= mod.max) {
					KeyValues mod_data;
					bool mod_data_allocated;

					if(mod.type == mod_merge_parent) {
						mod_data = new KeyValues("Population");
						mod_data_allocated = true;
						mod_data.Import(mod.data);

						if(mod_data.GotoFirstSubKey()) {
							do {
								mod_data.GetSectionName(tmp_sec_name, sizeof(tmp_sec_name));

								if(StrEqual(tmp_sec_name, "WaveSpawn")) {
									if(!mod_data.JumpToKey("WaitForAllSpawned")) {
										wavespawn.GetWaitForAllSpawned(tmp_sec_name, sizeof(tmp_sec_name));
										mod_data.SetString("WaitForAllSpawned", tmp_sec_name);
									} else {
										mod_data.GoBack();
									}

									if(!mod_data.JumpToKey("WaitForAllDead")) {
										wavespawn.GetWaitForAllSpawned(tmp_sec_name, sizeof(tmp_sec_name));
										mod_data.SetString("WaitForAllDead", tmp_sec_name);
									} else {
										mod_data.GoBack();
									}

									if(!mod_data.JumpToKey("WaitBetweenSpawns")) {
										mod_data.SetFloat("WaitBetweenSpawns", wavespawn.WaitBetweenSpawns);
									} else {
										mod_data.GoBack();
									}

									if(!mod_data.JumpToKey("WaitBeforeStarting")) {
										mod_data.SetFloat("WaitBeforeStarting", wavespawn.WaitBeforeStarting);
									} else {
										mod_data.GoBack();
									}
								}
							} while(mod_data.GotoNextKey());
							mod_data.GoBack();
						}
					} else {
						mod_data = mod.data;
					}

					switch(mod.type) {
						case mod_merge: {
							if(!wavespawn.ParseAdditive(mod_data)) {
								if(mod_data_allocated) {
									delete mod_data;
								}
								result = false;
								return Plugin_Stop;
							}
						}
						case mod_merge_parent: {
							if(!wave.ParseAdditive(mod_data)) {
								if(mod_data_allocated) {
									delete mod_data;
								}
								result = false;
								return Plugin_Stop;
							}
						}
						case mod_merge_root: {
							if(!merge_pop(mod_data)) {
								if(mod_data_allocated) {
									delete mod_data;
								}
								result = false;
								return Plugin_Stop;
							}
						}
					}

					if(mod_data_allocated) {
						delete mod_data;
					}
				}
			}
		}
	}

	return Plugin_Continue;
}
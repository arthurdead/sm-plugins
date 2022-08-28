#include <sourcemod>
#include <popspawner>
#include <sdktools>

enum struct SoundInfo
{
	char path[PLATFORM_MAX_PATH];
	bool is_script;
}

static ArrayList soundinfos[3];

public void OnPluginStart()
{
	soundinfos[0] = new ArrayList(sizeof(SoundInfo));
	soundinfos[1] = new ArrayList(sizeof(SoundInfo));
	soundinfos[2] = new ArrayList(sizeof(SoundInfo));
}

public void pop_event_fired(const char[] name)
{
	int type = -1;

	if(StrEqual(name, "StartWaveOutput")) {
		type = 0;
	} else if(StrEqual(name, "DoneOutput")) {
		type = 1;
	} else if(StrEqual(name, "InitWaveOutput")) {
		type = 2;
	}

	if(type == -1) {
		return
	}

	ArrayList which = soundinfos[type];

	int len = which.Length;
	if(len == 0) {
		return;
	}

	int idx = GetURandomInt() % len;

	SoundInfo info;
	which.GetArray(idx, info, sizeof(SoundInfo));

	if(info.is_script) {
		EmitGameSoundToAll(info.path);
	} else {
		EmitSoundToAll(info.path);
	}
}

public Action wave_parse(CWave populator, KeyValues data, bool &result)
{
	//TODO!!! support per-wave sounds

	return Plugin_Continue;
}

static void parse_sound_section(KeyValues data, ArrayList which, SoundInfo info)
{
	if(data.GotoFirstSubKey()) {
		do {
			data.GetString("sample", info.path, PLATFORM_MAX_PATH);
			info.is_script = false;
			if(info.path[0] == '\0') {
				data.GetString("script", info.path, PLATFORM_MAX_PATH);
				info.is_script = true;
			}

			which.PushArray(info, sizeof(SoundInfo));
		} while(data.GotoNextKey());
		data.GoBack();
	}
}

public Action pop_parse(KeyValues data, bool &result)
{
	for(int i = 0; i < 3; ++i) {
		soundinfos[i].Clear();
	}

	SoundInfo info;

	if(data.JumpToKey("WaveStartSound")) {
		parse_sound_section(data, soundinfos[0], info);
		data.GoBack();
	}

	if(data.JumpToKey("WaveEndSound")) {
		parse_sound_section(data, soundinfos[1], info);
		data.GoBack();
	}

	if(data.JumpToKey("IntermissionStartSound")) {
		parse_sound_section(data, soundinfos[2], info);
		data.GoBack();
	}

	for(int i = 0; i < 3; ++i) {
		int len = soundinfos[i].Length;
		for(int j = 0; j < len; ++j) {
			soundinfos[i].GetArray(j, info, sizeof(SoundInfo));
			if(info.is_script) {
				PrecacheScriptSound(info.path);
			} else {
				PrecacheSound(info.path);
			}
		}
	}

	return Plugin_Continue;
}
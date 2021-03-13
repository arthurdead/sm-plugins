#include <sourcemod>

Handle hud = null;
Handle hud_timer[MAXPLAYERS+1] = {null, ...};

ConVar hudnotifyfix_max_icon = null;
ConVar hudnotifyfix_max_text = null;
ConVar hudnotifyfix_duration = null;
ConVar hudnotifyfix_mode = null;

void on_mode_change(ConVar convar, const char[] oldValue, const char[] newValue)
{
	int value = StringToInt(newValue);

	if(value == 1) {
		hud = CreateHudSynchronizer();
	} else {
		delete hud;

		for(int i = 1; i <= MaxClients; ++i) {
			delete hud_timer[i];
		}
	}
}

public void OnPluginStart()
{
	hudnotifyfix_max_text = CreateConVar("hudnotifyfix_max_text", "255");
	hudnotifyfix_max_icon = CreateConVar("hudnotifyfix_max_icon", "32");
	hudnotifyfix_duration = CreateConVar("hudnotifyfix_duration", "3");
	hudnotifyfix_mode = CreateConVar("hudnotifyfix_mode", "1", "0 == disable, 1 == hud, 2 == chat");

	hudnotifyfix_mode.AddChangeHook(on_mode_change);

	HookUserMessage(GetUserMessageId("HudNotifyCustom"), HudNotifyCustom);
}

public void OnConfigsExecuted()
{
	if(hudnotifyfix_mode.IntValue == 1) {
		hud = CreateHudSynchronizer();
	}
}

public void OnClientDisconnect(int client)
{
	delete hud_timer[client];
}

Action Timer_RemoveHud(Handle timer, int client)
{
	client = GetClientOfUserId(client);
	if(client != -1) {
		ClearSyncHud(client, hud);
		hud_timer[client] = null;
	}
	return Plugin_Continue;
}

void PrintHudNotifyCustom(int client, float duration, DataPack data)
{
	data.Reset();

	int textlen = data.ReadCell();
	char[] text = new char[textlen];
	data.ReadString(text, textlen);

	int iconlen = data.ReadCell();
	char[] icon = new char[iconlen];
	data.ReadString(icon, iconlen);

	int team = data.ReadCell();

	delete data;

	if(hudnotifyfix_mode.IntValue == 1) {
		if(hud == null) {
			hud = CreateHudSynchronizer();
		}

		int r = 255;
		int g = 255;
		int b = 255;

		switch(team) {
			case 2: {
				g = 0;
				b = 0;
			}
			case 3: {
				r = 0;
				g = 0;
			}
			case 1: {
				r = 150;
				g = 150;
				b = 150;
			}
		}

		float x = (0.5 - ((textlen / 2) * 0.01)) + 0.04;

		ClearSyncHud(client, hud);
		SetHudTextParams(x, 0.64, duration, r, g, b, 255);
		ShowSyncHudText(client, hud, "%s", text);

		if(hud_timer[client] != null) {
			KillTimer(hud_timer[client]);
		}
		hud_timer[client] = CreateTimer(duration, Timer_RemoveHud, GetClientUserId(client));
	} else if(hudnotifyfix_mode.IntValue == 2) {
		char code[20];

		switch(team) {
			case 0: { strcopy(code, sizeof(code), "\x1\aFFFFFF"); }
			case 1: { strcopy(code, sizeof(code), "\x1\a717171"); }
			case 2: { strcopy(code, sizeof(code), "\x1\aFF0000"); }
			case 3: { strcopy(code, sizeof(code), "\x1\a0000FF"); }
		}

		PrintToChat(client, "%s[HudNotify] \x01%s", code, text);
	}
}

void tf_hud_notification_duration(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, DataPack data)
{
	--data.Position;
	int value = data.ReadCell();

	float duration = StringToFloat(cvarValue);
	if(value == 1 || duration <= 0) {
		if(duration <= 0) {
			duration = hudnotifyfix_duration.FloatValue;
		}
		PrintHudNotifyCustom(client, duration, data);
	}
}

void cl_hud_minmode(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, DataPack data)
{
	int value = StringToInt(cvarValue);
	data.WriteCell(value);

	QueryClientConVar(client, "tf_hud_notification_duration", tf_hud_notification_duration, data);
}

Action HudNotifyCustom(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if(hudnotifyfix_mode.IntValue == 0) {
		return Plugin_Continue;
	}

	for(int i = 0; i < playersNum; ++i) {
		DataPack data = new DataPack();

		int len = hudnotifyfix_max_text.IntValue;

		char[] text = new char[len];
		len = msg.ReadString(text, len);
		data.WriteCell(len);
		data.WriteString(text);

		len = hudnotifyfix_max_icon.IntValue;

		char[] icon = new char[len];
		len = msg.ReadString(icon, len);
		data.WriteCell(len);
		data.WriteString(icon);

		data.WriteCell(msg.ReadByte());

		QueryClientConVar(players[i], "cl_hud_minmode", cl_hud_minmode, data);
	}

	return Plugin_Continue;
}
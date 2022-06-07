#include <sourcemod>

Handle hud;
Handle hud_timer[MAXPLAYERS+1];

//ConVar hudnotifyfix_max_icon;
ConVar hudnotifyfix_max_text;
ConVar hudnotifyfix_duration;
ConVar hudnotifyfix_mode;

bool cl_hud_minmode[MAXPLAYERS+1];
float tf_hud_notification_duration[MAXPLAYERS+1] = {3.0, ...};

static void on_mode_change(ConVar convar, const char[] oldValue, const char[] newValue)
{
	int value = StringToInt(newValue);

	if(value == 1) {
		if(hud == null) {
			hud = CreateHudSynchronizer();
		}
	} else {
		delete hud;

		for(int i = 1; i <= MaxClients; ++i) {
			if(hud_timer[i] != null) {
				KillTimer(hud_timer[i]);
				hud_timer[i] = null;
			}
		}
	}
}

public void OnPluginStart()
{
	hudnotifyfix_max_text = CreateConVar("hudnotifyfix_max_text", "255");
	//hudnotifyfix_max_icon = CreateConVar("hudnotifyfix_max_icon", "32");
	hudnotifyfix_duration = CreateConVar("hudnotifyfix_duration", "3.0");
	hudnotifyfix_mode = CreateConVar("hudnotifyfix_mode", "1", "0 == disable, 1 == hud, 2 == chat, 3 == hint, 4 == center");

	hudnotifyfix_mode.AddChangeHook(on_mode_change);

	HookUserMessage(GetUserMessageId("HudNotifyCustom"), HudNotifyCustom);

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnConfigsExecuted()
{
	if(hudnotifyfix_mode.IntValue == 1) {
		if(hud == null) {
			hud = CreateHudSynchronizer();
		}
	}
}

public void OnClientPutInServer(int client)
{
	if(!IsFakeClient(client)) {
		QueryClientConVar(client, "tf_hud_notification_duration", tf_hud_notification_duration_query);
		QueryClientConVar(client, "cl_hud_minmode", cl_hud_minmode_query);
	}
}

public void OnClientDisconnect(int client)
{
	cl_hud_minmode[client] = false;
	tf_hud_notification_duration[client] = 3.0;
	if(hud_timer[client] != null) {
		KillTimer(hud_timer[client]);
		hud_timer[client] = null;
	}
}

static Action Timer_RemoveHud(Handle timer, int client)
{
	client = GetClientOfUserId(client);
	if(client != 0) {
		ClearSyncHud(client, hud);
		hud_timer[client] = null;
	}
	return Plugin_Continue;
}

static void tf_hud_notification_duration_query(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any data)
{
	if(result == ConVarQuery_Okay) {
		float value = StringToFloat(cvarValue);
		tf_hud_notification_duration[client] = value;
	}
}

static void cl_hud_minmode_query(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any data)
{
	if(result == ConVarQuery_Okay) {
		int value = StringToInt(cvarValue);
		cl_hud_minmode[client] = view_as<bool>(value);
	}
}

static Action Timer_HudNotifyCustom(Handle timer, DataPack data)
{
	data.Reset();

	int client = data.ReadCell();
	client = GetClientOfUserId(client);
	if(client == 0) {
		return Plugin_Continue;
	}

	int textlen = data.ReadCell();
	char[] text = new char[textlen];
	data.ReadString(text, textlen);

	/*int iconlen = data.ReadCell();
	char[] icon = new char[iconlen];
	data.ReadString(icon, iconlen);*/

	int team = data.ReadCell();

	int mode = hudnotifyfix_mode.IntValue;
	switch(mode) {
		case 1: {
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

			float duration = tf_hud_notification_duration[client];
			if(duration <= 0) {
				duration = hudnotifyfix_duration.FloatValue;
			}

			ClearSyncHud(client, hud);
			SetHudTextParams(x, 0.64, duration, r, g, b, 255);
			ShowSyncHudText(client, hud, "%s", text);

			if(hud_timer[client] != null) {
				KillTimer(hud_timer[client]);
			}
			hud_timer[client] = CreateTimer(duration, Timer_RemoveHud, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		}
		case 2: {
			char code[20];

			switch(team) {
				case 0: { strcopy(code, sizeof(code), "\x1\aFFFFFF"); }
				case 1: { strcopy(code, sizeof(code), "\x1\a717171"); }
				case 2: { strcopy(code, sizeof(code), "\x1\aFF0000"); }
				case 3: { strcopy(code, sizeof(code), "\x1\a0000FF"); }
			}

			PrintToChat(client, "%s[HudNotify] \x01%s", code, text);
		}
		case 3: {
			PrintHintText(client, "%s", text);
		}
		case 4: {
			PrintCenterText(client, "%s", text);
		}
	}

	return Plugin_Handled;
}

static Action HudNotifyCustom(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if(hudnotifyfix_mode.IntValue == 0) {
		return Plugin_Continue;
	}

	for(int i = 0; i < playersNum; ++i) {
		int client = players[i];

		if(!cl_hud_minmode[client] && tf_hud_notification_duration[client] > 0) {
			continue;
		}

		DataPack data;
		CreateDataTimer(0.1, Timer_HudNotifyCustom, data, TIMER_FLAG_NO_MAPCHANGE);

		data.WriteCell(GetClientUserId(client));

		int textlen = hudnotifyfix_max_text.IntValue;
		char[] text = new char[textlen];
		textlen = msg.ReadString(text, textlen)+1;
		data.WriteCell(textlen);
		data.WriteString(text);

		/*int iconlen = hudnotifyfix_max_icon.IntValue;
		char[] icon = new char[iconlen];
		iconlen = msg.ReadString(icon, iconlen)+1;
		data.WriteCell(iconlen);
		data.WriteString(icon);*/

		int team = msg.ReadByte();
		data.WriteCell(team);
	}

	return Plugin_Continue;
}

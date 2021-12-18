#define MISSI_DESC_FORMATED_MAX (MAX_MISSION_DESCRIPTION+(INT_STR_MAX*MAX_MISSION_PARAMS))
#define MISSI_TITLE_MAX (MAX_MISSION_NAME+2)

Action sm_missigiv(int client, int args)
{
	if(args < 2) {
		ReplyToCommand(client, "[SM] Usage: sm_missigiv <filter> <name>");
		return Plugin_Handled;
	}

	char missiname[MAX_MISSION_NAME];
	GetCmdArg(2, missiname, MAX_MISSION_NAME);

	MissionEntry missi = MissionEntry.FindByName(missiname);
	if(missi == MissionEntry_Null) {
		ReplyToCommand(client, "[SM] Invalid missi: %s", missiname);
		return Plugin_Handled;
	}

	char plrname[MAX_NAME_LENGTH];
	GetCmdArg(1, plrname, MAX_NAME_LENGTH);

	int targets[MAXPLAYERS];
	int count = ProcessTargetString(plrname, client, targets, MAXPLAYERS, COMMAND_FILTER_ALIVE|COMMAND_FILTER_NO_IMMUNITY, __ignorename, 1, __ignoreisml);
	if(count <= 0) {
		ReplyToTargetError(client, count);
		return Plugin_Handled;
	}

	for(int i = 0; i < count; i++) {
		int target = targets[i];
		
		missi.Give(target);
	}

	return Plugin_Handled;
}

int MenuHandler_MissiInfo(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		switch(param2) {
			case 8:
			{ DisplayMissiMenu(param1); }
			case 7: {
				
			}
		}
	}

	return 0;
}

void format_missi_desc(int client, int pidx, int midx, char[] desc, int size)
{
	missi_cache.GetDesc(-1, desc, size, midx);

	char param[1+INT_STR_MAX];
	int value_len = 7;
	char[] value_str = new char[value_len];

	for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {
		int value = PlayerMissiCache[client].GetParamValue(-1, i, pidx);

		MissionParamType type;
		int min;
		int max;
		missi_cache.GetParamInfo(-1, i, type, min, max, midx);

		switch(type) {
			case MPARAM_INT:
			{ IntToString(value, value_str, value_len); }
			case MPARAM_CLASS: {
				TFClassType class = view_as<TFClassType>(value);
				switch(class) {
					case TFClass_Scout:
					{ strcopy(value_str, value_len, "scout"); }
					case TFClass_Sniper:
					{ strcopy(value_str, value_len, "sniper"); }
					case TFClass_Soldier:
					{ strcopy(value_str, value_len, "soldier"); }
					case TFClass_DemoMan:
					{ strcopy(value_str, value_len, "demoman"); }
					case TFClass_Medic:
					{ strcopy(value_str, value_len, "medic"); }
					case TFClass_Heavy:
					{ strcopy(value_str, value_len, "heavy"); }
					case TFClass_Pyro:
					{ strcopy(value_str, value_len, "pyro"); }
					case TFClass_Spy:
					{ strcopy(value_str, value_len, "spy"); }
					case TFClass_Engineer:
					{ strcopy(value_str, value_len, "engineer"); }
				}
			}
		}

		Format(param, sizeof(param), "$%i", i+1);
		ReplaceString(desc, size, param, value_str);
	}
}

int MenuHandler_Missi(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		char num[5];
		menu.GetItem(param2, num, sizeof(num));

		int idx = StringToInt(num);
		int mission_id = PlayerMissiCache[param1].GetMissionID(-1, idx);

		int midx = missi_cache.Find(mission_id);

		char title[MISSI_TITLE_MAX];
		missi_cache.GetName(mission_id, title, MISSI_TITLE_MAX, midx);

		if(PlayerMissiCache[param1].IsCompleted(-1, idx)) {
			StrCat(title, MISSI_TITLE_MAX, " *");
		}

		char desc[MISSI_DESC_FORMATED_MAX];
		format_missi_desc(param1, idx, midx, desc, MISSI_DESC_FORMATED_MAX);

		Panel info = new Panel();
		info.SetTitle(title);
		info.DrawText(desc);
		info.DrawItem("", ITEMDRAW_SPACER);
		info.CurrentKey = 7;
		info.DrawItem("cancel", ITEMDRAW_DISABLED);
		info.CurrentKey = 8;
		info.DrawItem("Back", ITEMDRAW_CONTROL);
		info.DrawItem("", ITEMDRAW_SPACER);
		info.CurrentKey = 10;
		info.DrawItem("Exit", ITEMDRAW_CONTROL);
		info.Send(param1, MenuHandler_MissiInfo, MENU_TIME_FOREVER);
	} else if(action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

void DisplayMissiMenu(int client, int item = -1)
{
	if(PlayerMissiCache[client] == null) {
		return;
	}

	Menu menu = new Menu(MenuHandler_Missi);
	menu.SetTitle("Missions");

	char desc[MISSI_DESC_FORMATED_MAX];
	char num[INT_STR_MAX];

	int len = PlayerMissiCache[client].Length;
	for(int i = 0; i < len; ++i) {
		int mission_id = PlayerMissiCache[client].GetMissionID(-1, i);

		int midx = missi_cache.Find(mission_id);

		format_missi_desc(client, i, midx, desc, MISSI_DESC_FORMATED_MAX);

		if(PlayerMissiCache[client].IsCompleted(-1, i)) {
			StrCat(desc, sizeof(desc), " *");
		}

		IntToString(i, num, sizeof(num));
		menu.AddItem(num, desc);
	}

	if(item == -1) {
		menu.Display(client, MENU_TIME_FOREVER);
	} else {
		menu.DisplayAt(client, item, MENU_TIME_FOREVER);
	}
}

Action sm_missions(int client, int args)
{
	DisplayMissiMenu(client);

	return Plugin_Handled;
}
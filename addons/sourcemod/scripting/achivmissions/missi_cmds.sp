Action sm_missigiv(int client, int args)
{
	if(args < 2) {
		ReplyToCommand(client, "[SM] Usage: sm_missigiv <filter> <name>");
		return Plugin_Handled;
	}

	char missiname[MAX_MISSION_NAME];
	GetCmdArg(2, missiname, sizeof(missiname));

	MissionEntry missi = MissionEntry.FindByName(missiname);
	if(missi == MissionEntry_Null) {
		ReplyToCommand(client, "[SM] Invalid missi: %s", missiname);
		return Plugin_Handled;
	}

	char filter[32];
	GetCmdArg(1, filter, sizeof(filter));

	char name[MAX_TARGET_LENGTH];
	int targets[MAXPLAYERS];
	bool isml = false;
	int count = ProcessTargetString(filter, client, targets, MAXPLAYERS, COMMAND_FILTER_ALIVE|COMMAND_FILTER_NO_IMMUNITY, name, sizeof(name), isml);
	if(count == 0) {
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

int MenuHandler_Missi(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		char num[5];
		menu.GetItem(param2, num, sizeof(num));

		int idx = StringToInt(num);
		int mission_id = PlayerMissiCache[param1].GetMissionID(-1, idx);

		int midx = missi_cache.Find(mission_id);

		char title[MAX_MISSION_NAME + 10];
		missi_cache.GetName(mission_id, title, sizeof(title), midx);

		if(PlayerMissiCache[param1].IsCompleted(-1, idx)) {
			StrCat(title, sizeof(title), " *");
		}

		char desc[MAX_MISSION_DESCRIPTION];
		missi_cache.GetDesc(mission_id, desc, sizeof(desc), midx);

		for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {
			int value = PlayerMissiCache[param1].GetParamValue(-1, i, idx);

			MissionParamType type;
			int min;
			int max;
			missi_cache.GetParamInfo(mission_id, i, type, min, max, midx);

			char tmpnum[10];
			switch(type) {
				case MPARAM_INT:
				{ IntToString(value, tmpnum, sizeof(tmpnum)); }
				case MPARAM_CLASS: {
					switch(value) {
						case 1:
						{ strcopy(tmpnum, sizeof(tmpnum), "scout"); }
						case 2:
						{ strcopy(tmpnum, sizeof(tmpnum), "sniper"); }
						case 3:
						{ strcopy(tmpnum, sizeof(tmpnum), "soldier"); }
						case 4:
						{ strcopy(tmpnum, sizeof(tmpnum), "demoman"); }
						case 5:
						{ strcopy(tmpnum, sizeof(tmpnum), "medic"); }
						case 6:
						{ strcopy(tmpnum, sizeof(tmpnum), "heavy"); }
						case 7:
						{ strcopy(tmpnum, sizeof(tmpnum), "pyro"); }
						case 8:
						{ strcopy(tmpnum, sizeof(tmpnum), "spy"); }
						case 9:
						{ strcopy(tmpnum, sizeof(tmpnum), "engineer"); }
					}
				}
			}

			Format(num, sizeof(num), "$%i", i+1);
			ReplaceString(desc, sizeof(desc), num, tmpnum);
		}

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
	Menu menu = new Menu(MenuHandler_Missi);
	menu.SetTitle("Missions");

	char num[5];
	char name[MAX_MISSION_NAME + 4];

	int len = PlayerMissiCache[client].Length;
	for(int i = 0; i < len; ++i) {
		int mission_id = PlayerMissiCache[client].GetMissionID(-1, i);

		missi_cache.GetName(mission_id, name, sizeof(name));

		if(PlayerMissiCache[client].IsCompleted(-1, i)) {
			StrCat(name, sizeof(name), " *");
		}

		IntToString(i, num, sizeof(num));
		menu.AddItem(num, name);
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
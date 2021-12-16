Action sm_achivgiv(int client, int args)
{
	if(args < 2) {
		ReplyToCommand(client, "[SM] Usage: sm_achivgiv <filter> <name>");
		return Plugin_Handled;
	}

	char achivname[MAX_ACHIEVEMENT_NAME];
	GetCmdArg(2, achivname, sizeof(achivname));

	Achievement achiv = Achievement.FindByName(achivname);
	if(achiv == Achievement_Null) {
		ReplyToCommand(client, "[SM] Invalid achiv: %s", achivname);
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
		
		achiv.Award(target);
	}

	return Plugin_Handled;
}

Action sm_achivrem(int client, int args)
{
	if(args < 2) {
		ReplyToCommand(client, "[SM] Usage: sm_achivrem <filter> <name>");
		return Plugin_Handled;
	}

	char achivname[MAX_ACHIEVEMENT_NAME];
	GetCmdArg(2, achivname, sizeof(achivname));

	Achievement achiv = Achievement.FindByName(achivname);
	if(achiv == Achievement_Null) {
		ReplyToCommand(client, "[SM] Invalid achiv: %s", achivname);
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
		
		achiv.Remove(target);
	}

	return Plugin_Handled;
}

Action sm_achivprog(int client, int args)
{
	if(args < 3) {
		ReplyToCommand(client, "[SM] Usage: sm_achivprog <filter> <name> <prog>");
		return Plugin_Handled;
	}

	char achivname[MAX_ACHIEVEMENT_NAME];
	GetCmdArg(2, achivname, sizeof(achivname));

	Achievement achiv = Achievement.FindByName(achivname);
	if(achiv == Achievement_Null) {
		ReplyToCommand(client, "[SM] Invalid achiv: %s", achivname);
		return Plugin_Handled;
	}

	char filter[32];
	GetCmdArg(1, filter, sizeof(filter));

	int prog = GetCmdArgInt(3);

	char name[MAX_TARGET_LENGTH];
	int targets[MAXPLAYERS];
	bool isml = false;
	int count = ProcessTargetString(filter, client, targets, MAXPLAYERS, COMMAND_FILTER_ALIVE|COMMAND_FILTER_NO_IMMUNITY, name, sizeof(name), isml);
	if(count == 0) {
		return Plugin_Handled;
	}

	for(int i = 0; i < count; i++) {
		int target = targets[i];
		
		achiv.AwardProgress(target, prog);
	}

	return Plugin_Handled;
}

Action sm_achivremprog(int client, int args)
{
	if(args < 3) {
		ReplyToCommand(client, "[SM] Usage: sm_achivremprog <filter> <name> <prog>");
		return Plugin_Handled;
	}

	char achivname[MAX_ACHIEVEMENT_NAME];
	GetCmdArg(2, achivname, sizeof(achivname));

	Achievement achiv = Achievement.FindByName(achivname);
	if(achiv == Achievement_Null) {
		ReplyToCommand(client, "[SM] Invalid achiv: %s", achivname);
		return Plugin_Handled;
	}

	char filter[32];
	GetCmdArg(1, filter, sizeof(filter));

	int prog = GetCmdArgInt(3);

	char name[MAX_TARGET_LENGTH];
	int targets[MAXPLAYERS];
	bool isml = false;
	int count = ProcessTargetString(filter, client, targets, MAXPLAYERS, COMMAND_FILTER_ALIVE|COMMAND_FILTER_NO_IMMUNITY, name, sizeof(name), isml);
	if(count == 0) {
		return Plugin_Handled;
	}

	for(int i = 0; i < count; i++) {
		int target = targets[i];
		
		achiv.RemoveProgress(target, prog);
	}

	return Plugin_Handled;
}

int MenuHandler_AchivInfo(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		if(param2 == 8) {
			DisplayAchivMenu(param1);
		}
	}

	return 0;
}

int MenuHandler_Achiv(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select) {
		char num[5];
		menu.GetItem(param2, num, sizeof(num));

		int idx = StringToInt(num);
		int id = achiv_cache.GetID(idx);

		char title[MAX_ACHIEVEMENT_NAME + 10];
		achiv_cache.GetName(id, title, sizeof(title), idx);

		int max = achiv_cache.GetMax(id, idx);
		if(max > 0) {
			int progress = PlayerAchivCache[param1].GetProgress(id);
			Format(title, sizeof(title), "%s (%i/%i)", title, progress, max);
		}

		if(PlayerAchivCache[param1].HasAchieved(id)) {
			StrCat(title, sizeof(title), " *");
		}

		char desc[MAX_ACHIEVEMENT_DESCRIPTION];
		achiv_cache.GetDesc(id, desc, sizeof(desc), idx);

		Panel info = new Panel();
		info.SetTitle(title);
		info.DrawText(desc);
		info.DrawItem("", ITEMDRAW_SPACER);
		info.CurrentKey = 8;
		info.DrawItem("Back", ITEMDRAW_CONTROL);
		info.DrawItem("", ITEMDRAW_SPACER);
		info.CurrentKey = 10;
		info.DrawItem("Exit", ITEMDRAW_CONTROL);
		info.Send(param1, MenuHandler_AchivInfo, MENU_TIME_FOREVER);
	} else if(action == MenuAction_End) {
		delete menu;
	}
	
	return 0;
}

void DisplayAchivMenu(int client, int item = -1)
{
	Menu menu = new Menu(MenuHandler_Achiv);

	int num_player_achieved = PlayerAchivCache[client].Length;

	char title[64];
	Format(title, sizeof(title), "Achievements (%i/%i)", num_player_achieved, num_achivs);
	menu.SetTitle(title);

	char num[5];
	char name[MAX_ACHIEVEMENT_NAME + 4];
	for(int i = 0; i < num_achivs; ++i) {
		int id = achiv_cache.GetID(i);

		bool achieved = PlayerAchivCache[client].HasAchieved(id);
		if(!achieved && achiv_cache.IsHidden(id, i)) {
			continue;
		}

		achiv_cache.GetName(id, name, sizeof(name), i);

		if(achieved) {
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

Action sm_achievements(int client, int args)
{
	DisplayAchivMenu(client);

	return Plugin_Handled;
}
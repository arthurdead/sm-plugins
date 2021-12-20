#define ACHIV_INFO_TITLE_MAX (MAX_ACHIEVEMENT_NAME+8+(INT_STR_MAX*2))
#define ACHIV_DISPLAY_MAX (MAX_ACHIEVEMENT_NAME+4)
#define ACHIVS_TITLE_MAX (16+(INT_STR_MAX*2))

Action sm_achivgiv(int client, int args)
{
	if(args < 2) {
		ReplyToCommand(client, "[SM] Usage: sm_achivgiv <filter> <name>");
		return Plugin_Handled;
	}

	char achivname[MAX_ACHIEVEMENT_NAME];
	GetCmdArg(2, achivname, MAX_ACHIEVEMENT_NAME);

	Achievement achiv = Achievement.FindByName(achivname);
	if(achiv == Achievement_Null) {
		ReplyToCommand(client, "[SM] Invalid achiv: %s", achivname);
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
	GetCmdArg(2, achivname, MAX_ACHIEVEMENT_NAME);

	Achievement achiv = Achievement.FindByName(achivname);
	if(achiv == Achievement_Null) {
		ReplyToCommand(client, "[SM] Invalid achiv: %s", achivname);
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
	GetCmdArg(2, achivname, MAX_ACHIEVEMENT_NAME);

	Achievement achiv = Achievement.FindByName(achivname);
	if(achiv == Achievement_Null) {
		ReplyToCommand(client, "[SM] Invalid achiv: %s", achivname);
		return Plugin_Handled;
	}

	char plrname[MAX_NAME_LENGTH];
	GetCmdArg(1, plrname, MAX_NAME_LENGTH);

	int prog = GetCmdArgInt(3);

	int targets[MAXPLAYERS];
	int count = ProcessTargetString(plrname, client, targets, MAXPLAYERS, COMMAND_FILTER_ALIVE|COMMAND_FILTER_NO_IMMUNITY, __ignorename, 1, __ignoreisml);
	if(count <= 0) {
		ReplyToTargetError(client, count);
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
	GetCmdArg(2, achivname, MAX_ACHIEVEMENT_NAME);

	Achievement achiv = Achievement.FindByName(achivname);
	if(achiv == Achievement_Null) {
		ReplyToCommand(client, "[SM] Invalid achiv: %s", achivname);
		return Plugin_Handled;
	}

	char plrname[MAX_NAME_LENGTH];
	GetCmdArg(1, plrname, MAX_NAME_LENGTH);

	int prog = GetCmdArgInt(3);

	int targets[MAXPLAYERS];
	int count = ProcessTargetString(plrname, client, targets, MAXPLAYERS, COMMAND_FILTER_ALIVE|COMMAND_FILTER_NO_IMMUNITY, __ignorename, 1, __ignoreisml);
	if(count <= 0) {
		ReplyToTargetError(client, count);
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
		char num[INT_STR_MAX];
		menu.GetItem(param2, num, INT_STR_MAX);

		int idx = StringToInt(num);
		int id = achiv_cache.GetID(idx);

		char achivtitle[ACHIV_INFO_TITLE_MAX];
		achiv_cache.GetName(id, achivtitle, ACHIV_INFO_TITLE_MAX, idx);

		bool achieved = PlayerAchivCache[param1].HasAchieved(id);

		int max = achiv_cache.GetMax(id, idx);
		if(max > 0) {
			int progress = achieved ? max : PlayerAchivCache[param1].GetProgress(id);
			Format(achivtitle, ACHIV_INFO_TITLE_MAX, "%s (%i/%i)", achivtitle, progress, max);
		}

		if(achieved) {
			StrCat(achivtitle, ACHIV_INFO_TITLE_MAX, " *");
		}

		if(achiv_cache.IsHidden(id, idx)) {
			StrCat(achivtitle, ACHIV_INFO_TITLE_MAX, " $");
		}

		char achivdesc[MAX_ACHIEVEMENT_DESCRIPTION];
		achiv_cache.GetDesc(id, achivdesc, MAX_ACHIEVEMENT_DESCRIPTION, idx);

		Panel info = new Panel();
		info.SetTitle(achivtitle);
		info.DrawText(achivdesc);
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
	if(PlayerAchivCache[client] == null) {
		return;
	}

	Menu menu = new Menu(MenuHandler_Achiv);

	int num_player_achieved = PlayerAchivCache[client].Length;

	char achivstitle[ACHIVS_TITLE_MAX];
	Format(achivstitle, ACHIVS_TITLE_MAX, "Achievements (%i/%i)", num_player_achieved, num_achivs);
	menu.SetTitle(achivstitle);

	char achivdisplay[ACHIV_DISPLAY_MAX];
	char num[INT_STR_MAX];

	for(int i = 0; i < num_achivs; ++i) {
		int id = achiv_cache.GetID(i);

		bool achieved = PlayerAchivCache[client].HasAchieved(id);
		bool hidden = achiv_cache.IsHidden(id, i);

		if(!achieved && hidden) {
			strcopy(achivdisplay, ACHIV_DISPLAY_MAX, "????");
		} else {
			achiv_cache.GetName(id, achivdisplay, ACHIV_DISPLAY_MAX, i);
		}

		if(achieved) {
			StrCat(achivdisplay, ACHIV_DISPLAY_MAX, " *");
			if(hidden) {
				StrCat(achivdisplay, ACHIV_DISPLAY_MAX, " $");
			}
		}

		IntToString(i, num, INT_STR_MAX);
		menu.AddItem(num, achivdisplay, (!achieved && hidden) ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
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
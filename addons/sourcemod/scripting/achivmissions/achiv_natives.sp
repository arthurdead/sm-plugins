int NativeAchiv_Get(Handle plugin, int args)
{
	#pragma unused plugin,args

	int idx = GetNativeCell(1);

	if(idx >= achiv_cache.Length) {
		return -1;
	}

	int id = achiv_cache.GetID(idx);

	return id;
}

int NativeAchiv_FindByID(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);

	int idx = achiv_cache.Find(id);
	if(idx == -1) {
		return -1;
	}

	return id;
}

int NativeAchiv_GetCount(Handle plugin, int args)
{
	#pragma unused plugin,args

	return num_achivs;
}

int NativeAchiv_FindByName(Handle plugin, int args)
{
	#pragma unused plugin,args

	int len = 0;
	GetNativeStringLength(1, len);
	++len;
	
	char[] name = new char[len];
	GetNativeString(1, name, len);

	int id = -1;
	if(mapAchivIds.GetValue(name, id)) {
		return id;
	}

	return -1;
}

int NativeAchiv_GetName(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);
	int len = GetNativeCell(3);

	char[] name = new char[len];
	achiv_cache.GetName(id, name, len);

	SetNativeString(2, name, len);
	return 0;
}

int NativeAchiv_GetDesc(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);
	int len = GetNativeCell(3);

	char[] desc = new char[len];
	if(!achiv_cache.GetDesc(id, desc, len)) {
		return 0;
	}

	SetNativeString(2, desc, len);
	return 0;
}

int NativeAchiv_Remove(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);
	int client = GetNativeCell(2);

	int idx = PlayerAchivCache[client].Find(id);
	if(idx == -1) {
		return 0;
	}

	bool achieved = PlayerAchivCache[client].HasAchieved(id, idx);

	PlayerAchivCache[client].Erase(id, idx);

	if(achieved) {
		Call_StartForward(hOnAchievementStatusChanged);
		Call_PushCell(client);
		Call_PushCell(false);
		Call_PushCell(id);
		Call_Finish();
	}

	int accid = GetSteamAccountID(client);
	dbAchiv.Format(tmpquery, sizeof(tmpquery), "delete from achiv_player_data where id=%i and accountid=%i;",id,accid);
	dbAchiv.Query(OnErrorQuery, tmpquery);

	return 0;
}

int NativeAchiv_RemoveProgress(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);
	int client = GetNativeCell(2);
	int value = GetNativeCell(3);

	int idx = PlayerAchivCache[client].Find(id);
	if(idx == -1) {
		return 0;
	}

	int progress = PlayerAchivCache[client].GetProgress(id, idx);
	if(progress == 0) {
		return 0;
	}

	int oldprogress = progress;

	bool remove = false;

	progress -= value;
	if(progress <= 0) {
		progress = 0;
		remove = true;
	}

	Call_StartForward(hOnAchievementProgressChanged);
	Call_PushCell(client);
	Call_PushCell(oldprogress);
	Call_PushCell(progress);
	Call_PushCell(id);
	Call_Finish();

	PlayerAchivCache[client].SetProgress(id, progress, idx);

	int accid = GetSteamAccountID(client);

	if(remove) {
		dbAchiv.Format(tmpquery, sizeof(tmpquery), "delete from achiv_player_data where id=%i and accountid=%i;",id,accid);
		dbAchiv.Query(OnErrorQuery, tmpquery);
		PlayerAchivCache[client].Erase(id, idx);

		if(PlayerAchivCache[client].HasAchieved(id, idx)) {
			Call_StartForward(hOnAchievementStatusChanged);
			Call_PushCell(client);
			Call_PushCell(false);
			Call_PushCell(id);
			Call_Finish();
		}
	} else {
		dbAchiv.Format(tmpquery, sizeof(tmpquery), "update achiv_player_data set progress=%i where id=%i and accountid=%i;",progress,id,accid);
		dbAchiv.Query(OnErrorQuery, tmpquery);
	}

	return 0;
}

int NativeAchiv_AwardAchievement(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);
	int client = GetNativeCell(2);

	if(!PlayerAchivCache[client].HasAchieved(id)) {
		int accid = GetSteamAccountID(client);
		int time = GetTime();
		dbAchiv.Format(tmpquery, sizeof(tmpquery), "insert into achiv_player_data values(%i,%i,null,null,%i) on duplicate key update achieved=%i;",id,accid,time,time);
		dbAchiv.Query(OnErrorQuery, tmpquery);
		PlayerAchivCache[client].Push(id);
		AnnouceAchievement(client, id);

		Call_StartForward(hOnAchievementStatusChanged);
		Call_PushCell(client);
		Call_PushCell(true);
		Call_PushCell(id);
		Call_Finish();
	}

	return 0;
}

int NativeAchiv_AwardProgress(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);
	int client = GetNativeCell(2);
	int value = GetNativeCell(3);

	int aidx = achiv_cache.Find(id);
	if(aidx == -1) {
		return 0;
	}

	bool achieved = PlayerAchivCache[client].HasAchieved(id);
	if(achieved) {
		return 0;
	}

	int max = achiv_cache.GetMax(id, aidx);
	if(max == -1) {
		return 0;
	}

	int progress = 0;

	int pidx = PlayerAchivCache[client].Find(id);
	if(pidx == -1) {
		pidx = PlayerAchivCache[client].Push(id);
	} else {
		progress = PlayerAchivCache[client].GetProgress(id, pidx);
		if(progress >= max) {
			return 0;
		}
	}

	int oldprogress = progress;

	progress += value;
	if(progress >= max) {
		progress = max;
		achieved = true;
	}

	Call_StartForward(hOnAchievementProgressChanged);
	Call_PushCell(client);
	Call_PushCell(oldprogress);
	Call_PushCell(progress);
	Call_PushCell(id);
	Call_Finish();

	PlayerAchivCache[client].SetProgress(id, progress, pidx);

	int accid = GetSteamAccountID(client);
	if(achieved) {
		int time = GetTime();
		dbAchiv.Format(tmpquery, sizeof(tmpquery), "insert into achiv_player_data values(%i,%i,%i,null,%i) on duplicate key update progress=%i,achieved=%i;",id,accid,progress,time,progress,time);
		AnnouceAchievement(client, id, aidx);
		PlayerAchivCache[client].SetAchievedTime(id, time, pidx);
		Call_StartForward(hOnAchievementStatusChanged);
		Call_PushCell(client);
		Call_PushCell(true);
		Call_PushCell(id);
		Call_Finish();
	} else {
		dbAchiv.Format(tmpquery, sizeof(tmpquery), "insert into achiv_player_data values(%i,%i,%i,null,null) on duplicate key update progress=%i;",id,accid,progress,progress);
	}
	dbAchiv.Query(OnErrorQuery, tmpquery);

	return achieved;
}

int NativeAchiv_GetProgress(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);
	int client = GetNativeCell(2);

	int idx = PlayerAchivCache[client].Find(id);
	if(idx == -1) {
		return -1;
	}

	return PlayerAchivCache[client].GetProgress(id, idx);
}

int NativeAchiv_SetPluginData(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);
	int client = GetNativeCell(2);
	any value = GetNativeCell(3);

	int pidx = PlayerAchivCache[client].Find(id);
	if(pidx == -1) {
		pidx = PlayerAchivCache[client].Push(id);
	}

	PlayerAchivCache[client].SetPluginData(id, value, pidx);

	int accid = GetSteamAccountID(client);
	dbAchiv.Format(tmpquery, sizeof(tmpquery), "insert into achiv_player_data values(%i,%i,null,%i,null) on duplicate key update plugin_data=%i;",id,accid,value,value);
	dbAchiv.Query(OnErrorQuery, tmpquery);

	return 0;
}

int NativeAchiv_GetPluginData(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);
	int client = GetNativeCell(2);

	int idx = PlayerAchivCache[client].Find(id);
	if(idx == -1) {
		return -1;
	}

	return PlayerAchivCache[client].GetPluginData(id, idx);
}

int NativeAchiv_GetMax(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);
	
	int idx = achiv_cache.Find(id);
	if(idx == -1) {
		return -1;
	}

	return achiv_cache.GetMax(id, idx);
}

int NativeAchiv_HasAchieved(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);
	int client = GetNativeCell(2);

	return PlayerAchivCache[client].HasAchieved(id);
}

int NativeAchiv_GetID(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);

	return id;
}
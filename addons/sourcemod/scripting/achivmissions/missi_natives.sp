#define PARAM_NAME_MAX (6+INT_STR_MAX)

int NativeMissi_Get(Handle plugin, int args)
{
	int idx = GetNativeCell(1);

	if(missi_cache == null) {
		return -1;
	}

	if(idx >= missi_cache.Length) {
		return -1;
	}

	int id = missi_cache.GetID(idx);

	return id;
}

int NativeMissi_GetCount(Handle plugin, int args)
{
	return num_missis;
}

int NativeMissi_FindByName(Handle plugin, int args)
{
	if(mapMissiIds == null) {
		return -1;
	}

	int len = 0;
	GetNativeStringLength(1, len);
	char[] name = new char[++len];
	GetNativeString(1, name, len);

	int id = -1;
	if(mapMissiIds.GetValue(name, id)) {
		return id;
	}

	return -1;
}

int NativeMissi_FindByID(Handle plugin, int args)
{
	int id = GetNativeCell(1);

	if(missi_cache == null) {
		return -1;
	}

	int idx = missi_cache.Find(id);
	if(idx == -1) {
		return -1;
	}

	return id;
}

int NativeMissi_GetName(Handle plugin, int args)
{
	int id = GetNativeCell(1);
	int len = GetNativeCell(3);

	char[] name = new char[len];
	missi_cache.GetName(id, name, len);

	SetNativeString(2, name, len);
	return 0;
}

int NativeMissi_GetDesc(Handle plugin, int args)
{
	int id = GetNativeCell(1);
	int len = GetNativeCell(3);

	char[] desc = new char[len];
	if(!missi_cache.GetDesc(id, desc, len)) {
		return 0;
	}

	SetNativeString(2, desc, len);
	return 0;
}

int NativeMissi_GetID(Handle plugin, int args)
{
	int id = GetNativeCell(1);

	return id;
}

int NativeMissi_GetInstanceCache(Handle plugin, int args)
{
	int id = GetNativeCell(1);
	int client = GetNativeCell(2);

	if(missi_map == null) {
		return 0;
	}

	return view_as<int>(missi_map.Get(client, id));
}

int GenerateParamValue(int id, int i, int midx = -1)
{
	MissionParamType type;
	int min;
	int max;

	missi_cache.GetParamInfo(id, i, type, min, max, midx);

	int value = 0;

	switch(type) {
		case MPARAM_INT, MPARAM_CLASS: {
			if(min == max) {
				value = min;
			} else {
				value = GetRandomInt(min, max);
			}
		}
	}

	return value;
}

int NativeMissi_GiveToPlayerEx(Handle plugin, int args)
{
	int id = GetNativeCell(1);
	int client = GetNativeCell(2);

	int[] values = new int[MAX_MISSION_PARAMS];
	GetNativeArray(3, values, MAX_MISSION_PARAMS);

	int instid = -1;

	if(!IsFakeClient(client)) {
		int accid = GetSteamAccountID(client);

		char param_values[(1+INT_STR_MAX) * MAX_MISSION_PARAMS];
		char param_names[(1+PARAM_NAME_MAX) * MAX_MISSION_PARAMS];

		char param_value[INT_STR_MAX];
		char param_name[PARAM_NAME_MAX];

		for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {
			IntToString(values[i], param_value, INT_STR_MAX);
			StrCat(param_values, sizeof(param_values), ",");
			StrCat(param_values, sizeof(param_values), param_value);

			FormatEx(param_name, PARAM_NAME_MAX, "param_%i", i+1);
			StrCat(param_names, sizeof(param_names), ",");
			StrCat(param_names, sizeof(param_names), param_name);
		}

		char query[QUERY_STR_MAX];
		dbMissi.Format(query, QUERY_STR_MAX,
			"insert into missi_player_data " ...
			" (mission_id,accountid%s) " ...
			" values(%i,%i%s);"
			,param_names,
			id,accid,param_values
		);

		SQL_LockDatabase(dbMissi);
		SQL_FastQuery(dbMissi, query);
		DBResultSet results = SQL_Query(dbMissi,
			"select last_insert_id();"
		);
		SQL_UnlockDatabase(dbMissi);
		if(results.HasResults) {
			do {
				do {
					if(!results.FetchRow()) {
						continue;
					}

					instid = results.FetchInt(0);
				} while(results.MoreRows);
			} while(results.FetchMoreResults());
		}
		delete results;

		int pidx = GetOrCreatePlrMissiCache(client, instid);

		PlayerMissiCache[client].SetMissionID(instid, id, pidx);

		for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {
			PlayerMissiCache[client].SetParamValue(instid, i, values[i], pidx);
		}
	} else {
		static int fakeid = 0;
		instid = fakeid++;

		int pidx = GetOrCreatePlrMissiCache(client, instid);

		PlayerMissiCache[client].SetMissionID(instid, id, pidx);

		for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {
			PlayerMissiCache[client].SetParamValue(instid, i, values[i], pidx);
		}
	}

	missi_map.Add(client, id, instid);

	return instid;
}

int NativeMissi_GiveToPlayer(Handle plugin, int args)
{
	int id = GetNativeCell(1);
	int client = GetNativeCell(2);

	int midx = missi_cache.Find(id);

	int instid = -1;

	if(!IsFakeClient(client)) {
		int accid = GetSteamAccountID(client);

		char param_values[(1+INT_STR_MAX) * MAX_MISSION_PARAMS];
		char param_names[(1+PARAM_NAME_MAX) * MAX_MISSION_PARAMS];

		char param_value[INT_STR_MAX];
		char param_name[PARAM_NAME_MAX];

		int values[MAX_MISSION_PARAMS];
		for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {
			values[i] = GenerateParamValue(id, i, midx);
			IntToString(values[i], param_value, INT_STR_MAX);
			StrCat(param_values, sizeof(param_values), ",");
			StrCat(param_values, sizeof(param_values), param_value);

			FormatEx(param_name, PARAM_NAME_MAX, "param_%i", i+1);
			StrCat(param_names, sizeof(param_names), ",");
			StrCat(param_names, sizeof(param_names), param_name);
		}

		char query[QUERY_STR_MAX];
		dbMissi.Format(query, QUERY_STR_MAX,
			"insert into missi_player_data " ...
			" (mission_id,accountid%s) " ...
			" values(%i,%i%s);"
			,param_names,
			id,accid,param_values
		);

		SQL_LockDatabase(dbMissi);
		SQL_FastQuery(dbMissi, query);
		DBResultSet results = SQL_Query(dbMissi,
			"select last_insert_id();"
		);
		SQL_UnlockDatabase(dbMissi);
		if(results.HasResults) {
			do {
				do {
					if(!results.FetchRow()) {
						continue;
					}

					instid = results.FetchInt(0);
				} while(results.MoreRows);
			} while(results.FetchMoreResults());
		}
		delete results;

		int pidx = GetOrCreatePlrMissiCache(client, instid);

		PlayerMissiCache[client].SetMissionID(instid, id, pidx);

		for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {
			PlayerMissiCache[client].SetParamValue(instid, i, values[i], pidx);
		}
	} else {
		static int fakeid = 0;
		instid = fakeid++;

		int pidx = GetOrCreatePlrMissiCache(client, instid);

		PlayerMissiCache[client].SetMissionID(instid, id, pidx);

		for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {
			int value = GenerateParamValue(id, i, midx);
			PlayerMissiCache[client].SetParamValue(instid, i, value, pidx);
		}
	}

	missi_map.Add(client, id, instid);

	return instid;
}

int NativePlrMissi_Count(Handle plugin, int args)
{
	int client = GetNativeCell(1);

	if(PlayerMissiCache[client] == null) {
		return 0;
	}

	return PlayerMissiCache[client].Length;
}

int NativePlrMissi_Get(Handle plugin, int args)
{
	int client = GetNativeCell(1);
	int idx = GetNativeCell(2);

	if(PlayerMissiCache[client] == null) {
		return -1;
	}

	int usrid = GetClientUserId(client);
	int id = PlayerMissiCache[client].GetID(idx);

	return pack_2_ints(usrid, id);
}

int NativePlrMissi_GetEntry(Handle plugin, int args)
{
	int packed = GetNativeCell(1);

	int usrid;
	int id;
	unpack_2_ints(packed, usrid, id);

	int client = GetClientOfUserId(usrid);
	if(client == 0) {
		return -1;
	}

	return PlayerMissiCache[client].GetMissionID(id);
}

int NativePlrMissi_AwardProgress(Handle plugin, int args)
{
	int packed = GetNativeCell(1);

	int usrid;
	int id;
	unpack_2_ints(packed, usrid, id);

	int client = GetClientOfUserId(usrid);
	if(client == 0) {
		return -1;
	}

	int value = GetNativeCell(2);

	int pidx = PlayerMissiCache[client].Find(id);

	int progress = PlayerMissiCache[client].GetProgress(id, pidx);

	int oldprogress = progress;

	progress += value;

	Call_StartForward(hOnMissionProgressChanged);
	Call_PushCell(client);
	Call_PushCell(oldprogress);
	Call_PushCell(progress);
	Call_PushCell(packed);
	Call_Finish();

	PlayerMissiCache[client].SetProgress(id, progress, pidx);

	char query[QUERY_STR_MAX];
	dbMissi.Format(query, QUERY_STR_MAX,
		"update missi_player_data set " ...
		" progress=%i " ...
		" where " ...
		" id=%i;"
		,progress,
		id
	);
	dbMissi.Query(OnErrorQuery, query);

	return 0;
}

int NativePlrMissi_RemoveProgress(Handle plugin, int args)
{
	int packed = GetNativeCell(1);

	int usrid;
	int id;
	unpack_2_ints(packed, usrid, id);

	int client = GetClientOfUserId(usrid);
	if(client == 0) {
		return -1;
	}

	int value = GetNativeCell(2);

	int pidx = PlayerMissiCache[client].Find(id);

	int progress = PlayerMissiCache[client].GetProgress(id, pidx);
	if(progress == 0) {
		return 0;
	}

	bool completed = PlayerMissiCache[client].IsCompleted(id, pidx);

	int oldprogress = progress;

	bool remove = false;

	progress -= value;
	if(progress <= 0) {
		progress = 0;
		remove = true;
	}

	Call_StartForward(hOnMissionProgressChanged);
	Call_PushCell(client);
	Call_PushCell(oldprogress);
	Call_PushCell(progress);
	Call_PushCell(packed);
	Call_Finish();

	PlayerMissiCache[client].SetProgress(id, progress, pidx);

	if(completed && remove) {
		Call_StartForward(hOnMissionStatusChanged);
		Call_PushCell(client);
		Call_PushCell(MISSION_UNCOMPLETED);
		Call_PushCell(packed);
		Call_Finish();
	}

	char query[QUERY_STR_MAX];
	if(remove) {
		dbMissi.Format(query, QUERY_STR_MAX,
			"update missi_player_data set " ...
			" progress=0,completed=null " ...
			" where " ...
			" id=%i;"
			,id
		);
		PlayerMissiCache[client].SetCompletedTime(id, -1, pidx);
	} else {
		dbMissi.Format(query, QUERY_STR_MAX,
			"update missi_player_data set " ...
			" progress=%i " ...
			" where " ...
			" id=%i;"
			,progress,
			id
		);
	}
	dbMissi.Query(OnErrorQuery, query);

	return view_as<int>(remove);
}

int NativePlrMissi_Complete(Handle plugin, int args)
{
	int packed = GetNativeCell(1);

	int usrid;
	int id;
	unpack_2_ints(packed, usrid, id);

	int client = GetClientOfUserId(usrid);
	if(client == 0) {
		return -1;
	}

	int pidx = PlayerMissiCache[client].Find(id);

	if(PlayerMissiCache[client].IsCompleted(id, pidx)) {
		return 0;
	}

	Call_StartForward(hOnMissionStatusChanged);
	Call_PushCell(client);
	Call_PushCell(MISSION_COMPLETED);
	Call_PushCell(packed);
	Call_Finish();

	int time = GetTime();

	char query[QUERY_STR_MAX];
	dbMissi.Format(query, QUERY_STR_MAX,
		"update missi_player_data set " ...
		" completed=%i " ...
		" where " ...
		" id=%i;"
		,time,
		id
	);
	dbMissi.Query(OnErrorQuery, query);

	PlayerMissiCache[client].SetCompletedTime(id, time, pidx);

	return 1;
}

int handle_cancel_native(bool cancel)
{
	int packed = GetNativeCell(1);

	int usrid;
	int id;
	unpack_2_ints(packed, usrid, id);

	int client = GetClientOfUserId(usrid);
	if(client == 0) {
		return -1;
	}

	Call_StartForward(hOnMissionStatusChanged);
	Call_PushCell(client);
	Call_PushCell(cancel ? MISSION_CANCELED : MISSION_TURNEDIN);
	Call_PushCell(packed);
	Call_Finish();

	char query[QUERY_STR_MAX];
	dbMissi.Format(query, QUERY_STR_MAX,
		"delete from missi_player_data where id=%i;"
		,id
	);
	dbMissi.Query(OnErrorQuery, query);

	int pidx = PlayerMissiCache[client].Find(id);

	int mission_id = PlayerMissiCache[client].GetMissionID(id, pidx);

	missi_map.RemoveInstance(client, mission_id, id);

	PlayerMissiCache[client].Erase(id, pidx);

	return 0;
}

int NativePlrMissi_Cancel(Handle plugin, int args)
{
	return handle_cancel_native(true);
}

int NativePlrMissi_TurnIn(Handle plugin, int args)
{
	return handle_cancel_native(false);
}

int NativePlrMissi_SetParamValue(Handle plugin, int args)
{
	int packed = GetNativeCell(1);

	int usrid;
	int id;
	unpack_2_ints(packed, usrid, id);

	int client = GetClientOfUserId(usrid);
	if(client == 0) {
		return -1;
	}

	int param = GetNativeCell(2);
	int value = GetNativeCell(3);

	PlayerMissiCache[client].SetParamValue(id, param, value);

	char param_name[PARAM_NAME_MAX];
	FormatEx(param_name, PARAM_NAME_MAX, "param_%i", param);

	char query[QUERY_STR_MAX];
	dbMissi.Format(query, QUERY_STR_MAX,
		"update missi_player_data set " ...
		" %s=%i " ...
		" where " ...
		" id=%i;"
		,param_name,value,
		id
	);
	dbMissi.Query(OnErrorQuery, query);

	return 0;
}

int NativePlrMissi_GetParamValue(Handle plugin, int args)
{
	int packed = GetNativeCell(1);

	int usrid;
	int id;
	unpack_2_ints(packed, usrid, id);

	int client = GetClientOfUserId(usrid);
	if(client == 0) {
		return -1;
	}

	int param = GetNativeCell(2);

	return PlayerMissiCache[client].GetParamValue(id, param);
}

int NativePlrMissi_GetPluginData(Handle plugin, int args)
{
	int packed = GetNativeCell(1);

	int usrid;
	int id;
	unpack_2_ints(packed, usrid, id);

	int client = GetClientOfUserId(usrid);
	if(client == 0) {
		return -1;
	}

	int param = GetNativeCell(2);

	return PlayerMissiCache[client].GetPluginData(id, param);
}

int NativePlrMissi_GetProgress(Handle plugin, int args)
{
	int packed = GetNativeCell(1);

	int usrid;
	int id;
	unpack_2_ints(packed, usrid, id);

	int client = GetClientOfUserId(usrid);
	if(client == 0) {
		return -1;
	}

	return PlayerMissiCache[client].GetProgress(id);
}

int NativePlrMissi_GetCompleted(Handle plugin, int args)
{
	int packed = GetNativeCell(1);

	int usrid;
	int id;
	unpack_2_ints(packed, usrid, id);

	int client = GetClientOfUserId(usrid);
	if(client == 0) {
		return -1;
	}

	return PlayerMissiCache[client].IsCompleted(id);
}

int NativePlrMissi_GetOwner(Handle plugin, int args)
{
	int packed = GetNativeCell(1);

	int usrid;
	int id;
	unpack_2_ints(packed, usrid, id);

	int client = GetClientOfUserId(usrid);
	if(client == 0) {
		return -1;
	}

	return client;
}

int NativePlrMissi_GetID(Handle plugin, int args)
{
	int packed = GetNativeCell(1);

	int usrid;
	int id;
	unpack_2_ints(packed, usrid, id);

	int client = GetClientOfUserId(usrid);
	if(client == 0) {
		return -1;
	}

	return id;
}

int NativePlrMissi_SetPluginData(Handle plugin, int args)
{
	int packed = GetNativeCell(1);

	int usrid;
	int id;
	unpack_2_ints(packed, usrid, id);

	int client = GetClientOfUserId(usrid);
	if(client == 0) {
		return -1;
	}

	int value = GetNativeCell(2);

	PlayerMissiCache[client].SetPluginData(id, value);

	char query[QUERY_STR_MAX];
	dbMissi.Format(query, QUERY_STR_MAX,
		"update missi_player_data set " ...
		" plugin_data=%i " ...
		" where " ...
		" id=%i;"
		,value,
		id
	);
	dbMissi.Query(OnErrorQuery, query);

	return 0;
}
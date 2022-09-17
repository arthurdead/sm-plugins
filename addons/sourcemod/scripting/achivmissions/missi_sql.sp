#define MAX_MISSI_PARAM_VARNAME 6
#define MAX_MISSI_PARAM_VARVALUE INT_STR_MAX
#define MAX_MISSI_PARAM_STRING (MAX_MISSI_PARAM_VARNAME+1+MAX_MISSI_PARAM_VARVALUE)
#define MAX_MISSI_PARAM_INPUT_STR ((MAX_MISSI_PARAM_STRING+1) * 3)

void OnMissiDatabaseConnect(Database db, const char[] error, any data)
{
	if(db == null) {
		LogError("%s", error);
		return;
	}

	dbMissi = db;

	dbMissi.SetCharset("utf8");

	Transaction tr = new Transaction();

	char query[QUERY_STR_MAX];
	dbMissi.Format(query, QUERY_STR_MAX,
		"create table if not exists missi_data (" ...
		" id int not null primary key auto_increment, " ...
		" name varchar(%i) not null, " ...
		" description varchar(%i) default null "
		,MAX_MISSION_NAME,
		MAX_MISSION_DESCRIPTION
	);

	int param_info_name_len = (39+digit_count(MAX_MISSION_PARAMS)+MAX_MISSI_PARAM_INPUT_STR);
	char[] param_info_name = new char[param_info_name_len];
	for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {
		dbMissi.Format(param_info_name, param_info_name_len,
			", param_%i_info varchar(%i) default null "
			,i+1,MAX_MISSI_PARAM_INPUT_STR
		);
		StrCat(query, sizeof(query), param_info_name);
	}

	StrCat(query, sizeof(query),
		", constraint unique(name) " ...
		");"
	);

#if defined DEBUG
	PrintToServer("missi_data table query:");
	PrintToServer("\n%s\n", query);
#endif

	tr.AddQuery(query);

	query[0] = '\0';

	StrCat(query, sizeof(query),
		"create table if not exists missi_player_data (" ...
		" id int not null primary key auto_increment, " ...
		" mission_id int not null, " ...
		" accountid int not null, " ...
		" progress int default null, " ...
		" plugin_data int default null, " ...
		" completed int default null "
	);

	int param_value_name_len = (26+digit_count(MAX_MISSION_PARAMS));
	char[] param_value_name = new char[param_value_name_len];
	for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {
		dbMissi.Format(param_value_name, param_value_name_len,
			", param_%i int default null "
			,i+1
		);
		StrCat(query, sizeof(query), param_value_name);
	}

	StrCat(query, sizeof(query), ");");

#if defined DEBUG
	PrintToServer("missi_player_data table query:");
	PrintToServer("\n%s\n", query);
#endif

	tr.AddQuery(query);

	tr.AddQuery(
		"select * from missi_data;"
	);

	dbMissi.Execute(tr, CacheMissiData, OnErrorTransaction);
}

void QueryPlayerMissiData(Database db, int client, Transaction tr = null)
{
	int accid = GetSteamAccountID(client);
	int userid = GetClientUserId(client);

	char query[QUERY_STR_MAX];
	db.Format(query, QUERY_STR_MAX,
		"select * from missi_player_data where accountid=%i;"
		,accid
	);
	if(tr != null) {
		tr.AddQuery(query, userid);
	} else {
		db.Query(CachePlayerMissiData, query, userid);
	}
}

void ParseMissiParam(char str[MAX_MISSI_PARAM_INPUT_STR], MissionParamType &type, int &min, int &max)
{
	if(str[0] == '\0') {
		return;
	}

	char missiparambuff[3][MAX_MISSI_PARAM_STRING];
	int num = ExplodeString(str, ";", missiparambuff, 3, MAX_MISSI_PARAM_STRING);

	type = MPARAM_INT;

	char varname[MAX_MISSI_PARAM_VARNAME];
	for(int i = 0; i < num; ++i) {
		int idx = SplitString(missiparambuff[i], "=", varname, sizeof(varname));

		if(idx != -1) {
			if(StrEqual(varname, "type")) {
				if(StrEqual(missiparambuff[i][idx], "int")) {
					type = MPARAM_INT;
				} else if(StrEqual(missiparambuff[i][idx], "class")) {
					type = MPARAM_CLASS;
				} else {
					LogError("unknown type %s", missiparambuff[i][idx]);
				}
			} else if(StrEqual(varname, "min")) {
				min = StringToInt(missiparambuff[i][idx]);
			} else if(StrEqual(varname, "max")) {
				max = StringToInt(missiparambuff[i][idx]);
			} else if(StrEqual(varname, "value")) {
				int value = StringToInt(missiparambuff[i][idx]);
				min = value;
				max = value;
			} else {
				LogError("unknown varname %s", varname);
			}
		} else {
			if(StrEqual(missiparambuff[i], "random_class")) {
				type = MPARAM_CLASS;
				min = 1;
				max = 9;
			} else {
				LogError("unknown str %s", missiparambuff[i]);
			}
		}
	}
}

void CacheMissiData(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	DBResultSet set = results[2];
	if(set.HasResults) {
		mapMissiIds = new StringMap();
		missi_cache = new MMissiCache();
		missi_map = new MMissiMap();
		missi_names = new ArrayList(ByteCountToCells(MAX_MISSION_NAME));
		missi_descs = new ArrayList(ByteCountToCells(MAX_MISSION_DESCRIPTION));

		char name[MAX_MISSION_NAME];
		char desc[MAX_MISSION_DESCRIPTION];
		char param[MAX_MISSION_PARAMS][MAX_MISSI_PARAM_INPUT_STR];

		do {
			do {
				if(!set.FetchRow()) {
					continue;
				}

				++num_missis;

				int id = set.FetchInt(0);

				set.FetchString(1, name, MAX_MISSION_NAME);

				mapMissiIds.SetValue(name, id);

				int idx = missi_cache.Push(id);

				missi_cache.SetName(id, name, idx);

				if(!set.IsFieldNull(2)) {
					set.FetchString(2, desc, MAX_MISSION_DESCRIPTION);
					missi_cache.SetDesc(id, desc, idx);
				} else {
					strcopy(desc, MAX_MISSION_DESCRIPTION, "<<missing description>>");
					missi_cache.NullDesc(id, idx);
				}

				for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {
					set.FetchString(3+i, param[i], MAX_MISSI_PARAM_INPUT_STR);

					MissionParamType type = MPARAM_INVALID;
					int min = 0;
					int max = 0;

					ParseMissiParam(param[i], type, min, max);

					missi_cache.SetParamInfo(id, i, type, min, max, idx);
				}
			} while(set.MoreRows);
		} while(set.FetchMoreResults());
	}

	Transaction tr = new Transaction();

	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			IsFakeClient(i) ||
			bMissiCacheLoaded[i]) {
			continue;
		}

		QueryPlayerMissiData(db, i, tr);
	}

	db.Execute(tr, CachePlayersMissiData, OnErrorTransaction);

	if(hOnMissionsLoaded.FunctionCount > 0) {
		Call_StartForward(hOnMissionsLoaded);
		Call_Finish();
	}
}

void CachePlayersMissiData(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	for(int i = 0; i < numQueries; ++i) {
		CachePlayerMissiData(db, results[i], "", queryData[i]);
	}
}

void CachePlayerMissiData(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null) {
		LogError("%s", error);
		return;
	}

	int client = GetClientOfUserId(data);
	if(client == 0) {
		return;
	}

	if(results.HasResults) {
		PlayerMissiCache[client] = new MPlayerMissiCache();

		do {
			do {
				if(!results.FetchRow()) {
					continue;
				}

				int id = results.FetchInt(0);

				int mission_id = results.FetchInt(1);

				int time = -1;
				if(!results.IsFieldNull(5)) {
					time = results.FetchInt(5);
				}

				int progress = 0;
				if(!results.IsFieldNull(3)) {
					progress = results.FetchInt(3);
				}

				any plugin_data = -1;
				if(!results.IsFieldNull(4)) {
					plugin_data = results.FetchInt(4);
				}

				int idx = PlayerMissiCache[client].Push(id);

				PlayerMissiCache[client].SetMissionID(id, mission_id, idx);
				PlayerMissiCache[client].SetCompletedTime(id, time, idx);
				PlayerMissiCache[client].SetProgress(id, progress, idx);
				PlayerMissiCache[client].SetPluginData(id, plugin_data, idx);

				for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {
					int value = -1;
					if(!results.IsFieldNull(6+i)) {
						value = results.FetchInt(6+i);
					}

					PlayerMissiCache[client].SetParamValue(id, i, value, idx);
				}

				missi_map.Add(client, mission_id, id);

				bMissiCacheLoaded[client] = true;
			} while(results.MoreRows);
		} while(results.FetchMoreResults());
	}

	if(hOnMissionDataLoaded.FunctionCount > 0) {
		Call_StartForward(hOnMissionDataLoaded);
		Call_PushCell(client);
		Call_Finish();
	}
}
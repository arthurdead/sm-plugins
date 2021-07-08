#define MAX_MISSI_PARAM_STRING 64
#define MAX_MISSI_PARAM_VARNAME 64

void OnMissiDatabaseConnect(Database db, const char[] error, any data)
{
	#pragma unused data

	if(db == null) {
		LogError("%s", error);
		return;
	}

	dbAchiv = db;

	db.SetCharset("utf8");

	db.Format(tmpquery, sizeof(tmpquery), "select * from missi_data;");
	db.Query(CacheMissiData, tmpquery);
}

void QueryPlayerMissiData(Database db, int client, Transaction tr = null)
{
	int accid = GetSteamAccountID(client);
	int userid = GetClientUserId(client);

	db.Format(tmpquery, sizeof(tmpquery), "select * from missi_player_data where accountid=%i;", accid);
	if(tr != null) {
		tr.AddQuery(tmpquery, userid);
	} else {
		db.Query(CachePlayerMissiData, tmpquery, userid);
	}
}

char missiparambuff[3][MAX_MISSI_PARAM_STRING];
void ParseMissiParam(const char[] str, MissionParamType &type, int &min, int &max)
{
	if(str[0] == '\0') {
		return;
	}

	int num = ExplodeString(str, ";", missiparambuff, 3, MAX_MISSI_PARAM_STRING);

	char varname[MAX_MISSI_PARAM_VARNAME];
	for(int i = 0; i < num; ++i) {
		if(missiparambuff[i][0] == '\0') {
			continue;
		}

		int idx = SplitString(missiparambuff[i], "=", varname, sizeof(varname));

		if(StrEqual(varname, "type")) {
			if(StrEqual(missiparambuff[i][idx], "int")) {
				type = MPARAM_INT;
			} else if(StrEqual(missiparambuff[i][idx], "player_class")) {
				type = MPARAM_PLRCLASS;
				min = 1;
				max = 9;
			}
		} else if(StrEqual(varname, "min")) {
			min = StringToInt(missiparambuff[i][idx]);
		} else if(StrEqual(varname, "max")) {
			max = StringToInt(missiparambuff[i][idx]);
		} else if(StrEqual(varname, "value")) {
			int value = StringToInt(missiparambuff[i][idx]);
			min = value;
			max = value;
		}
	}
}

void CacheMissiData(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null) {
		LogError("%s", error);
		return;
	}

	if(results.HasResults) {
		mapMissiIds = new StringMap();
		missi_cache = new MMissiCache();
		missi_names = new ArrayList(ByteCountToCells(MAX_MISSION_NAME));
		missi_descs = new ArrayList(ByteCountToCells(MAX_MISSION_DESCRIPTION));

		char name[MAX_MISSION_NAME];
		char desc[MAX_MISSION_DESCRIPTION];
		char param[MAX_MISSION_PARAMS][MAX_MISSI_PARAM_STRING];
		do {
			do {
				if(!results.FetchRow()) {
					continue;
				}

				++num_missis;

				int id = results.FetchInt(0);

				results.FetchString(1, name, sizeof(name));

				mapMissiIds.SetValue(name, id);

				int idx = missi_cache.Push(id);

				missi_cache.SetName(id, name, idx);

				if(!results.IsFieldNull(2)) {
					results.FetchString(1, desc, sizeof(desc));
					missi_cache.SetDesc(id, desc, idx);
				} else {
					strcopy(desc, sizeof(desc), "<<missing description>>");
					missi_cache.NullDesc(id, idx);
				}

				for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {
					results.FetchString(3+i, param[i], MAX_MISSI_PARAM_STRING);

					MissionParamType type = MPARAM_INVALID;
					int min = 0;
					int max = 0;

					ParseMissiParam(param[i], type, min, max);

					missi_cache.SetParamInfo(id, i, type, min, max, idx);
				}

			#if defined DEBUG
				PrintToServer("missi %i %s:\n desc: %s", id, name, desc);
				for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {

					MissionParamType type = MPARAM_INVALID;
					int min = 0;
					int max = 0;

					missi_cache.GetParamInfo(id, i, type, min, max, idx);

					PrintToServer(" param%i: %s (%i, %i, %i)", i+1, param[i], type, min, max);
				}
			#endif
			} while(results.MoreRows);
		} while(results.FetchMoreResults());
	}

	Transaction tr = new Transaction();

	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			bMissiCacheLoaded[i]) {
			continue;
		}

		QueryPlayerMissiData(db, i, tr);
	}

	db.Execute(tr, CachePlayersMissiData, OnErrorTransaction);

	Call_StartForward(hOnMissionsLoaded);
	Call_Finish();
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

				int time = -1;
				if(!results.IsFieldNull(3)) {
					time = results.FetchInt(3);
				}

				int progress = -1;
				if(!results.IsFieldNull(1)) {
					progress = results.FetchInt(1);
				}

				any plugin_data = -1;
				if(!results.IsFieldNull(2)) {
					plugin_data = results.FetchInt(2);
				}

				int idx = PlayerMissiCache[client].Push(id);

				PlayerMissiCache[client].SetCompletedTime(id, time, idx);
				PlayerMissiCache[client].SetProgress(id, progress, idx);
				PlayerMissiCache[client].SetPluginData(id, plugin_data, idx);

				for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {
					int value = -1;
					if(!results.IsFieldNull(3+i)) {
						value = results.FetchInt(3+i);
					}

					PlayerMissiCache[client].SetParamValue(id, i, value, idx);
				}

				bMissiCacheLoaded[client] = true;

			#if defined DEBUG
				PrintToServer("missi %N %i %i %i", client, id, progress, plugin_data);
				for(int i = 0; i < MAX_MISSION_PARAMS; ++i) {
					PrintToServer(" param1: %i", PlayerMissiCache[client].GetParamValue(id, i, idx));
				}
			#endif
			} while(results.MoreRows);
		} while(results.FetchMoreResults());
	}

	Call_StartForward(hOnMissionDataLoaded);
	Call_PushCell(client);
	Call_Finish();
}
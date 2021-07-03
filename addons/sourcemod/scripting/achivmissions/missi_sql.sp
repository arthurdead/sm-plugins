void OnMissiDatabaseConnect(Database db, const char[] error, any data)
{
	#pragma unused data

	if(db == null) {
		LogError("%s", error);
		return;
	}

	dbAchiv = db;

	db.SetCharset("utf8");

	db.Format(tmpquery, sizeof(tmpquery), "select id,name,description,max from missi_data;");
	db.Query(CacheMissiData, tmpquery);
}

void QueryPlayerMissiData(Database db, int client, Transaction tr = null)
{
	int accid = GetSteamAccountID(client);
	int userid = GetClientUserId(client);

	db.Format(tmpquery, sizeof(tmpquery), "select id,progress,plugin_data,completed from missi_player_data where accountid=%i;", accid);
	if(tr != null) {
		tr.AddQuery(tmpquery, userid);
	} else {
		db.Query(CachePlayerMissiData, tmpquery, userid);
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

				int max = -1;
				if(!results.IsFieldNull(3)) {
					max = results.FetchInt(3);
				}
				missi_cache.SetMax(id, max, idx);

			#if defined DEBUG
				PrintToServer("missi %i %s %i:\n %s", id, name, max, desc);
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

				bMissiCacheLoaded[client] = true;

			#if defined DEBUG
				PrintToServer("missi %N %i %i %i", client, id, progress, plugin_data);
			#endif
			} while(results.MoreRows);
		} while(results.FetchMoreResults());
	}

	Call_StartForward(hOnMissionDataLoaded);
	Call_PushCell(client);
	Call_Finish();
}
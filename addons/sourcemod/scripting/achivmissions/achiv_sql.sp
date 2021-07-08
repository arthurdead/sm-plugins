void OnAchivDatabaseConnect(Database db, const char[] error, any data)
{
	#pragma unused data

	if(db == null) {
		LogError("%s", error);
		return;
	}

	dbAchiv = db;

	db.SetCharset("utf8");

	Transaction tr = new Transaction();

	db.Format(tmpquery, sizeof(tmpquery), "select * from achiv_data;");
	tr.AddQuery(tmpquery);

	db.Format(tmpquery, sizeof(tmpquery), "select id,description,hidden from achiv_display;");
	tr.AddQuery(tmpquery);

	db.Execute(tr, CacheAchivData, OnErrorTransaction);
}

void QueryPlayerAchivData(Database db, int client, Transaction tr = null)
{
	int accid = GetSteamAccountID(client);
	int userid = GetClientUserId(client);

	db.Format(tmpquery, sizeof(tmpquery), "select * from achiv_player_data where accountid=%i;", accid);
	if(tr != null) {
		tr.AddQuery(tmpquery, userid);
	} else {
		db.Query(CachePlayerAchivData, tmpquery, userid);
	}
}

void CacheAchivData(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	DBResultSet set = results[0];
	if(set.HasResults) {
		mapAchivIds = new StringMap();
		achiv_cache = new MAchivCache();
		achiv_names = new ArrayList(ByteCountToCells(MAX_ACHIEVEMENT_NAME));

		char name[MAX_ACHIEVEMENT_NAME];
		do {
			do {
				if(!set.FetchRow()) {
					continue;
				}

				++num_achivs;

				int id = set.FetchInt(0);

				set.FetchString(1, name, sizeof(name));

				mapAchivIds.SetValue(name, id);

				int idx = achiv_cache.Push(id);

				achiv_cache.SetName(id, name, idx);

				int max = -1;
				if(!set.IsFieldNull(2)) {
					max = set.FetchInt(2);
				}
				achiv_cache.SetMax(id, max, idx);

				achiv_cache.NullDesc(id, idx);
				achiv_cache.SetHidden(id, false, idx);

			#if defined DEBUG
				PrintToServer("achiv %i %s %i", id, name, max);
			#endif
			} while(set.MoreRows);
		} while(set.FetchMoreResults());
	}

	set = results[1];
	if(set.HasResults) {
		achiv_descs = new ArrayList(ByteCountToCells(MAX_ACHIEVEMENT_DESCRIPTION));

		char desc[MAX_ACHIEVEMENT_DESCRIPTION];
		do {
			do {
				if(!set.FetchRow()) {
					continue;
				}

				int id = set.FetchInt(0);

				int idx = achiv_cache.Find(id);

				if(!set.IsFieldNull(1)) {
					set.FetchString(1, desc, sizeof(desc));
					achiv_cache.SetDesc(id, desc, idx);
				} else {
					strcopy(desc, sizeof(desc), "<<missing description>>");
				}

				bool hidden = (!set.IsFieldNull(2) && (set.FetchInt(2) == 1));
				achiv_cache.SetHidden(id, hidden, idx);

			#if defined DEBUG
				PrintToServer("achiv %i %i:\n %s", id, hidden, desc);
			#endif
			} while(set.MoreRows);
		} while(set.FetchMoreResults());
	}

	Transaction tr = new Transaction();

	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			bAchivCacheLoaded[i]) {
			continue;
		}

		QueryPlayerAchivData(db, i, tr);
	}

	db.Execute(tr, CachePlayersAchivData, OnErrorTransaction);

	Call_StartForward(hOnAchievementsLoaded);
	Call_Finish();
}

void CachePlayersAchivData(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	for(int i = 0; i < numQueries; ++i) {
		CachePlayerAchivData(db, results[i], "", queryData[i]);
	}
}

void CachePlayerAchivData(Database db, DBResultSet results, const char[] error, any data)
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
		PlayerAchivCache[client] = new MPlayerAchivCache();

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

				int idx = PlayerAchivCache[client].Push(id);

				PlayerAchivCache[client].SetAchievedTime(id, time, idx);
				PlayerAchivCache[client].SetProgress(id, progress, idx);
				PlayerAchivCache[client].SetPluginData(id, plugin_data, idx);

				bAchivCacheLoaded[client] = true;

			#if defined DEBUG
				PrintToServer("achiv %N %i %i %i", client, id, progress, plugin_data);
			#endif
			} while(results.MoreRows);
		} while(results.FetchMoreResults());
	}

	Call_StartForward(hOnAchievementDataLoaded);
	Call_PushCell(client);
	Call_Finish();
}
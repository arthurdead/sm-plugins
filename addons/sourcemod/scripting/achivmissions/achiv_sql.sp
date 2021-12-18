void OnAchivDatabaseConnect(Database db, const char[] error, any data)
{
	if(db == null) {
		LogError("%s", error);
		return;
	}

	dbAchiv = db;

	dbAchiv.SetCharset("utf8");

	Transaction tr = new Transaction();

	char query[QUERY_STR_MAX];
	dbAchiv.Format(query, QUERY_STR_MAX,
		"create table if not exists achiv_data ( " ...
		" id int not null primary key auto_increment, " ...
		" name varchar(%i) not null, " ...
		" max int default null, " ...
		" description varchar(%i) not null, " ...
		" hidden int default 0, " ...
		" constraint unique(name) " ...
		");"
		,MAX_ACHIEVEMENT_NAME,
		MAX_ACHIEVEMENT_DESCRIPTION
	);
	tr.AddQuery(query);

#if defined DEBUG
	PrintToServer("achiv_data table query:");
	PrintToServer("\n%s\n", query);
#endif

	tr.AddQuery(
		"create table if not exists achiv_player_data ( " ...
		" id int not null primary key, " ...
		" accountid int not null, " ...
		" progress int default null, " ...
		" plugin_data int default null, " ...
		" achieved int default null, " ...
		" constraint unique(id) " ...
		");"
	);

	tr.AddQuery(
		"select * from achiv_data;"
	);

	dbAchiv.Execute(tr, CacheAchivData, OnErrorTransaction);
}

void QueryPlayerAchivData(Database db, int client, Transaction tr = null)
{
	int accid = GetSteamAccountID(client);
	int userid = GetClientUserId(client);

	char query[QUERY_STR_MAX];
	db.Format(query, QUERY_STR_MAX,
		"select * from achiv_player_data where accountid=%i;"
		,accid
	);
	if(tr != null) {
		tr.AddQuery(query, userid);
	} else {
		db.Query(CachePlayerAchivData, query, userid);
	}
}

void CacheAchivData(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	DBResultSet set = results[2];
	if(set.HasResults) {
		mapAchivIds = new StringMap();
		achiv_cache = new MAchivCache();
		achiv_names = new ArrayList(ByteCountToCells(MAX_ACHIEVEMENT_NAME));
		achiv_descs = new ArrayList(ByteCountToCells(MAX_ACHIEVEMENT_DESCRIPTION));

		char name[MAX_ACHIEVEMENT_NAME];
		char desc[MAX_ACHIEVEMENT_DESCRIPTION];

	#if defined DEBUG
		PrintToServer("achievements:");
	#endif

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

				set.FetchString(3, desc, sizeof(desc));

				achiv_cache.SetDesc(id, desc, idx);

				bool hidden = view_as<bool>(set.FetchInt(4));

				achiv_cache.SetHidden(id, hidden, idx);

			#if defined DEBUG
				PrintToServer("  %s:", name);
				PrintToServer("    desc = %s", desc);
				PrintToServer("    max = %i", max);
				PrintToServer("    hidden = %s", hidden ? "true" : "false");
			#endif
			} while(set.MoreRows);
		} while(set.FetchMoreResults());
	}

	Transaction tr = new Transaction();

	for(int i = 1; i <= MaxClients; ++i) {
		if(!IsClientInGame(i) ||
			IsFakeClient(i) ||
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

	#if defined DEBUG
		PrintToServer("%N achievements:", client);
	#endif

		do {
			do {
				if(!results.FetchRow()) {
					continue;
				}

				int id = results.FetchInt(0);

				int time = -1;
				if(!results.IsFieldNull(4)) {
					time = results.FetchInt(4);
				}

				int progress = 0;
				if(!results.IsFieldNull(2)) {
					progress = results.FetchInt(2);
				}

				any plugin_data = -1;
				if(!results.IsFieldNull(3)) {
					plugin_data = results.FetchInt(3);
				}

				int idx = PlayerAchivCache[client].Push(id);

				PlayerAchivCache[client].SetAchievedTime(id, time, idx);
				PlayerAchivCache[client].SetProgress(id, progress, idx);
				PlayerAchivCache[client].SetPluginData(id, plugin_data, idx);

			#if defined DEBUG
				PrintToServer("  %i:", id);
				PrintToServer("    achieved = %i", time);
				PrintToServer("    progress = %i", progress);
				PrintToServer("    plugin_data = %i", plugin_data);
			#endif

				bAchivCacheLoaded[client] = true;
			} while(results.MoreRows);
		} while(results.FetchMoreResults());
	}

	Call_StartForward(hOnAchievementDataLoaded);
	Call_PushCell(client);
	Call_Finish();
}
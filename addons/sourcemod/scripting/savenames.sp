#include <sourcemod>
#include <bit>

#define QUERY_STR_MAX 1024

static Database names_db;

static StringMap names_map;

public void OnPluginStart()
{
	names_map = new StringMap();

	if(SQL_CheckConfig("savenames")) {
		Database.Connect(database_connect, "savenames");
	}

	HookEvent("player_changename", player_changename);

	for(int i = 1; i <= MaxClients; ++i) {
		if(IsClientConnected(i)) {
			OnClientConnected(i);
		}
	}
}

static int native_sn_get(Handle plugin, int params)
{
	int accid = GetNativeCell(1);

	char str[5];
	pack_int_in_str(accid, str);

	char name[MAX_NAME_LENGTH];
	if(names_map.GetString(str, name, MAX_NAME_LENGTH)) {
		int len = GetNativeCell(3);
		SetNativeString(2, name, len);
		return 1;
	}

	return 0;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("savenames");
	CreateNative("sn_get", native_sn_get);
	return APLRes_Success;
}

static void query_error(Database db, DBResultSet results, const char[] error, any data)
{
	if(!results) {
		LogError("%s", error);
	}
}

static void transaction_error(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("%s", error);
}

static void database_connect(Database db, const char[] error, any data)
{
	if(db == null) {
		LogError("%s", error);
		return;
	}

	names_db = db;
	names_db.SetCharset("utf8");

	Transaction tr = new Transaction();

	char query[QUERY_STR_MAX];
	names_db.Format(query, QUERY_STR_MAX,
		"create table if not exists name ( " ...
		" accid int primary key, " ...
		" name varchar(%i) not null " ...
		");"
		,MAX_NAME_LENGTH
	);
	tr.AddQuery(query);

	tr.AddQuery(
		"select accid,name from name;"
	);

	names_db.Execute(tr, cache_data, transaction_error);
}

static void handle_result_set(DBResultSet set, Function func, any data=0)
{
	if(!set.HasResults) {
		LogError("void result");
		return;
	}

	for(int i = 0; i < set.RowCount; ++i) {
		if(!set.FetchRow()) {
			LogError("fetch failed");
			return;
		}

		Call_StartFunction(null, func);
		Call_PushCell(set);
		Call_PushCell(data);
		Call_Finish();
	}
}

static void cache_names(DBResultSet set)
{
	int accid = set.FetchInt(0);

	char name[MAX_NAME_LENGTH];
	set.FetchString(1, name, MAX_NAME_LENGTH);

	char str[5];
	pack_int_in_str(accid, str);

	names_map.SetString(str, name);
}

static void cache_data(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	handle_result_set(results[numQueries-1], cache_names);
}

static void update_name_ex(int client, const char[] name)
{
	int accid = GetSteamAccountID(client);

	if(names_db != null) {
		char query[QUERY_STR_MAX];
		names_db.Format(query, QUERY_STR_MAX,
			"replace into name set " ...
			" accid=%i,name='%s' " ...
			";"
			,accid,name
		);
		names_db.Query(query_error, query);
	}

	char str[5];
	pack_int_in_str(accid, str);

	names_map.SetString(str, name);
}

static void update_name(int client)
{
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, MAX_NAME_LENGTH);

	update_name_ex(client, name);
}

static void player_changename(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(IsFakeClient(client)) {
		return;
	}

	char newname[MAX_NAME_LENGTH];
	event.GetString("newname", newname, MAX_NAME_LENGTH);

	update_name_ex(client, newname);
}

public void OnClientConnected(int client)
{
	if(IsFakeClient(client)) {
		return;
	}

	update_name(client);
}
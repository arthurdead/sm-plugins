int NativeMissi_GetCount(Handle plugin, int args)
{
	#pragma unused plugin,args

	return num_missis;
}

int NativeMissi_FindByName(Handle plugin, int args)
{
	#pragma unused plugin,args

	int len = 0;
	GetNativeStringLength(1, len);
	++len;
	
	char[] name = new char[len];
	GetNativeString(1, name, len);

	int id = -1;
	if(mapMissiIds.GetValue(name, id)) {
		return id;
	}

	return -1;
}

int NativeMissi_FindByID(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);

	int idx = missi_cache.Find(id);
	if(idx == -1) {
		return -1;
	}

	return id;
}

int NativeMissi_GetName(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);
	int len = GetNativeCell(3);

	char[] name = new char[len];
	missi_cache.GetName(id, name, len);

	SetNativeString(2, name, len);
	return 0;
}

int NativeMissi_GetDesc(Handle plugin, int args)
{
	#pragma unused plugin,args

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
	#pragma unused plugin,args

	int id = GetNativeCell(1);

	return id;
}

int NativeMissi_GetMax(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);
	
	int idx = missi_cache.Find(id);
	if(idx == -1) {
		return -1;
	}

	return missi_cache.GetMax(id, idx);
}

int NativeMissi_GiveToPlayer(Handle plugin, int args)
{
	#pragma unused plugin,args

	int id = GetNativeCell(1);
	int client = GetNativeCell(2);

	int idx = PlayerMissiCache[client].Find(id);
	if(idx == -1) {
		int accid = GetSteamAccountID(client);
		dbAchiv.Format(tmpquery, sizeof(tmpquery), "insert ignore into missi_player_data values(%i,%i,null,null,null);",id,accid);
		dbAchiv.Query(OnErrorQuery, tmpquery);
		PlayerMissiCache[client].Push(id);
	}

	return PackInts(client, id);
}

int NativeMissi_Find(Handle plugin, int args)
{
	#pragma unused plugin,args

	int client = GetNativeCell(1);
	int id = GetNativeCell(2);

	int idx = PlayerMissiCache[client].Find(id);
	if(idx == -1) {
		return -1;
	}
	
	return PackInts(client, id);
}

int NativeMissi_FindByName2(Handle plugin, int args)
{
	#pragma unused plugin,args

	int client = GetNativeCell(1);

	int len = 0;
	GetNativeStringLength(2, len);
	++len;
	
	char[] name = new char[len];
	GetNativeString(2, name, len);

	int id = -1;
	if(!mapMissiIds.GetValue(name, id)) {
		return -1;
	}

	int idx = PlayerMissiCache[client].Find(id);
	if(idx == -1) {
		return -1;
	}

	return PackInts(client, id);
}

int NativeMissi_FindByID2(Handle plugin, int args)
{
	#pragma unused plugin,args

	int client = GetNativeCell(1);

	int id = GetNativeCell(2);

	int idx = missi_cache.Find(id);
	if(idx == -1) {
		return -1;
	}

	idx = PlayerMissiCache[client].Find(id);
	if(idx == -1) {
		return -1;
	}

	return PackInts(client, id);
}

int NativeMissi_GiveByName(Handle plugin, int args)
{
	#pragma unused plugin,args

	int client = GetNativeCell(1);

	int len = 0;
	GetNativeStringLength(2, len);
	++len;
	
	char[] name = new char[len];
	GetNativeString(2, name, len);

	int id = -1;
	if(!mapMissiIds.GetValue(name, id)) {
		return -1;
	}

	int idx = PlayerMissiCache[client].Find(id);
	if(idx == -1) {
		int accid = GetSteamAccountID(client);
		dbMissi.Format(tmpquery, sizeof(tmpquery), "insert ignore into missi_player_data values(%i,%i,null,null,null);",id,accid);
		dbMissi.Query(OnErrorQuery, tmpquery);
		PlayerMissiCache[client].Push(id);
	}

	return PackInts(client, id);
}

int NativeMissi_GiveByID(Handle plugin, int args)
{
	#pragma unused plugin,args

	int client = GetNativeCell(1);

	int id = GetNativeCell(2);

	int idx = missi_cache.Find(id);
	if(idx == -1) {
		return -1;
	}

	idx = PlayerMissiCache[client].Find(id);
	if(idx == -1) {
		int accid = GetSteamAccountID(client);
		dbMissi.Format(tmpquery, sizeof(tmpquery), "insert ignore into missi_player_data values(%i,%i,null,null,null);",id,accid);
		dbMissi.Query(OnErrorQuery, tmpquery);
		PlayerMissiCache[client].Push(id);
	}

	return PackInts(client, id);
}
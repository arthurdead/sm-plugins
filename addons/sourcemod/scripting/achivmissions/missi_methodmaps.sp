#define MISSIPLAYERCACHE_BLOCK (5+MAX_MISSION_PARAMS)
#define MISSIPLAYERCACHE_ENTRY_IDX 1
#define MISSIPLAYERCACHE_PROG_IDX 2
#define MISSIPLAYERCACHE_COMPLT_IDX 3
#define MISSIPLAYERCACHE_PLUDATA_IDX 4
#define MISSIPLAYERCACHE_PARAMS_START_IDX 5
#define MISSIPLAYERCACHE_PARAM_IDX(%1) (MISSIPLAYERCACHE_PARAMS_START_IDX+(%1))

methodmap MPlayerMissiCache < Handle
{
	public any __GenericGet(int id, int block, int idx = -1)
	{
		ArrayList arr = view_as<ArrayList>(this);
		if(idx == -1) {
			idx = arr.FindValue(id);
			if(idx == -1) {
				return -1;
			}
		}
		return arr.Get(idx, block);
	}

	public void __GenericSet(int id, any value, int block, int idx = -1)
	{
		ArrayList arr = view_as<ArrayList>(this);
		if(idx == -1) {
			idx = arr.FindValue(id);
			if(idx == -1) {
				return;
			}
		}
		arr.Set(idx, value, block);
	}

	public MPlayerMissiCache()
	{
		ArrayList arr = new ArrayList(MISSIPLAYERCACHE_BLOCK);
		return view_as<MPlayerMissiCache>(arr);
	}

	public int Push(int id)
	{
		ArrayList arr = view_as<ArrayList>(this);
		int idx = arr.Push(id);
		return idx;
	}

	public int Find(int id)
	{
		ArrayList arr = view_as<ArrayList>(this);
		int idx = arr.FindValue(id);
		return idx;
	}

	public int GetID(int idx)
	{
		ArrayList arr = view_as<ArrayList>(this);
		return arr.Get(idx, 0);
	}

	public int GetMissionID(int id, int idx = -1)
	{
		return this.__GenericGet(id, MISSIPLAYERCACHE_ENTRY_IDX, idx);
	}

	public void SetMissionID(int id, int value, int idx = -1)
	{
		this.__GenericSet(id, value, MISSIPLAYERCACHE_ENTRY_IDX, idx);
	}

	public int GetProgress(int id, int idx = -1)
	{
		int progress = this.__GenericGet(id, MISSIPLAYERCACHE_PROG_IDX, idx);
		if(progress == -1) {
			progress = 0;
		}
		return progress;
	}

	public void SetProgress(int id, int value, int idx = -1)
	{
		this.__GenericSet(id, value, MISSIPLAYERCACHE_PROG_IDX, idx);
	}

	public int GetCompletedTime(int id, int idx = -1)
	{
		return this.__GenericGet(id, MISSIPLAYERCACHE_COMPLT_IDX, idx);
	}

	public void SetCompletedTime(int id, int value, int idx = -1)
	{
		this.__GenericSet(id, value, MISSIPLAYERCACHE_COMPLT_IDX, idx);
	}

	public any GetPluginData(int id, int idx = -1)
	{
		return this.__GenericGet(id, MISSIPLAYERCACHE_PLUDATA_IDX, idx);
	}

	public void SetPluginData(int id, int value, int idx = -1)
	{
		this.__GenericSet(id, value, MISSIPLAYERCACHE_PLUDATA_IDX, idx);
	}

	public void SetParamValue(int id, int param, int value, int idx = -1)
	{
		this.__GenericSet(id, value, MISSIPLAYERCACHE_PARAM_IDX(param), idx);
	}

	public int GetParamValue(int id, int param, int idx = -1)
	{
		return this.__GenericGet(id, MISSIPLAYERCACHE_PARAM_IDX(param), idx);
	}

	public bool IsCompleted(int id, int idx = -1)
	{
		return (this.GetCompletedTime(id, idx) > 0);
	}

	property int Length
	{
		public get()
		{
			ArrayList arr = view_as<ArrayList>(this);
			return arr.Length;
		}
	}

	public void Erase(int id, int idx = -1)
	{
		ArrayList arr = view_as<ArrayList>(this);
		if(idx == -1) {
			idx = arr.FindValue(id);
			if(idx == -1) {
				return;
			}
		}
		arr.Erase(idx);
	}
};

#define MISSICACHE_BLOCK (3+MAX_MISSION_PARAMS)
#define MISSICACHE_NAME_IDX 1
#define MISSICACHE_DESC_IDX 2
#define MISSICACHE_PARAMS_START_IDX 3
#define MISSICACHE_PARAM_IDX(%1) (MISSICACHE_PARAMS_START_IDX+(%1))

methodmap MMissiCache < Handle
{
	public any __GenericGet(int id, int block, int idx = -1)
	{
		ArrayList arr = view_as<ArrayList>(this);
		if(idx == -1) {
			idx = arr.FindValue(id);
			if(idx == -1) {
				return -1;
			}
		}
		return arr.Get(idx, block);
	}

	public void __GenericSet(int id, any value, int block, int idx = -1)
	{
		ArrayList arr = view_as<ArrayList>(this);
		if(idx == -1) {
			idx = arr.FindValue(id);
			if(idx == -1) {
				return;
			}
		}
		arr.Set(idx, value, block);
	}

	public MMissiCache()
	{
		ArrayList arr = new ArrayList(MISSICACHE_BLOCK);
		return view_as<MMissiCache>(arr);
	}

	public int Push(int id)
	{
		ArrayList arr = view_as<ArrayList>(this);
		int idx = arr.Push(id);
		return idx;
	}

	public int Find(int id)
	{
		ArrayList arr = view_as<ArrayList>(this);
		int idx = arr.FindValue(id);
		return idx;
	}

	property int Length
	{
		public get()
		{
			ArrayList arr = view_as<ArrayList>(this);
			return arr.Length;
		}
	}

	public int GetID(int idx)
	{
		ArrayList arr = view_as<ArrayList>(this);
		return arr.Get(idx, 0);
	}

	public void SetName(int id, const char[] name, int idx = -1)
	{
		int nidx = missi_names.PushString(name);
		this.__GenericSet(id, nidx, MISSICACHE_NAME_IDX, idx);
	}

	public void SetDesc(int id, const char[] desc, int idx = -1)
	{
		int nidx = missi_descs.PushString(desc);
		this.__GenericSet(id, nidx, MISSICACHE_DESC_IDX, idx);
	}

	public void SetParamInfo(int id, int param, MissionParamType type, int min = 0, int max = 0, int idx = -1)
	{
		int value = pack_3_ints(view_as<int>(type), min, max);
		this.__GenericSet(id, value, MISSICACHE_PARAM_IDX(param), idx);
	}

	public void GetParamInfo(int id, int param, MissionParamType &type = MPARAM_INT, int &min = 0, int &max = 0, int idx = -1)
	{
		int value = this.__GenericGet(id, MISSICACHE_PARAM_IDX(param), idx);
		unpack_3_ints(value, view_as<int>(type), min, max);
	}

	public void NullDesc(int id, int idx = -1)
	{
		this.__GenericSet(id, -1, MISSICACHE_DESC_IDX, idx);
	}

	public void GetName(int id, char[] name, int len, int idx = -1)
	{
		int nidx = this.__GenericGet(id, MISSICACHE_NAME_IDX, idx);
		missi_names.GetString(nidx, name, len);
	}

	public bool GetDesc(int id, char[] desc, int len, int idx = -1)
	{
		int nidx = this.__GenericGet(id, MISSICACHE_DESC_IDX, idx);
		if(nidx == -1) {
			return false;
		}
		missi_descs.GetString(nidx, desc, len);
		return true;
	}
};

methodmap MMissiMap < Handle
{
	public MMissiMap()
	{
		ArrayList arr = new ArrayList(2);
		return view_as<MMissiMap>(arr);
	}

	public void Add(int client, int mission_id, int instid)
	{
		ArrayList arr = view_as<ArrayList>(this);
		int usrid = GetClientUserId(client);
		int cidx = arr.FindValue(usrid);
		ArrayList missions = null;
		if(cidx == -1) {
			cidx = arr.Push(usrid);
			missions = new ArrayList(2);
			arr.Set(cidx, missions, 1);
		} else {
			missions = arr.Get(cidx, 1);
		}
		ArrayList instances = null;
		int midx = missions.FindValue(mission_id);
		if(midx == -1) {
			midx = missions.Push(mission_id);
			instances = new ArrayList();
			missions.Set(midx, instances, 1);
		} else {
			instances = missions.Get(midx, 1);
		}
		int packed = pack_2_ints(usrid, instid);
		instances.Push(packed);
	}

	public ArrayList Get(int client, int mission_id)
	{
		ArrayList arr = view_as<ArrayList>(this);
		int usrid = GetClientUserId(client);
		int cidx = arr.FindValue(usrid);
		if(cidx == -1) {
			return null;
		}
		ArrayList missions = arr.Get(cidx, 1);
		int midx = missions.FindValue(mission_id);
		if(midx == -1) {
			return null;
		}
		return missions.Get(midx, 1);
	}

	public void RemoveClient(int client)
	{
		ArrayList arr = view_as<ArrayList>(this);
		int usrid = GetClientUserId(client);
		int cidx = arr.FindValue(usrid);
		if(cidx == -1) {
			return;
		}
		ArrayList missions = arr.Get(cidx, 1);
		int mlen = missions.Length;
		for(int i = 0; i < mlen; ++i) {
			ArrayList instances = missions.Get(i, 1);
			delete instances;
		}
		delete missions;
		arr.Erase(cidx);
	}

	public void RemoveInstance(int client, int mission_id, int instid)
	{
		ArrayList instances = this.Get(client, mission_id);
		if(instances == null) {
			return;
		}

		int usrid = GetClientUserId(client);

		int iidx = instances.FindValue(pack_2_ints(usrid, instid));
		if(iidx == -1) {
			return;
		}

		instances.Erase(iidx);
	}
};

MPlayerMissiCache PlayerMissiCache[MAXPLAYERS+1] = {null, ...};
MMissiCache missi_cache = null;
MMissiMap missi_map = null;

int GetOrCreatePlrMissiCache(int client, int id)
{
	if(PlayerMissiCache[client] == null) {
		PlayerMissiCache[client] = new MPlayerMissiCache();
	}

	int idx = PlayerMissiCache[client].Find(id);
	if(idx == -1) {
		idx = PlayerMissiCache[client].Push(id);
	}

	return idx;
}
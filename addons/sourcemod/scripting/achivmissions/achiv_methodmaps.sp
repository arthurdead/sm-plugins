#define ACHIVPLAYERCACHE_BLOCK 4
#define ACHIVPLAYERCACHE_PROG_IDX 1
#define ACHIVPLAYERCACHE_ACHIV_IDX 2
#define ACHIVPLAYERCACHE_PLUDATA_IDX 3

methodmap MPlayerAchivCache < Handle
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

	public MPlayerAchivCache()
	{
		ArrayList arr = new ArrayList(ACHIVPLAYERCACHE_BLOCK);
		return view_as<MPlayerAchivCache>(arr);
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

	public int GetProgress(int id, int idx = -1)
	{
		return this.__GenericGet(id, ACHIVPLAYERCACHE_PROG_IDX, idx);
	}

	public void SetProgress(int id, int value, int idx = -1)
	{
		this.__GenericSet(id, value, ACHIVPLAYERCACHE_PROG_IDX, idx);
	}

	public int GetAchivedTime(int id, int idx = -1)
	{
		return this.__GenericGet(id, ACHIVPLAYERCACHE_ACHIV_IDX, idx);
	}

	public void SetAchievedTime(int id, int value, int idx = -1)
	{
		this.__GenericSet(id, value, ACHIVPLAYERCACHE_ACHIV_IDX, idx);
	}

	public any GetPluginData(int id, int idx = -1)
	{
		return this.__GenericGet(id, ACHIVPLAYERCACHE_PLUDATA_IDX, idx);
	}

	public void SetPluginData(int id, int value, int idx = -1)
	{
		this.__GenericSet(id, value, ACHIVPLAYERCACHE_PLUDATA_IDX, idx);
	}

	public bool HasAchieved(int id, int idx = -1)
	{
		return (this.GetAchivedTime(idx, idx) > 0);
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

#define ACHIVCACHE_BLOCK 5
#define ACHIVCACHE_MAX_IDX 1
#define ACHIVCACHE_NAME_IDX 2
#define ACHIVCACHE_DESC_IDX 3
#define ACHIVCACHE_HIDD_IDX 4

methodmap MAchivCache < Handle
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

	public MAchivCache()
	{
		ArrayList arr = new ArrayList(ACHIVCACHE_BLOCK);
		return view_as<MAchivCache>(arr);
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

	public int GetMax(int id, int idx = -1)
	{
		return this.__GenericGet(id, ACHIVCACHE_MAX_IDX, idx);
	}

	public void SetMax(int id, int value, int idx = -1)
	{
		this.__GenericSet(id, value, ACHIVCACHE_MAX_IDX, idx);
	}

	public bool IsHidden(int id, int idx = -1)
	{
		return (this.__GenericGet(id, ACHIVCACHE_HIDD_IDX, idx) == 1);
	}

	public void SetHidden(int id, bool value, int idx = -1)
	{
		this.__GenericSet(id, value ? 1 : 0, ACHIVCACHE_HIDD_IDX, idx);
	}

	public void SetName(int id, const char[] name, int idx = -1)
	{
		int nidx = achiv_names.PushString(name);
		this.__GenericSet(id, nidx, ACHIVCACHE_NAME_IDX, idx);
	}

	public void SetDesc(int id, const char[] desc, int idx = -1)
	{
		int nidx = achiv_descs.PushString(desc);
		this.__GenericSet(id, nidx, ACHIVCACHE_DESC_IDX, idx);
	}

	public void NullDesc(int id, int idx = -1)
	{
		this.__GenericSet(id, -1, ACHIVCACHE_DESC_IDX, idx);
	}

	public void GetName(int id, char[] name, int len, int idx = -1)
	{
		int nidx = this.__GenericGet(id, ACHIVCACHE_NAME_IDX, idx);
		achiv_names.GetString(nidx, name, len);
	}

	public bool GetDesc(int id, char[] desc, int len, int idx = -1)
	{
		int nidx = this.__GenericGet(id, ACHIVCACHE_DESC_IDX, idx);
		if(nidx == -1) {
			return false;
		}
		achiv_descs.GetString(nidx, desc, len);
		return true;
	}
};

MPlayerAchivCache PlayerAchivCache[MAXPLAYERS+1] = {null, ...};
MAchivCache achiv_cache = null;
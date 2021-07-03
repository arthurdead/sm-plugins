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
		arr.Set(idx, value, 1);
	}

	public MPlayerMissiCache()
	{
		ArrayList arr = new ArrayList(4);
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

	public int GetProgress(int id, int idx = -1)
	{
		return this.__GenericGet(id, 1, idx);
	}

	public void SetProgress(int id, int value, int idx = -1)
	{
		this.__GenericSet(id, value, 1, idx);
	}

	public int GetCompletedTime(int id, int idx = -1)
	{
		return this.__GenericGet(id, 2, idx);
	}

	public void SetCompletedTime(int id, int value, int idx = -1)
	{
		this.__GenericSet(id, value, 2, idx);
	}

	public any GetPluginData(int id, int idx = -1)
	{
		return this.__GenericGet(id, 3, idx);
	}

	public void SetPluginData(int id, int value, int idx = -1)
	{
		this.__GenericSet(id, value, 3, idx);
	}

	public bool IsCompleted(int id, int idx = -1)
	{
		return (this.GetCompletedTime(idx, idx) > 0);
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
		arr.Set(idx, value, 1);
	}

	public MMissiCache()
	{
		ArrayList arr = new ArrayList(4);
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

	public int GetMax(int id, int idx = -1)
	{
		return this.__GenericGet(id, 1, idx);
	}

	public void SetMax(int id, int value, int idx = -1)
	{
		this.__GenericSet(id, value, 1, idx);
	}

	public void SetName(int id, const char[] name, int idx = -1)
	{
		int nidx = missi_names.PushString(name);
		this.__GenericSet(id, nidx, 2, idx);
	}

	public void SetDesc(int id, const char[] desc, int idx = -1)
	{
		int nidx = missi_descs.PushString(desc);
		this.__GenericSet(id, nidx, 3, idx);
	}

	public void NullDesc(int id, int idx = -1)
	{
		this.__GenericSet(id, -1, 3, idx);
	}

	public void GetName(int id, char[] name, int len, int idx = -1)
	{
		int nidx = this.__GenericGet(id, 2, idx);
		missi_names.GetString(nidx, name, len);
	}

	public bool GetDesc(int id, char[] desc, int len, int idx = -1)
	{
		int nidx = this.__GenericGet(id, 3, idx);
		if(nidx == -1) {
			return false;
		}
		missi_descs.GetString(nidx, desc, len);
		return true;
	}
};

MPlayerMissiCache PlayerMissiCache[MAXPLAYERS+1] = {null, ...};
MMissiCache missi_cache = null;
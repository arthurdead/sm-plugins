#if defined aliasrandom_inc
	#endinput
#endif
#define aliasrandom_inc

methodmap AliasRandom < Handle
{
	public AliasRandom(ArrayList weights)
	{
		return view_as<AliasRandom>(CreateAliasRandom(weights));
	}

	public int Get()
	{
		return GetAliasRandom(view_as<ArrayList>(this));
	}
}

stock ArrayList CreateAliasRandom(ArrayList weights)
{
	int len = weights.Length;

	float avg = 0.0;
	for(int i = 0; i < len; ++i) {
		float weight = weights.Get(i);
		avg += weight;
	}
	if(avg > 0.0) {
		avg /= len;
	}

	ArrayList smalls = new ArrayList(2);
	ArrayList bigs = new ArrayList(2);

	int small_i = 0;
	int big_i = 0;

	for(int i = 0; i < len; ++i) {
		float weight = weights.Get(i);

		if(weight == avg) {
			weight += GetRandomFloat(-1.0, 1.0);
		}

		bool is_small = (weight < avg);
		bool is_big = (weight > avg);

		ArrayList target = null;
		int target_i = -1;
		if(is_small) {
			target = smalls;
			target_i = small_i;
		} else if(is_big) {
			target = bigs;
			target_i = big_i;
		}

		target.Push(i);
		if(weight > 0.0 && avg > 0.0) {
			weight = weight/avg;
		} else {
			weight = 0.0;
		}
		target.Set(target_i, weight, 1);

		if(is_small) {
			++small_i;
		} else if(is_big) {
			++big_i;
		}
	}

	small_i = 0;
	big_i = 0;

	ArrayList aliases = null;

	int smalllen = smalls.Length;
	int biglen = bigs.Length;

	aliases = new ArrayList(2, len);
	for(int i = 0; i < len; ++i) {
		aliases.Set(i, 1.0, 0);
		aliases.Set(i, -1, 1);
	}

	if(smalllen > 0 && biglen > 0) {
		int small_idx = smalls.Get(0, 0);
		float small_weight = smalls.Get(0, 1);

		int big_idx = bigs.Get(0, 0);
		float big_weight = bigs.Get(0, 1);

		static const bool shutupspcomp = true;
		while(shutupspcomp) {
			aliases.Set(small_idx, small_weight, 0);
			aliases.Set(small_idx, big_idx, 1);

			big_weight -= (1.0 - small_weight);
			if(big_weight < 0.0) {
				big_weight = 0.0;
			}

			if(big_weight < 1.0) {
				small_idx = big_idx;
				small_weight = big_weight;
				++big_i;
				if(big_i < biglen) {
					big_idx = bigs.Get(big_i, 0);
					big_weight = bigs.Get(big_i, 1);
				} else {
					break;
				}
			} else {
				++small_i;
				if(small_i < smalllen) {
					small_idx = smalls.Get(small_i, 0);
					small_weight = smalls.Get(small_i, 1);
				} else {
					break;
				}
			}
		}
	}

	delete smalls;
	delete bigs;

	return aliases;
}

stock int GetAliasRandom(ArrayList aliases)
{
	if(!aliases) {
		return -1;
	}
	int len = aliases.Length;
	if(len == 0) {
		return -1;
	}
	float r = GetRandomFloat(0.0, 1.0) * len;
	int i = RoundToFloor(r);
	int alias = aliases.Get(i, 1);
	float odds = aliases.Get(i, 0);
	if((r - float(i)) > odds) {
		return alias;
	} else {
		return i;
	}
}
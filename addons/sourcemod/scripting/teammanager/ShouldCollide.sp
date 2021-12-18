Handle dhShouldCollide = null;

void ShouldCollideCreate(GameData gamedata)
{
	dhShouldCollide = DHookCreateFromConf(gamedata, "CBaseEntity::ShouldCollide");
}

void ShouldCollideEntityCreated(int entity, const char[] classname)
{
	//SDKHook(entity, SDKHook_ShouldCollide, ShouldCollideSDKHook);
	//DHookEntity(dhShouldCollide, false, entity, INVALID_FUNCTION, ShouldCollideDHookPre);
}

#define COLLISION_GROUP_PLAYER_MOVEMENT 8
#define TFCOLLISION_GROUP_ROCKETS 24
#define CONTENTS_REDTEAM 0x800
#define CONTENTS_BLUETEAM 0x1000

int ShouldCollideHelper(int owner, int other, int collisiongroup, int contentsmask)
{
	/*if(IsPlayer(owner)) {
		if(collisiongroup != -1 && contentsmask != -1) {
			if(collisiongroup == COLLISION_GROUP_PLAYER_MOVEMENT) {
				if(PlayerFF[owner]) {
					int team = GetEntityTeam(owner);
					switch(team) {
						case 2: {
							if(!(contentsmask & CONTENTS_REDTEAM)) {
								return 1;
							}
						}
						case 3: {
							if(!(contentsmask & CONTENTS_BLUETEAM)) {
								return 1;
							}
						}
					}
				}
			}
		}
	}*/

	return -1;
}

MRESReturn ShouldCollideDHookPre(int pThis, Handle hReturn, Handle hParams)
{
	int owner = GetOwner(pThis);
	int group = DHookGetParam(hParams, 1);
	int mask = DHookGetParam(hParams, 2);

	int val = ShouldCollideHelper(owner, -1, group, mask);
	if(val != -1) {
		DHookSetReturn(hReturn, val);
		return MRES_Supercede;
	}

	return MRES_Ignored;
}

/*public Action CH_PassFilter(int ent1, int ent2, bool &result)
{
	return Plugin_Continue;
}

public Action CH_ShouldCollide(int ent1, int ent2, bool &result)
{
	int val = ShouldCollideHelper(GetOwner(ent1), GetOwner(ent2), -1, -1);
	if(val != -1) {
		result = (val == 1);
		return Plugin_Changed;
	}

	return Plugin_Continue;
}*/

bool ShouldCollideSDKHook(int entity, int collisiongroup, int contentsmask, bool originalResult)
{
	int owner = GetOwner(entity);

	int val = ShouldCollideHelper(owner, -1, collisiongroup, contentsmask);
	if(val != -1) {
		return (val == 1);
	}

	return originalResult;
}
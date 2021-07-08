Handle dhPlayerRelationship = null;

void PlayerRelationshipCreate(GameData gamedata)
{
	dhPlayerRelationship = DHookCreateFromConf(gamedata, "CTeamplayRules::PlayerRelationship");
}

void PlayerRelationshipMapStart()
{
	DHookGamerules(dhPlayerRelationship, false, INVALID_FUNCTION, PlayerRelationshipPre);
}

#define GR_NOTTEAMMATE 0
#define GR_TEAMMATE 1
#define GR_ENEMY 2
#define GR_ALLY 3
#define GR_NEUTRAL 4

MRESReturn PlayerRelationshipPre(int pThis, Handle hReturn, Handle hParams)
{
	int owner = GetOwner(DHookGetParam(hParams, 2));
	int other = GetOwner(DHookGetParam(hParams, 1));

	Call_StartForward(fwInSameTeam);
	Call_PushCell(owner);
	Call_PushCell(other);

	Action result = Plugin_Continue;
	Call_Finish(result);

	if(result == Plugin_Continue) {
		return MRES_Ignored;
	} else {
		if(result == Plugin_Changed) {
			DHookSetReturn(hReturn, GR_TEAMMATE);
		} else {
			DHookSetReturn(hReturn, GR_NOTTEAMMATE);
		}
		return MRES_Supercede;
	}
}
Handle dhSmack = null;

void SmackCreate(GameData gamedata)
{
	dhSmack = DHookCreateFromConf(gamedata, "CTFWrench::Smack");

	DHookEnableDetour(dhSmack, false, SmackPre);
	DHookEnableDetour(dhSmack, true, SmackPost);
}

int SmackTempTeam = -1;
int SmackTempEntity = -1;

MRESReturn SmackPre(int pThis)
{
	int owner = GetOwner(pThis);

	float eye[3];
	GetClientEyeAngles(owner, eye);

	float fwd[3];
	GetAngleVectors(eye, fwd, NULL_VECTOR, NULL_VECTOR);

	float vecSwingStart[3];
	GetClientEyePosition(owner, vecSwingStart);

	ScaleVector(fwd, 70.0);

	float vecSwingEnd[3];
	AddVectors(vecSwingEnd, vecSwingStart, vecSwingEnd);
	AddVectors(vecSwingEnd, fwd, vecSwingEnd);

	TR_TraceRayFilter(vecSwingStart, vecSwingEnd, MASK_SOLID, RayType_EndPoint, TraceFilterPlayers);

	float frac = TR_GetFraction();
	if(frac >= 1.0) {
		float vecSwingMins[3];
		vecSwingMins[0] = -18.0;
		vecSwingMins[1] = -18.0;
		vecSwingMins[2] = -18.0;
		
		float vecSwingMaxs[3];
		vecSwingMaxs[0] = 18.0;
		vecSwingMaxs[1] = 18.0;
		vecSwingMaxs[2] = 18.0;

		TR_TraceHullFilter(vecSwingStart, vecSwingEnd, vecSwingMins, vecSwingMaxs, MASK_SOLID, TraceFilterPlayers);

		frac = TR_GetFraction();
	}

	SmackTempEntity = -1;
	SmackTempTeam = -1;

	if(frac < 1.0) {
		int other = TR_GetEntityIndex();
		if(other != -1) {
			int owner_team = GetClientTeam(owner);
			int other_team = GetEntityTeam(other);

			char classname[32];
			GetEntityClassname(other, classname, sizeof(classname));

			if(StrContains(classname, "obj_") != -1) {
				Call_StartForward(fwCanHeal);
				Call_PushCell(owner);
				Call_PushCell(GetOwner(other));
				Call_PushCell(HEAL_WRENCH);

				Action result = Plugin_Continue;
				Call_Finish(result);

				if(result == Plugin_Continue) {
					return MRES_Ignored;
				} else if(result == Plugin_Changed) {
					SmackTempEntity = other;
					SmackTempTeam = other_team;
					SetEntityTeam(other, owner_team, true);
				} else {
					return MRES_Supercede;
				}
			}
		}
	}

	return MRES_Ignored;
}

MRESReturn SmackPost(int pThis)
{
	if(SmackTempEntity != -1 && SmackTempTeam != -1) {
		SetEntityTeam(SmackTempEntity, SmackTempTeam, true);
		SmackTempEntity = -1;
		SmackTempTeam = -1;
	}

	return MRES_Ignored;
}
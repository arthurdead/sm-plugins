Handle dhTryToPickupBuilding = null;
Handle dhStartBuilding = null;
Handle callAddObject = null;
Handle callRemoveObject = null;
Handle dhObjectKilled = null;

void TryToPickupBuildingCreate(GameData gamedata)
{
	dhTryToPickupBuilding = DHookCreateFromConf(gamedata, "CTFPlayer::TryToPickupBuilding");
	dhStartBuilding = DHookCreateFromConf(gamedata, "CBaseObject::StartBuilding");
	dhObjectKilled = DHookCreateFromConf(gamedata, "CBaseObject::Killed");

	DHookEnableDetour(dhTryToPickupBuilding, false, TryToPickupBuildingPre);
	DHookEnableDetour(dhTryToPickupBuilding, true, TryToPickupBuildingPost);

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayer::AddObject");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	callAddObject = EndPrepSDKCall();

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFPlayer::RemoveObject");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	callRemoveObject = EndPrepSDKCall();
}

int TryToPickupBuildingTempEntity = -1;
int TryToPickupBuildingTempTeam = -1;
int TryToPickupBuildingTempOwner[MAXPLAYERS+1] = {-1, ...};
int StartBuildingTempIDPre[MAXPLAYERS+1] = {-1, ...};
int StartBuildingTempIDPost[MAXPLAYERS+1] = {-1, ...};
int ObjectKilledIDPre[MAXPLAYERS+1] = {-1,...};

void TryToPickupBuildingRemoveHooks(int client)
{
	if(StartBuildingTempIDPre[client] != -1) {
		DHookRemoveHookID(StartBuildingTempIDPre[client]);
		StartBuildingTempIDPre[client] = -1;
	}
	if(StartBuildingTempIDPost[client] != -1) {
		DHookRemoveHookID(StartBuildingTempIDPost[client]);
		StartBuildingTempIDPost[client] = -1;
	}
	if(ObjectKilledIDPre[client] != -1) {
		DHookRemoveHookID(ObjectKilledIDPre[client]);
		ObjectKilledIDPre[client] = -1;
	}
}

void TryToPickupBuildingDisconnect(int client)
{
	TryToPickupBuildingRemoveHooks(client);
	TryToPickupBuildingTempOwner[client] = -1;
}

bool BuildingEnum(int entity)
{
	if(IsValidEntity(entity)) {
		char classname[32];
		GetEntityClassname(entity, classname, sizeof(classname));

		if(StrContains(classname, "obj_") != -1) {
			TryToPickupBuildingTempEntity = entity;
			return false;
		}
	}
	return true;
}

MRESReturn TryToPickupBuildingPre(int pThis, Handle hReturn)
{
	float eye[3];
	GetClientEyeAngles(pThis, eye);

	float fwd[3];
	GetAngleVectors(eye, fwd, NULL_VECTOR, NULL_VECTOR);

	float start[3];
	GetClientEyePosition(pThis, start);

	ScaleVector(fwd, 150.0);

	float end[3];
	AddVectors(end, start, end);
	AddVectors(end, fwd, end);

	TryToPickupBuildingTempTeam = -1;
	TryToPickupBuildingTempEntity = -1;

	TryToPickupBuildingDisconnect(pThis);

	TR_EnumerateEntities(start, end, PARTITION_SOLID_EDICTS, RayType_EndPoint, BuildingEnum);

	if(TryToPickupBuildingTempEntity != -1) {
		int owner = GetOwner(TryToPickupBuildingTempEntity);
		if(!IsPlayer(owner)) {
			TryToPickupBuildingTempEntity = -1;
			return MRES_Ignored;
		}

		Call_StartForward(fwCanPickupBuilding);
		Call_PushCell(pThis);
		Call_PushCell(owner);

		Action result = Plugin_Continue;
		Call_Finish(result);

		if(result == Plugin_Continue) {
			TryToPickupBuildingTempEntity = -1;
			return MRES_Ignored;
		} else if(result == Plugin_Changed) {
			if(owner != pThis) {
				TryToPickupBuildingTempTeam = GetEntityTeam(pThis);
				TryToPickupBuildingTempOwner[pThis] = owner;
				SetEntityTeam(pThis, GetEntityTeam(TryToPickupBuildingTempEntity), true);
				SDKCall(callAddObject, pThis, TryToPickupBuildingTempEntity);
			}
		} else {
			TryToPickupBuildingTempEntity = -1;
			DHookSetReturn(hReturn, 0);
			return MRES_Supercede;
		}
	}

	return MRES_Ignored;
}

MRESReturn TryToPickupBuildingPost(int pThis, Handle hReturn)
{
	if(TryToPickupBuildingTempEntity != -1) {
		SDKCall(callRemoveObject, pThis, TryToPickupBuildingTempEntity);
		TryToPickupBuildingRemoveHooks(pThis);
		StartBuildingTempIDPre[pThis] = DHookEntity(dhStartBuilding, false, TryToPickupBuildingTempEntity, INVALID_FUNCTION, StartBuildingPre);
		StartBuildingTempIDPost[pThis] = DHookEntity(dhStartBuilding, true, TryToPickupBuildingTempEntity, INVALID_FUNCTION, StartBuildingPost);
		ObjectKilledIDPre[pThis] = DHookEntity(dhObjectKilled, false, TryToPickupBuildingTempEntity, INVALID_FUNCTION, ObjectKilledPre);
		TryToPickupBuildingTempEntity = -1;
	}

	if(TryToPickupBuildingTempTeam != -1) {
		SetEntityTeam(pThis, TryToPickupBuildingTempTeam, true);
		TryToPickupBuildingTempTeam = -1;
	}

	return MRES_Ignored;
}

void TryToPickupBuildingDestroyed(int entity)
{
	if(entity == TryToPickupBuildingTempEntity) {
		TryToPickupBuildingTempEntity = -1;
	}
}

int StartBuildingHackTempWasDisposable = -1;

MRESReturn ObjectKilledPre(int pThis, Handle hReturn, Handle hParams)
{
	int fake_owner = GetOwner(pThis);

	int real_owner = TryToPickupBuildingTempOwner[fake_owner];
	if(real_owner != -1) {
		SetEntPropEnt(pThis, Prop_Send, "m_hBuilder", real_owner);
		TryToPickupBuildingTempOwner[fake_owner] = -1;
	}

	return MRES_Ignored;
}

MRESReturn StartBuildingPre(int pThis, Handle hReturn, Handle hParams)
{
	StartBuildingHackTempWasDisposable = -1;

	int fake_owner = GetOwner(pThis);
	int real_owner = TryToPickupBuildingTempOwner[fake_owner];
	if(real_owner != -1) {
		TryToPickupBuildingTempOwner[real_owner] = fake_owner;
		SetEntPropEnt(pThis, Prop_Send, "m_hBuilder", real_owner);
		StartBuildingHackTempWasDisposable = GetEntProp(pThis, Prop_Send, "m_bDisposableBuilding");
		SetEntProp(pThis, Prop_Send, "m_bDisposableBuilding", 1);
		TryToPickupBuildingTempOwner[fake_owner] = -1;
	}

	return MRES_Ignored;
}

MRESReturn StartBuildingPost(int pThis, Handle hReturn, Handle hParams)
{
	if(StartBuildingHackTempWasDisposable != -1) {
		SetEntProp(pThis, Prop_Send, "m_bDisposableBuilding", StartBuildingHackTempWasDisposable);
		StartBuildingHackTempWasDisposable = -1;
	}

	int real_owner = GetOwner(pThis);
	int fake_owner = TryToPickupBuildingTempOwner[real_owner];
	if(fake_owner != -1) {
		SDKCall(callRemoveObject, fake_owner, pThis);
		TryToPickupBuildingTempOwner[real_owner] = -1;
	}

	return MRES_Ignored;
}
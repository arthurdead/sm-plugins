bool ShouldAnnounceAchievement(int client)
{
	if(TF2_GetPlayerClass(client) == TFClass_Spy) {
		if(TF2_IsPlayerInCondition(client, TFCond_Cloaked) ||
			TF2_IsPlayerInCondition(client, TFCond_CloakFlicker) ||
			TF2_IsPlayerInCondition(client, TFCond_Stealthed) ||
			TF2_IsPlayerInCondition(client, TFCond_StealthedUserBuffFade) ||
			TF2_IsPlayerInCondition(client, TFCond_Disguised) ||
			TF2_IsPlayerInCondition(client, TFCond_Disguising))
		{
			return false;
		}
	}

	return m_flNextAchievementAnnounceTime[client] <= GetGameTime();
}

void OnAchievementAchieved(int client)
{
	float origin[3];
	GetClientAbsOrigin(client, origin);

	TE_SetupTFParticleEffect("achieved", origin, NULL_VECTOR, NULL_VECTOR, client, PATTACH_POINT_FOLLOW, 1, false);
	TE_SendToAll();

	EmitGameSoundToAll("Achievement.Earned", client, SND_NOFLAGS, -1, origin, NULL_VECTOR, true, 0.0);

	m_flNextAchievementAnnounceTime[client] = GetGameTime() + ACHIEVEMENT_ANNOUNCEMENT_MIN_TIME;
}

void AnnouceAchievement(int client, int id, int idx = -1)
{
	if(ShouldAnnounceAchievement(client)) {
		OnAchievementAchieved(client);
	}

	BfWrite usrmsg = view_as<BfWrite>(StartMessageAll("SayText2"));
	usrmsg.WriteByte(client);
	usrmsg.WriteByte(1);
	usrmsg.WriteString("#Achievement_Earned");

	char plname[MAX_NAME_LENGTH];
	GetClientName(client, plname, sizeof(plname));

	char name[MAX_ACHIEVEMENT_NAME];
	achiv_cache.GetName(id, name, sizeof(name), idx);

	usrmsg.WriteString(plname);
	usrmsg.WriteString(name);
	EndMessage();
}
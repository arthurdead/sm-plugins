Database dbAchiv;
StringMap mapAchivIds;

bool bAchivCacheLoaded[MAXPLAYERS+1];

ArrayList achiv_names;
ArrayList achiv_descs;

int num_achivs;

GlobalForward hOnAchievementDataLoaded;
GlobalForward hOnAchievementsLoaded;

GlobalForward hOnAchievementProgressChanged;
GlobalForward hOnAchievementStatusChanged;

float m_flNextAchievementAnnounceTime[MAXPLAYERS+1];
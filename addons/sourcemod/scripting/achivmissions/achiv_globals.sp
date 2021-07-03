Database dbAchiv = null;
StringMap mapAchivIds = null;

bool bAchivCacheLoaded[MAXPLAYERS+1] = {false, ...};

ArrayList achiv_names = null;
ArrayList achiv_descs = null;

int num_achivs = 0;

GlobalForward hOnAchievementDataLoaded = null;
GlobalForward hOnAchievementsLoaded = null;

GlobalForward hOnAchievementProgressChanged = null;
GlobalForward hOnAchievementStatusChanged = null;

float m_flNextAchievementAnnounceTime[MAXPLAYERS+1] = {0.0, ...};
Database dbMissi = null;
StringMap mapMissiIds = null;

bool bMissiCacheLoaded[MAXPLAYERS+1] = {false, ...};

ArrayList missi_names = null;
ArrayList missi_descs = null;

int num_missis = 0;

GlobalForward hOnMissionDataLoaded = null;
GlobalForward hOnMissionsLoaded = null;

GlobalForward hOnMissionProgressChanged = null;
GlobalForward hOnMissionStatusChanged = null;
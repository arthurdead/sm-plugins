Database dbMissi;
StringMap mapMissiIds;

bool bMissiCacheLoaded[MAXPLAYERS+1];

ArrayList missi_names;
ArrayList missi_descs;

int num_missis;

GlobalForward hOnMissionDataLoaded;
GlobalForward hOnMissionsLoaded;

GlobalForward hOnMissionProgressChanged;
GlobalForward hOnMissionStatusChanged;
#if defined _bm_spawn_reviews_included
 #endinput
#endif
#define _bm_spawn_reviews_included

#define BM_REVIEW_NOTE_LENGTH 192

enum struct BMReview {
	int id;
	float point[3];
	float normal[3];
	float eye[3];
	float angles[3];
	int objective;
	bool counterattack;
	int observerMode;
	int created;
	bool resolved;
	char admin[64];
	char steamid[64];
	char note[BM_REVIEW_NOTE_LENGTH];
}

stock void BMReview_Path(char[] path, int size) {
	char map[PLATFORM_MAX_PATH];
	GetCurrentMap(map, sizeof map);
	ReplaceString(map, sizeof map, "/", "_");
	ReplaceString(map, sizeof map, "\\", "_");
	BuildPath(Path_SM, path, size, "data/bm_botspawn_reviews/%s.txt", map);
}

stock bool BMReview_Vector(KeyValues kv, const char[] field, float value[3]) {
	char text[192], parts[4][48];
	kv.GetString(field, text, sizeof text);
	if (ExplodeString(text, " ", parts, sizeof parts, sizeof parts[]) != 3)
		return false;
	for (int i = 0; i < 3; i++) {
		int len = strlen(parts[i]);
		if (len == 0 || len >= sizeof parts[] - 1 || StringToFloatEx(parts[i], value[i]) != len)
			return false;
		if ((view_as<int>(value[i]) & 0x7F800000) == 0x7F800000)
			return false;
	}
	return true;
}

stock void BMReview_SetVector(KeyValues kv, const char[] field, const float value[3]) {
	char text[128];
	Format(text, sizeof text, "%.6f %.6f %.6f", value[0], value[1], value[2]);
	kv.SetString(field, text);
}

stock bool BMReview_Validate(KeyValues kv) {
	kv.Rewind();
	char root[64], map[PLATFORM_MAX_PATH], savedMap[PLATFORM_MAX_PATH];
	kv.GetSectionName(root, sizeof root);
	GetCurrentMap(map, sizeof map);
	kv.GetString("map", savedMap, sizeof savedMap);
	if (!StrEqual(root, "BMSpawnReviews") || kv.GetNum("version") != 1 || !StrEqual(map, savedMap))
		return false;
	if (!kv.JumpToKey("markers"))
		return false;
	StringMap ids = new StringMap();
	bool valid = true;
	if (kv.GotoFirstSubKey()) {
		do {
			char key[32], canonical[32];
			int id, duplicate;
			kv.GetSectionName(key, sizeof key);
			if (StringToIntEx(key, id) != strlen(key) || id <= 0 || id == 2147483647) {
				valid = false;
				break;
			}
			IntToString(id, canonical, sizeof canonical);
			if (!StrEqual(key, canonical) || ids.GetValue(key, duplicate)) {
				valid = false;
				break;
			}
			ids.SetValue(key, 1);
			float vector[3];
			if (!BMReview_Vector(kv, "point", vector) || !BMReview_Vector(kv, "normal", vector)
				|| !BMReview_Vector(kv, "eye", vector) || !BMReview_Vector(kv, "angles", vector)) {
				valid = false;
				break;
			}
		} while (kv.GotoNextKey());
	}
	delete ids;
	kv.Rewind();
	return valid;
}

stock KeyValues BMReview_Load(char[] error, int size) {
	char path[PLATFORM_MAX_PATH], backup[PLATFORM_MAX_PATH];
	BMReview_Path(path, sizeof path);
	Format(backup, sizeof backup, "%s.bak", path);
	KeyValues kv = new KeyValues("BMSpawnReviews");
	kv.SetEscapeSequences(true);
	if (!FileExists(path) && !FileExists(backup)) {
		char map[PLATFORM_MAX_PATH];
		GetCurrentMap(map, sizeof map);
		kv.SetNum("version", 1);
		kv.SetString("map", map);
		kv.JumpToKey("markers", true);
		kv.Rewind();
		return kv;
	}
	// A missing main file with an intact backup can result from an interrupted save.
	if (!kv.ImportFromFile(FileExists(path) ? path : backup) || !BMReview_Validate(kv)) {
		strcopy(error, size, "Review file is unreadable, invalid, or belongs to another map. File retained.");
		delete kv;
		return null;
	}
	return kv;
}

stock bool BMReview_Save(KeyValues kv, char[] error, int size) {
	char dir[PLATFORM_MAX_PATH], path[PLATFORM_MAX_PATH], temp[PLATFORM_MAX_PATH], backup[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, dir, sizeof dir, "data/bm_botspawn_reviews");
	if (!DirExists(dir) && !CreateDirectory(dir, 511)) {
		strcopy(error, size, "Cannot create the review directory.");
		return false;
	}
	BMReview_Path(path, sizeof path);
	Format(temp, sizeof temp, "%s.tmp", path);
	Format(backup, sizeof backup, "%s.bak", path);
	kv.Rewind();
	if (!kv.ExportToFile(temp)) {
		strcopy(error, size, "Cannot write the review file. Previous file retained.");
		return false;
	}
	KeyValues verify = new KeyValues("BMSpawnReviews");
	verify.SetEscapeSequences(true);
	bool valid = verify.ImportFromFile(temp) && BMReview_Validate(verify);
	delete verify;
	if (!valid) {
		DeleteFile(temp);
		strcopy(error, size, "Review save verification failed. Previous file retained.");
		return false;
	}
	bool hadFile = FileExists(path);
	if (hadFile && ((FileExists(backup) && !DeleteFile(backup)) || !RenameFile(backup, path))) {
		DeleteFile(temp);
		strcopy(error, size, "Cannot back up the review file. Previous file retained.");
		return false;
	}
	if (!RenameFile(path, temp)) {
		if (hadFile)
			RenameFile(path, backup);
		strcopy(error, size, "Cannot finish saving reviews. Previous data retained in the file or .bak backup.");
		return false;
	}
	return true;
}

stock bool BMReview_Get(KeyValues kv, int id, BMReview mark) {
	char key[16];
	IntToString(id, key, sizeof key);
	kv.Rewind();
	if (!kv.JumpToKey("markers") || !kv.JumpToKey(key))
		return false;
	mark.id = id;
	BMReview_Vector(kv, "point", mark.point);
	BMReview_Vector(kv, "normal", mark.normal);
	BMReview_Vector(kv, "eye", mark.eye);
	BMReview_Vector(kv, "angles", mark.angles);
	mark.objective = kv.GetNum("objective", -1);
	mark.counterattack = kv.GetNum("counterattack") != 0;
	mark.observerMode = kv.GetNum("observer_mode");
	mark.created = kv.GetNum("created");
	mark.resolved = kv.GetNum("resolved") != 0;
	kv.GetString("admin", mark.admin, sizeof mark.admin);
	kv.GetString("steamid", mark.steamid, sizeof mark.steamid);
	kv.GetString("note", mark.note, sizeof mark.note);
	kv.Rewind();
	return true;
}

stock ArrayList BMReview_IDs(KeyValues kv, bool includeResolved = false) {
	ArrayList ids = new ArrayList();
	kv.Rewind();
	if (kv.JumpToKey("markers") && kv.GotoFirstSubKey()) {
		do {
			if (!includeResolved && kv.GetNum("resolved") != 0)
				continue;
			char key[16];
			kv.GetSectionName(key, sizeof key);
			ids.Push(StringToInt(key));
		} while (kv.GotoNextKey());
	}
	kv.Rewind();
	return ids;
}

stock bool BMReview_Add(BMReview mark, char[] error, int size) {
	KeyValues kv = BMReview_Load(error, size);
	if (kv == null)
		return false;
	ArrayList ids = BMReview_IDs(kv, true);
	int next = 1;
	for (int i = 0; i < ids.Length; i++)
		if (ids.Get(i) >= next)
			next = ids.Get(i) + 1;
	delete ids;
	if (next == 2147483647) {
		delete kv;
		strcopy(error, size, "Review marker ID limit reached.");
		return false;
	}
	mark.id = next;
	char key[16];
	IntToString(next, key, sizeof key);
	kv.JumpToKey("markers");
	kv.JumpToKey(key, true);
	BMReview_SetVector(kv, "point", mark.point);
	BMReview_SetVector(kv, "normal", mark.normal);
	BMReview_SetVector(kv, "eye", mark.eye);
	BMReview_SetVector(kv, "angles", mark.angles);
	kv.SetNum("objective", mark.objective);
	kv.SetNum("counterattack", mark.counterattack);
	kv.SetNum("observer_mode", mark.observerMode);
	kv.SetNum("created", mark.created);
	kv.SetNum("resolved", 0);
	kv.SetString("admin", mark.admin);
	kv.SetString("steamid", mark.steamid);
	kv.SetString("note", mark.note);
	bool saved = BMReview_Save(kv, error, size);
	delete kv;
	return saved;
}

stock bool BMReview_Resolve(int id, bool resolved, const char[] admin, char[] error, int size) {
	KeyValues kv = BMReview_Load(error, size);
	if (kv == null)
		return false;
	char key[16];
	IntToString(id, key, sizeof key);
	if (!kv.JumpToKey("markers") || !kv.JumpToKey(key)) {
		delete kv;
		strcopy(error, size, "Review marker no longer exists.");
		return false;
	}
	kv.SetNum("resolved", resolved);
	kv.SetNum("resolved_at", resolved ? GetTime() : 0);
	kv.SetString("resolved_by", resolved ? admin : "");
	bool saved = BMReview_Save(kv, error, size);
	delete kv;
	return saved;
}

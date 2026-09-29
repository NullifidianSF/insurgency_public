#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <entitylump>

// WARNING: These rules reduce the map's original spawnpoints.
// Intended for servers using bm_botrespawn with custom spawns configured
// for each listed map. Without custom spawns, thinning can concentrate bots
// at the remaining points and change normal spawning behavior.
// Only add maps you have tested through all objectives and counterattacks.
// Leave this list empty to disable spawnpoint trimming.
//
// Map, team (security / insurgent / both), target spawnpoints kept per zone.
// Overlaps/map-controlled points can retain extras; unmatched points are preserved.
// Add one row per map. Other maps are untouched. Changes apply on the next map load.
static const char g_SpawnTrimRules[][][] = {
	{ "oilfield_pve", "insurgent", "1" },
	{ "embassy_coop", "insurgent", "1"},
	{ "frequency_open_coop", "insurgent", "1"},
	{ "prospect_coop_b6", "insurgent", "1"},
	{ "congress_open_coop", "insurgent", "1"},
	{ "ins_coastdawn_a3", "insurgent", "1"},
	{ "congress_coop", "insurgent", "1"}
};

enum struct TrimZone {
	int team;
	ArrayList brushes;
	ArrayList members;
	float origin[3];
	float angles[3];
	float fwd[3];
	float right[3];
	float up[3];
	float center[3];
	char name[128];
	char state[96];
	int total;
	bool unsafe;
}

enum struct TrimPoint {
	int lump;
	int zone;
	float origin[3];
	bool keep;
}

ArrayList g_TrimPlanes, g_TrimNodes, g_TrimLeaves, g_TrimModels;
ArrayList g_TrimLeafBrushes, g_TrimBrushes, g_TrimSides;

public void OnMapInit(const char[] mapName) {
	RemoveInitialMapEntities(mapName);
	TrimMapSpawns(mapName);
}

static void TrimMapSpawns(const char[] mapName) {
	int rule = -1;
	for (int i = 0; i < sizeof(g_SpawnTrimRules); i++) {
		if (StrEqual(mapName, g_SpawnTrimRules[i][0], false)) {
			rule = i;
			break;
		}
	}
	if (rule == -1)
		return;

	int team, limit;
	if (StrEqual(g_SpawnTrimRules[rule][1], "security", false))
		team = 2;
	else if (StrEqual(g_SpawnTrimRules[rule][1], "insurgent", false))
		team = 3;
	else if (!StrEqual(g_SpawnTrimRules[rule][1], "both", false)) {
		LogError("Spawn filter: invalid team for %s; nothing removed.", mapName);
		return;
	}
	if (!TrimParseInt(g_SpawnTrimRules[rule][2], limit) || limit < 0) {
		LogError("Spawn filter: invalid keep count for %s; nothing removed.", mapName);
		return;
	}

	if (!TrimLoadBsp(mapName)) {
		LogError("Spawn filter: cannot read supported BSP collision lumps for %s; nothing removed.", mapName);
		TrimFreeBsp();
		return;
	}

	ArrayList zones = new ArrayList(sizeof(TrimZone));
	ArrayList points = new ArrayList(sizeof(TrimPoint));
	bool success = TrimCollectZones(zones, team) && TrimCollectPoints(zones, points, team);
	TrimFreeBsp();
	if (success)
		TrimApply(mapName, zones, points, limit);
	else
		LogError("Spawn filter: unsupported zone geometry or keys on %s; nothing removed.", mapName);

	TrimZone zone;
	for (int i = 0; i < zones.Length; i++) {
		zones.GetArray(i, zone);
		delete zone.brushes;
		delete zone.members;
	}
	delete zones;
	delete points;
}

static void RemoveInitialMapEntities(const char[] mapName) {
	if (StrEqual(mapName, "dedust1p2_aof", false))
		EraseMapEntities("logic_relay", "logic_breakdoor");
	else if (StrEqual(mapName, "hard_rain", false) || StrEqual(mapName, "ins_mountain_escape_v1_3", false) || StrEqual(mapName, "karkand_redux_p2", false))
		EraseMapEntities("env_fog_controller");
	else if (StrEqual(mapName, "estates_b4_push", false)) {
		EraseMapEntities("func_door_rotating");
		EraseMapEntities("func_door");
	}
}

static void EraseMapEntities(const char[] classname, const char[] targetname = "") {
	int removed;
	char value[128];
	for (int i = EntityLump.Length() - 1; i >= 0; i--) {
		EntityLumpEntry entry = EntityLump.Get(i);
		TrimKey(entry, "classname", value, sizeof(value));
		bool match = StrEqual(value, classname);
		if (match && targetname[0]) {
			TrimKey(entry, "targetname", value, sizeof(value));
			match = StrEqual(value, targetname, false);
		}
		delete entry;
		if (!match)
			continue;
		EntityLump.Erase(i);
		removed++;
	}
	if (removed)
		LogMessage("Prevented %d %s entities named '%s' from spawning (empty name = all).", removed, classname, targetname);
}

static bool TrimParseInt(const char[] value, int &number) {
	if (!value[0])
		return false;
	int start = value[0] == '-' ? 1 : 0;
	if (!value[start])
		return false;
	for (int i = start; value[i]; i++) {
		if (value[i] < '0' || value[i] > '9')
			return false;
	}
	return StringToIntEx(value, number) == strlen(value);
}

static bool TrimVector(const char[] text, float vec[3]) {
	char parts[3][32];
	if (ExplodeString(text, " ", parts, sizeof(parts), sizeof(parts[])) != 3)
		return false;
	for (int i = 0; i < 3; i++) {
		if (!parts[i][0] || StringToFloatEx(parts[i], vec[i]) != strlen(parts[i]) || !TrimFinite(vec[i]))
			return false;
	}
	return true;
}

static bool TrimFinite(float value) {
	return (view_as<int>(value) & 0x7F800000) != 0x7F800000;
}

static void TrimKey(EntityLumpEntry entry, const char[] key, char[] value, int size) {
	entry.GetNextKey(key, value, size);
}

static int TrimTeam(EntityLumpEntry entry) {
	char value[32];
	TrimKey(entry, "TeamNum", value, sizeof(value));
	int team;
	if (!TrimParseInt(value, team))
		return -1;
	return team;
}

static bool TrimCollectZones(ArrayList zones, int selectedTeam) {
	char cls[64], value[128];
	for (int i = 0; i < EntityLump.Length(); i++) {
		EntityLumpEntry entry = EntityLump.Get(i);
		TrimKey(entry, "classname", cls, sizeof(cls));
		if (!StrEqual(cls, "ins_spawnzone")) {
			delete entry;
			continue;
		}
		TrimZone zone;
		zone.team = TrimTeam(entry);
		if (zone.team != 2 && zone.team != 3) {
			delete entry;
			return false;
		}
		if (selectedTeam && zone.team != selectedTeam) {
			delete entry;
			continue;
		}
		TrimKey(entry, "targetname", zone.name, sizeof(zone.name));
		if (!zone.name[0])
			Format(zone.name, sizeof(zone.name), "lump #%d", i);
		TrimKey(entry, "parentname", value, sizeof(value));
		bool valid = !value[0];
		// Brush entities without an origin key use the world origin.
		if (entry.GetNextKey("origin", value, sizeof(value)) != -1)
			valid = valid && TrimVector(value, zone.origin);
		TrimKey(entry, "angles", value, sizeof(value));
		if (value[0])
			valid = valid && TrimVector(value, zone.angles);
		TrimKey(entry, "model", value, sizeof(value));
		int model;
		valid = valid && value[0] == '*' && TrimParseInt(value[1], model) && model > 0 && model < g_TrimModels.Length;
		delete entry;
		if (!valid)
			return false;
		zone.brushes = new ArrayList();
		if (!TrimModelBrushes(model, zone.brushes)) {
			delete zone.brushes;
			return false;
		}
		float local[3];
		for (int k = 0; k < 3; k++) {
			float mins = view_as<float>(g_TrimModels.Get(model, k)), maxs = view_as<float>(g_TrimModels.Get(model, k + 3));
			if (!TrimFinite(mins) || !TrimFinite(maxs) || mins > maxs) {
				delete zone.brushes;
				return false;
			}
			local[k] = (mins + maxs) * 0.5;
		}
		GetAngleVectors(zone.angles, zone.fwd, zone.right, zone.up);
		for (int k = 0; k < 3; k++)
			zone.center[k] = zone.origin[k] + zone.fwd[k] * local[0] - zone.right[k] * local[1] + zone.up[k] * local[2];
		zone.members = new ArrayList();
		zones.PushArray(zone);
	}
	return true;
}

static bool TrimCollectPoints(ArrayList zones, ArrayList points, int selectedTeam) {
	char cls[64], value[128], state[96], disabled[24], squad[24], flags[24];
	for (int i = 0; i < EntityLump.Length(); i++) {
		EntityLumpEntry entry = EntityLump.Get(i);
		TrimKey(entry, "classname", cls, sizeof(cls));
		if (!StrEqual(cls, "ins_spawnpoint")) {
			delete entry;
			continue;
		}
		int team = TrimTeam(entry);
		if ((team != 2 && team != 3) || (selectedTeam && team != selectedTeam)) {
			delete entry;
			continue;
		}
		TrimPoint point;
		point.lump = i;
		point.zone = -1;
		TrimKey(entry, "origin", value, sizeof(value));
		if (!TrimVector(value, point.origin)) {
			delete entry;
			return false;
		}
		TrimKey(entry, "targetname", value, sizeof(value));
		bool protectedPoint = value[0] != '\0';
		TrimKey(entry, "parentname", value, sizeof(value));
		if (value[0]) {
			point.keep = true;
			points.PushArray(point);
			delete entry;
			continue;
		}
		TrimKey(entry, "StartDisabled", disabled, sizeof(disabled));
		TrimKey(entry, "SquadID", squad, sizeof(squad));
		TrimKey(entry, "spawnflags", flags, sizeof(flags));
		Format(state, sizeof(state), "%s|%s|%s", disabled, squad, flags);
		// Named points and point-specific map logic must not disappear under I/O.
		for (int k = 0; k < entry.Length; k++) {
			entry.Get(k, value, sizeof(value));
			if (StrContains(value, "On", false) == 0 || StrEqual(value, "controlpoint", false))
				protectedPoint = true;
		}
		delete entry;
		int matches;
		TrimZone zone;
		for (int z = 0; z < zones.Length; z++) {
			zones.GetArray(z, zone);
			if (zone.team != team || !TrimInside(point.origin, zone))
				continue;
			matches++;
			point.zone = z;
			if (!zone.total)
				strcopy(zone.state, sizeof(zone.state), state);
			zone.total++;
			zone.members.Push(points.Length);
			zone.unsafe = zone.unsafe || protectedPoint || !StrEqual(zone.state, state);
			zones.SetArray(z, zone);
		}
		if (!matches)
			point.keep = true;
		points.PushArray(point);
	}
	return true;
}

static void TrimApply(const char[] mapName, ArrayList zones, ArrayList points, int limit) {
	TrimZone zone;
	TrimPoint point, other;
	int removed, preserved;
	// Preserve map-controlled groups before choosing shared points for other zones.
	for (int z = 0; z < zones.Length; z++) {
		zones.GetArray(z, zone);
		if (!zone.unsafe)
			continue;
		for (int p = 0; p < zone.members.Length; p++) {
			int index = zone.members.Get(p);
			points.GetArray(index, point);
			point.keep = true;
			points.SetArray(index, point);
		}
	}
	for (int z = 0; z < zones.Length; z++) {
		zones.GetArray(z, zone);
		int kept;
		for (int p = 0; p < zone.members.Length; p++) {
			points.GetArray(zone.members.Get(p), point);
			if (point.keep)
				kept++;
		}
		while (kept < limit && kept < zone.total) {
			int best = -1;
			float bestScore = -1.0e30;
			for (int p = 0; p < zone.members.Length; p++) {
				int index = zone.members.Get(p);
				points.GetArray(index, point);
				if (point.keep)
					continue;
				float score = -GetVectorDistance(point.origin, zone.center, true);
				if (kept) {
					score = 1.0e30;
					for (int q = 0; q < zone.members.Length; q++) {
						points.GetArray(zone.members.Get(q), other);
						if (!other.keep)
							continue;
						float distance = GetVectorDistance(point.origin, other.origin, true);
						if (distance < score)
							score = distance;
					}
				}
				if (best == -1 || score > bestScore) {
					best = index;
					bestScore = score;
				}
			}
			if (best == -1)
				break;
			points.GetArray(best, point);
			point.keep = true;
			points.SetArray(best, point);
			kept++;
		}
	}
	for (int z = 0; z < zones.Length; z++) {
		zones.GetArray(z, zone);
		int kept;
		for (int p = 0; p < zone.members.Length; p++) {
			points.GetArray(zone.members.Get(p), point);
			if (point.keep)
				kept++;
		}
		LogMessage("Spawn filter %s: zone '%s' team %d: %d -> %d%s", mapName, zone.name, zone.team, zone.total, kept, zone.unsafe ? " (preserved: named point or mixed activation settings)" : (kept > limit ? " (shared with overlapping zone)" : ""));
	}
	// Reverse entity-lump order keeps all saved indices valid while erasing.
	for (int p = points.Length - 1; p >= 0; p--) {
		points.GetArray(p, point);
		if (point.keep || point.zone == -1) {
			preserved++;
			continue;
		}
		EntityLump.Erase(point.lump);
		removed++;
	}
	LogMessage("Spawn filter %s: removed %d ins_spawnpoint before creation; retained %d selected-team points in/around %d zones (target %d per zone).", mapName, removed, preserved, zones.Length, limit);
}


static bool TrimInside(const float world[3], TrimZone zone) {
	float delta[3], local[3];
	SubtractVectors(world, zone.origin, delta);
	local[0] = GetVectorDotProduct(delta, zone.fwd);
	local[1] = -GetVectorDotProduct(delta, zone.right);
	local[2] = GetVectorDotProduct(delta, zone.up);
	for (int b = 0; b < zone.brushes.Length; b++) {
		int brush = zone.brushes.Get(b);
		int first = g_TrimBrushes.Get(brush, 0), count = g_TrimBrushes.Get(brush, 1);
		bool inside = true;
		for (int s = first; s < first + count; s++) {
			int plane = g_TrimSides.Get(s, 0) & 0xFFFF;
			float distance = -view_as<float>(g_TrimPlanes.Get(plane, 3));
			for (int k = 0; k < 3; k++)
				distance += local[k] * view_as<float>(g_TrimPlanes.Get(plane, k));
			if (distance > 0.01) {
				inside = false;
				break;
			}
		}
		if (inside)
			return true;
	}
	return false;
}

static bool TrimModelBrushes(int model, ArrayList result) {
	ArrayList stack = new ArrayList();
	stack.Push(g_TrimModels.Get(model, 9));
	StringMap visited = new StringMap();
	char key[16];
	bool valid = true;
	while (stack.Length && valid) {
		int last = stack.Length - 1;
		int node = stack.Get(last);
		stack.Erase(last);
		if (node >= 0) {
			IntToString(node, key, sizeof(key));
			int seen;
			if (node >= g_TrimNodes.Length || visited.GetValue(key, seen)) {
				valid = false;
				break;
			}
			visited.SetValue(key, 1);
			stack.Push(g_TrimNodes.Get(node, 1));
			stack.Push(g_TrimNodes.Get(node, 2));
			continue;
		}
		int leaf = -(node + 1);
		if (leaf < 0 || leaf >= g_TrimLeaves.Length) {
			valid = false;
			break;
		}
		int packed = g_TrimLeaves.Get(leaf, 6);
		int first = packed & 0xFFFF, count = (packed >>> 16) & 0xFFFF;
		if (first > g_TrimLeafBrushes.Length || count > g_TrimLeafBrushes.Length - first) {
			valid = false;
			break;
		}
		for (int i = first; i < first + count; i++) {
			int brush = g_TrimLeafBrushes.Get(i);
			if (brush < 0 || brush >= g_TrimBrushes.Length) {
				valid = false;
				break;
			}
			if (result.FindValue(brush) == -1 && g_TrimBrushes.Get(brush, 2)) {
				int side = g_TrimBrushes.Get(brush, 0), sides = g_TrimBrushes.Get(brush, 1);
				if (side < 0 || sides < 4 || side > g_TrimSides.Length || sides > g_TrimSides.Length - side) {
					valid = false;
					break;
				}
				for (int s = side; s < side + sides; s++) {
					int plane = g_TrimSides.Get(s, 0) & 0xFFFF;
					if (plane >= g_TrimPlanes.Length) {
						valid = false;
						break;
					}
					for (int k = 0; k < 4; k++) {
						if (!TrimFinite(view_as<float>(g_TrimPlanes.Get(plane, k))))
							valid = false;
					}
				}
				result.Push(brush);
			}
		}
	}
	delete stack;
	delete visited;
	return valid && result.Length > 0;
}

static bool TrimLoadBsp(const char[] mapName) {
	char path[PLATFORM_MAX_PATH];
	// External BSP lump overrides require a matching parser; never use stale geometry.
	for (int i = 0; i < 64; i++) {
		Format(path, sizeof(path), "maps/%s_l_%d.lmp", mapName, i);
		if (FileExists(path, true))
			return false;
	}
	Format(path, sizeof(path), "maps/%s.bsp", mapName);
	File file = OpenFile(path, "rb", true);
	if (file == null)
		return false;
	int magic, version;
	bool valid = file.ReadInt32(magic) && file.ReadInt32(version) && magic == 0x50534256 && (version == 20 || version == 21);
	if (valid) {
		g_TrimPlanes = TrimReadLump(file, 1, 20);
		g_TrimNodes = TrimReadLump(file, 5, 32);
		g_TrimLeaves = TrimReadLump(file, 10, 32);
		g_TrimModels = TrimReadLump(file, 14, 48);
		g_TrimLeafBrushes = TrimReadLump(file, 17, 2);
		g_TrimBrushes = TrimReadLump(file, 18, 12);
		g_TrimSides = TrimReadLump(file, 19, 8);
		valid = g_TrimPlanes != null && g_TrimNodes != null && g_TrimLeaves != null && g_TrimModels != null && g_TrimLeafBrushes != null && g_TrimBrushes != null && g_TrimSides != null;
	}
	delete file;
	return valid;
}

static ArrayList TrimReadLump(File file, int id, int stride) {
	int offset, length, version, compressed;
	if (!file.Seek(8 + id * 16, SEEK_SET) || !file.ReadInt32(offset) || !file.ReadInt32(length) || !file.ReadInt32(version) || !file.ReadInt32(compressed))
		return null;
	if (id == 10 && version == 0)
		stride = 56;
	else if (version != (id == 10 ? 1 : 0))
		return null;
	int size = file.Size();
	if (compressed || offset < 1036 || length <= 0 || length > 16777216 || offset > size || length > size - offset || length % stride || !file.Seek(offset, SEEK_SET))
		return null;
	int cells = stride == 2 ? 1 : stride / 4;
	ArrayList data = new ArrayList(cells);
	int row[14];
	for (int i = 0; i < length / stride; i++) {
		if (file.Read(row, cells, stride == 2 ? 2 : 4) != cells) {
			delete data;
			return null;
		}
		if (stride == 2)
			row[0] &= 0xFFFF;
		data.PushArray(row, cells);
	}
	return data;
}

static void TrimFreeBsp() {
	delete g_TrimPlanes;
	delete g_TrimNodes;
	delete g_TrimLeaves;
	delete g_TrimModels;
	delete g_TrimLeafBrushes;
	delete g_TrimBrushes;
	delete g_TrimSides;
}

bool	g_bEventHooked = false;
int		g_iMapId = -1;

enum {
	prospect_coop_b6 = 0,
	sinjar_coop,
	jail_break_coop_ws,
	crash_course,
	ins_dog_red,
	arcate_aof,
	dedust1p2_aof,
	hard_rain,
	facilityb2_coop_v1_1,
	cs_workout_v1,
	ins_mountain_escape_v1_3,
	karkand_redux_p2,
	pipeline_coop,
	ins_prison_2020_new,
	siege_coop,
	nova_prospect,
	estates_b4_push
};

public Plugin myinfo = {
	name = "map_entities",
	author = "Nullifidian + ChatGPT",
	description = "remove or modify entities for some maps",
	version = "3.6.4"
};

public void OnPluginStart() {
	RegAdminCmd("sm_totalent", cmd_totalent, ADMFLAG_RCON, "Print total entities");
	RegAdminCmd("sm_entstats", cmd_entstats, ADMFLAG_RCON, "List entity counts by classname.");
	RegAdminCmd("sm_entdelete", cmd_entdelete, ADMFLAG_RCON, "Delete ents by classname with optional name/model filters");
	RegAdminCmd("sm_entaiminfo", cmd_entaiminfo, ADMFLAG_RCON, "Dump info about the aimed entity to your console.");
}

public void OnPluginEnd() {
	if (g_bEventHooked)
		HookRoundStartEvent(false);
}

public void OnMapStart() {
	// Retain runtime cleanup for late loads and entities created after OnMapInit.
	char sMapName[32];
	GetCurrentMap(sMapName, sizeof(sMapName));

	g_iMapId = -1;

	if (strcmp(sMapName, "prospect_coop_b6", false) == 0) {
		g_iMapId = prospect_coop_b6;
	}
	else if (strcmp(sMapName, "sinjar_coop", false) == 0) {
		g_iMapId = sinjar_coop;
	}
	else if (strcmp(sMapName, "jail_break_coop_ws", false) == 0) {
		g_iMapId = jail_break_coop_ws;
	}
	else if (strcmp(sMapName, "crash_course", false) == 0) {
		g_iMapId = crash_course;
	}
	else if (strcmp(sMapName, "ins_dog_red", false) == 0) {
		g_iMapId = ins_dog_red;
	}
	else if (strcmp(sMapName, "arcate_aof", false) == 0) {
		g_iMapId = arcate_aof;
	}
	else if (strcmp(sMapName, "dedust1p2_aof", false) == 0) {
		g_iMapId = dedust1p2_aof;
		RemoveEntities("logic_relay", "logic_breakdoor", false);
	}
	else if (strcmp(sMapName, "hard_rain", false) == 0) {
		g_iMapId = hard_rain;
		RemoveEntities("env_fog_controller", "", false);
	}
	else if (strcmp(sMapName, "facilityb2_coop_v1_1", false) == 0) {
		g_iMapId = facilityb2_coop_v1_1;
	}
	else if (strcmp(sMapName, "cs_workout_v1", false) == 0) {
		g_iMapId = cs_workout_v1;
	}
	else if (strcmp(sMapName, "ins_mountain_escape_v1_3", false) == 0) {
		g_iMapId = ins_mountain_escape_v1_3;
		RemoveEntities("env_fog_controller", "", false);
	}
	else if (strcmp(sMapName, "karkand_redux_p2", false) == 0) {
		g_iMapId = karkand_redux_p2;
		RemoveEntities("env_fog_controller", "", false);
	}
	else if (strcmp(sMapName, "pipeline_coop", false) == 0) {
		g_iMapId = pipeline_coop;
	}
	else if (strcmp(sMapName, "ins_prison_2020_new", false) == 0) {
		g_iMapId = ins_prison_2020_new;
	}
	else if (strcmp(sMapName, "siege_coop", false) == 0) {
		g_iMapId = siege_coop;
	}
	else if (strcmp(sMapName, "nova_prospect", false) == 0) {
		g_iMapId = nova_prospect;
	}
	else if (strcmp(sMapName, "estates_b4_push", false) == 0) {
		g_iMapId = estates_b4_push;
		RemoveEntities("func_door_rotating", "", false);
		RemoveEntities("func_door", "", false);
	}

	bool bNeedsRoundHook = MapNeedsRoundStartHook(g_iMapId);
	if (bNeedsRoundHook != g_bEventHooked)
		HookRoundStartEvent(bNeedsRoundHook);
}

static bool MapNeedsRoundStartHook(int mapId) {
	switch (mapId) {
		case prospect_coop_b6,
			sinjar_coop,
			jail_break_coop_ws,
			crash_course,
			ins_dog_red,
			arcate_aof,
			dedust1p2_aof,
			facilityb2_coop_v1_1,
			cs_workout_v1,
			pipeline_coop,
			ins_prison_2020_new,
			siege_coop,
			nova_prospect,
			estates_b4_push: {
			return true;
		}
	}

	return false;
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	RequestFrame(NF_ApplyRoundStartEdits, g_iMapId);
	return Plugin_Continue;
}

static void NF_ApplyRoundStartEdits(any mapIdAny) {
	int mapId = mapIdAny;
	if (mapId != g_iMapId)
		return;

	switch (mapId) {
		case prospect_coop_b6: {
			int iEnt = -1;
			while ((iEnt = FindEntityByClassname(iEnt, "env_fog_controller")) != -1) {
				AcceptEntityInput(iEnt, "TurnOff");	//turn off fog
				//turn on FarZ to improve FPS
				SetVariantString("7000");
				AcceptEntityInput(iEnt, "SetFarZ");
			}
		}
		case sinjar_coop: {
			RemoveEntities("func_breakable", "Breakable_CP5");
		}
		case jail_break_coop_ws: {
			RemoveEntities("func_door", "prison_door2");
			RemoveEntities("func_door", "prison_door3");
			RemoveEntities("func_door", "road_gate");
			RemoveEntities("func_door", "final_door1");
			RemoveEntities("func_door", "final_door2");
			RemoveEntities("func_breakable", "breakout_wall");
		}
		case crash_course: {
			RemoveEntities("func_nav_blocker", "bridge_navblocker");
			RemoveEntities("prop_dynamic", "howitzer_door");
		}
		case ins_dog_red: {
			RemoveEntities("func_door", "Bunker_Doors");
		}
		case arcate_aof: {
			RemoveEntities("func_door_rotating", "doorC");
		}
		case dedust1p2_aof: {
			RemoveEntities("func_breakable", "breakdoor");
			RemoveEntities("prop_dynamic", "ied_model");
		}
		case facilityb2_coop_v1_1: {
			int iEnt = -1;
			while ((iEnt = FindEntityByClassname(iEnt, "func_breakable")) != -1) {
				//set hp on windows so we can break them
				SetVariantString("100");
				AcceptEntityInput(iEnt, "SetHealth");
			}
		}
		case cs_workout_v1: {
			RemoveEntities("func_door_rotating");	//remove doors
			//remove door handles
			char sModelName[64];
			int iEnt = -1;
			while ((iEnt = FindEntityByClassname(iEnt, "prop_dynamic")) != -1) {
				GetEntPropString(iEnt, Prop_Data, "m_ModelName", sModelName, sizeof(sModelName));
				if (StrContains(sModelName, "door_handle_01", false) > -1) {
					SafeKillIdx(iEnt);
				}
			}
		}
		case pipeline_coop: {
			int iEnt = -1;
			while ((iEnt = FindEntityByClassname(iEnt, "func_breakable")) != -1) {
				if (GetEntProp(iEnt, Prop_Data, "m_iHealth") != 500)
					SafeKillIdx(iEnt);
			}
			
			RemoveEntities("prop_door_rotating");
			RemoveEntities("func_brush");
		}
		case ins_prison_2020_new: {
			RemoveEntities("func_door_rotating");
		}
		case siege_coop: {
			RemoveEntities("func_door");
		}
		case nova_prospect: {
			RemoveEntitiesByModel("prop_physics", "metal_panel01a");
			RemoveEntitiesByModel("prop_physics", "oildrum001");
		}
		case estates_b4_push: {
			RemoveEntities("func_door_rotating", "", false);
			RemoveEntities("func_door", "", false);
		}
	}
}

void RemoveEntities(const char[] sClass, const char[] sName = "", bool reportMissing = true) {
	int	iCount = 0,
		iEnt = -1;

	if (sName[0]) {
		char sTempName[64];
		while ((iEnt = FindEntityByClassname(iEnt, sClass)) != -1) {
			if (!HasEntProp(iEnt, Prop_Data, "m_iName"))
				continue;

			GetEntPropString(iEnt, Prop_Data, "m_iName", sTempName, sizeof(sTempName));
			if (strcmp(sTempName, sName, false) == 0) {
				SafeKillIdx(iEnt);
				iCount++;
			}
		}
	} else {
		while ((iEnt = FindEntityByClassname(iEnt, sClass)) != -1) {
			SafeKillIdx(iEnt);
			iCount++;
		}
	}

	if (iCount > 0) {
		if (sName[0]) {
			PrintToServer("[map_entities] Removed: \"%s\" named \"%s\" x %d", sClass, sName, iCount);
		} else {
			PrintToServer("[map_entities] Removed: \"%s\" x %d", sClass, iCount);
		}
	} else if (reportMissing) {
		if (sName[0]) {
			PrintToServer("[map_entities] Didn't find: \"%s\" named \"%s\"", sClass, sName);
		} else {
			PrintToServer("[map_entities] Didn't find: \"%s\"", sClass);
		}
	}
}

void RemoveEntitiesByModel(const char[] sClass, const char[] sModelSubstr) {
	int iCount = 0, iEnt = -1;
	char sTempModel[PLATFORM_MAX_PATH];

	while ((iEnt = FindEntityByClassname(iEnt, sClass)) != -1) {
		if (!HasEntProp(iEnt, Prop_Data, "m_ModelName"))
			continue;

		GetEntPropString(iEnt, Prop_Data, "m_ModelName", sTempModel, sizeof(sTempModel));
		if (StrContains(sTempModel, sModelSubstr, false) == -1)
			continue;

		SafeKillIdx(iEnt);
		iCount++;
	}

	if (iCount > 0)
		PrintToServer("[map_entities] Removed: \"%s\" model~\"%s\" x %d", sClass, sModelSubstr, iCount);
	else
		PrintToServer("[map_entities] Didn't find: \"%s\" model~\"%s\"", sClass, sModelSubstr);
}

public Action cmd_totalent(int client, int args) {
	ReplyToCommand(client, "Total entities: %i", CountEnt());
	return Plugin_Handled;
}

public Action cmd_entaiminfo(int client, int args) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client)) {
		ReplyToCommand(client, "[map_entities] In-game clients only.");
		return Plugin_Handled;
	}

	int ent = -1;

	if (args >= 1) {
		char sEnt[16];
		GetCmdArg(1, sEnt, sizeof(sEnt));
		ent = StringToInt(sEnt);
	}
	else {
		ent = GetClientAimTarget(client, false);
	}

	if (ent <= 0 || !IsValidEntity(ent)) {
		ReplyToCommand(client, "[map_entities] No valid entity targeted.");
		return Plugin_Handled;
	}

	PrintEntAimInfo(client, ent);
	ReplyToCommand(client, "[map_entities] Entity info dumped to your console (ent %d).", ent);
	return Plugin_Handled;
}

static void MoveTypeToString(MoveType mt, char[] out, int maxlen) {
	switch (mt) {
		case MOVETYPE_NONE: strcopy(out, maxlen, "NONE");
		case MOVETYPE_ISOMETRIC: strcopy(out, maxlen, "ISOMETRIC");
		case MOVETYPE_WALK: strcopy(out, maxlen, "WALK");
		case MOVETYPE_STEP: strcopy(out, maxlen, "STEP");
		case MOVETYPE_FLY: strcopy(out, maxlen, "FLY");
		case MOVETYPE_FLYGRAVITY: strcopy(out, maxlen, "FLYGRAVITY");
		case MOVETYPE_VPHYSICS: strcopy(out, maxlen, "VPHYSICS");
		case MOVETYPE_PUSH: strcopy(out, maxlen, "PUSH");
		case MOVETYPE_NOCLIP: strcopy(out, maxlen, "NOCLIP");
		case MOVETYPE_LADDER: strcopy(out, maxlen, "LADDER");
		case MOVETYPE_OBSERVER: strcopy(out, maxlen, "OBSERVER");
		default: strcopy(out, maxlen, "UNKNOWN");
	}
}

static bool GetSendPropOffsetBits(int ent, const char[] prop, int &offs, int &bits) {
	char netClass[64];
	bits = 0;

	if (!GetEntityNetClass(ent, netClass, sizeof(netClass))) {
		offs = -1;
		return false;
	}

	offs = FindSendPropInfo(netClass, prop, _, bits);
	return (offs > 0);
}

static bool GetDataMapOffset(int ent, const char[] prop, int &offs) {
	offs = FindDataMapInfo(ent, prop);
	return (offs > 0);
}

static bool DumpEntIntProp(int client, int ent, const char[] prop) {
	bool printed = false;

	if (HasEntProp(ent, Prop_Send, prop)) {
		int v = GetEntProp(ent, Prop_Send, prop);
		PrintToConsole(client, "send.%s = %d (0x%X)", prop, v, v);
		printed = true;
	}

	if (HasEntProp(ent, Prop_Data, prop)) {
		int v = GetEntProp(ent, Prop_Data, prop);
		PrintToConsole(client, "data.%s = %d (0x%X)", prop, v, v);
		printed = true;
	}

	return printed;
}

static bool DumpEntFloatProp(int client, int ent, const char[] prop) {
	bool printed = false;

	if (HasEntProp(ent, Prop_Send, prop)) {
		int offs, bits;
		if (GetSendPropOffsetBits(ent, prop, offs, bits)) {
			int raw = GetEntData(ent, offs, 4);
			float v = GetEntDataFloat(ent, offs);
			PrintToConsole(client, "send.%s = %.6f (int=%d 0x%X bits=%d offs=%d)", prop, v, raw, raw, bits, offs);
			printed = true;
		}
	}

	if (HasEntProp(ent, Prop_Data, prop)) {
		int offs;
		if (GetDataMapOffset(ent, prop, offs)) {
			int raw = GetEntData(ent, offs, 4);
			float v = GetEntDataFloat(ent, offs);
			PrintToConsole(client, "data.%s = %.6f (int=%d 0x%X offs=%d)", prop, v, raw, raw, offs);
			printed = true;
		}
	}

	return printed;
}

static bool DumpEntVectorProp(int client, int ent, const char[] prop) {
	bool printed = false;

	float v[3];

	if (HasEntProp(ent, Prop_Send, prop)) {
		GetEntPropVector(ent, Prop_Send, prop, v);
		PrintToConsole(client, "send.%s = %.3f %.3f %.3f", prop, v[0], v[1], v[2]);
		printed = true;
	}

	if (HasEntProp(ent, Prop_Data, prop)) {
		GetEntPropVector(ent, Prop_Data, prop, v);
		PrintToConsole(client, "data.%s = %.3f %.3f %.3f", prop, v[0], v[1], v[2]);
		printed = true;
	}

	return printed;
}

static bool DumpEntStringProp(int client, int ent, PropType ptype, const char[] prop, const char[] prefix) {
	if (!HasEntProp(ent, ptype, prop))
		return false;

	char buf[PLATFORM_MAX_PATH];
	GetEntPropString(ent, ptype, prop, buf, sizeof(buf));
	if (!buf[0])
		return false;

	PrintToConsole(client, "%s.%s = %s", prefix, prop, buf);
	return true;
}

static void PrintEntAimInfo(int client, int ent) {
	char cls[64];
	GetEntityClassname(ent, cls, sizeof(cls));

	char net[64];
	net[0] = '\0';
	GetEntityNetClass(ent, net, sizeof(net));

	PrintToConsole(client, " ");
	PrintToConsole(client, "==================== [ENT AIM INFO] ====================");
	PrintToConsole(client, "entindex: %d", ent);
	PrintToConsole(client, "classname: %s", cls);
	PrintToConsole(client, "netclass: %s", net[0] ? net : "(n/a)");

	if (ent >= 1 && ent <= MaxClients && IsClientInGame(ent)) {
		char pname[64];
		GetClientName(ent, pname, sizeof(pname));

		char steam2[32]; steam2[0] = '\0';
		char steam64[32]; steam64[0] = '\0';
		GetClientAuthId(ent, AuthId_Steam2, steam2, sizeof(steam2), true);
		GetClientAuthId(ent, AuthId_SteamID64, steam64, sizeof(steam64), true);

		PrintToConsole(client, "player: %s", pname);
		PrintToConsole(client, "userid: %d  team: %d  alive: %d  health: %d",
			GetClientUserId(ent),
			GetClientTeam(ent),
			IsPlayerAlive(ent),
			GetClientHealth(ent));
		PrintToConsole(client, "steam2: %s", steam2[0] ? steam2 : "(n/a)");
		PrintToConsole(client, "steam64: %s", steam64[0] ? steam64 : "(n/a)");
	}

	// targetname / model
	DumpEntStringProp(client, ent, Prop_Data, "m_iName", "data");
	DumpEntStringProp(client, ent, Prop_Data, "m_ModelName", "data");
	DumpEntStringProp(client, ent, Prop_Send, "m_ModelName", "send");

	// hammer id if present
	if (HasEntProp(ent, Prop_Data, "m_iHammerID"))
		PrintToConsole(client, "data.m_iHammerID = %d", GetEntProp(ent, Prop_Data, "m_iHammerID"));

	// origin / angles
	float org[3];
	float ang[3];
	bool hasOrg = false;
	bool hasAng = false;

	if (HasEntProp(ent, Prop_Send, "m_vecOrigin")) {
		GetEntPropVector(ent, Prop_Send, "m_vecOrigin", org);
		hasOrg = true;
	}
	else if (HasEntProp(ent, Prop_Data, "m_vecAbsOrigin")) {
		GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", org);
		hasOrg = true;
	}

	if (HasEntProp(ent, Prop_Send, "m_angRotation")) {
		GetEntPropVector(ent, Prop_Send, "m_angRotation", ang);
		hasAng = true;
	}
	else if (HasEntProp(ent, Prop_Data, "m_angAbsRotation")) {
		GetEntPropVector(ent, Prop_Data, "m_angAbsRotation", ang);
		hasAng = true;
	}

	if (hasOrg)
		PrintToConsole(client, "origin: %.3f %.3f %.3f", org[0], org[1], org[2]);
	if (hasAng)
		PrintToConsole(client, "angles: %.3f %.3f %.3f", ang[0], ang[1], ang[2]);

	// distance from caller
	if (hasOrg) {
		float eye[3];
		GetClientEyePosition(client, eye);

		float dx = org[0] - eye[0];
		float dy = org[1] - eye[1];
		float dz = org[2] - eye[2];

		float dist = SquareRoot(dx * dx + dy * dy + dz * dz);
		PrintToConsole(client, "distance(from you): %.1f units (%.2f m)", dist, dist * 0.0254);
	}

	// bbox
	if (HasEntProp(ent, Prop_Send, "m_vecMins") && HasEntProp(ent, Prop_Send, "m_vecMaxs")) {
		float mins[3];
		float maxs[3];
		GetEntPropVector(ent, Prop_Send, "m_vecMins", mins);
		GetEntPropVector(ent, Prop_Send, "m_vecMaxs", maxs);
		PrintToConsole(client, "bbox mins: %.2f %.2f %.2f", mins[0], mins[1], mins[2]);
		PrintToConsole(client, "bbox maxs: %.2f %.2f %.2f", maxs[0], maxs[1], maxs[2]);
	}

	// movetype / flags / render
	MoveType mt = GetEntityMoveType(ent);
	char mtStr[16];
	MoveTypeToString(mt, mtStr, sizeof(mtStr));
	PrintToConsole(client, "movetype: %d (%s)", mt, mtStr);

	int flags = GetEntityFlags(ent);
	PrintToConsole(client, "flags: 0x%X (%d)", flags, flags);

	int r, g, b, a;
	GetEntityRenderColor(ent, r, g, b, a);

	RenderMode rm = GetEntityRenderMode(ent);
	RenderFx fx = GetEntityRenderFx(ent);
	PrintToConsole(client, "render: mode=%d fx=%d color=%d %d %d %d", rm, fx, r, g, b, a);

	// owner / parent
	if (HasEntProp(ent, Prop_Send, "m_hOwnerEntity"))
		PrintToConsole(client, "send.m_hOwnerEntity = %d", GetEntPropEnt(ent, Prop_Send, "m_hOwnerEntity"));
	if (HasEntProp(ent, Prop_Send, "m_hMoveParent"))
		PrintToConsole(client, "send.m_hMoveParent = %d", GetEntPropEnt(ent, Prop_Send, "m_hMoveParent"));

	PrintToConsole(client, "------------------- [common props] --------------------");

	static const char g_IntProps[][] = {
		"m_spawnflags",
		"m_iTeamNum",
		"m_iHealth",
		"m_iMaxHealth",
		"m_takedamage",
		"m_nModelIndex",
		"m_nSkin",
		"m_nBody",
		"m_fEffects",
		"m_iEFlags",
		"m_nRenderMode",
		"m_nRenderFX",
		"m_nSolidType",
		"m_usSolidFlags",
		"m_CollisionGroup",
		"m_MoveCollide"
	};

	static const char g_FloatProps[][] = {
		"m_flModelScale",
		"m_flSimulationTime",
		"m_flAnimTime"
	};

	static const char g_VecProps[][] = {
		"m_vecVelocity",
		"m_vecAbsVelocity",
		"m_angAbsRotation",
		"m_vecAbsOrigin"
	};

	for (int i = 0; i < sizeof(g_IntProps); i++)
		DumpEntIntProp(client, ent, g_IntProps[i]);

	for (int i = 0; i < sizeof(g_FloatProps); i++)
		DumpEntFloatProp(client, ent, g_FloatProps[i]);

	for (int i = 0; i < sizeof(g_VecProps); i++)
		DumpEntVectorProp(client, ent, g_VecProps[i]);

	// some extra strings (best-effort)
	DumpEntStringProp(client, ent, Prop_Data, "m_iGlobalname", "data");
	DumpEntStringProp(client, ent, Prop_Data, "m_iClassname", "data");

	PrintToConsole(client, "========================================================");
}

int CountEnt() {
	int iCount = 0;
	for (int i = 0; i < GetMaxEntities(); i++) {
		if (!IsValidEntity(i))
			continue;
		iCount++;
	}
	return iCount;
}

void HookRoundStartEvent(bool hook = true) {
	if (hook) {
		g_bEventHooked = true;
		HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	} else {
		UnhookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
		g_bEventHooked = false;
	}
}

public Action cmd_entstats(int client, int args) {
	StringMap counts = new StringMap();
	int used = 0;
	int classified = 0;
	char cls[64];

	int maxe = GetMaxEntities();
	for (int i = 0; i < maxe; i++) {
		if (!IsValidEntity(i))
			continue;

		used++;

		if (i >= 1 && i <= MaxClients)
			continue;

		GetEntityClassname(i, cls, sizeof(cls));
		if (!cls[0])
			continue;

		int c;
		if (counts.GetValue(cls, c))
			counts.SetValue(cls, c + 1);
		else
			counts.SetValue(cls, 1);

		classified++;
	}

	StringMapSnapshot snap = counts.Snapshot();
	int n = snap.Length;

	int[] order = new int[n];
	for (int i = 0; i < n; i++)
		order[i] = i;

	for (int a = 0; a < n - 1; a++) {
		int best = a;
		int bestCount = EntClassCountBySnap(counts, snap, order[best]);

		for (int b = a + 1; b < n; b++) {
			int curCount = EntClassCountBySnap(counts, snap, order[b]);
			if (curCount > bestCount) {
				best = b;
				bestCount = curCount;
			}
		}

		if (best != a) {
			int tmp = order[a];
			order[a] = order[best];
			order[best] = tmp;
		}
	}

	bool toClient = (client > 0 && IsClientInGame(client));
	if (toClient) {
		PrintToConsole(client, "=== Entity class counts (excluding players) ===");
		PrintToConsole(client, "Used edicts: %d / %d (free: %d)", used, maxe, (maxe - used));
		PrintToConsole(client, "Classified non-player edicts: %d", classified);
		PrintToConsole(client, "%-5s  %-40s  %s", "#", "classname", "count");
	}
	else {
		PrintToServer("=== Entity class counts (excluding players) ===");
		PrintToServer("Used edicts: %d / %d (free: %d)", used, maxe, (maxe - used));
		PrintToServer("Classified non-player edicts: %d", classified);
		PrintToServer("%-5s  %-40s  %s", "#", "classname", "count");
	}

	char key[64];
	for (int i = 0; i < n; i++) {
		snap.GetKey(order[i], key, sizeof(key));
		int cnt = 0;
		counts.GetValue(key, cnt);

		if (toClient)
			PrintToConsole(client, "%-5d  %-40s  %d", i + 1, key, cnt);
		else
			PrintToServer("%-5d  %-40s  %d", i + 1, key, cnt);
	}

	if (toClient)
		ReplyToCommand(client, "Entity stats printed to your console.");

	delete snap;
	delete counts;
	return Plugin_Handled;
}

public Action cmd_entdelete(int client, int args) {
	if (args < 1) {
		ReplyToCommand(client, "Usage: sm_entdelete <classname> [name|model:<substr>] [-contains]");
		return Plugin_Handled;
	}

	char cls[64];
	GetCmdArg(1, cls, sizeof(cls));

	char nameFilter[64]; nameFilter[0] = '\0';
	char modelFilter[PLATFORM_MAX_PATH]; modelFilter[0] = '\0';
	bool contains = false;

	if (args >= 2) {
		char arg2[PLATFORM_MAX_PATH];
		GetCmdArg(2, arg2, sizeof(arg2));

		if (StrContains(arg2, "model:", false) == 0) {
			strcopy(modelFilter, sizeof(modelFilter), arg2[6]);
			if (!modelFilter[0]) {
				ReplyToCommand(client, "[map_entities] Model filter cannot be empty.");
				return Plugin_Handled;
			}
		}
		else {
			strcopy(nameFilter, sizeof(nameFilter), arg2);
		}
	}

	if (args >= 3) {
		char arg3[32];
		GetCmdArg(3, arg3, sizeof(arg3));
		contains = (StrEqual(arg3, "-contains", false) || StrEqual(arg3, "-c", false));
	}

	int removed = RemoveEntitiesByCmd(cls, nameFilter, contains, modelFilter);

	if (removed > 0)
		ReplyToCommand(client, "[map_entities] Removed \"%s\" %s%s%s x %d",
			cls,
			modelFilter[0] ? "model~" : (nameFilter[0] ? "named " : ""),
			modelFilter[0] ? modelFilter : (nameFilter[0] ? nameFilter : ""),
			contains && nameFilter[0] ? " (contains)" : "",
			removed);
	else
		ReplyToCommand(client, "[map_entities] No matches for \"%s\" with given filters.", cls);

	return Plugin_Handled;
}

static int RemoveEntitiesByCmd(const char[] sClass, const char[] sNameFilter = "", bool contains = false, const char[] sModelFilter = "") {
	int count = 0;
	int ent = -1;

	char tempName[64];
	char tempModel[PLATFORM_MAX_PATH];

	while ((ent = FindEntityByClassname(ent, sClass)) != -1) {
		if (ent <= MaxClients || !IsValidEntity(ent))
			continue;

		bool match = true;

		if (sModelFilter[0]) {
			if (!HasEntProp(ent, Prop_Data, "m_ModelName"))
				match = false;
			else {
				GetEntPropString(ent, Prop_Data, "m_ModelName", tempModel, sizeof(tempModel));
			if (!tempModel[0] || StrContains(tempModel, sModelFilter, false) == -1)
				match = false;
			}
		}

		if (match && sNameFilter[0]) {
			if (!HasEntProp(ent, Prop_Data, "m_iName"))
				match = false;
			else
				GetEntPropString(ent, Prop_Data, "m_iName", tempName, sizeof(tempName));

			if (contains) {
				if (StrContains(tempName, sNameFilter, false) == -1)
					match = false;
			}
			else {
				if (strcmp(tempName, sNameFilter, false) != 0)
					match = false;
			}
		}

		if (!match)
			continue;

		SafeKillIdx(ent);
		count++;
	}

	return count;
}

static int EntClassCountBySnap(StringMap map, StringMapSnapshot snap, int snapIndex) {
	char k[64];
	snap.GetKey(snapIndex, k, sizeof(k));
	int c = 0;
	map.GetValue(k, c);
	return c;
}

stock void SafeKillIdx(int ent) {
	if (ent <= MaxClients) return;
	int ref = EntIndexToEntRef(ent);
	if (ref == INVALID_ENT_REFERENCE) return;
	RequestFrame(NF_KillEntity, ref);
}

stock void SafeKillRef(int entref) {
	if (entref == INVALID_ENT_REFERENCE) return;
	RequestFrame(NF_KillEntity, entref);
}

stock void NF_KillEntity(any entref) {
	int ent = EntRefToEntIndex(entref);
	if (ent <= MaxClients || !IsValidEntity(ent)) return;

	if (!AcceptEntityInput(ent, "Kill"))
		RemoveEntity(ent);
}

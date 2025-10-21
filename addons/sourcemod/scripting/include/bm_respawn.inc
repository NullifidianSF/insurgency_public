#if defined _bm_respawn_included
	#endinput
#endif
#define _bm_respawn_included

/**
 * BM Respawn <-> Props shared API
 *
 * Provided by the respawn plugin. The props plugin can use these natives to
 * block building near map spawns (before bots actually spawn).
 */

/** Returns the number of map spawn points known to respawn. */
native int BM_GetMapSpawnCount();

/**
 * Writes the spawn position at index to `pos`.
 * @return true on success, false if index out of bounds
 */
native bool BM_GetMapSpawn(int index, float pos[3]);

/**
 * Checks distance against ALL map spawns using a 2D (horizontal) radius and
 * a max vertical delta. Returns true if any spawn is within range.
 */
native bool BM_IsNearMapSpawn2D(const float pos[3], float minHoriz, float maxVert);

/**
 * Forward fired by respawn whenever the map spawns are (re)built.
 * Props can optionally sweep existing props here to clean up any violations.
 */
forward void BM_OnMapSpawnsRebuilt();

native bool BM_IsNearBotSpawn2D(const float pos[3], float minHoriz, float maxVert);
native bool BM_IsNearNextBotSpawn2D(const float pos[3], float minHoriz, float maxVert);
native bool BM_IsNearFinalBotSpawn2D(const float pos[3], float minHoriz, float maxVert);
// Convenience: checks bot + next-bot + final-bot in one call
native bool BM_IsNearAnyBotSpawn2D(const float pos[3], float minHoriz, float maxVert);

/**
 * get remaining lives for Insurgents
 */
native int BM_GetRemainingLivesIns();
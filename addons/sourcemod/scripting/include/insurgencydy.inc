#if defined _insurgencydy_included
#endinput
#endif
#define _insurgencydy_included

//#include <sourcemod>
//#include <sdktools>
//#include <loghelper>
#if defined REQUIRE_PLUGIN
#undef REQUIRE_PLUGIN
//#include <updater>
#include <smlib>
#define REQUIRE_PLUGIN
#else
//#include <updater>
#include <smlib>
#endif

#define MAX_DEFINABLE_WEAPONS 256
#define MAX_DEFINABLE_GEAR 256
#define MAX_DEFINABLE_AMMO 256
#define MAX_DEFINABLE_EXPLOSIVES 256
#define MAX_DEFINABLE_WEAPON_UPGRADES 256

#define MAX_WEAPON_LEN 32
#define MAX_SQUAD_LEN 32
#define MAX_CLASS_LEN 64
#define MAX_CONTROLPOINTS 64
#define PREFIX_LEN 7
#define MAX_SQUADS 16
#define SQUAD_SIZE 32
#define MAX_MAPS 256
#define MAX_GAMEMODES 32

/*				Player Flags			*/
#define		INS_PL_ZOOM				(1 << 0)		// 1		// Force to zoom
#define		INS_PL_1				(1 << 1)		// 2		// It could be ducking but massive buggy to use
#define		INS_PL_RUN				(1 << 2)		// 4		// Force to run if keep setting this, player cant normal walk or slow walk
#define		INS_PL_WALK				(1 << 3)		// 8		// Force to walk only but player still can run just cannot normal walking
#define		INS_PL_4				(1 << 4)		// 16		// 
#define		INS_PL_FOCUS			(1 << 5)		// 32		// Zoom Focus (Buggy)
#define		INS_PL_SLIDE			(1 << 6)		// 64		// Force to sliding, if you keep setting this, player forever sliding lol
#define		INS_PL_BUYZONE			(1 << 7)		// 128		// Buyzone, Resupply everywhere! (Note: Buyzone makes no friendlyfire damage)
#define		INS_PL_8				(1 << 8)		// 256		// 
#define		INS_PL_BLOCKZONE		(1 << 9)		// 512		// Restricted Zone, Player will be restricted, (Note: This flag applied with INS_PL_LOWERZONE)
#define		INS_PL_LOWERZONE		(1 << 10)		// 1024		// Weapon Lower Zone
#define		INS_PL_SPAWNZONE		(1 << 11)		// 2048		// ENTER SPAWN ZONE (Also can resupply)
#define		INS_PL_12				(1 << 12)		// 4096		//

#define 	MAX_BUTTONS 29
#define		INS_ATTACK1				(1 << 0)
#define		INS_JUMP				(1 << 1)
#define		INS_DUCK				(1 << 2)
#define		INS_PRONE				(1 << 3)
#define		INS_FORWARD				(1 << 4)
#define		INS_BACKWARD			(1 << 5)
#define		INS_USE					(1 << 6)
#define		INS_LEFT				(1 << 9)
#define		INS_RIGHT				(1 << 10)
#define		INS_RELOAD				(1 << 11)
#define		INS_FIREMODE			(1 << 12)
#define		INS_LEAN_LEFT			(1 << 13)
#define		INS_LEAN_RIGHT			(1 << 14)
#define		INS_SPRINT				(1 << 15)
#define		INS_WALK				(1 << 16)
#define		INS_SPECIAL1			(1 << 17)
#define		INS_AIM					(1 << 18)
#define		INS_SCOREBOARD			(1 << 19)
#define		INS_FLASHLIGHT			(1 << 22)
#define		INS_AIM_TOGGLE			(1 << 27)
#define		INS_ACCESSORY			(1 << 28)


/*				COLORS							*/

#define		COLOR_INSURGENTS			"AC4029FF"
#define		COLOR_SECURITY				"84961CFF"
#define		COLOR_SPECTATOR				"F2EBD8FF"

#define		COLOR_ALICEBLUE				"F0F8FFFF"
#define		COLOR_ALLIES				"4D7942FF" // SAME AS ALLIES TEAM IN DOD:S
#define		COLOR_ANCIENT				"EB4B4BFF" // SAME AS ANCIENT ITEM RARITY IN DOTA 2
#define		COLOR_ANTIQUEWHITE			"FAEBD7FF"
#define		COLOR_AQUA					"00FFFFFF"
#define		COLOR_AQUAMARINE			"7FFFD4FF"
#define		COLOR_ARCANA				"ADE55CFF" // SAME AS ARCANA ITEM RARITY IN DOTA 2
#define		COLOR_AXIS					"FF4040FF" // SAME AS AXIS TEAM IN DOD:S
#define		COLOR_AZURE					"007FFFFF"
#define		COLOR_BEIGE					"F5F5DCFF"
#define		COLOR_BISQUE				"FFE4C4FF"
#define		COLOR_BLACK					"000000FF"
#define		COLOR_BLANCHEDALMOND		"FFEBCDFF"
#define		COLOR_BLUE					"99CCFFFF" // SAME AS BLU/COUNTER-TERRORIST TEAM COLOR
#define		COLOR_BLUEVIOLET			"8A2BE2FF"
#define		COLOR_BROWN					"A52A2AFF"
#define		COLOR_BURLYWOOD				"DEB887FF"
#define		COLOR_CADETBLUE				"5F9EA0FF"
#define		COLOR_CHARTREUSE			"7FFF00FF"
#define		COLOR_CHOCOLATE				"D2691EFF"
#define		COLOR_COLLECTORS			"AA0000FF" // SAME AS COLLECTOR'S ITEM QUALITY IN TF2
#define		COLOR_COMMON				"B0C3D9FF" // SAME AS COMMON ITEM RARITY IN DOTA 2
#define		COLOR_COMMUNITY				"70B04AFF" // SAME AS COMMUNITY ITEM QUALITY IN TF2
#define		COLOR_CORAL					"FF7F50FF"
#define		COLOR_CORNFLOWERBLUE		"6495EDFF"
#define		COLOR_CORNSILK				"FFF8DCFF"
#define		COLOR_CORRUPTED				"A32C2EFF" // SAME AS CORRUPTED ITEM QUALITY IN DOTA 2
#define		COLOR_CRIMSON				"DC143CFF"
#define		COLOR_CYAN					"00FFFFFF"
#define		COLOR_DARKBLUE				"00008BFF"
#define		COLOR_DARKCYAN				"008B8BFF"
#define		COLOR_DARKGOLDENROD			"B8860BFF"
#define		COLOR_DARKGRAY				"A9A9A9FF"
#define		COLOR_DARKGREY				"A9A9A9FF"
#define		COLOR_DARKGREEN				"006400FF"
#define		COLOR_DARKKHAKI				"BDB76BFF"
#define		COLOR_DARKMAGENTA			"8B008BFF"
#define		COLOR_DARKOLIVEGREEN		"556B2FFF"
#define		COLOR_DARKORANGE			"FF8C00FF"
#define		COLOR_DARKORCHID			"9932CCFF"
#define		COLOR_DARKRED				"8B0000FF"
#define		COLOR_DARKSALMON			"E9967AFF"
#define		COLOR_DARKSEAGREEN			"8FBC8FFF"
#define		COLOR_DARKSLATEBLUE			"483D8BFF"
#define		COLOR_DARKSLATEGRAY			"2F4F4FFF"
#define		COLOR_DARKSLATEGREY			"2F4F4FFF"
#define		COLOR_DARKTURQUOISE			"00CED1FF"
#define		COLOR_DARKVIOLET			"9400D3FF"
#define		COLOR_DEEPPINK				"FF1493FF"
#define		COLOR_DEEPSKYBLUE			"00BFFFFF"
#define		COLOR_DIMGRAY				"696969FF"
#define		COLOR_DIMGREY				"696969FF"
#define		COLOR_DODGERBLUE			"1E90FFFF"
#define		COLOR_EXALTED				"CCCCCDFF" // SAME AS EXALTED ITEM QUALITY IN DOTA 2
#define		COLOR_FIREBRICK				"B22222FF"
#define		COLOR_FLORALWHITE			"FFFAF0FF"
#define		COLOR_FORESTGREEN			"228B22FF"
#define		COLOR_FROZEN				"4983B3FF" // SAME AS FROZEN ITEM QUALITY IN DOTA 2
#define		COLOR_FUCHSIA				"FF00FFFF"
#define		COLOR_FULLBLUE				"0000FFFF"
#define		COLOR_FULLRED				"FF0000FF"
#define		COLOR_GAINSBORO				"DCDCDCFF"
#define		COLOR_GENUINE				"4D7455FF" // SAME AS GENUINE ITEM QUALITY IN TF2
#define		COLOR_GHOSTWHITE			"F8F8FFFF"
#define		COLOR_GOLD					"FFD700FF"
#define		COLOR_GOLDENROD				"DAA520FF"
#define		COLOR_GRAY					"CCCCCCFF" // SAME AS SPECTATOR TEAM COLOR
#define		COLOR_GREY					"CCCCCCFF"
#define		COLOR_GREEN					"3EFF3EFF"
#define		COLOR_GREENYELLOW			"ADFF2FFF"
#define		COLOR_HAUNTED				"38F3ABFF" // SAME AS HAUNTED ITEM QUALITY IN TF2
#define		COLOR_HONEYDEW				"F0FFF0FF"
#define		COLOR_HOTPINK				"FF69B4FF"
#define		COLOR_IMMORTAL				"E4AE33FF" // SAME AS IMMORTAL ITEM RARITY IN DOTA 2
#define		COLOR_INDIANRED				"CD5C5CFF"
#define		COLOR_INDIGO				"4B0082FF"
#define		COLOR_IVORY					"FFFFF0FF"
#define		COLOR_KHAKI					"F0E68CFF"
#define		COLOR_LAVENDER				"E6E6FAFF"
#define		COLOR_LAVENDERBLUSH			"FFF0F5FF"
#define		COLOR_LAWNGREEN				"7CFC00FF"
#define		COLOR_LEGENDARY				"D32CE6FF" // SAME AS LEGENDARY ITEM RARITY IN DOTA 2
#define		COLOR_LEMONCHIFFON			"FFFACDFF"
#define		COLOR_LIGHTBLUE				"ADD8E6FF"
#define		COLOR_LIGHTCORAL			"F08080FF"
#define		COLOR_LIGHTCYAN				"E0FFFFFF"
#define		COLOR_LIGHTGOLDENRODYELLOW	"FAFAD2FF"
#define		COLOR_LIGHTGRAY				"D3D3D3FF"
#define		COLOR_LIGHTGREY				"D3D3D3FF"
#define		COLOR_LIGHTGREEN			"99FF99FF"
#define		COLOR_LIGHTPINK				"FFB6C1FF"
#define		COLOR_LIGHTSALMON			"FFA07AFF"
#define		COLOR_LIGHTSEAGREEN			"20B2AAFF"
#define		COLOR_LIGHTSKYBLUE			"87CEFAFF"
#define		COLOR_LIGHTSLATEGRAY		"778899FF"
#define		COLOR_LIGHTSLATEGREY		"778899FF"
#define		COLOR_LIGHTSTEELBLUE		"B0C4DEFF"
#define		COLOR_LIGHTYELLOW			"FFFFE0FF"
#define		COLOR_LIME					"00FF00FF"
#define		COLOR_LIMEGREEN				"32CD32FF"
#define		COLOR_LINEN					"FAF0E6FF"
#define		COLOR_MAGENTA				"FF00FFFF"
#define		COLOR_MAROON				"800000FF"
#define		COLOR_MEDIUMAQUAMARINE		"66CDAAFF"
#define		COLOR_MEDIUMBLUE			"0000CDFF"
#define		COLOR_MEDIUMORCHID			"BA55D3FF"
#define		COLOR_MEDIUMPURPLE			"9370D8FF"
#define		COLOR_MEDIUMSEAGREEN		"3CB371FF"
#define		COLOR_MEDIUMSLATEBLUE		"7B68EEFF"
#define		COLOR_MEDIUMSPRINGGREEN		"00FA9AFF"
#define		COLOR_MEDIUMTURQUOISE		"48D1CCFF"
#define		COLOR_MEDIUMVIOLETRED		"C71585FF"
#define		COLOR_MIDNIGHTBLUE			"191970FF"
#define		COLOR_MINTCREAM				"F5FFFAFF"
#define		COLOR_MISTYROSE				"FFE4E1FF"
#define		COLOR_MOCCASIN				"FFE4B5FF"
#define		COLOR_MYTHICAL				"8847FFFF" // SAME AS MYTHICAL ITEM RARITY IN DOTA 2
#define		COLOR_NAVAJOWHITE			"FFDEADFF"
#define		COLOR_NAVY					"000080FF"
#define		COLOR_NORMAL				"B2B2B2FF" // SAME AS NORMAL ITEM QUALITY IN TF2
#define		COLOR_OLDLACE				"FDF5E6FF"
#define		COLOR_OLIVE					"9EC34FFF"
#define		COLOR_OLIVEDRAB				"6B8E23FF"
#define		COLOR_ORANGE				"FFA500FF"
#define		COLOR_ORANGERED				"FF4500FF"
#define		COLOR_ORCHID				"DA70D6FF"
#define		COLOR_PALEGOLDENROD			"EEE8AAFF"
#define		COLOR_PALEGREEN				"98FB98FF"
#define		COLOR_PALETURQUOISE			"AFEEEEFF"
#define		COLOR_PALEVIOLETRED			"D87093FF"
#define		COLOR_PAPAYAWHIP			"FFEFD5FF"
#define		COLOR_PEACHPUFF				"FFDAB9FF"
#define		COLOR_PERU					"CD853FFF"
#define		COLOR_PINK					"FFC0CBFF"
#define		COLOR_PLUM					"DDA0DDFF"
#define		COLOR_POWDERBLUE			"B0E0E6FF"
#define		COLOR_PURPLE				"800080FF"
#define		COLOR_RARE					"4B69FFFF" // SAME AS RARE ITEM RARITY IN DOTA 2
#define		COLOR_RED					"FF4040FF" // SAME AS RED/TERRORIST TEAM COLOR
#define		COLOR_ROSYBROWN				"BC8F8FFF"
#define		COLOR_ROYALBLUE				"4169E1FF"
#define		COLOR_SADDLEBROWN			"8B4513FF"
#define		COLOR_SALMON				"FA8072FF"
#define		COLOR_SANDYBROWN			"F4A460FF"
#define		COLOR_SEAGREEN				"2E8B57FF"
#define		COLOR_SEASHELL				"FFF5EEFF"
#define		COLOR_SELFMADE				"70B04AFF" // SAME AS SELF-MADE ITEM QUALITY IN TF2
#define		COLOR_SIENNA				"A0522DFF"
#define		COLOR_SILVER				"C0C0C0FF"
#define		COLOR_SKYBLUE				"87CEEBFF"
#define		COLOR_SLATEBLUE				"6A5ACDFF"
#define		COLOR_SLATEGRAY				"708090FF"
#define		COLOR_SLATEGREY				"708090FF"
#define		COLOR_SNOW					"FFFAFAFF"
#define		COLOR_SPRINGGREEN			"00FF7FFF"
#define		COLOR_STEELBLUE				"4682B4FF"
#define		COLOR_STRANGE				"CF6A32FF" // SAME AS STRANGE ITEM QUALITY IN TF2
#define		COLOR_TAN					"D2B48CFF"
#define		COLOR_TEAL					"008080FF"
#define		COLOR_THISTLE				"D8BFD8FF"
#define		COLOR_TOMATO				"FF6347FF"
#define		COLOR_TURQUOISE				"40E0D0FF"
#define		COLOR_UNCOMMON				"B0C3D9FF" // SAME AS UNCOMMON ITEM RARITY IN DOTA 2
#define		COLOR_UNIQUE				"FFD700FF" // SAME AS UNIQUE ITEM QUALITY IN TF2
#define		COLOR_UNUSUAL				"8650ACFF" // SAME AS UNUSUAL ITEM QUALITY IN TF2
#define		COLOR_VALVE					"A50F79FF" // SAME AS VALVE ITEM QUALITY IN TF2
#define		COLOR_VINTAGE				"476291FF" // SAME AS VINTAGE ITEM QUALITY IN TF2
#define		COLOR_VIOLET				"EE82EEFF"
#define		COLOR_WHEAT					"F5DEB3FF"
#define		COLOR_WHITE					"FFFFFFFF"
#define		COLOR_WHITESMOKE			"F5F5F5FF"
#define		COLOR_YELLOW				"FFFF00FF"
#define		COLOR_YELLOWGREEN			"9ACD32FF"
native int Ins_ObjectiveResource_GetProp(const char[] prop, int size=4, int element=0);
//native Ins_Log(ELOG_LEVEL:level,const String:format[], any:...);
native int Ins_GetMaxClip1(int weapon);
native int Ins_GetWeaponGetMaxClip1(int weapon);
native int Ins_GetDefaultClip1(int weapon);
native int Ins_DecrementAmmo(int weapon, int value);
//native Ins_AddMags(client, value);
native float Ins_ObjectiveResource_GetPropFloat(const char[] prop, int size=4, int element=0);
native int Ins_ObjectiveResource_GetPropEnt(const char[] prop, int element=0);
native bool Ins_ObjectiveResource_GetPropBool(const char[] prop, int element=0);
native int Ins_ObjectiveResource_GetPropVector(const char[] prop, float vec[3], int element=0);
native int Ins_ObjectiveResource_GetPropString(const char[] prop, char[] buffer, int maxlen);

native bool Ins_InCounterAttack();

native int Ins_GetPlayerScore(int client);
native int Ins_GetPlayerClass(int client, char[] buffer, int maxlen);
native int Ins_GetClassName(int squad, int squad_slot);
//native GameLogic_();

native int Ins_GetWeaponName(int weaponid, char[] buffer, int maxlen);
native int Ins_GetWeaponId(char[] weapon_name);

// Team numbers. This is Insurgency specific right now
// TODO: Add support for DoI style factions, or make it load from a cfg file
enum Teams
{
	TEAM_NONE = 0,
	TEAM_SPECTATORS,
	TEAM_SECURITY,
	TEAM_INSURGENTS,
}

// Round stats for players
enum struct RoundStatFields {
	int STAT_KILLS;
	int STAT_DEATHS;
	int STAT_SHOTS;
	int STAT_HITS;
	int STAT_GRENADES;
	int STAT_CAPTURES;
	int STAT_CACHES;
	int STAT_DMG_GIVEN;
	int STAT_DMG_TAKEN;
	int STAT_TEAMKILLS;
	int STAT_SCORE;
	int STAT_SUPPRESSIONS;
	int STAT_ACCURACY;
}

// Damage hitgroups
enum Hitgroups
{
	HITGROUP_GENERIC = 0,
	HITGROUP_HEAD,
	HITGROUP_CHEST,
	HITGROUP_STOMACH,
	HITGROUP_LEFTARM,
	HITGROUP_RIGHTARM,
	HITGROUP_LEFTLEG,
	HITGROUP_RIGHTLEG,
}

// Weapon stat fields
enum struct WeaponStatFields {
	int LOG_HIT_SHOTS;
	int LOG_HIT_HITS;
	int LOG_HIT_KILLS;
	int LOG_HIT_HEADSHOTS;
	int LOG_HIT_TEAMKILLS;
	int LOG_HIT_DAMAGE;
	int LOG_HIT_DEATHS;
	int LOG_HIT_GENERIC;
	int LOG_HIT_HEAD;
	int LOG_HIT_CHEST;
	int LOG_HIT_STOMACH;
	int LOG_HIT_LEFTARM;
	int LOG_HIT_RIGHTARM;
	int LOG_HIT_LEFTLEG;
	int LOG_HIT_RIGHTLEG;
}

// Log levels
enum LOG_LEVEL {
	DEFAULT = 0,
	TRACE,
	DEBUG,
	INFO,
	WARN,
	ERROR
}

// Log level names
char g_sLogLevel[6][32] = {
	"default",
	"trace",
	"debug",
	"info",
	"warn",
	"error"
};

// Global log level variable
//new LOG_LEVEL:g_iLogLevel;
LOG_LEVEL g_iLogLevel;// = sizeof(g_sLogLevel);

/**
* Log events to console, based upon level
*
* @param level
*/
stock void InsLog(LOG_LEVEL level,const char[] format, any ...) {
	if ((level) && (level > g_iLogLevel))
		return;
	char buffer[512], sLevel[32];
	String_ToUpper(g_sLogLevel[level],sLevel,sizeof(sLevel));
	VFormat(buffer, sizeof(buffer), format, 3);
	PrintToServer("[%s] %s",sLevel,buffer);
}

/**
* 
*
* @param 
*/
stock void AddFolderToDownloadTable(const char[] Directory, bool recursive=false) {
	char FileName[64], Path[512];
	Handle Dir = OpenDirectory(Directory);
	FileType Type;
	while (ReadDirEntry(Dir, FileName, sizeof(FileName), Type))
	{
		if (Type == FileType_Directory && recursive) {
			FormatEx(Path, sizeof(Path), "%s/%s", Directory, FileName);
			AddFolderToDownloadTable(FileName,recursive);
			continue;
		}
		if (Type != FileType_File)
			continue;
		FormatEx(Path, sizeof(Path), "%s/%s", Directory, FileName);
		AddFileToDownloadsTable(Path);
	}
	return;
}

/* Returns True if the client is an ingame player, False otherwise.
* Checks are performed in the order least likely to spew an error.
*
* @return                  If the client is a valid client.
*/
stock bool IsValidClient(int client) {
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client)) {
		return false;
	}
	return true;
}

/**
* Counts the players in a team, alive or dead.
*
* @param team             Team index.
* @return                 Number of players.
*/
stock int Team_CountPlayers(int team) {
	int count = 0;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i) && GetClientTeam(i) == team) {
		count++;
		}
	}
	return count;
}

/**
* Counts the number of living players in a team.
*
* @param team             Team index.
* @return                 Number of living players.
*/
stock int Team_CountAlivePlayers(int team, bool ignorebots) {
	int count = 0;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i) && GetClientTeam(i) == team && IsPlayerAlive(i)) {
			switch (ignorebots) {
				case false: count++;
				case true: {
					if (!IsFakeClient(i)) {
						count++;
					}
				}
			}
		}
	}
	return count;
}

/**
* 
*
* @param 
*/
stock bool ClientCanSeeClient(int client, int target, float distance = 0.0, float height = 50.0) {
	float vTargetPosition[3];
	GetEntPropVector(target, Prop_Send, "m_vecOrigin", vTargetPosition);
	return ClientCanSeeVector(client,vTargetPosition,distance,height);
}

/**
* 
*
* @param 
*/
stock bool ClientCanSeeVector(int client, float vTargetPosition[3], float distance = 0.0, float height = 50.0) {
	float vClientPosition[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", vClientPosition); 
	vClientPosition[2] += height; 
	
	if (distance == 0.0 || GetVectorDistance(vClientPosition, vTargetPosition, false) < distance) {
		Handle trace = TR_TraceRayFilterEx(vClientPosition, vTargetPosition, MASK_SOLID_BRUSHONLY, RayType_EndPoint, Base_TraceFilter);

		if (TR_DidHit(trace)) {
			CloseHandle(trace);
			return (false);
		}
		CloseHandle(trace);
		return (true);
	}
	return false;
}

/**
* 
*
* @param 
*/
stock bool Base_TraceFilter(int entity, int contentsMask, any data) {
	if (entity != data)
		return (false);
	return (true);
}

/**
* 
*
* @param 
*/
stock bool IsClientInSightRange(int client, int target, float angle=90.0, float distance=0.0, bool heightcheck=true, bool negativeangle=false) {
	float targetpos[3];
//	if(!isClientConnectedIngameAlive(target))
//		ThrowError("Target is not Alive.");
	GetClientAbsOrigin(target, targetpos);
	return IsVectorInSightRange(client,targetpos,angle,distance,heightcheck,negativeangle);
}

/**
* 
*
* @param 
*/
stock bool IsVectorInSightRange(int client, float targetpos[3], float angle=90.0, float distance=0.0, bool heightcheck=true, bool negativeangle=false) {
	if (angle > 360.0 || angle < 0.0)
		ThrowError("Angle Max : 360 & Min : 0. %d isn't proper angle.", angle);
//	if(!isClientConnectedIngameAlive(client))
//		ThrowError("Client is not Alive.");
		
	float clientpos[3], anglevector[3], targetvector[3], resultangle, resultdistance;
	
	GetClientEyeAngles(client, anglevector);
	anglevector[0] = anglevector[2] = 0.0;
	GetAngleVectors(anglevector, anglevector, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(anglevector, anglevector);
	if (negativeangle)
		NegateVector(anglevector);

	GetClientAbsOrigin(client, clientpos);
	if (heightcheck && distance > 0)
		resultdistance = GetVectorDistance(clientpos, targetpos);
	clientpos[2] = targetpos[2] = 0.0;
	MakeVectorFromPoints(clientpos, targetpos, targetvector);
	NormalizeVector(targetvector, targetvector);
	
	resultangle = RadToDeg(ArcCosine(GetVectorDotProduct(targetvector, anglevector)));
	
	if (resultangle <= angle/2) {
		if(distance > 0) {
			if (!heightcheck)
				resultdistance = GetVectorDistance(clientpos, targetpos);
			if (distance >= resultdistance)
				return true;
			else
				return false;
		}
		else
			return true;
	}
	else
		return false;
}

/**
* 
*
* @param 
*/
stock int GetSendProp(const char[] sNetClass, const char[] sPropName, int iFail=1) {
	int m_iProp = FindSendPropInfo(sNetClass, sPropName);
	if (iFail) {
			if (m_iProp == -1) {
					LogError("Can't find %s::%s", sNetClass, sPropName);
			}
		}
	return m_iProp;
}


//Get and Set Ammo for storing weapons and ammo on death (reference weapon to make sure it exists)
stock int GetWeaponAmmo(int client, int weapon, int type) {
	PropType proptype = Prop_Data;
	//int ammoOffset = FindSendPropInfo("CINSPlayer", "m_iAmmo");
	int m_iPrimaryAmmoType, ammo;
	
	//return GetEntData(client, ammoOffset+(slot*4));
	// primary
	if (type == 0) {
		m_iPrimaryAmmoType = GetEntProp(weapon, proptype, "m_iPrimaryAmmoType");
		ammo = GetEntProp(client, proptype, "m_iAmmo", _, m_iPrimaryAmmoType);
	}
	 // secondary
	else if (type == 1) {
		m_iPrimaryAmmoType = GetEntProp(weapon, proptype, "m_iSecondaryAmmoType");
		ammo = GetEntProp(client, proptype, "m_iAmmo", _, m_iPrimaryAmmoType);
	}
	// grenades
	else if (type == 3) {
		m_iPrimaryAmmoType = GetEntProp(weapon, proptype, "m_iPrimaryAmmoType");
		//PrintToServer("m_iPrimaryAmmoType %d", m_iPrimaryAmmoType);
		ammo = GetEntProp(client, proptype, "m_iAmmo", _, m_iPrimaryAmmoType);
	}
	//PrintToServer("m_iPrimaryAmmoType: %i, Ammo %i", m_iPrimaryAmmoType, ammo);
	return ammo;
}

stock void SetWeaponAmmo(int client, int weapon, int ammo, int type) {
	PropType proptype = Prop_Send;
	//new ammoOffset = FindSendPropInfo("CBasePlayer", "m_iAmmo");
	int m_ammoType;

	//return GetEntData(client, ammoOffset+(slot*4));
	// primary
	if (type == 0) {
		m_ammoType = GetEntProp(weapon, proptype, "m_iPrimaryAmmoType");
		//PrintToServer("ammoOffset: %i, m_ammoType %i", ammoOffset, m_ammoType);
		SetEntProp(client, proptype, "m_iAmmo", ammo, _, m_ammoType);
	}
	// secondary
	else if (type == 1) {
		m_ammoType = GetEntProp(weapon, proptype, "m_iSecondaryAmmoType");
		SetEntProp(client, proptype, "m_iAmmo", ammo, _, m_ammoType);
	}
	// grenades
	else if (type == 3) {

	}
}

//Get / Set primary ammo count as it was when died
stock int GetPrimaryAmmo(int client, int weap, int type) {
	//new myweapons = FindSendPropInfo("CCSPlayer", "m_hMyWeapons");
	//new weap = GetEntDataEnt2(client, myweapons+ (slot*4));
	if (IsValidEntity(weap)) {
		if (type==0) {
			return GetEntData(weap, FindSendPropInfo("CBaseCombatWeapon", "m_iClip1"));
		}
		else if (type==1) {
			return GetEntData(weap, FindSendPropInfo("CBaseCombatWeapon", "m_iClip2"));
		}
	}
	return 0;
}

stock void SetPrimaryAmmo(int client, int weap, int ammo, int type) {
	//PropType proptype = Prop_Data;
	//new myweapons = FindSendPropInfo("CCSPlayer", "m_hMyWeapons");
	//new weap = GetEntDataEnt2(client, myweapons+ (slot*4));
	if (IsValidEntity(weap)) {
		if (type==0) {
			SetEntData(weap, FindSendPropInfo("CBaseCombatWeapon", "m_iClip1"), ammo, _, true);
		}
		else if (type==1) {
			SetEntData(weap, FindSendPropInfo("CBaseCombatWeapon", "m_iClip2"), ammo, _, true);
		}
	}
}


stock int GetGrenadeAmmo(int client, int grenadeType) {
	PropType proptype = Prop_Data;
	int ammo;
	////PrintToServer("grenadeType %d", grenadeType);
	ammo = GetEntProp(client, proptype, "m_iAmmo", _, grenadeType);
	return ammo;
}

stock void SetGrenadeAmmo(int client, int grenadeType, int grenadeAmount) {
	PropType proptype = Prop_Data;
	//PrintToServer("grenadeType %d, amount to set: %d", grenadeType, grenadeAmount);
	SetEntProp(client, proptype, "m_iAmmo", grenadeAmount, _, grenadeType);
}



/*
#define Gren_M67 68
#define Gren_Incen 73
#define Gren_Molot 74
#define Gren_M18 70
#define Gren_Flash 71
#define Gren_F1 69
#define Gren_IED 72
#define Gren_C4 72
#define Gren_AT4 67
#define Gren_RPG7 61
*/

stock bool ChangePlayerWeaponSlot(int iClient, int iSlot) {
	int iWeapon = GetPlayerWeaponSlot(iClient, iSlot);
	if (iWeapon > MaxClients) {
		SetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon", iWeapon);
		return true;
	}
	return false;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//									Scream Nades START
//									Scream Nades START
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

stock void PlayerGrenadeScreamRand(int client) {
	switch (GetRandomInt(0, 5)) {
		case 0: EmitSoundToAll("player/voice/botsurvival/leader/incominggrenade4.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 1: EmitSoundToAll("player/voice/botsurvival/leader/incominggrenade9.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 2: EmitSoundToAll("player/voice/botsurvival/leader/incominggrenade18.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 3: EmitSoundToAll("player/voice/botsurvival/subordinate/incominggrenade9.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 4: EmitSoundToAll("player/voice/botsurvival/subordinate/incominggrenade33.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 5: EmitSoundToAll("player/voice/botsurvival/subordinate/incominggrenade34.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
	}
}

stock void PlayerFireScreamRand(int client) {
	switch (GetRandomInt(0, 3)) {
		case 0: EmitSoundToAll("player/voice/responses/security/subordinate/damage/molotov_incendiary_detonated6.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 1: EmitSoundToAll("player/voice/responses/security/subordinate/damage/molotov_incendiary_detonated7.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 2: EmitSoundToAll("player/voice/responses/security/leader/damage/molotov_incendiary_detonated4.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 3: EmitSoundToAll("player/voice/responses/security/leader/damage/molotov_incendiary_detonated5.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
	}
}

stock void BotGrenadeScreamRand(int client) {
	switch (GetRandomInt(0, 5)) {
		case 0: EmitSoundToAll("player/voice/bot/subordinate/incominggrenade1.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 1: EmitSoundToAll("player/voice/bot/subordinate/incominggrenade2.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 2: EmitSoundToAll("player/voice/bot/subordinate/incominggrenade3.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 3: EmitSoundToAll("player/voice/bot/leader/incominggrenade11.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 4: EmitSoundToAll("player/voice/bot/leader/incominggrenade12.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 5: EmitSoundToAll("player/voice/bot/leader/incominggrenade13.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
	}
}

stock void BotFireScreamRand(int client) {
	switch (GetRandomInt(0, 2)) {
		case 0: EmitSoundToAll("player/voice/responses/insurgent/leader/damage/molotov_incendiary_detonated5.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 1: EmitSoundToAll("player/voice/responses/insurgent/leader/damage/molotov_incendiary_detonated7.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
		case 2: EmitSoundToAll("player/voice/responses/insurgent/subordinate/damage/molotov_incendiary_detonated3.ogg", client, SNDCHAN_VOICE, _, _, 1.0);
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//									Scream Nades END
//									Scream Nades END
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


stock void DisplayInstructorHint(int iTargetEntity, float fTime, float fHeight, float fRange, bool bFollow, bool bShowOffScreen, char[] sIconOnScreen, char[] sIconOffScreen, char[] sCmd, bool bShowTextAlways, int iColor[3], char[] sText) {
	int iEntity = CreateEntityByName("env_instructor_hint");
	if(iEntity <= 0)
		return;
		
	char sBuffer[32];
	FormatEx(sBuffer, sizeof(sBuffer), "%d", iTargetEntity);
	
	// Target
	DispatchKeyValue(iTargetEntity, "targetname", sBuffer);
	DispatchKeyValue(iEntity, "hint_target", sBuffer);
	
	// Static
	FormatEx(sBuffer, sizeof(sBuffer), "%d", !bFollow);
	DispatchKeyValue(iEntity, "hint_static", sBuffer);
	
	// Timeout
	FormatEx(sBuffer, sizeof(sBuffer), "%d", RoundToFloor(fTime));
	DispatchKeyValue(iEntity, "hint_timeout", sBuffer);
	
	// Height
	FormatEx(sBuffer, sizeof(sBuffer), "%d", RoundToFloor(fHeight));
	DispatchKeyValue(iEntity, "hint_icon_offset", sBuffer);
	
	// Range
	FormatEx(sBuffer, sizeof(sBuffer), "%d", RoundToFloor(fRange));
	DispatchKeyValue(iEntity, "hint_range", sBuffer);
	
	// Show off screen
	FormatEx(sBuffer, sizeof(sBuffer), "%d", !bShowOffScreen);
	DispatchKeyValue(iEntity, "hint_nooffscreen", sBuffer);
	
	// Icons
	DispatchKeyValue(iEntity, "hint_icon_onscreen", sIconOnScreen);
	DispatchKeyValue(iEntity, "hint_icon_offscreen", sIconOffScreen);
	
	// Command binding
	DispatchKeyValue(iEntity, "hint_binding", sCmd);
	
	// Show text behind walls
	FormatEx(sBuffer, sizeof(sBuffer), "%d", bShowTextAlways);
	DispatchKeyValue(iEntity, "hint_forcecaption", sBuffer);
	
	// Text color
	FormatEx(sBuffer, sizeof(sBuffer), "%d %d %d", iColor[0], iColor[1], iColor[2]);
	DispatchKeyValue(iEntity, "hint_color", sBuffer);
	
	//Text
	ReplaceString(sText, 254, "\n", " ");
	Format(sText, 254, "%s", sText);
	DispatchKeyValue(iEntity, "hint_caption", sText);

	if (fTime > 0.0) {
		Format(sBuffer, sizeof(sBuffer), "OnUser1 !self:kill::%f:1", fTime);
		SetVariantString(sBuffer);
		AcceptEntityInput(iEntity, "AddOutput");
		AcceptEntityInput(iEntity, "FireUser1");
	}
	
	DispatchSpawn(iEntity);
	AcceptEntityInput(iEntity, "ShowHint");
}
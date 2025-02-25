#pragma semicolon 1
#pragma newdecls required

// 头文件
#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <colors>
/* #include <readyup> */
#include <builtinvotes>
#include "treeutil\treeutil.sp"

#define CVAR_FLAGS FCVAR_NOTIFY
#define MAP_INFO_PATH "../../cfg/cfgogl/mapinfo.txt"
#define PROMPT_DIST 5
#define SPAWN_ATTEMPT 15
#define MENU_DISPLAY_TIME 20
#define DEBUG_ALL 1

public Plugin myinfo = 
{
	name 			= "Boss Controller",
	author 			= "CanadaRox，Sir，devilesk，Derpduck，Forgetest，Spoon，夜羽真白",
	description 	= "整合 witch_and_tankifier 与 boss_percent 与 boss_vote 的插件，战役或对抗 / 有无 mapInfo.txt 文件都允许在固定路程刷新 boss",
	version 		= "1.0.1.2 - SNAPSHOT",
	url 			= "https://steamcommunity.com/id/saku_ra/"
}

Handle tankTimer = null, witchTimer = null;
ConVar g_hVsBossBuffer, g_hVsBossFlowMin, g_hVsBossFlowMax, g_hTankCanSpawn, g_hWitchCanSpawn, g_hWitchAvoidTank, g_hVersusConsist, g_hCanVoteBoss, g_hEnablePrompt, g_hEnableDirector;
int nowTankFlow = 0, nowWitchFlow = 0, survivorPrompDist = 0, /* readyUpIndex = -1, */ versusFirstTankFlow = 0, versusFirstWitchFlow = 0, dkrFirstTankFlow = 0, dkrFirstWitchFlow = 0,
tankActFlow = -1, witchActFlow = -1, minFlow = -1, maxFlow = -1;
bool isReadyUpExist = false, isDKR = false /* , isReadyUpAdded = false */, canSetTank = false, canSetWitch = false, isLeftSafeArea = false, spawnedTank = false, spawnedWitch = false;
char curMapName[64] = {'\0'}, mapInfoPath[PLATFORM_MAX_PATH] = {'\0'};
float tankSpawnPos[3] = {0.0}, witchSpawnPos[3] = {0.0};
// 复杂数据类型
StringMap mStaticTankMaps, mStaticWitchMaps;
ArrayList lTankFlows, lWitchFlows;
KeyValues mapInfo = null;
// 其他
GlobalForward fUpdateBoss;

// 输出 boss 信息类型
enum
{
	TYPE_PLAYER,
	TYPE_ALL
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();
	if( test != Engine_Left4Dead2 )
	{
		strcopy(error, err_max, "该插件仅支持 L4D2");
		return APLRes_SilentFailure;
	}
	// 注册 witch_and_tankifier 插件的 Native
	CreateNative("IsStaticTankMap", Native_IsStaticTankMap);
	CreateNative("IsStaticWitchMap", Native_IsStaticWitchMap);
	CreateNative("IsTankPercentValid", Native_IsTankPercentValid);
	CreateNative("IsWitchPercentValid", Native_IsWitchPercentValid);
	CreateNative("IsWitchPercentBlockedForTank", Native_IsWitchPercentBlockedForTank);
	CreateNative("SetTankPercent", Native_SetTankPercent);
	CreateNative("SetWitchPercent", Native_SetWitchPercent);
	// 注册 boss_percent 插件的 Native
	CreateNative("SetTankDisabled", Native_SetTankDisabled);
	CreateNative("SetWitchDisabled", Native_SetWitchDisabled);
	/* CreateNative("UpdateBossPercents", Native_UpdateBossPercents); */
	CreateNative("GetStoredTankPercent", Native_GetStoredTankPercent);
	CreateNative("GetStoredWitchPercent", Native_GetStoredWitchPercent);
	/* CreateNative("GetReadyUpFooterIndex", Native_GetReadyUpFooterIndex); */
	CreateNative("IsDarkCarniRemix", Native_IsDarkCarniRemix);
	// 注册插件支持
	RegPluginLibrary("witch_and_tankifier");
	RegPluginLibrary("l4d_boss_percent");
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_hTankCanSpawn = CreateConVar("boss_tank_can_spawn", "1", "是否允许插件生成坦克", CVAR_FLAGS, true, 0.0, true, 1.0);
	g_hWitchCanSpawn = CreateConVar("boss_witch_can_spawn", "1", "是否允许插件生成女巫", CVAR_FLAGS, true, 0.0, true, 1.0);
	g_hWitchAvoidTank = CreateConVar("boss_witch_avoid_tank", "20", "女巫应该距离坦克刷新位置多远的路程刷新 \
	（将会以坦克刷新位置为中点，左右 / 2 距离，比如坦克在 76 刷，女巫则不能设置在 66 - 86 的路程）", CVAR_FLAGS, true, 0.0, true, 1.0);
	g_hVersusConsist = CreateConVar("boss_versus_consist", "1", "是否保持在对抗的两局中坦克女巫刷新在同一路程", CVAR_FLAGS, true, 0.0, true, 1.0);
	g_hCanVoteBoss = CreateConVar("boss_enable_vote", "1", "是否允许通过 !voteboss 等指令投票坦克女巫刷新位置", CVAR_FLAGS, true, 0.0, true, 1.0);
	g_hEnablePrompt = CreateConVar("boss_enable_prompt", "1", "在距离 boss 刷新位置前 PROMPT_DIST 开始提示生还者准备刷 boss", CVAR_FLAGS, true, 0.0, true, 1.0);
	g_hEnableDirector = CreateConVar("boss_enable_director", "0", "通过调整 director_no_bosses 决定是否允许导演系统刷新 boss", CVAR_FLAGS, true, 0.0, true, 1.0);
	g_hVsBossBuffer = FindConVar("versus_boss_buffer");
	g_hVsBossFlowMax = FindConVar("versus_boss_flow_max");
	g_hVsBossFlowMin = FindConVar("versus_boss_flow_min");
	// 初始化 KV 表，集合与字典
	fUpdateBoss = new GlobalForward("OnUpdateBosses", ET_Ignore, Param_Cell, Param_Cell);
	mStaticTankMaps = new StringMap();
	mStaticWitchMaps = new StringMap();
	lTankFlows = new ArrayList(2);
	lWitchFlows = new ArrayList(2);
	mapInfo = new KeyValues("MapInfo");
	BuildPath(Path_SM, mapInfoPath, sizeof(mapInfoPath), MAP_INFO_PATH);
	if (!FileToKeyValues(mapInfo, mapInfoPath))
	{
		delete mapInfo;
		mapInfo = null;
	}
	else
	{
		mapInfo.ImportFromFile(MAP_INFO_PATH);
	}
	// HookEvents
	HookEvent("round_start", evt_RoundStart, EventHookMode_PostNoCopy);
	// ServerCommand
	RegServerCmd("static_tank_map", Cmd_StaticTankMap);
	RegServerCmd("static_witch_map", Cmd_StaticWitchMap);
	RegServerCmd("reset_static_maps", Cmd_ResetStaticBossMap);
	// PlayerCommand
	RegConsoleCmd("sm_boss", Cmd_PrintBossPercent);
	RegConsoleCmd("sm_tank", Cmd_PrintBossPercent);
	RegConsoleCmd("sm_witch", Cmd_PrintBossPercent);
	RegConsoleCmd("sm_cur", Cmd_PrintBossPercent);
	RegConsoleCmd("sm_current", Cmd_PrintBossPercent);
	RegConsoleCmd("sm_voteboss", Cmd_BossVote);
	RegConsoleCmd("sm_bossvote", Cmd_BossVote);
	// AdminCmd
	RegAdminCmd("sm_ftank", Cmd_ForceTank, ADMFLAG_BAN);
	RegAdminCmd("sm_fwitch", Cmd_ForceWitch, ADMFLAG_BAN);
	// ChangeHook
	g_hEnableDirector.AddChangeHook(ConVarChanged_Cvars);
}
public void OnPluginEnd()
{
	UnhookEvent("round_start", evt_RoundStart, EventHookMode_PostNoCopy);
	delete mStaticTankMaps;
	delete mStaticWitchMaps;
	delete lTankFlows;
	delete lWitchFlows;
	delete mapInfo;
}

public void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (!L4D_IsVersusMode())
	{
		if (g_hEnableDirector.BoolValue)
		{
			SetCommandFlags("director_no_bosses", GetCommandFlags("director_no_bosses") & ~FCVAR_CHEAT);
			ServerCommand("director_no_bosses 0");
		}
		else
		{
			SetCommandFlags("director_no_bosses", GetCommandFlags("director_no_bosses") & ~FCVAR_CHEAT);
			ServerCommand("director_no_bosses 1");
		}
	}
}

// 检查 readyUp 插件是否存在
public void OnAllPluginsLoaded()
{
	isReadyUpExist = LibraryExists("readyup");
}
public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "readyup") == 0)
	{
		isReadyUpExist = false;
	}
}
public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "readyup") == 0)
	{
		isReadyUpExist = true;
	}
}

// 指令
public Action Cmd_StaticTankMap(int args)
{
	char mapName[64] = {'\0'};
	GetCmdArg(1, mapName, sizeof(mapName));
	mStaticTankMaps.SetValue(mapName, true);
	#if (DEBUG_ALL)
	{
		LogMessage("[Boss-Controller]：已成功添加新的静态坦克地图：%s", mapName);
	}
	#endif
	return Plugin_Handled;
}
public Action Cmd_StaticWitchMap(int args)
{
	char mapName[64] = {'\0'};
	GetCmdArg(1, mapName, sizeof(mapName));
	mStaticWitchMaps.SetValue(mapName, true);
	#if (DEBUG_ALL)
	{
		LogMessage("[Boss-Controller]：已成功添加新的静态女巫地图：%s", mapName);
	}
	#endif
	return Plugin_Handled;
}
public Action Cmd_ResetStaticBossMap(int args)
{
	mStaticTankMaps.Clear();
	mStaticWitchMaps.Clear();
	return Plugin_Handled;
}
public Action Cmd_PrintBossPercent(int client, int args)
{
	if (IsValidClient(client))
	{
		PrintBossPercent(TYPE_PLAYER, client);
	}
	else if (client == 0)
	{
		PrintToServer("[Boss-Controller]：Boss 位置查询不能用于服务器控制台");
	}
	return Plugin_Handled;
}
public Action Cmd_BossVote(int client, int args)
{
	if (!g_hCanVoteBoss.BoolValue || !IsValidClient(client) || !CheckCanVoteBoss(client))
	{
		return Plugin_Handled;
	}
	else if (args != 2)
	{
		CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}使用 !bossvote {G}<Tank> <Witch> {W}更改 Boss 刷新路程");
		CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}参数为 0 则禁止刷新 Boss，-1 则插件不接管 Boss 刷新");
		return Plugin_Handled;
	}
	char tankFlow[8] = {'\0'}, witchFlow[8] = {'\0'}, bossVoteTitle[64] = {'\0'};
	GetCmdArg(1, tankFlow, sizeof(tankFlow));
	GetCmdArg(2, witchFlow, sizeof(witchFlow));
	if (!IsInteger(tankFlow) || !IsInteger(witchFlow))
	{
		CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}请保证 Boss 刷新路程为整数路程");
		return Plugin_Handled;
	}
	tankActFlow = StringToInt(tankFlow);
	witchActFlow = StringToInt(witchFlow);
	#if (DEBUG_ALL)
	{
		LogMessage("[Boss-Controller]：路程是否有效：%b %b，是否允许更改 boss 位置：%b %b", IsValidTankFlow(tankActFlow), IsValidWitchFlow(witchActFlow, false), canSetTank, canSetWitch);
	}
	#endif
	if (IsStaticTankMap(curMapName))
	{
		canSetTank = false;
		CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}当前地图：%s 为静态坦克地图，坦克刷新路程将不会更改", curMapName);
	}
	else
	{
		canSetTank = tankActFlow > 0 ? true : false;
	}
	if (IsStaticWitchMap(curMapName))
	{
		canSetWitch = false;
		CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}当前地图：%s 为静态女巫地图，女巫刷新路程将不会更改", curMapName);
	}
	else
	{
		canSetWitch = witchActFlow > 0 ? true : false;
	}
	if ((!IsStaticTankMap(curMapName) && tankActFlow > 0 && !IsValidTankFlow(tankActFlow)) || (!IsStaticWitchMap(curMapName) && witchActFlow > 0 && !IsValidWitchFlow(witchActFlow, false)))
	{
		CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}请保证 Tank 或 Witch 刷新路程有效");
		return Plugin_Handled;
	}
	// 设置投票标题
	if (canSetTank && canSetWitch)
	{
		if (tankActFlow > 0 && witchActFlow > 0)
		{
			FormatEx(bossVoteTitle, sizeof(bossVoteTitle), "是否将 Tank 刷新在：%s%%，Witch 刷新在：%s%%", tankFlow, witchFlow);
		}
		else
		{
			FormatEx(bossVoteTitle, sizeof(bossVoteTitle), "是否禁用本轮 TanK 与 Witch 刷新");
		}
	}
	else if (canSetTank)
	{
		if (witchActFlow == 0)
		{
			FormatEx(bossVoteTitle, sizeof(bossVoteTitle), "是否将 Tank 刷新在：%s%% 并禁用本轮 Witch 刷新", tankFlow);
		}
		else
		{
			FormatEx(bossVoteTitle, sizeof(bossVoteTitle), "是否将 Tank 刷新在：%s%%", tankFlow);
		}
	}
	else if (canSetWitch)
	{
		if (tankActFlow == 0)
		{
			FormatEx(bossVoteTitle, sizeof(bossVoteTitle), "是否禁用本轮 Tank 刷新并将 Witch 刷新在：%s%%", witchFlow);
		}
		else
		{
			FormatEx(bossVoteTitle, sizeof(bossVoteTitle), "是否将 Witch 刷新在：%s%%", witchFlow);
		}
	}
	else
	{
		if (tankActFlow == 0 && witchActFlow == 0)
		{
			FormatEx(bossVoteTitle, sizeof(bossVoteTitle), "是否禁用本轮 Tank 和 Witch 刷新");
		}
		else if (tankActFlow == 0)
		{
			FormatEx(bossVoteTitle, sizeof(bossVoteTitle), "是否禁用本轮 Tank 刷新");
		}
		else if (witchActFlow == 0)
		{
			FormatEx(bossVoteTitle, sizeof(bossVoteTitle), "是否禁用本轮 Witch 刷新");
		}
		else
		{
			return Plugin_Handled;
		}
	}
	// 设置投票句柄
	if (!IsBuiltinVoteInProgress())
	{
		int playerNum = 0;
		int[] players = new int[MaxClients];
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && !IsFakeClient(i))
			{
				players[playerNum++] = i;
			}
		}
		Handle bossVoteHandler = CreateBuiltinVote(BossVote_Handler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
		SetBuiltinVoteArgument(bossVoteHandler, bossVoteTitle);
		SetBuiltinVoteInitiator(bossVoteHandler, client);
		DisplayBuiltinVote(bossVoteHandler, players, playerNum, MENU_DISPLAY_TIME);
		FakeClientCommand(client, "Vote Yes");
		CPrintToChatAll("{B}<{G}BossVote{B}>：{G}玩家 {O}%N {G}发起了一个设置 Boss 刷新路程的投票", client);
	}
	else
	{
		CPrintToChatAll("{B}<{G}BossVote{B}>：{G}当前有一个投票正在进行，无法进行新的投票");
	}
	return Plugin_Continue;
}
public int BossVote_Handler(Handle vote, BuiltinVoteAction action, int param1, int param2)
{
	switch (action)
	{
		/* 投票通过 */
		case BuiltinVoteAction_VoteEnd:
		{
			#if DEBUG_ALL
				LogMessage("[Boss-Controller]：投票结果：param1 是：%d，param2是：%d", param1, param2);
			#endif
			if (param1 == BUILTINVOTES_VOTE_YES)
			{
				char buffer[64] = {'\0'};
				/* 设置投票通过结果 */
				/* if (!IsInReady())
				{
					FormatEx(buffer, sizeof(buffer), "只允许在准备期间更改 Boss 刷新位置");
					DisplayBuiltinVoteFail(vote, buffer);
					return 0;
				} */
				if (canSetTank && canSetWitch)
				{
					FormatEx(buffer, sizeof(buffer), "正在更改 Boss 刷新路程...");
					DisplayBuiltinVotePass(vote, buffer);
				}
				else if (canSetTank)
				{
					FormatEx(buffer, sizeof(buffer), "正在更改 Tank 刷新路程...");
					DisplayBuiltinVotePass(vote, buffer);
				}
				else if (canSetWitch)
				{
					FormatEx(buffer, sizeof(buffer), "正在更改 Witch 刷新路程...");
					DisplayBuiltinVotePass(vote, buffer);
				}
				else
				{
					FormatEx(buffer, sizeof(buffer), "正在禁用本轮 Boss 刷新...");
					DisplayBuiltinVotePass(vote, buffer);
				}
				/* 更改 Boss 刷新路程 */
				SetTankPercent(tankActFlow);
				SetWitchPercent(witchActFlow);
				nowTankFlow = tankActFlow;
				nowWitchFlow = witchActFlow;
				if (tankActFlow == 0) { g_hTankCanSpawn.BoolValue = false; }
				if (witchActFlow == 0) { g_hWitchCanSpawn.BoolValue = false; }
				/* UpdateBossPercents(); */
				Call_StartForward(fUpdateBoss);
				Call_PushCell(tankActFlow);
				Call_PushCell(witchActFlow);
				Call_Finish();
			}
			else if (param1 == BUILTINVOTES_VOTE_NO)
			{
				DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
			}
			else
			{
				DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Generic);
			}
		}
		/* 投票被取消 */
		case BuiltinVoteAction_Cancel:
		{
			DisplayBuiltinVoteFail(vote, view_as<BuiltinVoteFailReason>(param1));
		}
		/* 投票结束，删除 vote 句柄 */
		case BuiltinVoteAction_End:
		{
			delete vote;
			vote = null;
		}
	}
	return 0;
}
// 管理员更改坦克女巫刷新位置
public Action Cmd_ForceTank(int client, int args)
{
	if (!g_hCanVoteBoss.BoolValue)
	{
		return Plugin_Handled;
	}
	else if (isDKR)
	{
		CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}当前地图：{O}%s {W}不允许投票更改 Boss 刷新路程", curMapName);
		return Plugin_Handled;
	}
	else if (IsStaticTankMap(curMapName))
	{
		CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}当前地图：%s 为静态坦克地图，插件不接管坦克刷新，无法投票更改坦克刷新路程", curMapName);
		return Plugin_Handled;
	}
	else if (spawnedTank)
	{
		CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}本轮坦克已经刷新完成，无法再次更改坦克刷新路程");
		return Plugin_Handled;
	}
	/* else if (!IsInReady())
	{
		CPrintToChatAll("{B}<{G}BossVote{B}>：{W}只能在准备期间投票更改 Boss 位置");
		return Plugin_Handled;
	} */
	char tankFlow[32] = {'\0'};
	GetCmdArg(1, tankFlow, sizeof(tankFlow));
	if (!IsInteger(tankFlow))
	{
		return Plugin_Handled;
	}
	int tankNewFlow = StringToInt(tankFlow);
	if (tankNewFlow < 0)
	{
		CPrintToChatAll("{B}<{G}BossVote{B}>：{W}新的坦克刷新路程必须大于等于 0");
		return Plugin_Handled;
	}
	else if (!IsValidTankFlow(tankNewFlow))
	{
		CPrintToChatAll("{B}<{G}BossVote{B}>：{W}当前坦克刷新路程：{O}%d {B}已被禁止", tankNewFlow);
		return Plugin_Handled;
	}
	SetTankPercent(tankNewFlow);
	tankActFlow = nowTankFlow = tankNewFlow;
	CPrintToChatAll("{B}<{G}BossVote{B}>：{G}管理员：{O}%N {W}更改本轮坦克刷新路程为：{O}%d", client, tankNewFlow);
	/* UpdateBossPercents(); */
	Call_StartForward(fUpdateBoss);
	Call_PushCell(tankNewFlow);
	Call_PushCell(-1);
	Call_Finish();
	return Plugin_Continue;
}
public Action Cmd_ForceWitch(int client, int args)
{
	if (!g_hCanVoteBoss.BoolValue)
	{
		return Plugin_Handled;
	}
	else if (isDKR)
	{
		CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}当前地图：{O}%s {W}不允许投票更改 Boss 刷新路程", curMapName);
		return Plugin_Handled;
	}
	else if (IsStaticWitchMap(curMapName))
	{
		CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}当前地图：%s 为静态女巫地图，插件不接管女巫刷新，无法投票更改女巫刷新路程", curMapName);
		return Plugin_Handled;
	}
	else if (spawnedWitch)
	{
		CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}本轮女巫已经刷新完成，无法再次更改女巫刷新路程");
		return Plugin_Handled;
	}
	/* else if (!IsInReady())
	{
		CPrintToChatAll("{B}<{G}BossVote{B}>：{W}只能在准备期间投票更改 Boss 位置");
		return Plugin_Handled;
	} */
	char witchFlow[32] = {'\0'};
	GetCmdArg(1, witchFlow, sizeof(witchFlow));
	if (!IsInteger(witchFlow))
	{
		return Plugin_Handled;
	}
	int witchNewFlow = StringToInt(witchFlow);
	if (witchNewFlow < 0)
	{
		CPrintToChatAll("{B}<{G}BossVote{B}>：{W}新的女巫刷新路程必须大于等于 0");
		return Plugin_Handled;
	}
	else if (!IsValidWitchFlow(witchNewFlow, false))
	{
		CPrintToChatAll("{B}<{G}BossVote{B}>：{W}当前女巫刷新路程：{O}%d {B}已被禁止", witchNewFlow);
		return Plugin_Handled;
	}
	SetWitchPercent(witchNewFlow);
	witchActFlow = nowWitchFlow = witchNewFlow;
	CPrintToChatAll("{B}<{G}BossVote{B}>：{G}管理员：{O}%N {W}更改本轮女巫刷新路程为：{O}%d", client, witchNewFlow);
	/* UpdateBossPercents(); */
	Call_StartForward(fUpdateBoss);
	Call_PushCell(-1);
	Call_PushCell(witchNewFlow);
	Call_Finish();
	return Plugin_Continue;
}

public void OnMapStart()
{
	// delete 会先进行是否为 null 检测，可直接使用 delete 删除时钟句柄
	delete tankTimer;
	delete witchTimer;
	GetCurrentMap(curMapName, sizeof(curMapName));
	isDKR = IsDKR();
	isLeftSafeArea = spawnedTank = spawnedWitch = false;
	ZeroVector(tankSpawnPos);
	ZeroVector(witchSpawnPos);
	// 重新设置导演模式
	g_hEnableDirector.IntValue = 0;
	// 非对抗模式下，且非静态 Boss 地图，接管 director_no_bosses
	if (!L4D_IsVersusMode() && !g_hEnableDirector.BoolValue && !IsStaticTankMap(curMapName) && !IsStaticWitchMap(curMapName))
	{
		#if (DEBUG_ALL)
		{
			LogMessage("[Boss-Controller]：当前非对抗模式，且非静态坦克女巫地图，不允许导演模式刷新 boss，更改 boss 刷新 Cvar：director_no_bosses 为 1");
		}
		#endif
		SetCommandFlags("director_no_bosses", GetCommandFlags("director_no_bosses") & ~FCVAR_CHEAT);
		ServerCommand("director_no_bosses 1");
	}
	// 非对抗模式下，是静态坦克地图或女巫地图，设置 director_no_bosses 为 0，允许刷新 boss，不允许刷新的则刷出来处死
	else if (!L4D_IsVersusMode() && IsStaticTankMap(curMapName) || IsStaticWitchMap(curMapName))
	{
		#if (DEBUG_ALL)
		{
			LogMessage("[Boss-Controller]：当前非对抗模式，是静态坦克或女巫地图，更改 boss 刷新 Cvar：director_no_bosses 为 0");
		}
		#endif
		SetCommandFlags("director_no_bosses", GetCommandFlags("director_no_bosses") & ~FCVAR_CHEAT);
		ServerCommand("director_no_bosses 0");
		g_hEnableDirector.IntValue = 1;
	}
}
public void OnMapEnd()
{
	versusFirstTankFlow = versusFirstWitchFlow = dkrFirstTankFlow = dkrFirstWitchFlow = nowTankFlow = nowWitchFlow = 0;
	// 每局结束，设置插件允许 boss 刷新
	g_hTankCanSpawn.BoolValue = g_hWitchCanSpawn.BoolValue = true;
}
public void evt_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	/* isReadyUpAdded = false;
	readyUpIndex = -1; */
	delete tankTimer;
	delete witchTimer;
	isLeftSafeArea = spawnedTank = spawnedWitch = false;
	nowTankFlow = nowWitchFlow = survivorPrompDist = 0;
	ZeroVector(tankSpawnPos);
	ZeroVector(witchSpawnPos);
	CreateTimer(0.5, Timer_GetBossFlow, TIMER_FLAG_NO_MAPCHANGE);
	// 更新 readyUp 面板
	/* UpdateReadyUpFooter(6.0); */
}
public Action Timer_GetBossFlow(Handle timer)
{
	// 清除集合中保存的的坦克与女巫刷新位置
	lTankFlows.Clear();
	lWitchFlows.Clear();
	// 获取设定 Boss 刷新范围
	minFlow = RoundToCeil(g_hVsBossFlowMin.FloatValue * 100.0);
	maxFlow = RoundToFloor(g_hVsBossFlowMax.FloatValue * 100.0);
	// 统一设置 minFlow 和 maxFlow
	for (int i = 1; i <= 100; i++)
	{
		lTankFlows.Push(i);
		lWitchFlows.Push(i);
		if (i < minFlow - 1 || i > maxFlow + 1)
		{
			lTankFlows.Set(i - 1, -1);
			lWitchFlows.Set(i - 1, -1);
		}
	}
	// 检查是否有 mapinfo 文件，没有则使用 Cvar min 和 max 设定值
	if (mapInfo != null)
	{
		// 如果是黑色狂欢节 remix 地图
		if (isDKR && L4D_IsVersusMode())
		{
			// 是对抗第二轮，设置第二轮坦克刷新位置为第一轮坦克刷新位置
			if (InVersusSecondRound())
			{
				nowTankFlow = dkrFirstTankFlow;
				nowWitchFlow = dkrFirstWitchFlow;
			}
			else
			{
				// 不能设置 boss 位置在黑色狂欢节 remix 这个地图，除非 boss 生成被禁用，检测 boss 生成是否被禁用
				if (!L4D2Direct_GetVSTankToSpawnThisRound(0))
				{
					if (GetTankFlow(0) * 100.0 < 1.0)
					{
						if (!g_hTankCanSpawn.BoolValue)
						{
							nowTankFlow = 0;
						}
					}
					else
					{
						nowTankFlow = dkrFirstTankFlow;
					}
				}
				if (!L4D2Direct_GetVSWitchToSpawnThisRound(0))
				{
					if (GetWitchFlow(0) * 100.0 < 1.0)
					{
						if (!g_hWitchCanSpawn.BoolValue)
						{
							nowWitchFlow = 0;
						}
					}
				}
				else
				{
					nowWitchFlow = dkrFirstWitchFlow;
				}
			}
			return Plugin_Stop;
		}
		int mapInfoMin = 0, mapInfoMax = 0;
		// 具有 mapinfo 文件，使用 mapinfo 中的信息覆盖 Boss 刷新范围
		mapInfoMin = KvGetNum(mapInfo, "versus_boss_flow_min", minFlow);
		mapInfoMax = KvGetNum(mapInfo, "versus_boss_flow_max", maxFlow);
		if (mapInfoMin != minFlow || mapInfoMax != maxFlow)
		{
			minFlow = mapInfoMin;
			maxFlow = mapInfoMax;
			lTankFlows.Clear();
			lWitchFlows.Clear();
			for (int i = 1; i <= 100; i++)
			{
				lTankFlows.Push(i);
				lWitchFlows.Push(i);
				if (i < minFlow - 1 || i > maxFlow + 1)
				{
					lTankFlows.Set(i - 1, -1);
					lWitchFlows.Set(i - 1, -1);
				}
			}
		}
		#if (DEBUG_ALL)
		{
			LogMessage("[Boss-Controller]：调整 Boss 刷新范围为：%d%% - %d%%，坦克集合长度：%d，女巫集合长度：%d", minFlow, maxFlow, lTankFlows.Length, lWitchFlows.Length);
		}
		#endif
		// 有 mapinfo 文件且允许刷新坦克，且不是静态坦克地图，可以随机一个坦克位置
		if (g_hTankCanSpawn.BoolValue && !IsStaticTankMap(curMapName))
		{
			#if (DEBUG_ALL)
			{
				LogMessage("[Boss-Controller]：当前地图：%s，非静态坦克地图，可以随机坦克位置", curMapName);
			}
			#endif
			// 可以投票设置坦克位置
			canSetTank = true;
			// 如果当前 mapinfo 文件存在当前地图的文件，则跳转到当前地图，读取 tankBanFlow
			if (mapInfo.JumpToKey(curMapName))
			{
				#if (DEBUG_ALL)
				{
					LogMessage("[Boss-Controller]：当前 mapinfo.txt 文件中存在当前地图信息：%s，进入读取信息", curMapName);
				}
				#endif
				// 读取 mapinfo 文件中的 tank ban flow 路程，MapInfo -> currentMap -> tankBanFlow -> 遍历下面的所有 min 和 max
				int interval[2] = {0};
				if (mapInfo.JumpToKey("tank_ban_flow") && mapInfo.GotoFirstSubKey())
				{
					do
					{
						interval[0] = mapInfo.GetNum("min", -1);
						interval[1] = mapInfo.GetNum("max", -1);
						#if (DEBUG_ALL)
						{
							LogMessage("[Boss-Controller]：找到了一个坦克禁止刷新路程：min %d，max %d", interval[0], interval[1]);
						}
						#endif
						// 禁止刷新距离有效，则将这个距离加入到集合中
						if (IsValidInterval(interval))
						{
							// 找到有效的禁止刷新距离，更改原集合中禁止刷新距离为 -1
							for (int i = (interval[0] - 1 < 0 ? 0 : interval[0] - 1); i < (interval[1] + 1 > 100 ? 100 : interval[1] + 1); i++)
							{
								lTankFlows.Set(i, -1);
							}
						}
					}
					while (mapInfo.GotoNextKey());
				}
				// -> mapInfo
				mapInfo.Rewind();
			}
			// 检查允许刷新集合中所有元素是否都为 -1 禁止刷新标识
			bool canSpawnTank = false;
			for (int i = 0; i < lTankFlows.Length; i++)
			{
				if (lTankFlows.Get(i) != -1)
				{
					canSpawnTank = true;
					break;
				}
			}
			if (!canSpawnTank)
			{
				// 不允许刷克时
				if (L4D_IsVersusMode()) { SetTankPercent(0); }
 				else { nowTankFlow = 0; }
				#if (DEBUG_ALL)
				{
					LogMessage("[Boss-Controller]：当前禁止刷新的路程涵盖了所有允许坦克刷新的路程，坦克将不会刷新");
				}
				#endif
			}
			else
			{
				// 允许刷克，随机一个坦克刷新位置
				nowTankFlow = GetRandomSpawnPos(lTankFlows);
				#if (DEBUG_ALL)
				{
					LogMessage("[Boss-Controller]：当前允许坦克刷新，随机一个坦克刷新位置：%d 路程", nowTankFlow);
				}
				#endif
				// 开启对抗模式刷新对齐，则记录第一轮刷新位置，第二轮时将更改为第一轮刷新位置
				if (g_hVersusConsist.BoolValue)
				{
					if (!InVersusSecondRound())
					{
						versusFirstTankFlow = nowTankFlow;
						SetTankPercent(nowTankFlow);
					}
					else
					{
						#if (DEBUG_ALL)
						{
							LogMessage("[Boss-Controller]：当前是对抗第二局，把坦克刷新位置更改为与第一局相同：%d", versusFirstTankFlow);
						}
						#endif
						nowTankFlow = versusFirstTankFlow;
						SetTankPercent(versusFirstTankFlow);
					}
				}
				else
				{
					// 没开对抗 Boss 对齐情况，直接设置坦克位置
					SetTankPercent(nowTankFlow);
				}
			}
		}
		else
		{
			// 是静态坦克地图，插件不接管刷克
			if (L4D_IsVersusMode()) { SetTankPercent(0); }
			else { nowTankFlow = 0; }
			#if (DEBUG_ALL)
			{
				LogMessage("[Boss-Controller]：当前地图：%s 是静态坦克地图，不允许坦克刷新", curMapName);
			}
			#endif
		}
		// 检查当前地图是否为静态女巫地图，不是，则随机一个女巫刷新位置
		if (g_hWitchCanSpawn.BoolValue && !IsStaticWitchMap(curMapName))
		{
			#if (DEBUG_ALL)
			{
				LogMessage("[Boss-Controller]：当前地图：%s，非静态女巫地图，可以随机女巫刷新位置", curMapName);
			}
			#endif
			// 可以投票设置女巫位置
			canSetWitch = true;
			if (mapInfo.JumpToKey(curMapName))
			{
				int interval[2] = {0};
				if (mapInfo.JumpToKey("witch_ban_flow") && mapInfo.GotoFirstSubKey())
				{
					do
					{
						interval[0] = mapInfo.GetNum("min", -1);
						interval[1] = mapInfo.GetNum("max", -1);
						#if (DEBUG_ALL)
						{
							LogMessage("[Boss-Controller]：找到了一个禁止女巫刷新的路程：min %d，max %d", interval[0], interval[1]);
						}
						#endif
						if (IsValidInterval(interval))
						{
							for (int i = (interval[0] - 1 < 0 ? 0 : interval[0] - 1); i < (interval[1] == 100 ? 100 : interval[1] + 1); i++)
							{
								lWitchFlows.Set(i, -1);
							}
						}
					}
					while (mapInfo.GotoNextKey());
				}
				mapInfo.Rewind();
			}
			// 如果开了女巫需要距离坦克一定距离刷新，则继续判断
			if (g_hWitchAvoidTank.IntValue > 0)
			{
				for (int i = nowTankFlow - (g_hWitchAvoidTank.IntValue / 2); i <= nowTankFlow + (g_hWitchAvoidTank.IntValue / 2); i++)
				{
					if (i >= 0 && i < lWitchFlows.Length) lWitchFlows.Set(i, -1);
				}
			}
			// 检查允许刷新集合中所有元素是否都为 -1 禁止刷新标识
			bool canSpawnWitch = false;
			for (int i = 0; i < lWitchFlows.Length; i++)
			{
				if (lWitchFlows.Get(i) != -1)
				{
					canSpawnWitch = true;
					break;
				}
			}
			// 此时女巫集合长度为 100，未删除 -1 元素，无需判断长度是否小于 g_hWitchAvoidTank.IntValue
			if (!canSpawnWitch)
			{
				if (L4D_IsVersusMode()) { SetWitchPercent(0); }
				else { nowWitchFlow = 0; }
				#if (DEBUG_ALL)
				{
					LogMessage("[Boss-Controller]：当前禁止刷新的路程涵盖了所有允许女巫刷新的路程，女巫将不会刷新");
				}
				#endif
			}
			else
			{
				nowWitchFlow = GetRandomSpawnPos(lWitchFlows);
				#if (DEBUG_ALL)
				{
					LogMessage("[Boss-Controller]：当前允许女巫刷新，随机一个女巫刷新位置：%d 路程", nowWitchFlow);
				}
				#endif
				// 非对抗第二轮，且开启 g_hVersusConsist 情况，记录第一轮刷新位置
				if (g_hVersusConsist.BoolValue)
				{
					if (!InVersusSecondRound())
					{
						versusFirstWitchFlow = nowWitchFlow;
						SetWitchPercent(nowWitchFlow);
					}
					else
					{
						#if (DEBUG_ALL)
						{
							LogMessage("[Boss-Controller]：当前是对抗第二局，把女巫刷新位置更改为与第一局相同：%d", versusFirstWitchFlow);
						}
						#endif
						nowWitchFlow = versusFirstWitchFlow;
						SetWitchPercent(versusFirstWitchFlow);
					}
				}
				else
				{
					SetWitchPercent(nowWitchFlow);
				}
			}
		}
		else
		{
			if (L4D_IsVersusMode()) { SetWitchPercent(0); }
			else { nowWitchFlow = 0; }
			#if (DEBUG_ALL)
			{
				LogMessage("[Boss-Controller]：当前地图：%s 是静态女巫地图，不允许女巫刷新", curMapName);
			}
			#endif
		}
	}
	else
	{
		// 设置坦克女巫允许调整为 true
		canSetTank = canSetWitch = true;
		if (!IsStaticTankMap(curMapName) && !IsStaticWitchMap(curMapName))
		{
			// 没有 mapinfo，且不是静态坦克女巫地图，直接随机一个在 minFlow 和 maxFlow 之间的位置
			nowTankFlow = GetRandomSpawnPos(lTankFlows);
			if (g_hWitchAvoidTank.IntValue > 0)
			{
				for (int i = nowTankFlow - (g_hWitchAvoidTank.IntValue / 2); i <= nowTankFlow + (g_hWitchAvoidTank.IntValue / 2); i++)
				{
					// i 大于等于 0 且小于集合长度，保证不越界，设置为 -1
					if (i >= 0 && i < lWitchFlows.Length) { lWitchFlows.Set(i, -1); }
				}
			}
			nowWitchFlow = GetRandomSpawnPos(lWitchFlows);
			if (L4D_IsVersusMode())
			{
				if (g_hVersusConsist.BoolValue)
				{
					if (!InVersusSecondRound())
					{
						versusFirstTankFlow = nowTankFlow;
						versusFirstWitchFlow = nowWitchFlow;
						SetTankPercent(nowTankFlow);
						SetWitchPercent(nowWitchFlow);
						#if (DEBUG_ALL)
						{
							LogMessage("[Boss-Controller]：当前地图：%s 不是静态坦克女巫地图，并且没有 mapinfo 文件，且为对抗模式，随机坦克位置：%d，随机女巫位置：%d", curMapName, nowTankFlow, nowWitchFlow);
						}
						#endif
					}
					else
					{
						nowTankFlow = versusFirstTankFlow;
						nowWitchFlow = versusFirstWitchFlow;
						SetTankPercent(versusFirstTankFlow);
						SetWitchPercent(versusFirstWitchFlow);
						#if (DEBUG_ALL)
						{
							LogMessage("[Boss-Controller]：当前地图：%s 不是静态坦克女巫地图，并且没有 mapinfo 文件，且为对抗模式，将坦克位置更改为与第一局相同：%d \
							将女巫位置更改为与第一局相同：%d", curMapName, versusFirstTankFlow, versusFirstWitchFlow);
						}
						#endif
					}
					return Plugin_Continue;
				}
				SetTankPercent(nowTankFlow);
				SetWitchPercent(nowWitchFlow);
				return Plugin_Continue;
			}
			#if (DEBUG_ALL)
			{
				LogMessage("[Boss-Controller]：当前地图：%s 不是静态坦克女巫地图，并且没有 mapinfo 文件，且非对抗模式，随机坦克位置：%d，随机女巫位置：%d", curMapName, nowTankFlow, nowWitchFlow);
			}
			#endif
		}
		// 当前地图是静态坦克地图且非静态女巫地图
		else if (IsStaticTankMap(curMapName) && !IsStaticWitchMap(curMapName))
		{
			if (L4D_IsVersusMode())
			{
				nowTankFlow = RoundToNearest(!InVersusSecondRound() ? L4D2Direct_GetVSTankFlowPercent(0) : L4D2Direct_GetVSTankFlowPercent(1));
				if (g_hWitchAvoidTank.IntValue > 0)
				{
					for (int i = nowTankFlow - (g_hWitchAvoidTank.IntValue / 2); i <= nowTankFlow + (g_hWitchAvoidTank.IntValue / 2); i++)
					{
						// i 大于等于 0 且小于集合长度，保证不越界，设置为 -1
						if (i >= 0 && i < lWitchFlows.Length) { lWitchFlows.Set(i, -1); }
					}
				}
				nowWitchFlow = GetRandomSpawnPos(lWitchFlows);
				if (g_hVersusConsist.BoolValue)
				{
					if (!InVersusSecondRound())
					{
						versusFirstWitchFlow = nowWitchFlow;
						SetWitchPercent(nowWitchFlow);
						#if (DEBUG_ALL)
						{
							LogMessage("[Boss-Controller]：当前非对抗第二局，并且没有 mapinfo 文件，且当前地图：%s 是静态坦克地图，随机女巫位置：%d", curMapName, nowWitchFlow);
						}
						#endif
					}
					else
					{
						nowWitchFlow = versusFirstWitchFlow;
						SetWitchPercent(versusFirstWitchFlow);
						#if (DEBUG_ALL)
						{
							LogMessage("[Boss-Controller]：当前是对抗第二局，并且没有 mapinfo 文件，且当前地图：%s 是静态坦克地图，把女巫刷新位置更改为与第一局相同：%d", curMapName, versusFirstWitchFlow);
						}
						#endif
					}
					return Plugin_Continue;
				}
				SetWitchPercent(nowWitchFlow);
			}
			else
			{
				// 不是对抗模式，获取不到当前坦克位置，直接随机女巫位置
				nowWitchFlow = GetRandomSpawnPos(lWitchFlows);
				#if (DEBUG_ALL)
				{
					LogMessage("[Boss-Controller]：当前地图：%s 是静态坦克地图且非静态女巫地图，非对抗模式，并且没有 mapinfo 文件，随机女巫位置：%d", curMapName, nowWitchFlow);
				}
				#endif
			}
		}
		else if (!IsStaticTankMap(curMapName) && IsStaticWitchMap(curMapName))
		{
			// 坦克无论在什么时候都可以随机刷新
			nowTankFlow = nowTankFlow = GetRandomSpawnPos(lTankFlows);
			// 不是静态坦克地图，对抗模式下
			if (L4D_IsVersusMode())
			{
				if (g_hVersusConsist.BoolValue)
				{
					if (!InVersusSecondRound())
					{
						versusFirstTankFlow = nowTankFlow;
						SetTankPercent(nowTankFlow);
						#if (DEBUG_ALL)
						{
							LogMessage("[Boss-Controller]：当前非对抗第二局，并且没有 mapinfo 文件，且当前地图：%s 是静态女巫地图，随机坦克位置：%d", curMapName, nowTankFlow);
						}
						#endif
					}
					else
					{
						nowTankFlow = versusFirstTankFlow;
						SetTankPercent(versusFirstTankFlow);
						#if (DEBUG_ALL)
						{
							LogMessage("[Boss-Controller]：当前是对抗第二局，并且没有 mapinfo 文件，且当前地图：%s 是静态女巫地图，把坦克刷新位置更改为与第一局相同：%d", curMapName, versusFirstTankFlow);
						}
						#endif
					}
					return Plugin_Continue;
				}
				SetTankPercent(nowTankFlow);
				return Plugin_Continue;
			}
			#if (DEBUG_ALL)
			{
				LogMessage("[Boss-Controller]：当前地图：%s 是静态女巫地图且非静态坦克地图，非对抗模式，并且没有 mapinfo 文件，随机坦克位置：%d", curMapName, nowTankFlow);
			}
			#endif
		}
	}
	return Plugin_Stop;
}
// 在坦克刷新位置发生变化的时候，此时 tankFlow 有效，动态调整女巫刷新位置
void DynamicAdjustWtichPercent(int tankFlow)
{
	if (g_hWitchCanSpawn.BoolValue)
	{
		// 全路段禁止刷新女巫，则直接设置为 0
		if (lWitchFlows.Length == 0)
		{
			#if (DEBUG_ALL)
			{
				LogMessage("[Boss-Controller]：坦克位置即将发生变化，新位置：%d，且禁止刷新的路程涵盖了所有允许女巫刷新的路程，女巫将不会刷新", tankFlow);
			}
			#endif
			if (L4D_IsVersusMode()) { SetWitchPercent(0); }
			else { nowWitchFlow = 0; }
			return;
		}
		int newWitchFlow = -1;
		if (L4D_IsVersusMode()) { newWitchFlow = RoundFloat(L4D2Direct_GetVSWitchFlowPercent(0) * 100); }
		else { newWitchFlow = nowWitchFlow; }
		if (g_hWitchAvoidTank.IntValue > 0)
		{
			// 找到新的被坦克位置阻挡的女巫范围，如果在集合中能找到索引，设置为 -1，否则跳出
			for (int i = tankFlow + (g_hWitchAvoidTank.IntValue / 2); i >= tankFlow - (g_hWitchAvoidTank.IntValue / 2); i--)
			{
				if (i >= 0 && i < lWitchFlows.Length) { lWitchFlows.Set(i, -1); }
			}
			// 找到原来被坦克范围阻挡的不能刷女巫的范围重新调整为可以刷女巫，此时集合已经处理完毕，需要在 minFlow 和 maxFlow 之间进行添加，而不是 0 - 100
			int interval[2] = {0};
			if (GetTankAvoidInterval(interval) && IsValidInterval(interval))
			{
				interval[0] = interval[0] - 1 < minFlow ? minFlow : interval[0] - 1;
				interval[1] = interval[1] + 1 > maxFlow ? maxFlow : interval[1] + 1;
				for (int i = interval[0]; i < interval[1]; i++)
				{
					lWitchFlows.Push(i);
				}
			}
			lWitchFlows.Sort(Sort_Descending, Sort_Integer);
		}
		bool canSpawnWitch = false;
		for (int i = 0; i < lWitchFlows.Length; i++)
		{
			if (lWitchFlows.Get(i) > -1)
			{
				canSpawnWitch = true;
				break;
			}
		}
		if (!canSpawnWitch)
		{
			#if (DEBUG_ALL)
			{
				LogMessage("[Boss-Controller]：坦克位置即将发生变化，新位置：%d，且禁止刷新的路程涵盖了所有允许女巫刷新的路程，女巫将不会刷新", tankFlow);
			}
			#endif
			if (L4D_IsVersusMode()) { SetWitchPercent(0); }
			else { newWitchFlow = nowWitchFlow = 0; }
			return;
		}
		newWitchFlow = GetRandomSpawnPos(lWitchFlows);
		if (L4D_IsVersusMode()) { SetWitchPercent(newWitchFlow); }
		else { nowWitchFlow = newWitchFlow; }
	}
}
// 生还者离开安全区域后，如果不是对抗模式，则创建时钟检测生还者路程
public Action L4D_OnFirstSurvivorLeftSafeArea(int client)
{
	if (g_hTankCanSpawn.BoolValue && !IsStaticTankMap(curMapName) && nowTankFlow > 0)
	{
		delete tankTimer;
		tankTimer = CreateTimer(0.5, Timer_SpawnTank, _, TIMER_REPEAT);
	}
	if (g_hWitchCanSpawn.BoolValue && !IsStaticWitchMap(curMapName) && nowWitchFlow > 0)
	{
		delete witchTimer;
		witchTimer = CreateTimer(0.5, Timer_SpawnWitch, _, TIMER_REPEAT);
	}
	PrintBossPercent(TYPE_ALL);
	if (!isReadyUpExist)
	{
		dkrFirstTankFlow = nowTankFlow;
		dkrFirstWitchFlow = nowWitchFlow;
	}
	isLeftSafeArea = true;
	return Plugin_Continue;
}
public Action Timer_SpawnTank(Handle timer)
{
	if (g_hTankCanSpawn.BoolValue && !IsStaticTankMap(curMapName))
	{
		int survivorDist = GetSurvivorFlow();
		if (!L4D_IsVersusMode() && survivorDist >= nowTankFlow && !spawnedTank)
		{
			SpawnBoss(view_as<int>(ZC_TANK));
			tankTimer = null;
			return Plugin_Stop;
		}
		else if (L4D_IsVersusMode() && survivorDist >= nowTankFlow && !spawnedTank)
		{
			// 对抗模式下，超过这个距离就算刷出了，设置 spawned 为真，结束时钟前，先将句柄设置为 null，防止计时器已经停止但仍然记录不为 null 的情况，删除出错
			spawnedTank = true;
			tankTimer = null;
			return Plugin_Stop;
		}
		else if (g_hEnablePrompt.BoolValue && (nowTankFlow - PROMPT_DIST <= survivorDist < nowTankFlow) && survivorDist >= survivorPrompDist)
		{
			CPrintToChatAll("{LG}当前：{O}%d%%，{LG}Tank 将于：{O}%d%% {LG}位置刷新", survivorDist, nowTankFlow);
			survivorPrompDist = survivorDist + 1;
		}
	}
	else
	{
		tankTimer = null;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}
public Action Timer_SpawnWitch(Handle timer)
{
	if (g_hWitchCanSpawn.BoolValue && !IsStaticWitchMap(curMapName))
	{
		int survivorDist = GetSurvivorFlow();
		if (!L4D_IsVersusMode() && survivorDist >= nowWitchFlow && !spawnedWitch)
		{
			SpawnBoss(view_as<int>(ZC_WITCH));
			witchTimer = null;
			return Plugin_Stop;
		}
		else if (L4D_IsVersusMode() && survivorDist >= nowWitchFlow && !spawnedWitch)
		{
			spawnedWitch = true;
			witchTimer = null;
			return Plugin_Stop;
		}
		else if (g_hEnablePrompt.BoolValue && (nowWitchFlow - PROMPT_DIST <= survivorDist < nowWitchFlow) && survivorDist >= survivorPrompDist)
		{
			CPrintToChatAll("{LG}当前：{O}%d%%，{LG}Witch 将于：{O}%d%% {LG}位置刷新", survivorDist, nowWitchFlow);
			survivorPrompDist = survivorDist + 1;
		}
	}
	else
	{
		witchTimer = null;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}
void SpawnBoss(int class)
{
	float spawnPos[3] = {0.0};
	int count = 0;
	for (int i = 0; i < SPAWN_ATTEMPT; i++)
	{
		count++;
		int target = L4D_GetHighestFlowSurvivor();
		if (IsValidSurvivor(target))
		{
			if (L4D_GetRandomPZSpawnPosition(target, class, SPAWN_ATTEMPT, spawnPos))
			{
				#if (DEBUG_ALL)
				{
					LogMessage("[Boss-Controller]：找到一个有效的 %s 刷新位置：%.2f %.2f %.2f", class == ZC_TANK ? "坦克" : "女巫", spawnPos[0], spawnPos[1], spawnPos[2]);
				}
				#endif
				// 找到刷新位置，并复制给相应的 spawnPos，跳出
				class == ZC_TANK ? CopyVectors(spawnPos, tankSpawnPos) : CopyVectors(spawnPos, witchSpawnPos);
				break;
			}
		}
	}
	if (count >= SPAWN_ATTEMPT)
	{
		#if (DEBUG_ALL)
		{
			LogMessage("[Boss-Controller]：找位：%d 次，无法找到刷新 boss 序号：%d 的位置，停止刷新", SPAWN_ATTEMPT, class);
		}
		#endif
		return;
	}
	if (class == view_as<int>(ZC_TANK))
	{
		int tankId = L4D2_SpawnTank(spawnPos, NULL_VECTOR);
		if (IsValidEntity(tankId) && IsValidEdict(tankId))
		{
			spawnedTank = true;
			// 刷新后，重置 spawnPos
			ZeroVector(tankSpawnPos);
			#if (DEBUG_ALL)
			{
				LogMessage("[Boss-Controller]：已在：%.2f %.2f %.2f 位置刷新坦克，坦克 ID：%d", spawnPos[0], spawnPos[1], spawnPos[2], tankId);
			}
			#endif
		}
	}
	else if (class == view_as<int>(ZC_WITCH))
	{
		int witchId = L4D2_SpawnWitch(spawnPos, NULL_VECTOR);
		if (IsValidEntity(witchId) && IsValidEdict(witchId))
		{
			spawnedWitch = true;
			ZeroVector(witchSpawnPos);
			#if (DEBUG_ALL)
			{
				LogMessage("[Boss-Controller]：已在：%.2f %.2f %.2f 位置刷新女巫，女巫 ID：%d", spawnPos[0], spawnPos[1], spawnPos[2], witchId);
			}
			#endif
		}
	}
}
void PrintBossPercent(int type, int client = -1)
{
	char tankStr[64] = {'\0'}, witchStr[64] = {'\0'};
	char hasSpawnedTank[32] = {'\0'}, hasSpawnedWitch[32] = {'\0'};
	spawnedTank == true ? FormatEx(hasSpawnedTank, sizeof(hasSpawnedTank), "已刷新") : FormatEx(hasSpawnedTank, sizeof(hasSpawnedTank), "未刷新");
	spawnedWitch == true ? FormatEx(hasSpawnedWitch, sizeof(hasSpawnedWitch), "已刷新") : FormatEx(hasSpawnedWitch, sizeof(hasSpawnedWitch), "未刷新");
	if (nowTankFlow > 0)
	{
		FormatEx(tankStr, sizeof(tankStr), "{G}Tank 刷新：{O}%d%%（%s）", nowTankFlow, hasSpawnedTank);
	}
	else if (!g_hTankCanSpawn.BoolValue)
	{
		FormatEx(tankStr, sizeof(tankStr), "{G}Tank：{O}禁止刷新");
	}
	else if (IsStaticTankMap(curMapName))
	{
		FormatEx(tankStr, sizeof(tankStr), "{G}Tank：{O}固定（Static）");
	}
	else
	{
		FormatEx(tankStr, sizeof(tankStr), "{G}Tank：{O}默认（Default）");
	}
	// Witch
	if (nowWitchFlow > 0)
	{
		FormatEx(witchStr, sizeof(witchStr), "{G}Witch 刷新：{O}%d%%（%s）", nowWitchFlow, hasSpawnedWitch);
	}
	else if (!g_hWitchCanSpawn.BoolValue)
	{
		FormatEx(witchStr, sizeof(witchStr), "{G}Witch：{O}禁止刷新");
	}
	else if (IsStaticWitchMap(curMapName))
	{
		FormatEx(witchStr, sizeof(witchStr), "{G}Witch：{O}固定（Static）");
	}
	else
	{
		FormatEx(witchStr, sizeof(witchStr), "{G}Witch：{O}默认（Default）");
	}
	// 整合两个字符串
	if (g_hTankCanSpawn.BoolValue && g_hWitchCanSpawn.BoolValue)
	{
		if (type == TYPE_PLAYER && IsValidClient(client))
		{
			CPrintToChat(client, "{G}当前：{O}%d%%", GetSurvivorFlow());
			CPrintToChat(client, "%s", tankStr);
			CPrintToChat(client, "%s", witchStr);
		}
		else
		{
			CPrintToChatAll("{G}当前：{O}%d%%", GetSurvivorFlow());
			CPrintToChatAll("%s", tankStr);
			CPrintToChatAll("%s", witchStr);
		}
	}
	else if (g_hTankCanSpawn.BoolValue)
	{
		if (type == TYPE_PLAYER && IsValidClient(client))
		{
			CPrintToChat(client, "{G}当前：{O}%d%%", GetSurvivorFlow());
			CPrintToChat(client, "%s", tankStr);
		}
		else
		{
			CPrintToChatAll("{G}当前：{O}%d%%", GetSurvivorFlow());
			CPrintToChatAll("%s", tankStr);
		}
	}
	else if (g_hWitchCanSpawn.BoolValue)
	{
		if (type == TYPE_PLAYER && IsValidClient(client))
		{
			CPrintToChat(client, "{G}当前：{O}%d%%", GetSurvivorFlow());
			CPrintToChat(client, "%s", witchStr);
		}
		else
		{
			CPrintToChatAll("{G}当前：{O}%d%%", GetSurvivorFlow());
			CPrintToChatAll("%s", witchStr);
		}
	}
	/* Tank 和 Witch 都禁止刷新的情况 */
	else
	{
		if (type == TYPE_PLAYER && IsValidClient(client))
		{
			CPrintToChat(client, "{G}当前：{O}%d%%", GetSurvivorFlow());
			CPrintToChat(client, "%s", tankStr);
			CPrintToChat(client, "%s", witchStr);
		}
		else
		{
			CPrintToChatAll("{G}当前：{O}%d%%", GetSurvivorFlow());
			CPrintToChatAll("%s", tankStr);
			CPrintToChatAll("%s", witchStr);
		}
	}
}
// 判断是否可以进行 boss 投票
bool CheckCanVoteBoss(int client)
{
	if (IsValidClient(client))
	{
		if (isDKR)
		{
			CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}当前地图：{O}%s {W}不允许投票更改 Boss 刷新路程", curMapName);
			return false;
		}
		if (isLeftSafeArea)
		{
			CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}当前已离开本地图起始安全区域，不允许投票更改 Boss 刷新路程");
			return false;
		}
		/* if (isReadyUpExist && !IsInReady())
		{
			CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}只能在准备期间投票更改 Boss 位置");
			return false;
		} */
		if (InVersusSecondRound())
		{
			CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}当前是对抗第二轮，不允许更改 Boss 刷新路程");
			return false;
		}
		if (GetClientTeam(client) == view_as<int>(TEAM_SPECTATOR))
		{
			CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}旁观者不允许更改 Boss 刷新路程");
			return false;
		}
		if (!IsNewBuiltinVoteAllowed())
		{
			CPrintToChat(client, "{B}<{G}BossVote{B}>：{W}当前暂时不允许发起新的投票更改 Boss 刷新路程");
			return false;
		}
		return true;
	}
	return false;
}

// 方法
bool IsStaticTankMap(const char[] mapName)
{
	bool result = false;
	if (mStaticTankMaps.GetValue(mapName, result))
	{
		return result;
	}
	return false;
}
bool IsStaticWitchMap(const char[] mapName)
{
	bool result = false;
	if (mStaticWitchMaps.GetValue(mapName, result))
	{
		return result;
	}
	return false;
}
// 是否有效禁止刷新路程，最小路程要大于 -1 且最大路程大于等于最小路程，则有效
bool IsValidInterval(int interval[2])
{
	return interval[0] > -1 && interval[0] <= 100 && interval[1] >= interval[0] && interval[1] <= 100;
}
// 设置坦克刷新位置
void SetTankPercent(int percent)
{
	if (percent == 0)
	{
		L4D2Direct_SetVSTankFlowPercent(0, 0.0);
		L4D2Direct_SetVSTankFlowPercent(1, 0.0);
		L4D2Direct_SetVSTankToSpawnThisRound(0, false);
		L4D2Direct_SetVSTankToSpawnThisRound(1, false);
	}
	else
	{
		float newPercent = (float(percent) / 100.0);
		L4D2Direct_SetVSTankFlowPercent(0, newPercent);
		L4D2Direct_SetVSTankFlowPercent(1, newPercent);
		L4D2Direct_SetVSTankToSpawnThisRound(0, true);
		L4D2Direct_SetVSTankToSpawnThisRound(1, true);
	}
}
// 设置女巫刷新位置
void SetWitchPercent(int percent) {
	if (percent == 0)
	{
		L4D2Direct_SetVSWitchFlowPercent(0, 0.0);
		L4D2Direct_SetVSWitchFlowPercent(1, 0.0);
		L4D2Direct_SetVSWitchToSpawnThisRound(0, false);
		L4D2Direct_SetVSWitchToSpawnThisRound(1, false);
	}
	else
	{
		float newPercent = (float(percent) / 100);
		L4D2Direct_SetVSWitchFlowPercent(0, newPercent);
		L4D2Direct_SetVSWitchFlowPercent(1, newPercent);
		L4D2Direct_SetVSWitchToSpawnThisRound(0, true);
		L4D2Direct_SetVSWitchToSpawnThisRound(1, true);
	}
}
bool GetTankAvoidInterval(int interval[2])
{
	if (g_hWitchAvoidTank.FloatValue != 0.0)
	{
		// 使用当前坦克位置计算，静态坦克地图为 0，非静态坦克地图则一定大于 0
		float flow = 0.0;
		if (nowTankFlow > 0) { flow = float(nowTankFlow); }
		if (flow != 0.0)
		{
			interval[0] = RoundToFloor((flow * 100.0) - (g_hWitchAvoidTank.FloatValue / 2.0));
			interval[1] = RoundToCeil((flow * 100.0) + (g_hWitchAvoidTank.FloatValue / 2.0));
			return true;
		}
		return false;
	}
	return false;
}
// 随机刷新位置
int GetRandomSpawnPos(ArrayList arr)
{
	// 对集合进行降序排序，如果有 -1 禁止刷新标识，则会排在后前面，遍历集合获取有效长度，截断
	int validLen = 0;
	arr.Sort(Sort_Descending, Sort_Integer);
	for (int i = 0; i < arr.Length; i++)
	{
		// 如果有禁止刷新标识，则去除这一元素
		if (arr.Get(i) != -1)
		{
			validLen += 1;
		}
	}
	arr.Resize(validLen);
	return arr.Get(GetURandomIntInRange(0, arr.Length - 1));
}
// GetRandomInt 会有约 4% 误差，不是等概率随机数发生器，这种方法可以将误差降低到 2% 左右
int GetURandomIntInRange(int min, int max)
{
	return (GetURandomInt() % (max - min + 1)) + min;
}
bool IsValidTankFlow(int flow)
{
	return (flow >= 0 && lTankFlows.Length > 0 && flow <= lTankFlows.Get(0) && flow >=lTankFlows.Get(lTankFlows.Length - 1));
}
bool IsValidWitchFlow(int flow, bool ignoreBlock)
{
	if (ignoreBlock)
	{
		return (flow >= 0 && lWitchFlows.Length > 0 && flow <= lWitchFlows.Get(0) && flow >= lWitchFlows.Get(lWitchFlows.Length - 1));
	}
	else
	{
		int interval[2] = {0};
		if (GetTankAvoidInterval(interval) && IsValidInterval(interval))
		{
			#if (DEBUG_ALL)
			{
				LogMessage("[Boss-Controller]：检测当前女巫路程是否有效，禁止刷新坦克路程：%d - %d，flow 是否大于 0：%b，集合长度大于 0：%b，是否小于 Get(0)：%b，是否大于 Get(n - 1)：%b，\
				flow 是否在 interval 外：%b", interval[0], interval[1], flow >= 0, lWitchFlows.Length > 0, flow <= lWitchFlows.Get(0), flow >= lWitchFlows.Get(lWitchFlows.Length - 1), (flow <= interval[0] - 1 || flow >= interval[1] + 1));
			}
			#endif
			return (flow >= 0 && lWitchFlows.Length > 0 && flow <= lWitchFlows.Get(0) && flow >= lWitchFlows.Get(lWitchFlows.Length - 1) && (flow <= interval[0] - 1 || flow >= interval[1] + 1));
		}
		return (flow >= 0 && lWitchFlows.Length > 0 && flow <= lWitchFlows.Get(0) && flow >= lWitchFlows.Get(lWitchFlows.Length - 1));
	}
}

// Boss 刷新控制
public Action L4D_OnSpawnTank(const float vecPos[3], const float vecAng[3])
{
	if (g_hTankCanSpawn.BoolValue)
	{
		// 非对抗模式下，允许坦克刷新且非静态坦克地图，且是静态女巫地图，插件可以接管坦克刷新，此时 director_no_bosses 设置为 0，判断是否插件刷新的克，不是则阻止生成
		// 允许刷坦克，允许刷女巫且都是静态地图时，返回 Plugin_Continue 可刷新
		if (!L4D_IsVersusMode() && (!IsStaticTankMap(curMapName) && IsStaticWitchMap(curMapName)) && IsZeroVector(tankSpawnPos))
		{
			#if (DEBUG_ALL)
			{
				LogMessage("[Boss-Controller]：当前找到了一个非插件刷出来的坦克，当前地图：%s 是静态女巫地图，位置是：%.2f %.2f %.2f，禁止刷新", curMapName, vecPos[0], vecPos[1], vecPos[2]);
			}
			#endif
			return Plugin_Handled;
		}
		return Plugin_Continue;
	}
	// 坦克不允许刷新时，阻止生成
	return Plugin_Handled;
}
public Action L4D_OnSpawnWitch(const float vecPos[3], const float vecAng[3])
{
	if (g_hWitchCanSpawn.BoolValue)
	{
		if (!L4D_IsVersusMode() && (IsStaticTankMap(curMapName) && !IsStaticWitchMap(curMapName)) && IsZeroVector(witchSpawnPos)) { return Plugin_Handled; }
		return Plugin_Continue;
	}
	return Plugin_Handled;
}
public Action L4D2_OnSpawnWitchBride(const float vecPos[3], const float vecAng[3])
{
	if (g_hWitchCanSpawn.BoolValue)
	{
		if (!L4D_IsVersusMode() && (IsStaticTankMap(curMapName) && !IsStaticWitchMap(curMapName)) && IsZeroVector(witchSpawnPos)) { return Plugin_Handled; }
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

// 提供 Native
public int Native_IsStaticTankMap(Handle plugins, int numParams)
{
	char mapName[64] = {'\0'};
	GetNativeString(1, mapName, sizeof(mapName));
	return IsStaticTankMap(mapName);
}
public int Native_IsStaticWitchMap(Handle plugins, int numParams)
{
	char mapName[64] = {'\0'};
	GetNativeString(1, mapName, sizeof(mapName));
	return IsStaticWitchMap(mapName);
}
public int Native_SetTankPercent(Handle plugin, int numParams)
{
	int flow = GetNativeCell(1);
	if (flow >= 0 && lTankFlows.Length > 0 && flow >= lTankFlows.Get(0) && flow <= lTankFlows.Get(lTankFlows.Length - 1))
	{
		DynamicAdjustWtichPercent(flow);
		SetTankPercent(flow);
		return true;
	}
	return false;
}
public int Native_SetWitchPercent(Handle plugin, int numParams)
{
	int flow = GetNativeCell(1);
	if (flow >= 0 && lWitchFlows.Length > 0 && flow >= lWitchFlows.Get(0) && flow <= lWitchFlows.Get(lWitchFlows.Length - 1))
	{
		SetWitchPercent(flow);
		return true;
	}
	return false;
}
public int Native_IsWitchPercentBlockedForTank(Handle plugin, int numParams)
{
	int interval[2] = {0};
	if (GetTankAvoidInterval(interval) && IsValidInterval(interval))
	{
		int flow = GetNativeCell(1);
		return (interval[0] <= flow <= interval[1]);
	}
	return false;
}
public int Native_IsTankPercentValid(Handle plugin, int numParams)
{
	int flow = GetNativeCell(1);
	return IsValidTankFlow(flow);
}
public int Native_IsWitchPercentValid(Handle plugin, int numParams)
{
	int flow = GetNativeCell(1);
	bool ignoreBlock = GetNativeCell(2);
	return IsValidWitchFlow(flow, ignoreBlock);
}
// boss_percent 的 Native
/* public int Native_UpdateBossPercents(Handle plugin, int numParams)
{
	UpdateReadyUpFooter(0.2);
	return 0;
} */
public int Native_SetTankDisabled(Handle plugin, int numParams)
{
	g_hTankCanSpawn.BoolValue = view_as<bool>(GetNativeCell(1));
	/* UpdateReadyUpFooter(); */
	return 0;
}
public int Native_SetWitchDisabled(Handle plugin, int numParams)
{
	g_hWitchCanSpawn.BoolValue = view_as<bool>(GetNativeCell(1));
	/* UpdateReadyUpFooter(); */
	return 0;
}
public int Native_IsDarkCarniRemix(Handle plugin, int numParams)
{
	return isDKR;
}
public int Native_GetStoredTankPercent(Handle plugin, int numParams)
{
	return nowTankFlow;
}
public int Native_GetStoredWitchPercent(Handle plugin, int numParams)
{
	return nowWitchFlow;
}
/* public int Native_GetReadyUpFooterIndex(Handle plugin, int numParams)
{
	if (isReadyUpExist)
	{
		return readyUpIndex;
	}
	return -1;
}
public int Native_RefreshReadyUp(Handle plugin, int numParams)
{
	if (isReadyUpExist)
	{
		UpdateReadyUpFooter();
		return true;
	}
	return false;
} */

int GetSurvivorFlow()
{
	static float survivorDistance;
	static int furthestSurvivor;
	furthestSurvivor = L4D_GetHighestFlowSurvivor();
	if (!IsValidSurvivor(furthestSurvivor)) { survivorDistance = L4D2_GetFurthestSurvivorFlow(); }
	else { survivorDistance = L4D2Direct_GetFlowDistance(furthestSurvivor); }
	return RoundToNearest(survivorDistance / L4D2Direct_GetMapMaxFlowDistance() * 100.0);
}
// 判断是否黑色狂欢节 remix 地图
bool IsDKR()
{
	if (strcmp(curMapName, "dkr_m1_motel") == 0 || strcmp(curMapName, "dkr_m2_carnival") == 0 || strcmp(curMapName, "dkr_m3_tunneloflove") == 0 || strcmp(curMapName, "dkr_m4_ferris") == 0 || strcmp(curMapName, "dkr_m5_stadium") == 0)
	{
		return true;
	}
	return false;
}
bool IsInteger(const char[] buffer)
{
	if (!IsCharNumeric(buffer[0]) && buffer[0] != '-')
	{
		return false;
	}
	for (int i = 1; i < strlen(buffer); i++)
	{
		if (!IsCharNumeric(buffer[i]))
		{
			return false;
		}
	}
	return true;
}

// 其他功能
stock float GetTankFlow(int round)
{
	return L4D2Direct_GetVSTankFlowPercent(round);
}
stock float GetWitchFlow(int round)
{
	return L4D2Direct_GetVSWitchFlowPercent(round);
}
stock float GetTankProgressFlow(int round)
{
	return L4D2Direct_GetVSTankFlowPercent(round) - GetBossBuffer();
}
stock float GetWitchProgressFlow(int round)
{
	return L4D2Direct_GetVSWitchFlowPercent(round) - GetBossBuffer();
}
stock float GetBossBuffer()
{
	return g_hVsBossBuffer.FloatValue / L4D2Direct_GetMapMaxFlowDistance();
}

// 其他插件支持
// readyUp 插件面板显示坦克女巫位置
/* public void OnRoundIsLive()
{
	PrintBossPercent(TYPE_ALL);
	if (isDKR && !InVersusSecondRound())
	{
		dkrFirstTankFlow = nowTankFlow;
		dkrFirstWitchFlow = nowWitchFlow;
	}
}
void UpdateReadyUpFooter(float interval = 0.1)
{
	float prevTime = 0.0;
	if (prevTime == 0.0)
	{
		prevTime = GetEngineTime();
	}
	float time = GetEngineTime() + interval;
	if (time < prevTime)
	{
		return;
	}
	prevTime = time;
	CreateTimer(interval, Timer_UpdateReadyUpFooter);
}
public Action Timer_UpdateReadyUpFooter(Handle timer)
{
	if (isReadyUpExist)
	{
		char tankStr[32] = {'\0'}, witchStr[32] = {'\0'}, mergeStr[65] = {'\0'};
		if (nowTankFlow > 0 && !IsStaticTankMap(curMapName))
		{
			FormatEx(tankStr, sizeof(tankStr), "Tank：%d%%", nowTankFlow);
		}
		else if (!g_hTankCanSpawn.BoolValue)
		{
			FormatEx(tankStr, sizeof(tankStr), "Tank：禁止刷新");
		}
		else if (IsStaticTankMap(curMapName))
		{
			FormatEx(tankStr, sizeof(tankStr), "Tank：固定");
		}
		else
		{
			FormatEx(tankStr, sizeof(tankStr), "Tank：默认");
		}
		// Witch
		if (nowWitchFlow > 0 && !IsStaticWitchMap(curMapName))
		{
			FormatEx(witchStr, sizeof(witchStr), "Witch：%d%%", nowWitchFlow);
		}
		else if (!g_hWitchCanSpawn.BoolValue)
		{
			FormatEx(witchStr, sizeof(witchStr), "Witch：禁止刷新");
		}
		else if (IsStaticWitchMap(curMapName))
		{
			FormatEx(witchStr, sizeof(witchStr), "Witch：固定");
		}
		else
		{
			FormatEx(witchStr, sizeof(witchStr), "Witch：默认");
		}
		// 整合两个字符串
		if (g_hTankCanSpawn.BoolValue && g_hWitchCanSpawn.BoolValue)
		{
			FormatEx(mergeStr, sizeof(mergeStr), "%s，%s", tankStr, witchStr);
		}
		else if (g_hTankCanSpawn.BoolValue)
		{
			FormatEx(mergeStr, sizeof(mergeStr), "%s", tankStr);
		}
		else if (g_hWitchCanSpawn.BoolValue)
		{
			FormatEx(mergeStr, sizeof(mergeStr), "%s", witchStr);
		}
		// 添加到 readyUp 面板中
		if (isReadyUpAdded)
		{
			EditFooterStringAtIndex(readyUpIndex, mergeStr);
		}
		else
		{
			readyUpIndex = AddStringToReadyFooter(mergeStr);
			isReadyUpAdded = true;
		}
	}
	return Plugin_Continue;
} */
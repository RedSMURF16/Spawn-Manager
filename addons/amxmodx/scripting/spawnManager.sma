/*
*
*	Spawn Manager by RedSMURF
*
*
*	Description:
*
*	Cvars:
*		None
*
*	Commands:
*       say /sm                 "Opens the Spawn menu."
*       say_team /sm            "Opens the Spawn menu."
*       say /spawn              "Opens the Spawn menu."
*       say_team /spawn         "Opens the Spawn menu."
*       sm_reload               "Reloads the configuration file."
*       spawn_reload            "Reloads the configuration file."
*
*	Changelog:
*       v1.0: Initial release.
*
*/

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <engine>
#include <fakemeta>
#include <fun>
#include <hamsandwich>
#include <xs>

#if !defined MAX_PLAYERS
    #define MAX_PLAYERS 32
#endif

#if !defined MAX_VALUE_LENGTH
    #define MAX_VALUE_LENGTH 64
#endif

#if !defined MAX_RESOURCE_PATH_LENGTH
    #define MAX_RESOURCE_PATH_LENGTH 128
#endif

#if !defined MAX_FILE_CELL_SIZE
    #define MAX_FILE_CELL_SIZE 192
#endif

#if !defined MAX_PLATFORM_PATH_LENGTH
    #define MAX_PLATFORM_PATH_LENGTH 256
#endif

#define MAX_ENT             64
#define SPAWN_KEY           778899
#define SPAWN_ARRAY_ITEM    pev_iuser1
#define SPAWN_CUSTOM        pev_iuser1

new const PLUGIN_VERSION[]       = "1.0"
new const Float:DELAY_ON_CONNECT = 1.0
new const ERROR_FILE[]           = "Spawn_ERRORS.log"

enum
{
    SECTION_NONE,
    SECTION_MAIN_SETTINGS
}

enum
{
    DTYPE_FLOAT,
    DTYPE_FLOAT_RANGE,
    DTYPE_INT,
    DTYPE_BOOL,
    DTYPE_FLAGS,
    DTYPE_VECTOR,
    DTYPE_VECTOR_FLOAT,
    DTYPE_STRING_MODEL,
    DTYPE_STRING_SOUND,
    DTYPE_STRING_SPRITE
}

enum
{
    TEAM_T,
    TEAM_CT
}

enum
{
    FLAG_SELECT             = (1 << 0),
    FLAG_GHOST              = (1 << 1)
}

enum
{
    SOUND_MENU_NAV,
    SOUND_MENU_REMOVE,
    SOUND_MENU_ALERT
}

enum _:MAIN_SETTINGS
{
    SETTING_DEFAULT_MODEL_T[MAX_RESOURCE_PATH_LENGTH],
    SETTING_DEFAULT_MODEL_CT[MAX_RESOURCE_PATH_LENGTH],
    SETTING_DEFAULT_SEQUENCE,
    Float:SETTING_DEFAULT_FRAMERATE,

    bool:SETTING_SPAWN_LOAD,
    bool:SETTING_SPAWN_DEFAULT,
    Float:SETTING_SPAWN_CHECK,
    Float:SETTING_OFFSET_BASE,
    Float:SETTING_OFFSET[2],
    Float:SETTING_OFFSET_STEP,
    SETTING_GHOST_ALPHA,

    SETTING_SOUND_MENU_NAV[MAX_RESOURCE_PATH_LENGTH],
    SETTING_SOUND_MENU_REMOVE[MAX_RESOURCE_PATH_LENGTH],
    SETTING_SOUND_MENU_ALERT[MAX_RESOURCE_PATH_LENGTH],

    SETTING_COLOR_SELECT[3]
}

enum _:SPAWN
{
    SPAWN_ID,
    SPAWN_TEAM,
    SPAWN_FLAGS,
    SPAWN_ENT_ID,

    Float:SPAWN_ORIGIN[3],
    Float:SPAWN_ANGLES[3]
}

enum _:PLAYER_DATA
{
    PDATA_SPAWN_GHOST,
    PDATA_SPAWN_MENU,
    bool:PDATA_SPAWN_ACTION,
    Float:PDATA_OFFSET,
    Float:PDATA_NEXT_OFFSET
}

enum
{
    MENU_ROOT,
    MENU_CREATE,
    MENU_REMOVE,
    MENU_ROTATE
}

enum
{
    ROOT_CREATE,
    ROOT_REMOVE,
    ROOT_SAVE,

    ROOT_NOCLIP = 4,
    ROOT_GODMODE
}

enum
{
    CREATE_T,
    CREATE_CT
}

enum
{
    REMOVE_NEXT,
    REMOVE_BACK,

    REMOVE_CURRENT = 3,
    REMOVE_ALL
}

enum
{
    ROTATE_RIGHT,
    ROTATE_LEFT,
    ROTATE_PLACE
}

new g_szMenuHandler[][] =
{
    "menuHandlerRoot",
    "menuHandlerCreate",
    "menuHandlerRemove",
    "menuHandlerRotate"
}

new Array:g_aSpawn,
    g_eSettings[MAIN_SETTINGS],
    g_ePlayerData[MAX_PLAYERS + 1][PLAYER_DATA],
    bool:g_bFileWasRead = false,
    g_iSpawn, g_iCountT, g_iCountCT,
    g_iMaxPlayers

public plugin_init()
{
    register_plugin("Spawn Manager", PLUGIN_VERSION, "RedSMURF")

    register_clcmd("say /sm",         "cmdMenu", ADMIN_RCON)
    register_clcmd("say_team /sm",    "cmdMenu", ADMIN_RCON)
    register_clcmd("say /spawn",      "cmdMenu", ADMIN_RCON)
    register_clcmd("say_team /spawn", "cmdMenu", ADMIN_RCON)
    register_concmd("sm_reload", "cmdReload", ADMIN_RCON, "-- Reload the configuration file")
    register_concmd("spawn_reload", "cmdReload", ADMIN_RCON, "-- Reload the configuration file")

    register_dictionary("SpawnManager.txt")

    register_forward(FM_UpdateClientData, "fwdUpdateClientData", 1)
    register_forward(FM_AddToFullPack, "fwdAddToFullPack", 1)
    RegisterHam(Ham_Spawn, "info_target", "fwdSpawn", 1)
    RegisterHam(Ham_Player_PreThink, "player", "fwdPreThink")
    RegisterHam(Ham_Killed, "player", "fwdKilled", 1)

    g_iMaxPlayers = get_maxplayers()
    spawnInit()

    set_task(0.1, "spawnTask", .flags = "b")
}

public plugin_precache()
{
    g_aSpawn = ArrayCreate(SPAWN)

    ReadFile()
}

public plugin_end()
{
    ArrayDestroy(g_aSpawn)
}

public cmdMenu(id, iLevel, iCmd)
{
    if ( !cmd_access(id, iLevel, iCmd, 1) )
        return PLUGIN_HANDLED

    spawnSound(id, SOUND_MENU_NAV)
    spawnMenu(id, MENU_ROOT)

    return PLUGIN_HANDLED
}

public cmdReload(id, iLevel, iCmd)
{
    if ( !cmd_access(id, iLevel, iCmd, 1) )
        return PLUGIN_HANDLED

    ReadFile()
    console_print(id, "The configuration file has been reloaded successfully !")

    return PLUGIN_HANDLED
}

public client_command(id)
{
    if ( !g_ePlayerData[id][PDATA_SPAWN_GHOST] )
        return PLUGIN_CONTINUE

    new szCmd[16]
    read_argv(0, szCmd, charsmax(szCmd))

    if ( contain(szCmd, "weapon_") != -1 ||
    equal(szCmd, "invnext") ||
    equal(szCmd, "invprev") ||
    equal(szCmd, "lastinv") )
        return PLUGIN_HANDLED

    return PLUGIN_CONTINUE
}

stock ReadFile()
{
    if ( g_bFileWasRead )
    {
        for ( new id = 1; id <= g_iMaxPlayers; id ++ )
            if ( is_user_connected(id))
                UpdateData(id)
    }

    new g_szFileName[MAX_RESOURCE_PATH_LENGTH]
    get_configsdir(g_szFileName, charsmax(g_szFileName))
    add(g_szFileName, charsmax(g_szFileName), "/SpawnManager.ini")

    new iFile
    iFile = fopen(g_szFileName, "rt")

    if ( !iFile )
    {
        set_fail_state("An error occured during the opening of the configuration file !")
    }

    new szData[MAX_FILE_CELL_SIZE],
        szKey[MAX_VALUE_LENGTH],
        szValue[MAX_RESOURCE_PATH_LENGTH],
        iSection = SECTION_NONE, iLine, iPos

    while( !feof(iFile) )
    {
        iLine ++
        fgets(iFile, szData, charsmax(szData))
        trim(szData)

        switch( szData[0] )
        {
            case EOS, ';', '#':
            {
                continue
            }
            case '[':
            {
                if ( szData[strlen(szData) - 1] == ']' )
                {
                    replace(szData, charsmax( szData ), "[", "")
                    replace(szData, charsmax( szData ), "]", "")
                    trim(szData)

                    if ( equali(szData, "Main Settings") )
                        iSection = SECTION_MAIN_SETTINGS
                }
                else
                {
                    LogConfigError(iLine, "Unclosed section name: %s", szData)
                    iSection = SECTION_NONE
                }
            }
            default:
            {
                strtok(szData, szKey, charsmax(szKey), szValue, charsmax(szValue), '=')
                iPos = contain(szValue, "#")
                if ( iPos != -1 )
                    szValue[iPos] = EOS

                trim(szKey)
                trim(szValue)

                switch( iSection )
                {
                    case SECTION_NONE:
                    {
                        LogConfigError(iLine, "Data is not in any defined section: %s", szData)
                    }
                    case SECTION_MAIN_SETTINGS:
                    {
                        if ( equali(szKey, "SETTING_DEFAULT_MODEL_T") )
                            parseSetting(DTYPE_STRING_MODEL, szKey, charsmax(szKey), szValue, charsmax(szValue), g_eSettings[SETTING_DEFAULT_MODEL_T], charsmax(g_eSettings[SETTING_DEFAULT_MODEL_T]))
                        else if ( equali(szKey, "SETTING_DEFAULT_MODEL_CT") )
                            parseSetting(DTYPE_STRING_MODEL, szKey, charsmax(szKey), szValue, charsmax(szValue), g_eSettings[SETTING_DEFAULT_MODEL_CT], charsmax(g_eSettings[SETTING_DEFAULT_MODEL_CT]))
                        else if ( equali(szKey, "SETTING_DEFAULT_SEQUENCE") )
                            parseSetting(DTYPE_INT, szKey, charsmax(szKey), szValue, charsmax(szValue), g_eSettings[SETTING_DEFAULT_SEQUENCE], charsmax(g_eSettings[SETTING_DEFAULT_SEQUENCE]))
                        else if ( equali(szKey, "SETTING_DEFAULT_FRAMERATE") )
                            parseSetting(DTYPE_FLOAT, szKey, charsmax(szKey), szValue, charsmax(szValue), g_eSettings[SETTING_DEFAULT_FRAMERATE], charsmax(g_eSettings[SETTING_DEFAULT_FRAMERATE]))
                        else if ( equali(szKey, "SETTING_SPAWN_LOAD") )
                            parseSetting(DTYPE_BOOL, szKey, charsmax(szKey), szValue, charsmax(szValue), g_eSettings[SETTING_SPAWN_LOAD], charsmax(g_eSettings[SETTING_SPAWN_LOAD]))
                        else if ( equali(szKey, "SETTING_SPAWN_DEFAULT") )
                            parseSetting(DTYPE_BOOL, szKey, charsmax(szKey), szValue, charsmax(szValue), g_eSettings[SETTING_SPAWN_DEFAULT], charsmax(g_eSettings[SETTING_SPAWN_DEFAULT]))
                        else if ( equali(szKey, "SETTING_SPAWN_CHECK") )
                            parseSetting(DTYPE_FLOAT, szKey, charsmax(szKey), szValue, charsmax(szValue), g_eSettings[SETTING_SPAWN_CHECK], charsmax(g_eSettings[SETTING_SPAWN_CHECK]))
                        else if ( equali(szKey, "SETTING_OFFSET_BASE") )
                            parseSetting(DTYPE_FLOAT, szKey, charsmax(szKey), szValue, charsmax(szValue), g_eSettings[SETTING_OFFSET_BASE], charsmax(g_eSettings[SETTING_OFFSET_BASE]))
                        else if ( equali(szKey, "SETTING_OFFSET") )
                            parseSetting(DTYPE_FLOAT_RANGE, szKey, charsmax(szKey), szValue, charsmax(szValue), g_eSettings[SETTING_OFFSET], charsmax(g_eSettings[SETTING_OFFSET]))
                        else if ( equali(szKey, "SETTING_OFFSET_STEP") )
                            parseSetting(DTYPE_FLOAT, szKey, charsmax(szKey), szValue, charsmax(szValue), g_eSettings[SETTING_OFFSET_STEP], charsmax(g_eSettings[SETTING_OFFSET_STEP]))
                        else if ( equali(szKey, "SETTING_GHOST_ALPHA") )
                            parseSetting(DTYPE_INT, szKey, charsmax(szKey), szValue, charsmax(szValue), g_eSettings[SETTING_GHOST_ALPHA], charsmax(g_eSettings[SETTING_GHOST_ALPHA]))
                        else if ( equali(szKey, "SETTING_SOUND_MENU_NAV") )
                            parseSetting(DTYPE_STRING_SOUND, szKey, charsmax(szKey), szValue, charsmax(szValue), g_eSettings[SETTING_SOUND_MENU_NAV], charsmax(g_eSettings[SETTING_SOUND_MENU_NAV]))
                        else if ( equali(szKey, "SETTING_SOUND_MENU_REMOVE") )
                            parseSetting(DTYPE_STRING_SOUND, szKey, charsmax(szKey), szValue, charsmax(szValue), g_eSettings[SETTING_SOUND_MENU_REMOVE], charsmax(g_eSettings[SETTING_SOUND_MENU_REMOVE]))
                        else if ( equali(szKey, "SETTING_SOUND_MENU_ALERT") )
                            parseSetting(DTYPE_STRING_SOUND, szKey, charsmax(szKey), szValue, charsmax(szValue), g_eSettings[SETTING_SOUND_MENU_ALERT], charsmax(g_eSettings[SETTING_SOUND_MENU_ALERT]))
                        else if ( equali(szKey, "SETTING_COLOR_SELECT") )
                            parseSetting(DTYPE_VECTOR, szKey, charsmax(szKey), szValue, charsmax(szValue), g_eSettings[SETTING_COLOR_SELECT], charsmax(g_eSettings[SETTING_COLOR_SELECT]))
                    }
                }
            }
        }
    }

    if ( g_eSettings[SETTING_SPAWN_LOAD] )
        loadData()

    g_bFileWasRead = true
    fclose(iFile)
}

public client_authorized(id)
{
    set_task(DELAY_ON_CONNECT, "UpdateData", id)
}

public client_disconnected(id)
{
    new eSpawn[SPAWN], iItem
    if ( g_ePlayerData[id][PDATA_SPAWN_GHOST]
    && spawnGet(eSpawn, g_ePlayerData[id][PDATA_SPAWN_GHOST]) != -1 )
    {
        spawnKill(eSpawn[SPAWN_ID])
        spawnRemove(iItem)
    }

    g_ePlayerData[id][PDATA_SPAWN_GHOST]  = 0
    g_ePlayerData[id][PDATA_SPAWN_ACTION] = false
    g_ePlayerData[id][PDATA_SPAWN_MENU]   = 0
}

public UpdateData(id)
{
    g_ePlayerData[id][PDATA_OFFSET] = g_eSettings[SETTING_OFFSET_BASE]
}

public spawnInit()
{
    if ( g_eSettings[SETTING_SPAWN_DEFAULT] )
        loadDefault()
}

public spawnMenu(id, iType)
{
    new szData[64], iMenu
    formatex(szData, charsmax(szData), "%L", id, "SPAWN_MENU_TITLE", PLUGIN_VERSION)
    iMenu = menu_create(szData, g_szMenuHandler[iType])

    switch( iType )
    {
        case MENU_ROOT:   { menuRoot(id, iMenu); }
        case MENU_CREATE: { menuCreate(id, iMenu);  format(szData, charsmax(szData), "%s^n%L", szData, id, "SPAWN_ROOT_CREATE"); }
        case MENU_REMOVE: { menuRemove(id, iMenu);  format(szData, charsmax(szData), "%s^n%L", szData, id, "SPAWN_ROOT_REMOVE"); }
        case MENU_ROTATE: { menuRotate(id, iMenu);  format(szData, charsmax(szData), "%s^n%L", szData, id, "SPAWN_ROOT_ROTATE"); }
    }

    if ( menu_pages(iMenu) > 1 )
        format(szData, charsmax(szData), "%s^n%L", szData, id, "SPAWN_MENU_TITLE_PAGE")

    menu_setprop(iMenu, MPROP_TITLE, szData)
    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_setprop(iMenu, MPROP_NUMBER_COLOR, "\r")

    menu_display(id, iMenu)
    return PLUGIN_HANDLED
}

stock menuNav(id, iMenu)
{
    new szItem[64]

    formatex(szItem, charsmax(szItem), "%L", id, "SPAWN_NAV_NEXT")
    menu_additem(iMenu, szItem)

    formatex(szItem, charsmax(szItem), "%L", id, "SPAWN_NAV_BACK")
    menu_additem(iMenu, szItem)

    menu_addblank2(iMenu)
}

public menuRoot(id, iMenu)
{
    new szItem[64]

    formatex(szItem, charsmax(szItem), "%L", id, "SPAWN_ROOT_CREATE")
    menu_additem(iMenu, szItem )

    formatex(szItem, charsmax(szItem), "%L", id, "SPAWN_ROOT_REMOVE")
    menu_additem(iMenu, szItem)

    formatex(szItem, charsmax(szItem), "%L", id, "SPAWN_ROOT_SAVE")
    menu_additem(iMenu, szItem)

    menu_addblank2(iMenu)

    formatex(szItem, charsmax(szItem), "%L", id, "SPAWN_ROOT_NOCLIP", id, get_user_noclip(id) ? "SPAWN_ON" : "SPAWN_OFF")
    menu_additem(iMenu, szItem)

    formatex(szItem, charsmax(szItem), "%L", id, "SPAWN_ROOT_GODMODE", id, get_user_godmode(id) ? "SPAWN_ON" : "SPAWN_OFF")
    menu_additem(iMenu, szItem)
}

public menuHandlerRoot(id, menu, item)
{
    if ( item == MENU_EXIT )
    {
        menu_destroy(menu)
        return PLUGIN_HANDLED
    }

    switch( item )
    {
        case ROOT_CREATE:
        {
            if ( g_iSpawn >= MAX_ENT )
            {
                client_print_color(id, id, "%L %L", id, "SPAWN_CHAT_TAG", id, "SPAWN_CHAT_LIMIT", MAX_ENT)
                spawnSound(id, SOUND_MENU_REMOVE)
            }
            else
            {
                spawnSound(id, SOUND_MENU_NAV)
                spawnMenu(id, MENU_CREATE)
            }
        }
        case ROOT_REMOVE:
        {
            if ( !g_iSpawn )
            {
                client_print_color(id, id, "%L %L", id, "SPAWN_CHAT_TAG", id, "SPAWN_CHAT_NO_SPAWN")
                spawnSound(id, SOUND_MENU_REMOVE)
            }
            else
            {
                spawnSound(id, SOUND_MENU_REMOVE)
                spawnMenu(id, MENU_REMOVE)
            }
        }
        case ROOT_SAVE:
        {
            saveData(id)
        }
        case ROOT_NOCLIP:
        {
            spawnNoClip(id)
        }
        case ROOT_GODMODE:
        {
            spawnGodMode(id)
        }
    }

    menu_destroy(menu)
    return PLUGIN_HANDLED
}

public menuCreate(id, iMenu)
{
    new szItem[64]
    formatex(szItem, charsmax(szItem), "%L", id, "SPAWN_CREATE_T", g_iCountT)
    menu_additem(iMenu, szItem )

    formatex(szItem, charsmax(szItem), "%L", id, "SPAWN_CREATE_CT", g_iCountCT)
    menu_additem(iMenu, szItem)
}

public menuHandlerCreate(id, menu, item)
{
    if ( item == MENU_EXIT
    || !is_user_alive(id) )
    {
        menu_destroy(menu)
        return PLUGIN_HANDLED
    }

    spawnCreate(id, item)
    spawnSound(id, SOUND_MENU_NAV)
    spawnMenu(id, MENU_ROTATE)

    menu_destroy(menu)
    return PLUGIN_HANDLED
}

public menuRemove(id, iMenu)
{
    new eSpawn[SPAWN], szItem[64]

    ArrayGetArray(g_aSpawn, g_ePlayerData[id][PDATA_SPAWN_MENU], eSpawn)
    menuNav(id, iMenu)

    formatex(szItem, charsmax(szItem), "%L", id, "SPAWN_REMOVE_CURRENT")
    menu_additem(iMenu, szItem)

    formatex(szItem, charsmax(szItem), "%L", id, "SPAWN_REMOVE_ALL")
    menu_additem(iMenu, szItem)

    g_ePlayerData[id][PDATA_SPAWN_ACTION] = true
    eSpawn[SPAWN_FLAGS] |= FLAG_SELECT
    ArraySetArray(g_aSpawn, g_ePlayerData[id][PDATA_SPAWN_MENU], eSpawn)
}

public menuHandlerRemove(id, menu, item)
{
    new eSpawn[SPAWN]

    ArrayGetArray(g_aSpawn, g_ePlayerData[id][PDATA_SPAWN_MENU], eSpawn)
    eSpawn[SPAWN_FLAGS] &= ~FLAG_SELECT
    ArraySetArray(g_aSpawn, g_ePlayerData[id][PDATA_SPAWN_MENU], eSpawn)

    switch( item )
    {
        case REMOVE_NEXT:
        {
            if ( g_ePlayerData[id][PDATA_SPAWN_MENU] >= g_iSpawn - 1 )
                g_ePlayerData[id][PDATA_SPAWN_MENU] = 0
            else
                g_ePlayerData[id][PDATA_SPAWN_MENU] ++

            spawnSound(id, SOUND_MENU_NAV)
            spawnMenu(id, MENU_REMOVE)
        }
        case REMOVE_BACK:
        {
            if ( g_ePlayerData[id][PDATA_SPAWN_MENU] <= 0 )
                g_ePlayerData[id][PDATA_SPAWN_MENU] = g_iSpawn - 1
            else
                g_ePlayerData[id][PDATA_SPAWN_MENU] --

            spawnSound(id, SOUND_MENU_NAV)
            spawnMenu(id, MENU_REMOVE)
        }
        case REMOVE_CURRENT:
        {
            spawnKill(eSpawn[SPAWN_ID])
            spawnKill(eSpawn[SPAWN_ENT_ID])
            spawnRemove(g_ePlayerData[id][PDATA_SPAWN_MENU])

            client_print_color(id, id, "%L %L", id, "SPAWN_CHAT_TAG", id, "SPAWN_CHAT_REMOVE_CURRENT")
            g_ePlayerData[id][PDATA_SPAWN_MENU] = 0

            spawnSound(id, g_iSpawn > 0 ? SOUND_MENU_REMOVE : SOUND_MENU_NAV)
            spawnMenu(id, g_iSpawn > 0 ? MENU_REMOVE : MENU_ROOT)
        }
        case REMOVE_ALL:
        {
            while ( g_iSpawn )
            {
                ArrayGetArray(g_aSpawn, 0, eSpawn)

                spawnKill(eSpawn[SPAWN_ID])
                spawnKill(eSpawn[SPAWN_ENT_ID])
                spawnRemove(0)
            }

            client_print_color(id, id, "%L %L", id, "SPAWN_CHAT_TAG", id, "SPAWN_CHAT_REMOVE_ALL")
            g_ePlayerData[id][PDATA_SPAWN_MENU] = 0

            spawnSound(id, SOUND_MENU_ALERT)
            spawnMenu(id, MENU_ROOT)
        }
        default:
        {
            g_ePlayerData[id][PDATA_SPAWN_ACTION] = false
            g_ePlayerData[id][PDATA_SPAWN_MENU] = 0
        }
    }

    menu_destroy(menu)
    return PLUGIN_HANDLED
}

public menuRotate(id, iMenu)
{
    new szItem[64]
    formatex(szItem, charsmax(szItem), "%L", id, "SPAWN_ROTATE_RIGHT")
    menu_additem(iMenu, szItem)

    formatex(szItem, charsmax(szItem), "%L", id, "SPAWN_ROTATE_LEFT")
    menu_additem(iMenu, szItem)

    formatex(szItem, charsmax(szItem), "%L", id, "SPAWN_ROTATE_PLACE")
    menu_additem(iMenu, szItem)
}

public menuHandlerRotate(id, menu, item)
{
    new eSpawn[SPAWN], iItem
    if ( (iItem = spawnGet(eSpawn, g_ePlayerData[id][PDATA_SPAWN_GHOST])) == -1 )
    {
        menu_destroy(menu)
        return PLUGIN_HANDLED
    }

    switch( item )
    {
        case ROTATE_RIGHT:
        {
            pev(eSpawn[SPAWN_ID], pev_angles, eSpawn[SPAWN_ANGLES])
            eSpawn[SPAWN_ANGLES][1] -= 22.5
            if ( eSpawn[SPAWN_ANGLES][1] < -180.0 ) eSpawn[SPAWN_ANGLES][1] += 360.0

            set_pev(eSpawn[SPAWN_ID], pev_angles, eSpawn[SPAWN_ANGLES])
            ArraySetArray(g_aSpawn, iItem, eSpawn)

            spawnSound(id, SOUND_MENU_NAV)
            spawnMenu(id, MENU_ROTATE)
        }
        case ROTATE_LEFT:
        {
            pev(eSpawn[SPAWN_ID], pev_angles, eSpawn[SPAWN_ANGLES])
            eSpawn[SPAWN_ANGLES][1] += 22.5
            if ( eSpawn[SPAWN_ANGLES][1] > 180.0 ) eSpawn[SPAWN_ANGLES][1] -= 360.0

            set_pev(eSpawn[SPAWN_ID], pev_angles, eSpawn[SPAWN_ANGLES])
            ArraySetArray(g_aSpawn, iItem, eSpawn)

            spawnSound(id, SOUND_MENU_NAV)
            spawnMenu(id, MENU_ROTATE)
        }
        case ROTATE_PLACE:
        {
            spawnTrace(eSpawn, id)
            g_ePlayerData[id][PDATA_SPAWN_GHOST] = 0
            g_ePlayerData[id][PDATA_SPAWN_ACTION] = false

            pev(eSpawn[SPAWN_ID], pev_origin, eSpawn[SPAWN_ORIGIN])
            pev(eSpawn[SPAWN_ID], pev_angles, eSpawn[SPAWN_ANGLES])
            spawnCreateEnt(eSpawn)

            eSpawn[SPAWN_FLAGS] &= ~FLAG_GHOST
            spawnSetAnim(eSpawn[SPAWN_ID])
            ArraySetArray(g_aSpawn, iItem, eSpawn)

            client_print_color(id, id, "%L %L", id, "SPAWN_CHAT_TAG", id, "SPAWN_CHAT_CREATE_NEW")
            spawnSound(id, SOUND_MENU_NAV)
            spawnMenu(id, MENU_ROOT)
        }
        default:
        {
            spawnKill(eSpawn[SPAWN_ID])
            spawnKill(eSpawn[SPAWN_ENT_ID])
            spawnRemove(iItem)

            g_ePlayerData[id][PDATA_SPAWN_GHOST] = 0
            g_ePlayerData[id][PDATA_SPAWN_ACTION] = false
        }
    }

    menu_destroy(menu)
    return PLUGIN_HANDLED
}

public spawnTask()
{
    new eSpawn[SPAWN]

    for ( new id = 1; id <= g_iMaxPlayers; id ++ )
    {
        if ( !is_user_alive(id) )
            continue

        if ( !g_ePlayerData[id][PDATA_SPAWN_GHOST] )
        {
            if ( g_ePlayerData[id][PDATA_SPAWN_ACTION] )
                spawnCheck(id)
        }
        else if ( spawnGet(eSpawn, g_ePlayerData[id][PDATA_SPAWN_GHOST]) != -1 )
        {
            spawnTrace(eSpawn, id)
        }
    }
}

stock spawnCreate(id, iTeam)
{
    new iEnt
    iEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"))
    if ( !pev_valid(iEnt) )
        return

    new eSpawn[SPAWN]
    eSpawn[SPAWN_ID] = iEnt
    eSpawn[SPAWN_TEAM] = iTeam
    if ( id )
    {
        g_ePlayerData[id][PDATA_SPAWN_GHOST] = iEnt
        g_ePlayerData[id][PDATA_SPAWN_ACTION] = true
        g_ePlayerData[id][PDATA_OFFSET] = g_eSettings[SETTING_OFFSET_BASE]

        eSpawn[SPAWN_FLAGS] |= FLAG_GHOST
    }

    set_pev(iEnt, SPAWN_ARRAY_ITEM, g_iSpawn)
    set_pev(iEnt, pev_impulse, SPAWN_KEY)
    if ( iTeam == TEAM_T ) { engfunc(EngFunc_SetModel, iEnt, g_eSettings[SETTING_DEFAULT_MODEL_T]); g_iCountT ++; }
    else                   { engfunc(EngFunc_SetModel, iEnt, g_eSettings[SETTING_DEFAULT_MODEL_CT]); g_iCountCT ++; }

    ArrayPushArray(g_aSpawn, eSpawn)
    g_iSpawn ++

    dllfunc(DLLFunc_Spawn, iEnt)
}

stock spawnCreateEnt(eSpawn[SPAWN])
{
    new iEnt
    if ( eSpawn[SPAWN_TEAM] == TEAM_T ) iEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_player_deathmatch"))
    else                                iEnt = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_player_start"))
    if ( !pev_valid(iEnt) )
        return

    eSpawn[SPAWN_ENT_ID] = iEnt
    set_pev(iEnt, SPAWN_CUSTOM, 1)
    set_pev(iEnt, pev_origin, eSpawn[SPAWN_ORIGIN])
    set_pev(iEnt, pev_angles, eSpawn[SPAWN_ANGLES])

    dllfunc(DLLFunc_Spawn, iEnt)
}

stock spawnRemove(iItem)
{
    new eSpawn[SPAWN]

    ArrayGetArray(g_aSpawn, iItem, eSpawn)
    if ( eSpawn[SPAWN_TEAM] == TEAM_T ) g_iCountT --
    else                                g_iCountCT --

    ArrayDeleteItem(g_aSpawn, iItem)
    g_iSpawn --

    for ( new i = iItem; i < g_iSpawn; i ++ )
    {
        ArrayGetArray(g_aSpawn, i, eSpawn)
        set_pev(eSpawn[SPAWN_ID], SPAWN_ARRAY_ITEM, i)
    }
}

public saveData(id)
{
    new eSpawn[SPAWN],
        szFile[128], iFile,
        szData[64]

    get_mapname(szFile, charsmax(szFile))
    format(szFile, charsmax(szFile), "maps/%s_SpawnManager.ini", szFile)

    iFile = fopen(szFile, "wt")
    if ( !iFile )
        return PLUGIN_HANDLED

    for ( new i = 0; i < g_iSpawn; i ++ )
    {
        ArrayGetArray(g_aSpawn, i, eSpawn)

        formatex(szData, charsmax(szData), "[%d]^n", i)
        fputs(iFile, szData)

        formatex(szData, charsmax(szData), "team = %d^n", eSpawn[SPAWN_TEAM])
        fputs(iFile, szData)

        formatex(szData, charsmax(szData), "origin = %.2f %.2f %.2f^n",
        eSpawn[SPAWN_ORIGIN][0], eSpawn[SPAWN_ORIGIN][1], eSpawn[SPAWN_ORIGIN][2])
        fputs(iFile, szData)

        formatex(szData, charsmax(szData), "angles = %.2f %.2f %.2f^n",
        eSpawn[SPAWN_ANGLES][0], eSpawn[SPAWN_ANGLES][1], eSpawn[SPAWN_ANGLES][2])
        fputs(iFile, szData)
    }

    client_print_color(id, id, "%L %L", id, "SPAWN_CHAT_TAG", id, "SPAWN_CHAT_SAVE", szFile)
    fclose(iFile)

    spawnSound(id, SOUND_MENU_NAV)
    spawnMenu(id, MENU_ROOT)
    return PLUGIN_HANDLED
}

public loadData()
{
    new szFile[128], iFile,
        szData[64], szKey[32], szValue[32],
        iTeam, Float:fOrigin[3], Float:fAngles[3], iCount = -1

    get_mapname(szFile, charsmax(szFile))
    format(szFile, charsmax(szFile), "maps/%s_SpawnManager.ini", szFile)

    iFile = fopen(szFile, "rt")
    if ( !iFile )
        return PLUGIN_HANDLED

    while( !feof(iFile) )
    {
        fgets(iFile, szData, charsmax(szData))

        if ( szData[0] == '[' )
        {
            if ( iCount != -1 )
                loadDataSpawn(fOrigin, fAngles, iTeam, iCount)

            iCount ++
        }
        else
        {
            strtok(szData, szKey, charsmax( szKey ), szValue, charsmax( szValue ), '=')
            trim(szKey)
            trim(szValue)

            if ( equal(szKey, "team") )
            {
                iTeam = str_to_num(szValue)
            }
            else if ( equal(szKey, "origin") )
            {
                strtok(szValue, szKey, charsmax(szKey), szValue, charsmax(szValue), ' ')
                fOrigin[0] = str_to_float(szKey)

                strtok(szValue, szKey, charsmax(szKey), szValue, charsmax(szValue), ' ')
                fOrigin[1] = str_to_float(szKey)
                fOrigin[2] = str_to_float(szValue)
            }
            else if ( equal(szKey, "angles") )
            {
                strtok(szValue, szKey, charsmax(szKey), szValue, charsmax(szValue), ' ')
                fAngles[0] = str_to_float(szKey)

                strtok(szValue, szKey, charsmax(szKey), szValue, charsmax(szValue), ' ')
                fAngles[1] = str_to_float(szKey)
                fAngles[2] = str_to_float(szValue)
            }
        }
    }

    if ( iCount != -1 )
        loadDataSpawn(fOrigin, fAngles, iTeam, iCount)

    fclose(iFile)
    return PLUGIN_HANDLED
}

stock loadDataSpawn(Float:fOrigin[3], Float:fAngles[3], iTeam, iCount)
{
    new eSpawn[SPAWN]
    spawnCreate(0, iTeam)
    ArrayGetArray(g_aSpawn, iCount, eSpawn)

    xs_vec_copy(fOrigin, eSpawn[SPAWN_ORIGIN])
    xs_vec_copy(fAngles, eSpawn[SPAWN_ANGLES])
    spawnCreateEnt(eSpawn)

    set_pev(eSpawn[SPAWN_ID], pev_origin, eSpawn[SPAWN_ORIGIN])
    set_pev(eSpawn[SPAWN_ID], pev_angles, eSpawn[SPAWN_ANGLES])
    spawnSetAnim(eSpawn[SPAWN_ID])

    ArraySetArray(g_aSpawn, iCount, eSpawn)
}

stock loadDefault()
{
    new eSpawn[SPAWN], iEnt = -1
    while ((iEnt = engfunc(EngFunc_FindEntityByString, iEnt, "classname", "info_player_deathmatch")))
    {
        if ( pev(iEnt, SPAWN_CUSTOM) )
            continue

        spawnCreate(0, TEAM_T)
        ArrayGetArray(g_aSpawn, g_iSpawn - 1, eSpawn)

        pev(iEnt, pev_origin, eSpawn[SPAWN_ORIGIN])
        pev(iEnt, pev_angles, eSpawn[SPAWN_ANGLES])
        eSpawn[SPAWN_ENT_ID] = iEnt

        set_pev(eSpawn[SPAWN_ID], pev_origin, eSpawn[SPAWN_ORIGIN])
        set_pev(eSpawn[SPAWN_ID], pev_angles, eSpawn[SPAWN_ANGLES])
        spawnSetAnim(eSpawn[SPAWN_ID])
        ArraySetArray(g_aSpawn, g_iSpawn - 1, eSpawn)
    }

    iEnt = -1
    while ((iEnt = engfunc(EngFunc_FindEntityByString, iEnt, "classname", "info_player_start")))
    {
        if ( pev(iEnt, SPAWN_CUSTOM) )
            continue

        spawnCreate(0, TEAM_CT)
        ArrayGetArray(g_aSpawn, g_iSpawn - 1, eSpawn)

        pev(iEnt, pev_origin, eSpawn[SPAWN_ORIGIN])
        pev(iEnt, pev_angles, eSpawn[SPAWN_ANGLES])
        eSpawn[SPAWN_ENT_ID] = iEnt

        set_pev(eSpawn[SPAWN_ID], pev_origin, eSpawn[SPAWN_ORIGIN])
        set_pev(eSpawn[SPAWN_ID], pev_angles, eSpawn[SPAWN_ANGLES])
        spawnSetAnim(eSpawn[SPAWN_ID])

        ArraySetArray(g_aSpawn, g_iSpawn - 1, eSpawn)
    }
}

public spawnNoClip(id)
{
    set_user_noclip(id, !get_user_noclip(id))

    spawnSound(id, SOUND_MENU_NAV)
    spawnMenu(id, MENU_ROOT)
}

public spawnGodMode(id)
{
    set_user_godmode(id, !get_user_godmode(id))

    spawnSound(id, SOUND_MENU_NAV)
    spawnMenu(id, MENU_ROOT)
}

public fwdUpdateClientData(id, iSendWeapons, iHandle)
{
    if ( g_ePlayerData[id][PDATA_SPAWN_GHOST] )
    {
        set_cd(iHandle, CD_WeaponAnim, 0)
        set_cd(iHandle, CD_flNextAttack, get_gametime() + 0.1)
    }

    return FMRES_IGNORED
}

public fwdAddToFullPack(es, e, iEnt, iHost, iHostFlags, iPlayer, pSet)
{
    if ( !pev_valid(iEnt)
    || !isSpawn(iEnt)
    || !get_orig_retval() )
        return FMRES_IGNORED

    new eSpawn[SPAWN]
    if ( spawnGet(eSpawn, iEnt) == -1 )
        return FMRES_IGNORED

    if ( !g_ePlayerData[iHost][PDATA_SPAWN_ACTION] )
    {
        set_es(es, ES_Effects, EF_NODRAW)
    }
    else
    {
        if ( eSpawn[SPAWN_FLAGS] & FLAG_GHOST )
        {
            set_es(es, ES_RenderMode, kRenderTransAlpha)
            set_es(es, ES_RenderAmt, g_eSettings[SETTING_GHOST_ALPHA])
        }

        if ( eSpawn[SPAWN_FLAGS] & FLAG_SELECT )
        {
            set_es(es, ES_RenderColor, g_eSettings[SETTING_COLOR_SELECT])
            set_es(es, ES_RenderFx, kRenderFxGlowShell)
        }
    }

    return FMRES_IGNORED
}

public pfn_keyvalue(iEnt)
{
    if ( !pev_valid(iEnt) )
        return PLUGIN_CONTINUE

    new szCN[32], szKey[32], szValue[32]
    copy_keyvalue(szCN, charsmax(szCN), szKey, charsmax(szKey), szValue, charsmax(szValue))

    if ( !equal(szCN, "info_player_start")
    && !equal(szCN, "info_player_deathmatch")
    && !pev(iEnt, SPAWN_CUSTOM) )
        return PLUGIN_CONTINUE

    if ( !g_eSettings[SETTING_SPAWN_DEFAULT] )
    {
        spawnKill(iEnt)
    }
    else if ( equal(szKey, "origin") )
    {
        new Float:fOrigin[3]
        parseSetting(DTYPE_VECTOR_FLOAT, szKey, charsmax(szKey), szValue, charsmax(szValue), fOrigin, charsmax(fOrigin))

        if ( !isSpawnSafe(fOrigin) )
            spawnKill(iEnt)
    }

    return PLUGIN_CONTINUE
}

public fwdKilled(id, iAttacker, bGib)
{
    g_ePlayerData[id][PDATA_SPAWN_ACTION] = false

    if ( g_ePlayerData[id][PDATA_SPAWN_GHOST] )
    {
        new eSpawn[SPAWN], iItem

        if ( (iItem = spawnGet(eSpawn, g_ePlayerData[id][PDATA_SPAWN_GHOST])) != -1 )
        {
            spawnKill(eSpawn[SPAWN_ENT_ID])
            spawnKill(eSpawn[SPAWN_ID])
            spawnRemove(iItem)

            g_ePlayerData[id][PDATA_SPAWN_GHOST] = 0
        }
    }

    return HAM_IGNORED
}

public fwdSpawn(iEnt)
{
    if ( !isSpawn(iEnt) )
        return HAM_IGNORED

    set_pev(iEnt, pev_solid, SOLID_NOT)
    set_pev(iEnt, pev_movetype, MOVETYPE_FLY)

    return HAM_IGNORED
}

public fwdPreThink(id)
{
    if ( !is_user_alive(id) )
        return HAM_IGNORED

    new iButton
    iButton = pev(id, pev_button)

    if ( g_ePlayerData[id][PDATA_SPAWN_GHOST] )
    {
        if ( get_gametime() >= g_ePlayerData[id][PDATA_NEXT_OFFSET] )
        {
            if ( iButton & IN_ATTACK )
            {
                g_ePlayerData[id][PDATA_OFFSET]      += g_eSettings[SETTING_OFFSET_STEP]
                g_ePlayerData[id][PDATA_OFFSET]      = floatclamp(g_ePlayerData[id][PDATA_OFFSET], g_eSettings[SETTING_OFFSET][0], g_eSettings[SETTING_OFFSET][1])
                g_ePlayerData[id][PDATA_NEXT_OFFSET] = get_gametime() + 0.1
            }
            else if ( iButton & IN_ATTACK2 )
            {
                g_ePlayerData[id][PDATA_OFFSET]      -= g_eSettings[SETTING_OFFSET_STEP]
                g_ePlayerData[id][PDATA_OFFSET]      = floatclamp(g_ePlayerData[id][PDATA_OFFSET], g_eSettings[SETTING_OFFSET][0], g_eSettings[SETTING_OFFSET][1])
                g_ePlayerData[id][PDATA_NEXT_OFFSET] = get_gametime() + 0.1
            }
        }

        iButton &= ~(IN_ATTACK | IN_ATTACK2)
        set_pev(id, pev_button, iButton)
    }

    return HAM_IGNORED
}

stock spawnTrace(eSpawn[SPAWN], id)
{
    new Float:fVec1[3]
    pev(id, pev_origin, eSpawn[SPAWN_ORIGIN])
    pev(id, pev_view_ofs, fVec1)
    xs_vec_add(eSpawn[SPAWN_ORIGIN], fVec1, eSpawn[SPAWN_ORIGIN])

    pev(id, pev_v_angle, fVec1)
    engfunc(EngFunc_MakeVectors, fVec1)
    global_get(glb_v_forward, fVec1)

    xs_vec_mul_scalar(fVec1, g_ePlayerData[id][PDATA_OFFSET], fVec1)
    xs_vec_add(fVec1, eSpawn[SPAWN_ORIGIN], fVec1)

    engfunc(EngFunc_TraceLine, eSpawn[SPAWN_ORIGIN], fVec1, IGNORE_MONSTERS, id, 0)
    get_tr2(0, TR_vecEndPos, eSpawn[SPAWN_ORIGIN])
    set_pev(eSpawn[SPAWN_ID], pev_origin, eSpawn[SPAWN_ORIGIN])
}

stock spawnCheck(id)
{
    new eSpawn[SPAWN], Float:fVec1[3], Float:fVec2[3], Float:fVec3[3]
    new iBest, Float:fBestDist, Float:fDot, Float:fDist

    pev(id, pev_origin, fVec1)
    pev(id, pev_view_ofs, fVec2)
    xs_vec_add(fVec1, fVec2, fVec1)

    pev(id, pev_v_angle, fVec2)
    engfunc(EngFunc_MakeVectors, fVec2)
    global_get(glb_v_forward, fVec2)

    iBest = -1
    fBestDist = g_eSettings[SETTING_SPAWN_CHECK]
    for ( new i = 0; i < g_iSpawn; i ++ )
    {
        ArrayGetArray(g_aSpawn, i, eSpawn)
        xs_vec_sub(eSpawn[SPAWN_ORIGIN], fVec1, fVec3)
        fDot = xs_vec_dot(fVec2, fVec3)

        if ( fDot < 0.0 )
            continue

        xs_vec_mul_scalar(fVec2, fDot, fVec3)
        xs_vec_add(fVec3, fVec1, fVec3)
        fDist = get_distance_f(fVec3, eSpawn[SPAWN_ORIGIN])
        if ( fDist < fBestDist )
        {
            fBestDist = fDist
            iBest = i
        }
    }

    if ( iBest != -1
    && g_ePlayerData[id][PDATA_SPAWN_MENU] != iBest )
    {
        ArrayGetArray(g_aSpawn, g_ePlayerData[id][PDATA_SPAWN_MENU], eSpawn)
        eSpawn[SPAWN_FLAGS] &= ~FLAG_SELECT
        ArraySetArray(g_aSpawn, g_ePlayerData[id][PDATA_SPAWN_MENU], eSpawn)

        ArrayGetArray(g_aSpawn, iBest, eSpawn)
        eSpawn[SPAWN_FLAGS] |= FLAG_SELECT
        ArraySetArray(g_aSpawn, iBest, eSpawn)
        g_ePlayerData[id][PDATA_SPAWN_MENU] = iBest
    }
}

stock spawnSetAnim(iEnt)
{
    set_pev(iEnt, pev_sequence, g_eSettings[SETTING_DEFAULT_SEQUENCE])
    set_pev(iEnt, pev_frame, 0.0)
    set_pev(iEnt, pev_framerate, g_eSettings[SETTING_DEFAULT_FRAMERATE])
    set_pev(iEnt, pev_animtime, get_gametime())
}

stock bool:isSpawnSafe(Float:fOrigin[3])
{
    new eSpawn[SPAWN]
    for ( new i = 0; i < g_iSpawn; i ++ )
    {
        ArrayGetArray(g_aSpawn, i, eSpawn)

        if ( xs_vec_distance(eSpawn[SPAWN_ORIGIN], fOrigin) < 5.0 )
            return false
    }

    return true
}

stock spawnSound(iEnt, iSound, iChan = CHAN_ITEM, bool:bPlayer = true, iFlags = 0, iPitch = PITCH_NORM)
{
    new szSample[MAX_RESOURCE_PATH_LENGTH]

    switch( iSound )
    {
        case SOUND_MENU_NAV:        copy(szSample, charsmax(szSample), g_eSettings[SETTING_SOUND_MENU_NAV])
        case SOUND_MENU_REMOVE:     copy(szSample, charsmax(szSample), g_eSettings[SETTING_SOUND_MENU_REMOVE])
        case SOUND_MENU_ALERT:      copy(szSample, charsmax(szSample), g_eSettings[SETTING_SOUND_MENU_ALERT])
    }

    if ( bPlayer )
        client_cmd(iEnt, "spk %s", szSample)
    else
        engfunc(EngFunc_EmitSound, iEnt, iChan, szSample, VOL_NORM, ATTN_NORM, iFlags, iPitch)
}

stock spawnGet(eSpawn[SPAWN], iEnt)
{
    new iItem
    iItem = pev(iEnt, SPAWN_ARRAY_ITEM)
    if ( iItem < 0 || iItem >= g_iSpawn )
        return -1

    ArrayGetArray(g_aSpawn, iItem, eSpawn)
    return iItem
}

stock bool:isSpawn(iEnt)
{
    return pev(iEnt, pev_impulse) == SPAWN_KEY
}

stock spawnKill(iEnt)
{
    if ( pev_valid(iEnt) )
        engfunc(EngFunc_RemoveEntity, iEnt)
}

stock parseSetting(iType, szKey[], iKeyLen, szValue[], iValueLen, any:output[], iOutputLen, const any:fallback[] = {0.0, 0.0})
{
    switch ( iType )
    {
        case DTYPE_FLOAT_RANGE:
        {
            strtok(szValue, szKey, iKeyLen, szValue, iValueLen, ' ')
            output[0] = str_to_float(szKey)
            output[1] = str_to_float(szValue)

            if ( output[0] < 0.0 ) output[0] = fallback[0]
            if ( output[1] < 0.0 ) output[1] = fallback[1]
        }
        case DTYPE_FLOAT:
        {
            output[0] = str_to_float(szValue)
            if ( output[0] < 0.0 ) output[0] = fallback[0]
        }
        case DTYPE_INT:
        {
            output[0] = str_to_num(szValue)
            if ( output[0] < 0 ) output[0] = fallback[0]
        }
        case DTYPE_BOOL:
        {
            output[0] = bool:str_to_num(szValue)
        }
        case DTYPE_FLAGS:
        {
            output[0] = read_flags(szValue)
        }
        case DTYPE_VECTOR:
        {
            strtok(szValue, szKey, iKeyLen, szValue, iValueLen, ' ')
            output[0] = str_to_num(szKey)

            strtok(szValue, szKey, iKeyLen, szValue, iValueLen, ' ')
            output[1] = str_to_num(szKey)
            output[2] = str_to_num(szValue)
        }
        case DTYPE_VECTOR_FLOAT:
        {
            strtok(szValue, szKey, iKeyLen, szValue, iValueLen, ' ')
            output[0] = str_to_float(szKey)

            strtok(szValue, szKey, iKeyLen, szValue, iValueLen, ' ')
            output[1] = str_to_float(szKey)
            output[2] = str_to_float(szValue)
        }
        case DTYPE_STRING_MODEL:
        {
            copy(output, iOutputLen, szValue)
            if ( !g_bFileWasRead ) precache_model(szValue)
        }
        case DTYPE_STRING_SOUND:
        {
            copy(output, iOutputLen, szValue)
            if ( !g_bFileWasRead ) precache_sound(szValue)
        }
    }
}

stock LogConfigError(const iLine, const szText[], any:...)
{
    new szError[MAX_PLATFORM_PATH_LENGTH]
    vformat(szError, charsmax(szError), szText, 3)

    log_to_file(ERROR_FILE, "^nLine %d: %s", iLine, szError)
}

#include <sourcemod>

#include <multicolors>
#include <autoexecconfig>

#include <translatedcustomcommand>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"

public Plugin myinfo =
{
    name = "SM:CustomCommands",
    author = "Nobody-x",
    description = "Adds custom commands for your players.",
    version = PLUGIN_VERSION,
    url = "https://github.com/Nobody-x/sm_custom_commands"
}

#define MAX_TRIGGER_LENGTH 2
#define CONVAR_MAX_LEN 255

#define CONFIG_NAME "CustomCommands"
char g_sConfigPath[PLATFORM_MAX_PATH];

// Translated type commands
ArrayList g_alTranslatedCommands = null;
ArrayList g_alTranslatedCommandsMap = null;

ConVar g_cvEnabled;
ConVar g_cvPublicTrigger;
ConVar g_cvSilentTrigger;

char g_sPublicTrigger[MAX_TRIGGER_LENGTH];
char g_sSilentTrigger[MAX_TRIGGER_LENGTH];

public void OnPluginStart()
{
    AutoExecConfig_SetFile("plugin.sm_custom_commands");

    CreateConVar("sm_smcc_version", PLUGIN_VERSION, "SM:CustomCommands version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
    g_cvEnabled = AutoExecConfig_CreateConVar("sm_smcc_enable", "1", "If set to 1, SM:CustomCommands is enabled. If set to 0, SM:CustomCommands is disabled.", 0, true, 0.0, true, 1.0);
    g_cvPublicTrigger = AutoExecConfig_CreateConVar("sm_smcc_public_chat_trigger", "!", "This will be the public command prefix and should be the same as PublicChatTrigger in sourcemod's core.cfg.", 0);
    g_cvSilentTrigger = AutoExecConfig_CreateConVar("sm_smcc_silent_chat_trigger", "/", "This will be the silent command prefix and should be the same as SilentChatTrigger in sourcemod's core.cfg.", 0);

    g_cvPublicTrigger.AddChangeHook(ConVarHook_PublicTrigger);
    g_cvSilentTrigger.AddChangeHook(ConVarHook_SilentTrigger);

    AutoExecConfig_ExecuteFile();

    LoadTranslations("sm_custom_commands.phrases");
    LoadTranslations("sm_custom_commands.translated_commands.phrases");

    RegAdminCmd("smcc_reload_config", ConfigReload, ADMFLAG_ROOT, "Reloads the SM:CustomCommands configuration file", "smcc");

    // Create our path to the configuration
    BuildPath(Path_SM, g_sConfigPath, sizeof(g_sConfigPath), "configs/sm_custom_commands.cfg");
}

public void OnMapStart()
{
    LoadConfig();

    g_cvPublicTrigger.GetString(g_sPublicTrigger, sizeof(g_sPublicTrigger));
    g_cvSilentTrigger.GetString(g_sSilentTrigger, sizeof(g_sSilentTrigger));
}

public Action ConfigReload(int client, int argc)
{
    LoadConfig();

    CReplyToCommand(client, "%t", "Configuration reloaded");

    return Plugin_Handled;
}

public Action OnClientCommand(int client, int args)
{
    if (!g_cvEnabled.BoolValue) {
        return Plugin_Continue;
    }

    char sCmd[192];
    GetCmdArg(0, sCmd, sizeof(sCmd));

    HandleClientCommand(client, sCmd);

    return Plugin_Continue;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
    if (!g_cvEnabled.BoolValue) {
        return Plugin_Continue;
    }

    char sSubStr[MAX_TRIGGER_LENGTH];
    strcopy(sSubStr, sizeof(sSubStr), sArgs);

    bool isSilent = strcmp(sSubStr, g_sSilentTrigger) == 0;
    bool isPublic = strcmp(sSubStr, g_sPublicTrigger) == 0;

    if (!isSilent && !isPublic) {
        // The message does not contains configured trigger at first position
        return Plugin_Continue;
    }

    // retrieve command (!cmd | /cmd => sm_cmd)
    char sCmd[CONVAR_MAX_LEN];

    // Store the current player command into it
    strcopy(sCmd, CONVAR_MAX_LEN, sArgs);

    ReplaceStringEx(
        sCmd,
        CONVAR_MAX_LEN,
        isSilent ? g_sSilentTrigger : g_sPublicTrigger,
        "sm_"
    );

    // Try to execute that command
    Action aResult = HandleClientCommand(client, sCmd);

    if (aResult == Plugin_Continue) {
        // The client command does nothing
        return Plugin_Continue;
    }

    // Handle silent trigger here
    return isSilent ? Plugin_Handled : Plugin_Continue;
}

public Action HandleClientCommand(int client, const char[] cmd)
{
    if (g_alTranslatedCommands && g_alTranslatedCommands.FindString(cmd) != -1) {
        OnClientExecuteTranslatedCommand(client, cmd);

        return Plugin_Handled;
    }

    return Plugin_Continue;
}

public void OnClientExecuteTranslatedCommand(int client, const char[] sArgs)
{
    int iCmdIndex = g_alTranslatedCommands.FindString(sArgs);
    char sTranslation[MAX_TRANSLATION_SIZE];
    TranslatedCustomCommand tcCommand;

    tcCommand = g_alTranslatedCommandsMap.Get(iCmdIndex);
    tcCommand.GetTranslation(sTranslation, sizeof(sTranslation));

    if (TranslationPhraseExists(sTranslation)) {
        CPrintToChat(client, "%t", sTranslation);

        return;
    }

    LogError("The translation %s for the command %s is not found.\nMaybe you forget to reload the translation ?", sTranslation, sArgs);
}

public void ConVarHook_PublicTrigger(ConVar convar, const char[] oldValue, const char[] newValue)
{
    convar.GetString(g_sPublicTrigger, sizeof(g_sPublicTrigger));
}

public void ConVarHook_SilentTrigger(ConVar convar, const char[] oldValue, const char[] newValue)
{
    convar.GetString(g_sSilentTrigger, sizeof(g_sSilentTrigger));
}


/**
 *  Load (or reload) the whole configuration file
 */
public void LoadConfig()
{
    // Reset all ArrayList
    CleanCommandsList();

    // Open config and retrieve a KeyValues
    KeyValues kv = GetKVConfig();
    if (!kv.GotoFirstSubKey()) {
        // No commands defined.
        return;
    }

    char sCmdName[CONVAR_MAX_LEN], sCmdType[CONVAR_MAX_LEN];
    do {
        kv.GetSectionName(sCmdName, sizeof(sCmdName));
        kv.GetString("type", sCmdType, sizeof(sCmdType));

        // Here handle all type of command
        if (StrEqual(sCmdType, "t")) {
            HandleTranslatedCmd(sCmdName, kv);
        }
    } while(kv.GotoNextKey());

    delete kv;
}

public void HandleTranslatedCmd(const char[] sCmdName, const KeyValues kv)
{
    // Check if the key exists
    if (!kv.JumpToKey("translation", false)) {
        LogError("Translation key not found for \"%s\" command.", sCmdName);
        return;
    }

    // Go back and get the key value
    kv.GoBack();

    char sTranslation[MAX_TRANSLATION_SIZE];
    kv.GetString("translation", sTranslation, sizeof(sTranslation));

    TranslatedCustomCommand tccCommand = new TranslatedCustomCommand();
    tccCommand.SetName(sCmdName);
    tccCommand.SetTranslation(sTranslation);

    if (!g_alTranslatedCommands) {
        g_alTranslatedCommands = new ArrayList(MAX_CUSTOM_COMMAND_NAME);
    }

    if (!g_alTranslatedCommandsMap) {
        g_alTranslatedCommandsMap = new ArrayList();
    }

    if (g_alTranslatedCommands.FindString(sCmdName) != -1) {
        return;
    }

    g_alTranslatedCommands.PushString(sCmdName);
    g_alTranslatedCommandsMap.Push(tccCommand);
}

stock void CleanCommandsList()
{
    delete g_alTranslatedCommands;
    delete g_alTranslatedCommandsMap;
}

stock KeyValues GetKVConfig() {
    if (!FileExists(g_sConfigPath))
        ThrowError("Unable to locate configuration file at \"%s\"", g_sConfigPath);

    KeyValues config = new KeyValues(CONFIG_NAME);
    if (!config)
        return null;

    config.ImportFromFile(g_sConfigPath);

    return config;
}
--[[
    ============================================================================
    FiveRoster - Shared Configuration
    ============================================================================

    This file contains all client-side and shared configuration options.
    For server-side configuration (API key), see server/config.lua

    Documentation: https://docs.fiveroster.com/fivem
    Support: https://discord.gg/FtZ57TGE64
    ============================================================================
]]

Config = {}

--[[
    ============================================================================
    DEBUG SETTINGS
    ============================================================================
    Enable debug mode to see detailed logs in the console.
    Useful for troubleshooting issues.
]]
Config.Debug = {
    enabled = false,              -- Set to true to enable debug logging
    logAPIRequests = true,        -- Log outgoing API requests
    logAPIResponses = true,       -- Log API responses
    logSessionCreation = true,    -- Log session creation details
    redactSensitiveData = true    -- Redact sensitive data (Discord IDs, etc.) in logs
}

--[[
    ============================================================================
    FIVEROSTER API SETTINGS
    ============================================================================
    Configure your FiveRoster instance URL.
    Default is the hosted FiveRoster service.
]]
Config.FiveRosterURL = 'https://fiveroster.com'

--[[
    ============================================================================
    DISCORD ID SOURCE
    ============================================================================
    Choose how to retrieve the player's Discord ID.

    Options:
      'fivem'  - Uses FiveM's built-in Discord identifier (recommended)
                 Requires players to have Discord linked to their FiveM account
      'esx'    - Uses ESX identity system, with FiveM fallback
      'qbcore' - Uses QBCore player metadata, with FiveM fallback
      'custom' - Uses a custom export from another resource
]]
Config.DiscordSource = 'fivem'

-- Custom Discord Export Configuration
-- Only used when DiscordSource is set to 'custom'
Config.CustomDiscordExport = {
    resource = 'your_resource',      -- The resource name that provides the export
    export = 'GetPlayerDiscordId'    -- The export function name
    -- The export should accept (source) and return the Discord ID as a string
}

--[[
    ============================================================================
    COMMAND SETTINGS
    ============================================================================
    Configure the command(s) that players use to open FiveRoster.
]]
Config.CommandName = 'rosters'           -- Primary command: /rosters
Config.CommandAliases = {'roster', 'fr'} -- Alternative commands: /roster, /fr

--[[
    ============================================================================
    NOTIFICATION SYSTEM
    ============================================================================
    Choose which notification system to use for displaying messages.

    Options:
      'native'  - GTA V native notifications (works everywhere)
      'ox_lib'  - ox_lib notifications (requires ox_lib resource)
      'esx'     - ESX notifications (requires es_extended)
      'qbcore'  - QBCore notifications (requires qb-core)
]]
Config.NotifySystem = 'native'

--[[
    ============================================================================
    TABLET ANIMATION
    ============================================================================
    Configure the tablet prop and animation shown when FiveRoster is open.
]]
Config.UseTablet = true                                       -- Show tablet prop and animation
Config.TabletModel = 'prop_cs_tablet'                         -- Tablet prop model
Config.TabletDict = 'amb@world_human_seat_wall_tablet@female@base'  -- Animation dictionary
Config.TabletAnim = 'base'                                    -- Animation name

--[[
    ============================================================================
    MESSAGES
    ============================================================================
    Customize notification messages. Useful for localization.
]]
Config.Messages = {
    no_discord = 'You must have Discord linked to your FiveM account to use FiveRoster.',
    loading = 'Loading FiveRoster...',
    error = 'An error occurred. Please try again.',
    session_error = 'Failed to connect to FiveRoster. Please try again.',
    not_in_guild = 'You are not a member of this Discord server.',
    no_rosters = 'You are not enrolled in any rosters.'
}

--[[
    ============================================================================
    RANK-TO-JOB SYNCHRONIZATION
    ============================================================================
    Automatically sync FiveRoster ranks to in-game jobs/grades.
    When a player's rank changes on FiveRoster, their in-game job will update.

    Framework options:
      'esx'    - Uses ESX job system (es_extended)
      'qbcore' - Uses QBCore job system (qb-core)
      'qbox'   - Uses QBox job system (qbx_core)
      'none'   - Disabled (default)
]]
Config.JobSync = {
    enabled = false,                  -- Set to true to enable rank-to-job sync
    framework = 'none',               -- 'esx', 'qbcore', 'qbox', or 'none'
    syncOnJoin = true,                -- Sync job when player joins the server
    syncOnRankChange = true,          -- Sync job when rank changes (via webhook)

    -- Multi-character frameworks (ESX/QBCore/QBox) fire their PlayerLoaded event
    -- every time a character is selected, including character switches. Leaving this
    -- at false restricts Discord role sync to the first character loaded in a session
    -- so switching characters does not apply the synced job to every character.
    -- Set to true to sync on every character load.
    syncOnCharacterSwitch = false,

    --[[
        Rank-to-Job Mappings
        Map FiveRoster rank UUIDs to in-game job/grade combinations.

        Get rank UUIDs from FiveRoster:
        1. Go to your roster on fiveroster.com
        2. Click Edit on a rank
        3. Click "Copy Rank ID" button

        Format:
        ['rank-uuid-here'] = {
            job = 'police',           -- The job name in your framework
            grade = 5,                -- The grade/rank number
            label = 'Sergeant'        -- Optional: custom label (QBCore/QBox only)
        }

        Example for a Police Department roster:
        ['abc123-def456-...'] = { job = 'police', grade = 0 },   -- Cadet
        ['ghi789-jkl012-...'] = { job = 'police', grade = 1 },   -- Officer
        ['mno345-pqr678-...'] = { job = 'police', grade = 2 },   -- Sergeant
        ['stu901-vwx234-...'] = { job = 'police', grade = 3 },   -- Lieutenant
        ['yza567-bcd890-...'] = { job = 'police', grade = 4 },   -- Captain
        ['efg123-hij456-...'] = { job = 'police', grade = 5 },   -- Chief

        You can also map ranks from different rosters to different jobs:
        ['pd-rank-uuid'] = { job = 'police', grade = 2 },
        ['ems-rank-uuid'] = { job = 'ambulance', grade = 3 },
        ['fire-rank-uuid'] = { job = 'fire', grade = 1 },
    ]]
    rankMappings = {
        -- Add your rank mappings here
        -- ['your-rank-uuid'] = { job = 'police', grade = 0 },
    },

    --[[
        Fallback Job (Optional)
        If a player is not in any mapped rank, set them to this job.
        Leave as nil to not change their job if no mapping is found.
    ]]
    fallbackJob = nil,               -- Example: { job = 'unemployed', grade = 0 }

    --[[
        Priority Order (Optional)
        If a player has multiple ranks across rosters, which job takes priority?
        List roster UUIDs in order of priority (first = highest priority).
        If not specified, the first matching rank found will be used.
    ]]
    rosterPriority = {
        -- 'pd-roster-uuid',         -- Police takes priority
        -- 'ems-roster-uuid',        -- Then EMS
        -- 'fire-roster-uuid',       -- Then Fire
    }
}

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

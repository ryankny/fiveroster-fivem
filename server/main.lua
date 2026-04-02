--[[
    ============================================================================
    FiveRoster for FiveM - Server Script
    ============================================================================

    This script handles:
    - FiveRoster API communication
    - Session creation and validation
    - Discord ID retrieval (multi-framework support)
    - Shift tracking and auto-end on disconnect

    Exports provided:
    - HasActiveShift(source) : boolean
    - GetActiveShift(source) : table or nil
    - StartShift(source, rosterUuid, flagId, callback) : boolean
    - EndShift(source, callback) : boolean
    - GetPlayerRosters(source, callback) : boolean

    Events triggered:
    - fiveroster:onShiftStarted (source, shiftData)
    - fiveroster:onShiftEnded (source, shiftData)

    Documentation: https://docs.fiveroster.com/fivem
    ============================================================================
]]

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

print('^3[FiveRoster]^7 Loading server/main.lua...')

-- Ensure ServerConfig exists (in case server/config.lua is missing or failed to load)
if not ServerConfig then
    print('^1[FiveRoster]^7 WARNING: ServerConfig is nil - server/config.lua may have failed to load')
    print('^1[FiveRoster]^7 Please copy server/config.lua.example to server/config.lua and add your API key')
    ServerConfig = {
        APIKey = 'YOUR_API_KEY_HERE'
    }
else
    print('^2[FiveRoster]^7 ServerConfig loaded successfully')
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Debug logging helper
local function DebugLog(category, message, ...)
    if not Config.Debug or not Config.Debug.enabled then return end

    local categoryEnabled = {
        api_request = Config.Debug.logAPIRequests,
        api_response = Config.Debug.logAPIResponses,
        session = Config.Debug.logSessionCreation,
        discord = Config.Debug.logSessionCreation
    }

    if categoryEnabled[category] == false then return end

    local prefix = '^3[FiveRoster:Server]^7'
    local categoryTag = '^5[' .. category:upper() .. ']^7'

    if select('#', ...) > 0 then
        print(string.format('%s %s %s', prefix, categoryTag, string.format(message, ...)))
    else
        print(string.format('%s %s %s', prefix, categoryTag, message))
    end
end

-- Redact sensitive data for logging
local function RedactString(str, showChars)
    if not Config.Debug or not Config.Debug.redactSensitiveData then return str end
    if not str or #str < 8 then return '***REDACTED***' end

    showChars = showChars or 4
    local prefix = string.sub(str, 1, showChars)
    local suffix = string.sub(str, -showChars)
    return prefix .. '...' .. string.rep('*', 8) .. '...' .. suffix
end

-- Get player Discord ID from various sources
local function GetPlayerDiscordId(source)
    DebugLog('discord', 'Retrieving Discord ID for player %s', GetPlayerName(source))

    -- FiveM native Discord identifier
    if Config.DiscordSource == 'fivem' then
        for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
            if string.match(identifier, 'discord:') then
                local discordId = string.gsub(identifier, 'discord:', '')
                DebugLog('discord', 'Found Discord ID via FiveM: %s', RedactString(discordId, 6))
                return discordId
            end
        end
        return nil
    end

    -- ESX Framework
    if Config.DiscordSource == 'esx' then
        if GetResourceState('es_extended') ~= 'started' then
            DebugLog('discord', 'ESX not found, falling back to FiveM identifiers')
            -- Fallback to FiveM identifiers
            for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
                if string.match(identifier, 'discord:') then
                    return string.gsub(identifier, 'discord:', '')
                end
            end
            return nil
        end

        local ESX = exports['es_extended']:getSharedObject()
        local xPlayer = ESX.GetPlayerFromId(source)

        if xPlayer then
            local discordId = xPlayer.get('discord')
            if discordId then
                DebugLog('discord', 'Found Discord ID via ESX: %s', RedactString(discordId, 6))
                return discordId
            end
        end

        -- Fallback to FiveM identifiers
        for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
            if string.match(identifier, 'discord:') then
                return string.gsub(identifier, 'discord:', '')
            end
        end

        return nil
    end

    -- QBCore Framework
    if Config.DiscordSource == 'qbcore' then
        if GetResourceState('qb-core') ~= 'started' then
            DebugLog('discord', 'QBCore not found, falling back to FiveM identifiers')
            -- Fallback to FiveM identifiers
            for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
                if string.match(identifier, 'discord:') then
                    return string.gsub(identifier, 'discord:', '')
                end
            end
            return nil
        end

        local QBCore = exports['qb-core']:GetCoreObject()
        local Player = QBCore.Functions.GetPlayer(source)

        if Player then
            local metadata = Player.PlayerData.metadata
            if metadata and metadata.discord then
                DebugLog('discord', 'Found Discord ID via QBCore: %s', RedactString(metadata.discord, 6))
                return metadata.discord
            end
        end

        -- Fallback to FiveM identifiers
        for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
            if string.match(identifier, 'discord:') then
                return string.gsub(identifier, 'discord:', '')
            end
        end

        return nil
    end

    -- Custom export
    if Config.DiscordSource == 'custom' then
        local resourceName = Config.CustomDiscordExport.resource
        local exportName = Config.CustomDiscordExport.export

        if GetResourceState(resourceName) ~= 'started' then
            DebugLog('discord', 'Custom resource %s not found', resourceName)
            return nil
        end

        local success, result = pcall(function()
            return exports[resourceName][exportName](source)
        end)

        if success and result then
            DebugLog('discord', 'Found Discord ID via custom export: %s', RedactString(result, 6))
            return result
        end

        return nil
    end

    return nil
end

-- Make HTTP request to FiveRoster API to create session
local function CreateFiveRosterSession(discordId, playerName, callback)
    local url = Config.FiveRosterURL .. '/api/v1/fivem/session'

    local requestBody = {
        discord_id = discordId,
        player_name = playerName,
        server_identifier = GetConvar('sv_hostname', 'Unknown Server')
    }

    DebugLog('api_request', 'POST %s', url)
    DebugLog('api_request', 'Discord ID: %s, Player: %s', RedactString(discordId, 6), playerName)

    PerformHttpRequest(url, function(statusCode, response, headers)
        DebugLog('api_response', 'Status: %s', tostring(statusCode))

        if statusCode == 200 or statusCode == 201 then
            local data = json.decode(response)

            if data and data.success and data.embed_url then
                DebugLog('api_response', 'Session created successfully')
                callback(true, data.embed_url, data.roster_count or 0)
            else
                local errorMsg = data and data.error and data.error.message or 'Unknown error'
                DebugLog('api_response', 'API Error: %s', errorMsg)

                -- Handle specific error codes
                if data and data.error then
                    if data.error.code == 'not_in_guild' then
                        callback(false, Config.Messages.not_in_guild)
                    else
                        callback(false, errorMsg)
                    end
                else
                    callback(false, Config.Messages.session_error)
                end
            end
        elseif statusCode == 401 then
            DebugLog('api_response', 'API Key invalid or expired')
            callback(false, 'API authentication failed. Contact server administrator.')
        elseif statusCode == 403 then
            DebugLog('api_response', 'Access forbidden - player may not be in guild')
            callback(false, Config.Messages.not_in_guild)
        else
            DebugLog('api_response', 'HTTP Error: %s', tostring(statusCode))
            callback(false, Config.Messages.session_error)
        end
    end, 'POST', json.encode(requestBody), {
        ['Content-Type'] = 'application/json',
        ['X-API-KEY'] = ServerConfig.APIKey,
        ['Accept'] = 'application/json'
    })
end

-- Handle session request from client
RegisterNetEvent('fiveroster:requestSession', function()
    local source = source
    local playerName = GetPlayerName(source)

    DebugLog('session', 'Session request from %s', playerName)

    -- Check API key is configured
    if not ServerConfig or not ServerConfig.APIKey or ServerConfig.APIKey == 'YOUR_API_KEY_HERE' then
        DebugLog('session', 'API key not configured!')
        TriggerClientEvent('fiveroster:sessionError', source, 'Server not configured. Contact administrator.')
        return
    end

    -- Get Discord ID
    local discordId = GetPlayerDiscordId(source)

    if not discordId then
        DebugLog('session', 'No Discord ID found for player')
        TriggerClientEvent('fiveroster:sessionError', source, Config.Messages.no_discord)
        return
    end

    -- Create session
    CreateFiveRosterSession(discordId, playerName, function(success, result, rosterCount)
        if success then
            DebugLog('session', 'Session created for %s (%d rosters)', playerName, rosterCount)
            TriggerClientEvent('fiveroster:sessionCreated', source, result, rosterCount)
        else
            DebugLog('session', 'Session failed for %s: %s', playerName, result)
            TriggerClientEvent('fiveroster:sessionError', source, result)
        end
    end)
end)

-- Track active shifts for each player (keyed by source)
local activeShifts = {}

-- Get player's active shift from FiveRoster API
local function GetPlayerActiveShift(discordId, callback)
    local url = Config.FiveRosterURL .. '/api/v1/fivem/player/' .. discordId .. '/active-shift'

    PerformHttpRequest(url, function(statusCode, response, headers)
        if statusCode == 200 then
            local data = json.decode(response)
            if data and data.success then
                callback(data.shift)
            else
                callback(nil)
            end
        else
            callback(nil)
        end
    end, 'GET', '', {
        ['Content-Type'] = 'application/json',
        ['X-API-KEY'] = ServerConfig.APIKey,
        ['Accept'] = 'application/json'
    })
end

-- End a player's active shift via FiveRoster API
local function EndPlayerShift(discordId, shiftId, reason, callback)
    local url = Config.FiveRosterURL .. '/api/v1/fivem/shift/' .. shiftId .. '/end'

    local requestBody = {
        discord_id = discordId,
        reason = reason or 'player_disconnect'
    }

    DebugLog('api_request', 'POST %s (ending shift)', url)

    PerformHttpRequest(url, function(statusCode, response, headers)
        DebugLog('api_response', 'End shift status: %s', tostring(statusCode))

        if statusCode == 200 then
            local data = json.decode(response)
            if data and data.success then
                callback(true, data)
            else
                callback(false, data and data.message or 'Unknown error')
            end
        else
            callback(false, 'HTTP error: ' .. tostring(statusCode))
        end
    end, 'POST', json.encode(requestBody), {
        ['Content-Type'] = 'application/json',
        ['X-API-KEY'] = ServerConfig.APIKey,
        ['Accept'] = 'application/json'
    })
end

-- Handle shift started notification from NUI/web
RegisterNetEvent('fiveroster:shiftStarted', function(shiftData)
    local source = source
    local discordId = GetPlayerDiscordId(source)

    if not discordId then return end

    -- Store active shift
    activeShifts[source] = {
        shiftId = shiftData.shift_id,
        rosterUuid = shiftData.roster_uuid,
        rosterName = shiftData.roster_name or 'Unknown Roster',
        startedAt = shiftData.started_at,
        discordId = discordId
    }

    DebugLog('shift', 'Player %s started shift %s on roster %s', GetPlayerName(source), shiftData.shift_id, shiftData.roster_uuid)

    -- Trigger event for other resources to use
    TriggerEvent('fiveroster:onShiftStarted', source, activeShifts[source])

    -- Notify client that shift is being tracked
    TriggerClientEvent('fiveroster:shiftTracking', source, true, activeShifts[source])
end)

-- Handle shift ended notification from NUI/web
RegisterNetEvent('fiveroster:shiftEnded', function(shiftData)
    local source = source
    local discordId = GetPlayerDiscordId(source)

    if not discordId then return end

    local previousShift = activeShifts[source]
    activeShifts[source] = nil

    DebugLog('shift', 'Player %s ended shift', GetPlayerName(source))

    -- Trigger event for other resources to use
    TriggerEvent('fiveroster:onShiftEnded', source, {
        shiftId = shiftData.shift_id,
        rosterUuid = shiftData.roster_uuid,
        durationSeconds = shiftData.duration_seconds,
        discordId = discordId
    })

    -- Notify client that shift tracking stopped
    TriggerClientEvent('fiveroster:shiftTracking', source, false, nil)
end)

-- Check if player has an active shift (export for other resources)
exports('HasActiveShift', function(source)
    return activeShifts[source] ~= nil
end)

-- Get player's active shift data (export for other resources)
exports('GetActiveShift', function(source)
    return activeShifts[source]
end)

-- Start a shift for a player via API (export for other resources like MDT)
-- Usage: exports['fiveroster']:StartShift(source, rosterUuid, flagId, callback)
-- callback receives (success, data) where data contains shift info or error message
exports('StartShift', function(source, rosterUuid, flagId, callback)
    local discordId = GetPlayerDiscordId(source)

    if not discordId then
        if callback then callback(false, 'Player has no Discord ID') end
        return false
    end

    -- Check if player already has an active shift locally
    if activeShifts[source] then
        if callback then
            callback(false, 'Player already has an active shift on ' .. (activeShifts[source].rosterName or 'another roster'))
        end
        return false
    end

    local url = Config.FiveRosterURL .. '/api/v1/fivem/shift/start'

    local requestBody = {
        discord_id = discordId,
        roster_uuid = rosterUuid,
        flag_id = flagId
    }

    DebugLog('api_request', 'POST %s (starting shift via export)', url)

    PerformHttpRequest(url, function(statusCode, response, headers)
        DebugLog('api_response', 'Start shift status: %s', tostring(statusCode))

        if statusCode == 200 or statusCode == 201 then
            local data = json.decode(response)
            if data and data.success and data.shift then
                -- Store active shift locally
                activeShifts[source] = {
                    shiftId = data.shift.id,
                    rosterUuid = data.shift.roster_uuid,
                    rosterName = data.shift.roster_name or 'Unknown Roster',
                    startedAt = data.shift.started_at,
                    discordId = discordId
                }

                DebugLog('shift', 'Player %s started shift via export on %s', GetPlayerName(source), data.shift.roster_name)

                -- Trigger event for other resources
                TriggerEvent('fiveroster:onShiftStarted', source, activeShifts[source])

                -- Notify client
                TriggerClientEvent('fiveroster:shiftTracking', source, true, activeShifts[source])
                TriggerClientEvent('fiveroster:shiftStartedExternal', source, activeShifts[source])

                if callback then callback(true, data.shift) end
            else
                local errorMsg = data and data.message or 'Unknown error'
                DebugLog('shift', 'Failed to start shift via export: %s', errorMsg)
                if callback then callback(false, errorMsg) end
            end
        else
            local errorMsg = 'HTTP error: ' .. tostring(statusCode)
            if statusCode == 400 then
                local data = json.decode(response)
                errorMsg = data and data.message or errorMsg
            end
            DebugLog('shift', 'Failed to start shift via export: %s', errorMsg)
            if callback then callback(false, errorMsg) end
        end
    end, 'POST', json.encode(requestBody), {
        ['Content-Type'] = 'application/json',
        ['X-API-KEY'] = ServerConfig.APIKey,
        ['Accept'] = 'application/json'
    })

    return true -- Request sent (async)
end)

-- End a player's active shift via API (export for other resources like MDT)
-- Usage: exports['fiveroster']:EndShift(source, callback)
-- callback receives (success, data) where data contains shift info or error message
exports('EndShift', function(source, callback)
    local discordId = GetPlayerDiscordId(source)

    if not discordId then
        if callback then callback(false, 'Player has no Discord ID') end
        return false
    end

    -- Check if player has an active shift locally
    local localShift = activeShifts[source]
    if not localShift then
        -- Still try API in case shift exists on server but not tracked locally
        DebugLog('shift', 'No local shift tracked, checking API...')
    end

    local url = Config.FiveRosterURL .. '/api/v1/fivem/shift/end'

    local requestBody = {
        discord_id = discordId,
        reason = 'external_resource'
    }

    DebugLog('api_request', 'POST %s (ending shift via export)', url)

    PerformHttpRequest(url, function(statusCode, response, headers)
        DebugLog('api_response', 'End shift status: %s', tostring(statusCode))

        if statusCode == 200 then
            local data = json.decode(response)
            if data and data.success and data.shift then
                -- Clear local tracking
                activeShifts[source] = nil

                DebugLog('shift', 'Player %s ended shift via export', GetPlayerName(source))

                -- Trigger event for other resources
                TriggerEvent('fiveroster:onShiftEnded', source, {
                    shiftId = data.shift.id,
                    rosterUuid = data.shift.roster_uuid,
                    rosterName = data.shift.roster_name,
                    durationSeconds = data.shift.duration_seconds,
                    durationFormatted = data.shift.duration_formatted,
                    discordId = discordId
                })

                -- Notify client
                TriggerClientEvent('fiveroster:shiftTracking', source, false, nil)
                TriggerClientEvent('fiveroster:shiftEndedExternal', source, data.shift)

                if callback then callback(true, data.shift) end
            else
                local errorMsg = data and data.message or 'Unknown error'
                DebugLog('shift', 'Failed to end shift via export: %s', errorMsg)
                if callback then callback(false, errorMsg) end
            end
        elseif statusCode == 404 then
            -- No active shift found
            activeShifts[source] = nil
            if callback then callback(false, 'No active shift found') end
        else
            local errorMsg = 'HTTP error: ' .. tostring(statusCode)
            DebugLog('shift', 'Failed to end shift via export: %s', errorMsg)
            if callback then callback(false, errorMsg) end
        end
    end, 'POST', json.encode(requestBody), {
        ['Content-Type'] = 'application/json',
        ['X-API-KEY'] = ServerConfig.APIKey,
        ['Accept'] = 'application/json'
    })

    return true -- Request sent (async)
end)

-- Get list of rosters a player can start shifts on (export for other resources)
-- Usage: exports['fiveroster']:GetPlayerRosters(source, callback)
-- callback receives (success, rosters) where rosters is an array of {roster_uuid, name, shift_tracking_enabled}
exports('GetPlayerRosters', function(source, callback)
    local discordId = GetPlayerDiscordId(source)

    if not discordId then
        if callback then callback(false, 'Player has no Discord ID') end
        return false
    end

    local url = Config.FiveRosterURL .. '/api/v1/fivem/rosters?discord_id=' .. discordId

    DebugLog('api_request', 'GET %s', url)

    PerformHttpRequest(url, function(statusCode, response, headers)
        DebugLog('api_response', 'Get rosters status: %s', tostring(statusCode))

        if statusCode == 200 then
            local data = json.decode(response)
            if data and data.success and data.rosters then
                if callback then callback(true, data.rosters) end
            else
                if callback then callback(false, 'Failed to get rosters') end
            end
        else
            if callback then callback(false, 'HTTP error: ' .. tostring(statusCode)) end
        end
    end, 'GET', '', {
        ['Content-Type'] = 'application/json',
        ['X-API-KEY'] = ServerConfig.APIKey,
        ['Accept'] = 'application/json'
    })

    return true
end)

-- Handle player dropping - auto-end their shift
AddEventHandler('playerDropped', function(reason)
    local source = source
    local shift = activeShifts[source]

    if shift then
        DebugLog('shift', 'Player %s disconnected with active shift, ending shift...', GetPlayerName(source))

        -- End the shift via API
        EndPlayerShift(shift.discordId, shift.shiftId, 'player_disconnect', function(success, result)
            if success then
                DebugLog('shift', 'Successfully ended shift for disconnected player')
                -- Trigger event for other resources
                TriggerEvent('fiveroster:onShiftEnded', source, {
                    shiftId = shift.shiftId,
                    rosterUuid = shift.rosterUuid,
                    reason = 'player_disconnect',
                    discordId = shift.discordId
                })
            else
                DebugLog('shift', 'Failed to end shift for disconnected player: %s', tostring(result))
            end
        end)

        -- Clear from local tracking
        activeShifts[source] = nil
    end
end)

-- Sync active shift when player joins/opens FiveRoster
RegisterNetEvent('fiveroster:syncActiveShift', function()
    local source = source
    local discordId = GetPlayerDiscordId(source)

    if not discordId then return end

    GetPlayerActiveShift(discordId, function(shift)
        if shift then
            activeShifts[source] = {
                shiftId = shift.id,
                rosterUuid = shift.roster_uuid,
                rosterName = shift.roster_name or 'Unknown Roster',
                startedAt = shift.started_at,
                discordId = discordId
            }

            TriggerClientEvent('fiveroster:shiftTracking', source, true, activeShifts[source])
            DebugLog('shift', 'Synced active shift for player %s', GetPlayerName(source))
        else
            activeShifts[source] = nil
            TriggerClientEvent('fiveroster:shiftTracking', source, false, nil)
        end
    end)
end)

-- Handle shift start request from client export
RegisterNetEvent('fiveroster:startShiftExternal', function(rosterUuid, flagId)
    local source = source

    exports['fiveroster']:StartShift(source, rosterUuid, flagId, function(success, result)
        if not success then
            TriggerClientEvent('fiveroster:shiftError', source, result)
        end
    end)
end)

-- Handle shift end request from client export
RegisterNetEvent('fiveroster:endShiftExternal', function()
    local source = source

    exports['fiveroster']:EndShift(source, function(success, result)
        if not success then
            TriggerClientEvent('fiveroster:shiftError', source, result)
        end
    end)
end)

-- Resource start message
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    print('^3[FiveRoster]^7 Resource started')
    print('^3[FiveRoster]^7 Command: /' .. Config.CommandName)

    if not ServerConfig or not ServerConfig.APIKey or ServerConfig.APIKey == 'YOUR_API_KEY_HERE' then
        print('^1[FiveRoster] WARNING: API key not configured!^7')
        print('^1[FiveRoster] Copy server/config.lua.example to server/config.lua and add your API key^7')
    end
end)

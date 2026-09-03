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
    - PauseShift(source, callback) : boolean
    - ResumeShift(source, callback) : boolean
    - ToggleShiftPause(source, callback) : boolean
    - IsShiftPaused(source) : boolean
    - GetShiftDuration(source) : number or nil
    - IsShiftPauseSupported() : boolean
    - GetPlayerRosters(source, callback) : boolean

    Events triggered:
    - fiveroster:onShiftStarted (source, shiftData)
    - fiveroster:onShiftEnded (source, shiftData)
    - fiveroster:onShiftPaused (source, shiftData)
    - fiveroster:onShiftResumed (source, shiftData)

    A paused shift is still an active shift: HasActiveShift stays true and
    GetActiveShift keeps returning the shift while the player is on a break.

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

-- Decode an API response body, reporting whether it was JSON at all.
-- A FiveRoster instance that predates a route answers with an HTML 404 page
-- rather than JSON, which is how we detect unsupported endpoints.
local function TryDecodeJson(response)
    if type(response) ~= 'string' or response == '' then
        return nil, false
    end

    local ok, decoded = pcall(json.decode, response)
    if ok and type(decoded) == 'table' then
        return decoded, true
    end

    return nil, false
end

-- Get all configured API keys (combines APIKey and APIKeys)
local function GetAllApiKeys()
    local keys = {}

    -- Add primary API key
    if ServerConfig.APIKey and ServerConfig.APIKey ~= 'YOUR_API_KEY_HERE' and ServerConfig.APIKey ~= '' then
        table.insert(keys, ServerConfig.APIKey)
    end

    -- Add additional API keys from APIKeys array
    if ServerConfig.APIKeys and type(ServerConfig.APIKeys) == 'table' then
        for _, key in ipairs(ServerConfig.APIKeys) do
            if key and key ~= 'YOUR_API_KEY_HERE' and key ~= '' then
                -- Avoid duplicates
                local isDuplicate = false
                for _, existingKey in ipairs(keys) do
                    if existingKey == key then
                        isDuplicate = true
                        break
                    end
                end
                if not isDuplicate then
                    table.insert(keys, key)
                end
            end
        end
    end

    return keys
end

-- Check if multiple API keys are configured
local function HasMultipleApiKeys()
    return #GetAllApiKeys() > 1
end

-- Get the primary API key (first valid key)
local function GetPrimaryApiKey()
    local keys = GetAllApiKeys()
    return keys[1]
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

-- ============================================================================
-- DISCORD ID CACHE
-- ============================================================================
-- Discord IDs are cached per source as soon as we see the player.
--
-- This matters most on disconnect: by the time playerDropped runs, the player
-- may already be gone from the framework's player list (ESX/QBCore/custom
-- sources return nothing), and on some builds their identifiers are no longer
-- readable either. Without a Discord ID we cannot ask the backend to end the
-- shift, which is exactly how shifts were being left open when a player quit.
-- A Discord ID belongs to the account, not the character, so caching it for
-- the lifetime of the connection is safe.
local playerDiscordIds = {}

-- Resolve a player's Discord ID, preferring the cached value.
local function ResolvePlayerDiscordId(source)
    local key = tonumber(source) or source
    if key == nil then return nil end

    local cached = playerDiscordIds[key]
    if cached then return cached end

    -- Identifier and framework lookups can come back empty (or missing
    -- entirely) for a player who is already on their way out, so never let one
    -- take down the handler that is trying to end their shift.
    local ok, resolved = pcall(GetPlayerDiscordId, source)
    if not ok then
        DebugLog('discord', 'Discord ID lookup failed for %s: %s', tostring(source), tostring(resolved))
        return nil
    end

    if type(resolved) == 'number' then resolved = tostring(resolved) end

    if type(resolved) == 'string' and resolved ~= '' then
        playerDiscordIds[key] = resolved
        return resolved
    end

    return nil
end

-- Is a Discord ID currently held by a connected player?
-- Used to abandon a retry when the player has already reconnected, so we never
-- end a brand new shift on behalf of the session that just dropped.
local function IsDiscordIdOnline(discordId)
    for _, cached in pairs(playerDiscordIds) do
        if cached == discordId then return true end
    end
    return false
end

-- Warm the cache for a player (fire and forget)
local function CachePlayerDiscordId(source)
    local discordId = ResolvePlayerDiscordId(source)
    if discordId then
        DebugLog('discord', 'Cached Discord ID for %s', GetPlayerName(source) or tostring(source))
    end
    return discordId
end

-- Identifiers are readable from playerJoining onwards, well before the player
-- can start a shift, so this is the earliest reliable point to cache.
AddEventHandler('playerJoining', function()
    local src = source
    CachePlayerDiscordId(src)
end)

-- Make HTTP request to FiveRoster API to create session (single guild)
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
            local ok, parsed = pcall(json.decode, response or '')
            if not ok then parsed = nil end
            local errCode = parsed and parsed.error and parsed.error.code or nil
            local errMsg = parsed and parsed.error and parsed.error.message or nil
            DebugLog('api_response', 'HTTP 403 (code=%s, message=%s)', tostring(errCode), tostring(errMsg))
            if errCode == 'not_in_guild' then
                callback(false, Config.Messages.not_in_guild)
            else
                callback(false, errMsg or Config.Messages.session_error)
            end
        else
            DebugLog('api_response', 'HTTP Error: %s', tostring(statusCode))
            callback(false, Config.Messages.session_error)
        end
    end, 'POST', json.encode(requestBody), {
        ['Content-Type'] = 'application/json',
        ['X-API-KEY'] = GetPrimaryApiKey(),
        ['Accept'] = 'application/json'
    })
end

-- Make HTTP request to FiveRoster API to create multi-guild session
local function CreateFiveRosterMultiSession(discordId, playerName, callback)
    local url = Config.FiveRosterURL .. '/api/v1/fivem/session/multi'
    local apiKeys = GetAllApiKeys()

    local requestBody = {
        discord_id = discordId,
        player_name = playerName,
        server_identifier = GetConvar('sv_hostname', 'Unknown Server')
    }

    DebugLog('api_request', 'POST %s (multi-guild, %d keys)', url, #apiKeys)
    DebugLog('api_request', 'Discord ID: %s, Player: %s', RedactString(discordId, 6), playerName)

    -- Create comma-separated API keys for header
    local apiKeysHeader = table.concat(apiKeys, ',')

    PerformHttpRequest(url, function(statusCode, response, headers)
        DebugLog('api_response', 'Status: %s', tostring(statusCode))

        if statusCode == 200 or statusCode == 201 then
            local data = json.decode(response)

            if data and data.success and data.embed_url then
                DebugLog('api_response', 'Multi-guild session created successfully (%d guilds, %d rosters)',
                    data.guild_count or 0, data.roster_count or 0)
                callback(true, data.embed_url, data.roster_count or 0)
            else
                local errorMsg = data and data.error and data.error.message or 'Unknown error'
                DebugLog('api_response', 'API Error: %s', errorMsg)

                -- Handle specific error codes
                if data and data.error then
                    if data.error.code == 'not_in_any_guild' then
                        callback(false, Config.Messages.not_in_guild)
                    elseif data.error.code == 'no_rosters' then
                        callback(false, Config.Messages.no_rosters)
                    else
                        callback(false, errorMsg)
                    end
                else
                    callback(false, Config.Messages.session_error)
                end
            end
        elseif statusCode == 401 then
            DebugLog('api_response', 'API Key(s) invalid or expired')
            callback(false, 'API authentication failed. Contact server administrator.')
        elseif statusCode == 403 then
            local ok, parsed = pcall(json.decode, response or '')
            if not ok then parsed = nil end
            local errCode = parsed and parsed.error and parsed.error.code or nil
            local errMsg = parsed and parsed.error and parsed.error.message or nil
            DebugLog('api_response', 'HTTP 403 (code=%s, message=%s)', tostring(errCode), tostring(errMsg))
            if errCode == 'not_in_any_guild' then
                callback(false, Config.Messages.not_in_guild)
            elseif errCode == 'no_rosters' then
                callback(false, Config.Messages.no_rosters)
            else
                callback(false, errMsg or Config.Messages.session_error)
            end
        else
            DebugLog('api_response', 'HTTP Error: %s', tostring(statusCode))
            callback(false, Config.Messages.session_error)
        end
    end, 'POST', json.encode(requestBody), {
        ['Content-Type'] = 'application/json',
        ['X-API-KEYS'] = apiKeysHeader,
        ['Accept'] = 'application/json'
    })
end

-- Handle session request from client
RegisterNetEvent('fiveroster:requestSession', function()
    local source = source
    local playerName = GetPlayerName(source)

    DebugLog('session', 'Session request from %s', playerName)

    -- Check API key(s) are configured
    local apiKeys = GetAllApiKeys()
    if #apiKeys == 0 then
        DebugLog('session', 'No API keys configured!')
        TriggerClientEvent('fiveroster:sessionError', source, 'Server not configured. Contact administrator.')
        return
    end

    DebugLog('session', 'Using %d API key(s)', #apiKeys)

    -- Get Discord ID
    local discordId = ResolvePlayerDiscordId(source)

    if not discordId then
        DebugLog('session', 'No Discord ID found for player')
        TriggerClientEvent('fiveroster:sessionError', source, Config.Messages.no_discord)
        return
    end

    -- Create session (use multi-guild endpoint if multiple API keys configured)
    local sessionCallback = function(success, result, rosterCount)
        if success then
            DebugLog('session', 'Session created for %s (%d rosters)', playerName, rosterCount)
            TriggerClientEvent('fiveroster:sessionCreated', source, result, rosterCount)
        else
            DebugLog('session', 'Session failed for %s: %s', playerName, result)
            TriggerClientEvent('fiveroster:sessionError', source, result)
        end
    end

    if HasMultipleApiKeys() then
        CreateFiveRosterMultiSession(discordId, playerName, sessionCallback)
    else
        CreateFiveRosterSession(discordId, playerName, sessionCallback)
    end
end)

-- Track active shifts for each player (keyed by source).
-- A paused shift stays in here: a break is not a clock-out.
local activeShifts = {}

-- Whether this FiveRoster instance exposes the shift pause/resume routes.
-- nil = not determined yet, true/false = confirmed. An instance older than the
-- break feature answers those routes with an HTML 404 instead of JSON.
local shiftPauseSupported = nil

-- Standard API headers for authenticated calls
local function ApiHeaders()
    return {
        ['Content-Type'] = 'application/json',
        ['X-API-KEY'] = GetPrimaryApiKey(),
        ['Accept'] = 'application/json'
    }
end

-- Whether breaks are usable at all (config + backend support)
local function IsShiftPauseAvailable()
    if Config.ShiftPause and Config.ShiftPause.enabled == false then return false end
    return shiftPauseSupported ~= false
end

-- Tell a client whether it should offer the pause control
local function SendPauseAvailability(src)
    TriggerClientEvent('fiveroster:shiftPauseSupported', src, IsShiftPauseAvailable())
end

-- Merge an API shift object into the locally tracked shift for a source.
-- Returns the tracked shift table (nil if there was nothing to apply).
local function ApplyShiftPayload(src, discordId, shift)
    if type(shift) ~= 'table' then return nil end

    local tracked = activeShifts[src] or {}

    tracked.shiftId = shift.id or tracked.shiftId
    tracked.rosterUuid = shift.roster_uuid or tracked.rosterUuid
    tracked.rosterName = shift.roster_name or tracked.rosterName or 'Unknown Roster'
    tracked.startedAt = shift.started_at or tracked.startedAt
    tracked.discordId = discordId or tracked.discordId

    -- Break state. An older backend omits these entirely, which correctly
    -- leaves the shift reading as running rather than paused.
    if shift.is_paused ~= nil then
        tracked.isPaused = shift.is_paused == true
        -- Keep a known break start if this payload did not carry one; clear it
        -- outright once the shift is running again.
        if tracked.isPaused then
            tracked.pausedAt = shift.paused_at or tracked.pausedAt
        else
            tracked.pausedAt = nil
        end
        -- The presence of the field proves the instance knows about breaks.
        if shiftPauseSupported == nil then shiftPauseSupported = true end
    else
        tracked.isPaused = tracked.isPaused or false
        tracked.pausedAt = shift.paused_at or tracked.pausedAt
    end
    tracked.pausedSeconds = shift.paused_seconds or tracked.pausedSeconds or 0
    tracked.pauseCount = shift.pause_count or tracked.pauseCount or 0
    tracked.durationSeconds = shift.duration_seconds or tracked.durationSeconds or 0
    tracked.formattedDuration = shift.formatted_duration or shift.duration_formatted or tracked.formattedDuration

    -- Wall-clock stamp of the last server-truth duration, so consumers can
    -- extrapolate a running shift without drifting a paused one.
    tracked.durationSyncedAt = os.time()

    activeShifts[src] = tracked
    return tracked
end

-- Worked seconds for a tracked shift, frozen while the shift is on a break.
local function GetTrackedShiftDuration(src)
    local tracked = activeShifts[src]
    if not tracked then return nil end

    local base = tracked.durationSeconds or 0
    if tracked.isPaused then return base end

    local since = tracked.durationSyncedAt
    if not since then return base end

    return base + math.max(0, os.time() - since)
end

-- Get player's active shift from FiveRoster API.
-- callback(shift, info) - shift is nil when there is no open shift; info.isJson
-- is false when the instance answered with something other than JSON.
local function GetPlayerActiveShift(discordId, callback)
    local url = Config.FiveRosterURL .. '/api/v1/fivem/player/' .. discordId .. '/active-shift'

    PerformHttpRequest(url, function(statusCode, response, headers)
        local data, isJson = TryDecodeJson(response)

        if not isJson then
            DebugLog('api_response', 'Active shift lookup returned a non-JSON body (status %s)', tostring(statusCode))
            callback(nil, { isJson = false, statusCode = statusCode })
            return
        end

        if statusCode == 200 and data.success then
            callback(data.shift, { isJson = true, statusCode = statusCode })
        else
            callback(nil, { isJson = true, statusCode = statusCode })
        end
    end, 'GET', '', ApiHeaders())
end

-- Pause or resume a player's shift via the FiveRoster API.
-- callback(success, info) where info may carry:
--   shift          - the returned shift object
--   alreadyInState - the shift was already paused/running (HTTP 409)
--   noActiveShift  - the player has no open shift (HTTP 404 with JSON)
--   unsupported    - this FiveRoster instance has no such route
--   message        - human-readable message
local function SetPlayerShiftPaused(discordId, paused, callback)
    local action = paused and 'pause' or 'resume'
    local url = Config.FiveRosterURL .. '/api/v1/fivem/shift/' .. action

    DebugLog('api_request', 'POST %s (%s shift)', url, action)

    PerformHttpRequest(url, function(statusCode, response, headers)
        DebugLog('api_response', 'Shift %s status: %s', action, tostring(statusCode))

        local data, isJson = TryDecodeJson(response)

        if not isJson then
            -- An instance without the break routes serves an HTML 404 page.
            -- Anything else in that range is still not something we can parse,
            -- so treat it the same way and stop offering the control.
            if type(statusCode) == 'number' and statusCode >= 200 and statusCode < 500 then
                shiftPauseSupported = false
                DebugLog('shift', 'Shift breaks are not supported by this FiveRoster instance')
                callback(false, { unsupported = true, message = 'Shift breaks are not available on this FiveRoster instance' })
            else
                -- Network/gateway failure - says nothing about route support.
                callback(false, { message = 'HTTP error: ' .. tostring(statusCode) })
            end
            return
        end

        shiftPauseSupported = true

        if statusCode == 200 and data.success then
            callback(true, { shift = data.shift, message = data.message })
        elseif statusCode == 409 then
            -- The shift was already in the requested state. Not an error, and
            -- deliberately not retried: the backend leaves the running break
            -- alone rather than restarting it and losing banked time.
            callback(true, {
                shift = data.shift,
                alreadyInState = true,
                code = data.code,
                message = data.message
            })
        elseif statusCode == 404 then
            callback(false, { noActiveShift = true, message = data.message or 'No active shift found' })
        elseif statusCode == 401 then
            callback(false, { message = 'API authentication failed. Contact server administrator.' })
        else
            callback(false, { message = data.message or ('HTTP error: ' .. tostring(statusCode)) })
        end
    end, 'POST', json.encode({ discord_id = discordId }), ApiHeaders())
end

-- End a player's currently active shift via FiveRoster API (identified by
-- Discord ID). Used to auto-end shifts when a player disconnects. This mirrors
-- the endpoint used by the EndShift export so the disconnect path and the
-- manual/export path behave identically, and so it works even when we don't
-- have the shift ID cached locally (e.g. shift started on the web dashboard).
--
-- The backend closes any open break itself and records the worked time, so a
-- paused shift needs no special handling here.
--
-- Transient failures are retried: the disconnect path has no user to retry it
-- and a dropped request leaves the shift open indefinitely.
local END_SHIFT_MAX_ATTEMPTS = 3
local END_SHIFT_RETRY_DELAYS = { 2000, 5000 }

local function EndPlayerShift(discordId, reason, callback, attempt)
    attempt = attempt or 1

    local url = Config.FiveRosterURL .. '/api/v1/fivem/shift/end'

    local requestBody = {
        discord_id = discordId,
        reason = reason or 'player_disconnect'
    }

    DebugLog('api_request', 'POST %s (ending shift, attempt %d)', url, attempt)

    PerformHttpRequest(url, function(statusCode, response, headers)
        DebugLog('api_response', 'End shift status: %s', tostring(statusCode))

        local data = TryDecodeJson(response)

        if statusCode == 200 then
            if data and data.success then
                callback(true, data)
            else
                callback(false, (data and data.message) or 'Unknown error')
            end
            return
        end

        if statusCode == 404 then
            -- No active shift on the backend - nothing to end
            callback(false, 'No active shift found')
            return
        end

        -- Timeouts, rate limits, gateway errors and outright connection
        -- failures (FiveM reports those as a non-positive status) are worth
        -- another go. Anything else is a real rejection.
        local retryable = type(statusCode) ~= 'number'
            or statusCode <= 0
            or statusCode == 408
            or statusCode == 429
            or statusCode >= 500

        if retryable and attempt < END_SHIFT_MAX_ATTEMPTS then
            local delay = END_SHIFT_RETRY_DELAYS[attempt] or 5000
            DebugLog('shift', 'End shift failed (status %s), retrying in %dms', tostring(statusCode), delay)
            SetTimeout(delay, function()
                -- If the player reconnected in the meantime, their new session
                -- owns the shift now. Ending it here would close a shift they
                -- just started.
                if reason == 'player_disconnect' and IsDiscordIdOnline(discordId) then
                    DebugLog('shift', 'Abandoning end-shift retry - player reconnected')
                    callback(false, 'Player reconnected before the retry')
                    return
                end

                EndPlayerShift(discordId, reason, callback, attempt + 1)
            end)
            return
        end

        callback(false, 'HTTP error: ' .. tostring(statusCode))
    end, 'POST', json.encode(requestBody), ApiHeaders())
end

-- Handle shift started notification from NUI/web
RegisterNetEvent('fiveroster:shiftStarted', function(shiftData)
    local source = source
    local discordId = ResolvePlayerDiscordId(source)

    if not discordId then return end

    -- Store active shift. A freshly started shift is never on a break.
    activeShifts[source] = {
        shiftId = shiftData.shift_id,
        rosterUuid = shiftData.roster_uuid,
        rosterName = shiftData.roster_name or 'Unknown Roster',
        startedAt = shiftData.started_at,
        discordId = discordId,
        isPaused = false,
        pausedAt = nil,
        pausedSeconds = 0,
        pauseCount = 0,
        durationSeconds = shiftData.duration_seconds or 0,
        durationSyncedAt = os.time()
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
    local discordId = ResolvePlayerDiscordId(source)

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

-- ============================================================================
-- SHIFT BREAKS (PAUSE / RESUME)
-- ============================================================================

-- Re-read a player's shift (including break state) from FiveRoster and push it
-- to the client. This is the single source of truth used on player load, on a
-- resource restart, and after the tablet reports a break change.
-- callback(shift or nil) is optional.
local function SyncPlayerShiftState(src, callback)
    local discordId = ResolvePlayerDiscordId(src)

    if not discordId then
        if callback then callback(nil) end
        return false
    end

    GetPlayerActiveShift(discordId, function(shift, info)
        -- The player may have left while the request was in flight.
        if not GetPlayerName(src) then
            if callback then callback(nil) end
            return
        end

        if shift then
            local tracked = ApplyShiftPayload(src, discordId, shift)
            TriggerClientEvent('fiveroster:shiftTracking', src, true, tracked)
            DebugLog('shift', 'Synced active shift for player %s (paused: %s)',
                GetPlayerName(src), tostring(tracked and tracked.isPaused))
            if callback then callback(tracked) end
        else
            activeShifts[src] = nil
            TriggerClientEvent('fiveroster:shiftTracking', src, false, nil)
            if callback then callback(nil) end
        end

        SendPauseAvailability(src)
    end)

    return true
end

-- Apply a break state change and fan it out to the client and other resources.
local function BroadcastPauseChange(src, discordId, paused, shift, info)
    info = info or {}

    local tracked
    if type(shift) == 'table' then
        tracked = ApplyShiftPayload(src, discordId, shift)
    else
        tracked = activeShifts[src]
        if tracked then
            tracked.isPaused = paused
            tracked.durationSyncedAt = os.time()
        end
    end

    if tracked then
        -- Trust the outcome of the call even if the payload was thin.
        tracked.isPaused = paused
    end

    DebugLog('shift', 'Player %s %s their shift', GetPlayerName(src) or tostring(src),
        paused and 'paused' or 'resumed')

    -- Keep the client's copy of the shift in step (silent state sync).
    TriggerClientEvent('fiveroster:shiftTracking', src, tracked ~= nil, tracked)

    -- Tell the client to surface the change, unless it originated there.
    if not info.silent then
        TriggerClientEvent('fiveroster:shiftPauseChanged', src, paused, tracked, {
            alreadyInState = info.alreadyInState == true,
            origin = info.origin
        })
    end

    -- Event for other resources. The shift is still active either way.
    TriggerEvent(paused and 'fiveroster:onShiftPaused' or 'fiveroster:onShiftResumed', src, tracked or {
        discordId = discordId,
        isPaused = paused
    })
end

-- Pause or resume the given player's shift.
-- callback(success, info) mirrors SetPlayerShiftPaused.
local function ChangeShiftPause(src, paused, callback, origin)
    if Config.ShiftPause and Config.ShiftPause.enabled == false then
        if callback then callback(false, { unsupported = true, message = 'Shift breaks are disabled on this server' }) end
        return false
    end

    if shiftPauseSupported == false then
        if callback then callback(false, { unsupported = true, message = 'Shift breaks are not available on this FiveRoster instance' }) end
        return false
    end

    local discordId = ResolvePlayerDiscordId(src)

    if not discordId then
        if callback then callback(false, { message = 'Player has no Discord ID' }) end
        return false
    end

    SetPlayerShiftPaused(discordId, paused, function(success, info)
        info = info or {}

        if success then
            -- A 409 means the shift was already in this state. That is not an
            -- error: sync from the returned shift and carry on.
            BroadcastPauseChange(src, discordId, paused, info.shift, {
                alreadyInState = info.alreadyInState,
                silent = origin == 'nui',
                origin = origin
            })
        elseif info.noActiveShift then
            -- Backend says there is no open shift - drop stale local tracking.
            activeShifts[src] = nil
            TriggerClientEvent('fiveroster:shiftTracking', src, false, nil)
        elseif info.unsupported then
            SendPauseAvailability(src)
        end

        if callback then callback(success, info) end
    end)

    return true
end

-- Handle a break started from the tablet (NUI reported it after the web app
-- already told the backend). Nothing to call - just mirror the state.
local function HandleNuiPauseReport(src, shiftData, paused)
    local discordId = ResolvePlayerDiscordId(src)
    if not discordId then return end

    shiftPauseSupported = true

    local shift = nil
    if type(shiftData) == 'table' then
        shift = {
            id = shiftData.shift_id,
            roster_uuid = shiftData.roster_uuid,
            is_paused = paused,
            duration_seconds = shiftData.duration_seconds
        }
    end

    BroadcastPauseChange(src, discordId, paused, shift, { silent = true, origin = 'nui' })

    -- The tablet payload carries no break totals, so pull the full picture.
    local syncAfter = not (Config.ShiftSync and Config.ShiftSync.afterPauseChange == false)
    if syncAfter then
        SetTimeout(1000, function()
            SyncPlayerShiftState(src)
        end)
    end
end

RegisterNetEvent('fiveroster:shiftPaused', function(shiftData)
    HandleNuiPauseReport(source, shiftData, true)
end)

RegisterNetEvent('fiveroster:shiftResumed', function(shiftData)
    HandleNuiPauseReport(source, shiftData, false)
end)

-- Turn a failed pause/resume into the right client-side outcome.
-- A missing route is never a red error: the control is hidden instead.
local function ReportPauseFailure(src, success, info)
    if success then return end

    info = info or {}

    if info.unsupported then
        SendPauseAvailability(src)
        TriggerClientEvent('fiveroster:shiftPauseUnavailable', src, info.message)
        return
    end

    if info.noActiveShift then
        TriggerClientEvent('fiveroster:shiftNotActive', src)
        return
    end

    TriggerClientEvent('fiveroster:shiftError', src, info.message)
end

-- Handle a break requested from a command, keybind or client export
RegisterNetEvent('fiveroster:pauseShiftExternal', function()
    local src = source
    ChangeShiftPause(src, true, function(success, info)
        ReportPauseFailure(src, success, info)
    end, 'command')
end)

RegisterNetEvent('fiveroster:resumeShiftExternal', function()
    local src = source
    ChangeShiftPause(src, false, function(success, info)
        ReportPauseFailure(src, success, info)
    end, 'command')
end)

RegisterNetEvent('fiveroster:toggleShiftPauseExternal', function()
    local src = source
    local tracked = activeShifts[src]

    if tracked then
        ChangeShiftPause(src, not tracked.isPaused, function(success, info)
            ReportPauseFailure(src, success, info)
        end, 'command')
        return
    end

    -- Nothing tracked locally: resync first so the toggle acts on the truth
    -- rather than guessing, which is what stops a reconnect auto-resuming.
    SyncPlayerShiftState(src, function(shift)
        if not shift then
            TriggerClientEvent('fiveroster:shiftNotActive', src)
            return
        end

        ChangeShiftPause(src, not shift.isPaused, function(success, info)
            ReportPauseFailure(src, success, info)
        end, 'command')
    end)
end)

-- Ask the server whether the pause control should be offered
RegisterNetEvent('fiveroster:requestPauseSupport', function()
    SendPauseAvailability(source)
end)

-- Pause a player's shift (export for other resources)
-- Usage: exports['fiveroster']:PauseShift(source, callback)
exports('PauseShift', function(source, callback)
    return ChangeShiftPause(source, true, callback, 'export')
end)

-- Resume a player's shift (export for other resources)
-- Usage: exports['fiveroster']:ResumeShift(source, callback)
exports('ResumeShift', function(source, callback)
    return ChangeShiftPause(source, false, callback, 'export')
end)

-- Toggle a player's break state (export for other resources)
exports('ToggleShiftPause', function(source, callback)
    local tracked = activeShifts[source]

    if not tracked then
        if callback then callback(false, { noActiveShift = true, message = 'No active shift found' }) end
        return false
    end

    return ChangeShiftPause(source, not tracked.isPaused, callback, 'export')
end)

-- Is the player's active shift on a break? (export for other resources)
-- Note: this is NOT the opposite of HasActiveShift - a paused player is still
-- on duty.
exports('IsShiftPaused', function(source)
    local tracked = activeShifts[source]
    return tracked ~= nil and tracked.isPaused == true
end)

-- Worked seconds on the player's shift, frozen while on a break
exports('GetShiftDuration', function(source)
    return GetTrackedShiftDuration(source)
end)

-- Whether shift breaks are usable on this server/instance
exports('IsShiftPauseSupported', function()
    return IsShiftPauseAvailable()
end)

-- Check if player has an active shift (export for other resources).
-- A paused shift is still an active shift.
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
    local discordId = ResolvePlayerDiscordId(source)

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
                -- Store active shift locally (carries break state if present)
                ApplyShiftPayload(source, discordId, data.shift)

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
        ['X-API-KEY'] = GetPrimaryApiKey(),
        ['Accept'] = 'application/json'
    })

    return true -- Request sent (async)
end)

-- End a player's active shift via API (export for other resources like MDT)
-- Usage: exports['fiveroster']:EndShift(source, callback)
-- callback receives (success, data) where data contains shift info or error message
exports('EndShift', function(source, callback)
    local discordId = ResolvePlayerDiscordId(source)

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
        ['X-API-KEY'] = GetPrimaryApiKey(),
        ['Accept'] = 'application/json'
    })

    return true -- Request sent (async)
end)

-- Get list of rosters a player can start shifts on (export for other resources)
-- Usage: exports['fiveroster']:GetPlayerRosters(source, callback)
-- callback receives (success, rosters) where rosters is an array of {roster_uuid, name, shift_tracking_enabled}
exports('GetPlayerRosters', function(source, callback)
    local discordId = ResolvePlayerDiscordId(source)

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
        ['X-API-KEY'] = GetPrimaryApiKey(),
        ['Accept'] = 'application/json'
    })

    return true
end)

-- Handle player dropping - auto-end their shift.
-- We can't rely solely on the in-memory activeShifts cache: a player may have
-- started their shift on the FiveRoster web dashboard (so it was never tracked
-- in-game), or the server may have restarted since the shift began, wiping the
-- cache. Player identifiers are still available during playerDropped, so we
-- resolve the Discord ID (from the cached shift if present, otherwise live) and
-- ask the backend to end whatever active shift the player has.
AddEventHandler('playerDropped', function(reason)
    local src = source
    local shift = activeShifts[src]

    local playerName = GetPlayerName(src) or ('source ' .. tostring(src))

    -- Resolve the Discord ID before clearing anything. Order matters: the
    -- cache is the only reliable source once the player is gone, because
    -- framework lookups (and, on some builds, identifiers) return nothing here.
    local discordId = (shift and shift.discordId) or ResolvePlayerDiscordId(src)

    -- Clear local tracking
    activeShifts[src] = nil
    playerDiscordIds[tonumber(src) or src] = nil

    if not discordId then
        -- Nothing we can do without an ID. Say so loudly when we knew the
        -- player was on shift, since their shift will stay open.
        if shift then
            print(('^1[FiveRoster]^7 Could not end shift for disconnecting player %s - no Discord ID could be resolved'):format(playerName))
        end
        return
    end

    DebugLog('shift', 'Player %s disconnected, ending any active shift...', playerName)

    -- End the shift via API (no-op on the backend if there is no active shift).
    -- A paused shift needs no special handling: the end endpoint closes the
    -- open break itself and records the worked time.
    EndPlayerShift(discordId, 'player_disconnect', function(success, result)
        if success then
            DebugLog('shift', 'Successfully ended shift for disconnected player %s', playerName)
            -- Trigger event for other resources (use cached details if available)
            TriggerEvent('fiveroster:onShiftEnded', src, {
                shiftId = shift and shift.shiftId,
                rosterUuid = shift and shift.rosterUuid,
                reason = 'player_disconnect',
                discordId = discordId
            })
        else
            DebugLog('shift', 'No shift ended for disconnected player %s: %s', playerName, tostring(result))
        end
    end)
end)

-- Sync active shift (including break state) when a player loads, opens the
-- tablet, or after a resource restart. Never auto-resumes: whatever the
-- backend reports is what the player gets.
--
-- Clients can trigger this, so it is throttled per player to keep a misbehaving
-- or scripted client from hammering the FiveRoster API.
local SYNC_COOLDOWN_SECONDS = 5
local lastSyncRequest = {}

RegisterNetEvent('fiveroster:syncActiveShift', function()
    local src = source
    local now = os.time()

    if lastSyncRequest[src] and (now - lastSyncRequest[src]) < SYNC_COOLDOWN_SECONDS then
        DebugLog('shift', 'Ignoring rapid shift sync request from %s', GetPlayerName(src) or tostring(src))
        return
    end

    lastSyncRequest[src] = now
    SyncPlayerShiftState(src)
end)

AddEventHandler('playerDropped', function()
    lastSyncRequest[source] = nil
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

-- ============================================================================
-- RANK-TO-JOB SYNCHRONIZATION
-- ============================================================================

-- Framework objects (cached on first use)
local ESX = nil
local QBCore = nil
local QBX = nil

-- Initialize framework objects
local function GetFrameworkObject()
    if not Config.JobSync or not Config.JobSync.enabled then return nil end

    local framework = Config.JobSync.framework

    if framework == 'esx' then
        if ESX then return ESX end
        if GetResourceState('es_extended') == 'started' then
            ESX = exports['es_extended']:getSharedObject()
            return ESX
        end
    elseif framework == 'qbcore' then
        if QBCore then return QBCore end
        if GetResourceState('qb-core') == 'started' then
            QBCore = exports['qb-core']:GetCoreObject()
            return QBCore
        end
    elseif framework == 'qbox' then
        if QBX then return QBX end
        if GetResourceState('qbx_core') == 'started' then
            QBX = exports['qbx_core']:GetCoreObject()
            return QBX
        end
    end

    return nil
end

-- Set a player's job based on framework
local function SetPlayerJob(source, jobName, grade, label)
    if not Config.JobSync or not Config.JobSync.enabled then return false end

    local framework = Config.JobSync.framework
    local fw = GetFrameworkObject()

    if not fw then
        DebugLog('job_sync', 'Framework %s not available', framework)
        return false
    end

    if framework == 'esx' then
        local xPlayer = fw.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.setJob(jobName, grade)
            DebugLog('job_sync', 'Set ESX job for player %s: %s grade %d', GetPlayerName(source), jobName, grade)
            return true
        end
    elseif framework == 'qbcore' then
        local Player = fw.Functions.GetPlayer(source)
        if Player then
            Player.Functions.SetJob(jobName, grade)
            DebugLog('job_sync', 'Set QBCore job for player %s: %s grade %d', GetPlayerName(source), jobName, grade)
            return true
        end
    elseif framework == 'qbox' then
        local Player = fw.Functions.GetPlayer(source)
        if Player then
            Player.Functions.SetJob(jobName, grade)
            DebugLog('job_sync', 'Set QBox job for player %s: %s grade %d', GetPlayerName(source), jobName, grade)
            return true
        end
    end

    return false
end

-- Get job mapping for a rank UUID
local function GetJobForRank(rankUuid)
    if not Config.JobSync or not Config.JobSync.rankMappings then return nil end
    return Config.JobSync.rankMappings[rankUuid]
end

-- Find the best job mapping for a player based on their ranks
local function FindBestJobMapping(ranks)
    if not Config.JobSync or not Config.JobSync.enabled then return nil end
    if not ranks or #ranks == 0 then return nil end

    -- If roster priority is configured, sort ranks by priority
    if Config.JobSync.rosterPriority and #Config.JobSync.rosterPriority > 0 then
        local priorityMap = {}
        for i, rosterUuid in ipairs(Config.JobSync.rosterPriority) do
            priorityMap[rosterUuid] = i
        end

        table.sort(ranks, function(a, b)
            local priorityA = priorityMap[a.roster_uuid] or 999
            local priorityB = priorityMap[b.roster_uuid] or 999
            return priorityA < priorityB
        end)
    end

    -- Find first matching rank mapping
    for _, rank in ipairs(ranks) do
        local mapping = GetJobForRank(rank.rank_uuid)
        if mapping then
            return mapping, rank
        end
    end

    return nil
end

-- Fetch player's ranks from FiveRoster API
local function FetchPlayerRanks(discordId, callback)
    local url = Config.FiveRosterURL .. '/api/v1/fivem/rosters?discord_id=' .. discordId .. '&include_ranks=true'

    PerformHttpRequest(url, function(statusCode, response, headers)
        if statusCode == 200 then
            local data = json.decode(response)
            if data and data.success and data.rosters then
                local ranks = {}
                for _, roster in ipairs(data.rosters) do
                    if roster.player_rank then
                        table.insert(ranks, {
                            roster_uuid = roster.roster_uuid,
                            roster_name = roster.name,
                            rank_uuid = roster.player_rank.uuid,
                            rank_name = roster.player_rank.name
                        })
                    end
                end
                callback(ranks)
            else
                callback({})
            end
        else
            DebugLog('job_sync', 'Failed to fetch ranks: HTTP %s', tostring(statusCode))
            callback({})
        end
    end, 'GET', '', {
        ['Content-Type'] = 'application/json',
        ['X-API-KEY'] = GetPrimaryApiKey(),
        ['Accept'] = 'application/json'
    })
end

-- Sync a player's job based on their FiveRoster ranks
local function SyncPlayerJob(source)
    if not Config.JobSync or not Config.JobSync.enabled then return end

    local discordId = ResolvePlayerDiscordId(source)
    if not discordId then
        DebugLog('job_sync', 'Cannot sync job - no Discord ID for player %s', GetPlayerName(source))
        return
    end

    DebugLog('job_sync', 'Syncing job for player %s', GetPlayerName(source))

    FetchPlayerRanks(discordId, function(ranks)
        local mapping, matchedRank = FindBestJobMapping(ranks)

        if mapping then
            local success = SetPlayerJob(source, mapping.job, mapping.grade, mapping.label)
            if success then
                DebugLog('job_sync', 'Synced player %s to job %s grade %d (rank: %s)',
                    GetPlayerName(source), mapping.job, mapping.grade, matchedRank.rank_name)

                -- Trigger event for other resources
                TriggerEvent('fiveroster:onJobSynced', source, {
                    job = mapping.job,
                    grade = mapping.grade,
                    rankUuid = matchedRank.rank_uuid,
                    rankName = matchedRank.rank_name,
                    rosterUuid = matchedRank.roster_uuid,
                    rosterName = matchedRank.roster_name
                })
            end
        elseif Config.JobSync.fallbackJob then
            -- Apply fallback job if configured
            local fallback = Config.JobSync.fallbackJob
            SetPlayerJob(source, fallback.job, fallback.grade, fallback.label)
            DebugLog('job_sync', 'Applied fallback job %s for player %s', fallback.job, GetPlayerName(source))
        else
            DebugLog('job_sync', 'No rank mapping found for player %s', GetPlayerName(source))
        end
    end)
end

-- Export for manually triggering job sync
exports('SyncPlayerJob', function(source)
    SyncPlayerJob(source)
end)

-- Export for getting job mapping for a rank
exports('GetJobForRank', function(rankUuid)
    return GetJobForRank(rankUuid)
end)

-- Track sources already synced this session to avoid re-syncing on character switches.
-- Multi-character frameworks fire their PlayerLoaded event every time a character is
-- loaded, which previously caused the Discord-derived job to be applied to every
-- character the player swapped to. Keyed by FiveM source, cleared on disconnect.
local jobSyncedSources = {}

local function TrySyncOnPlayerLoad(playerId)
    local syncOnSwitch = Config.JobSync.syncOnCharacterSwitch
    if syncOnSwitch == nil then syncOnSwitch = false end

    if not syncOnSwitch and jobSyncedSources[playerId] then
        DebugLog('job_sync', 'Skipping job sync for %s - already synced this session (character switch)', GetPlayerName(playerId))
        return
    end

    jobSyncedSources[playerId] = true
    SyncPlayerJob(playerId)
end

AddEventHandler('playerDropped', function()
    jobSyncedSources[source] = nil
end)

-- Sync job on player load (framework-specific)
local function SetupJobSyncOnPlayerLoad()
    if not Config.JobSync or not Config.JobSync.enabled or not Config.JobSync.syncOnJoin then return end

    local framework = Config.JobSync.framework

    if framework == 'esx' then
        if GetResourceState('es_extended') == 'started' then
            AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
                Wait(2000) -- Wait for player to fully load
                TrySyncOnPlayerLoad(playerId)
            end)
            DebugLog('job_sync', 'Registered ESX playerLoaded handler')
        end
    elseif framework == 'qbcore' then
        if GetResourceState('qb-core') == 'started' then
            RegisterNetEvent('QBCore:Server:PlayerLoaded', function()
                local src = source
                Wait(2000)
                TrySyncOnPlayerLoad(src)
            end)
            DebugLog('job_sync', 'Registered QBCore PlayerLoaded handler')
        end
    elseif framework == 'qbox' then
        if GetResourceState('qbx_core') == 'started' then
            RegisterNetEvent('QBCore:Server:PlayerLoaded', function()
                local src = source
                Wait(2000)
                TrySyncOnPlayerLoad(src)
            end)
            DebugLog('job_sync', 'Registered QBox PlayerLoaded handler')
        end
    end
end

-- Handle rank change webhook from FiveRoster
RegisterNetEvent('fiveroster:rankChanged', function(data)
    if not Config.JobSync or not Config.JobSync.enabled or not Config.JobSync.syncOnRankChange then return end

    local discordId = data.discord_id
    if not discordId then return end

    -- Find player by Discord ID
    for _, playerId in ipairs(GetPlayers()) do
        local playerDiscordId = ResolvePlayerDiscordId(playerId)
        if playerDiscordId == discordId then
            DebugLog('job_sync', 'Rank change detected for player %s, syncing job...', GetPlayerName(playerId))
            SyncPlayerJob(playerId)
            break
        end
    end
end)

-- Command to manually sync job (admin use)
RegisterCommand('syncjob', function(source, args)
    if source == 0 then
        -- Console
        if args[1] then
            local targetId = tonumber(args[1])
            if targetId then
                SyncPlayerJob(targetId)
                print('[FiveRoster] Synced job for player ' .. targetId)
            end
        else
            print('Usage: syncjob [player_id]')
        end
    else
        -- Player (could add permission check here)
        SyncPlayerJob(source)
    end
end, false)

-- ============================================================================
-- RESOURCE LIFECYCLE
-- ============================================================================

-- Resource start message
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    print('^3[FiveRoster]^7 Resource started')
    print('^3[FiveRoster]^7 Command: /' .. Config.CommandName)

    local apiKeys = GetAllApiKeys()
    if #apiKeys == 0 then
        print('^1[FiveRoster] WARNING: No API keys configured!^7')
        print('^1[FiveRoster] Copy server/config.lua.example to server/config.lua and add your API key^7')
    elseif #apiKeys == 1 then
        print('^2[FiveRoster]^7 Configured with 1 API key (single Discord server)')
    else
        print('^2[FiveRoster]^7 Configured with ' .. #apiKeys .. ' API keys (multi-guild mode)')
    end

    -- Setup job sync if enabled
    if Config.JobSync and Config.JobSync.enabled then
        print('^2[FiveRoster]^7 Job sync enabled (' .. Config.JobSync.framework .. ')')
        SetupJobSyncOnPlayerLoad()
    end

    if Config.ShiftPause and Config.ShiftPause.enabled == false then
        shiftPauseSupported = false
        print('^3[FiveRoster]^7 Shift breaks disabled by config')
    end

    -- A resource restart wipes the in-memory caches while players stay
    -- connected. Re-warm the Discord ID cache straight away so a disconnect is
    -- still able to end their shift; the clients re-request their own shift
    -- state as they come back up.
    CreateThread(function()
        Wait(1000)
        local players = GetPlayers()
        for _, playerId in ipairs(players) do
            CachePlayerDiscordId(tonumber(playerId) or playerId)
        end
        if #players > 0 then
            DebugLog('shift', 'Re-warmed Discord ID cache for %d connected player(s)', #players)
        end
    end)
end)

--[[
    ============================================================================
    FiveRoster for FiveM - Presentation Casting (Server)
    ============================================================================

    Puts a FiveRoster training presentation on a screen in the world.

    The game server owns the cast: it talks to FiveRoster, decides who may
    drive the deck, and tells every client which slide to show. Clients only
    render — a client never moves a deck on its own say-so, so a modified
    client cannot flip someone else's briefing.

    Casts are keyed by a screen key (the screen's rounded world position), so
    two briefings can run in two rooms at once without colliding.

    Documentation: https://docs.fiveroster.com/fivem
    ============================================================================
]]

-- Read at call time rather than captured on load. main.lua publishes this
-- table and the manifest orders it first, but a capture here would turn any
-- future reordering into unauthenticated requests and a cast that fails with
-- nothing to show for it.
local function Internals()
    return FiveRosterInternal or {}
end

local warnedMissingInternals = false

local function WarnMissingInternals()
    if warnedMissingInternals then return end
    warnedMissingInternals = true
    print('^1[FiveRoster]^7 server/cast.lua loaded without server/main.lua. Presentation casting will fail until the resource is restarted.')
end

local function DebugLog(...)
    local internal = Internals()
    if internal.DebugLog then internal.DebugLog(...) end
end

local function ApiHeaders()
    local internal = Internals()
    if internal.ApiHeaders then return internal.ApiHeaders() end

    -- Without main.lua there is no API key to send, so every call would come
    -- back 401 and look like a rejected presentation.
    WarnMissingInternals()

    return {
        ['Content-Type'] = 'application/json',
        ['Accept'] = 'application/json'
    }
end

local function ResolveDiscordId(source)
    local internal = Internals()
    if internal.ResolvePlayerDiscordId then
        return internal.ResolvePlayerDiscordId(source)
    end

    WarnMissingInternals()
    return nil
end

local function DecodeJson(response)
    local internal = Internals()
    if internal.TryDecodeJson then return internal.TryDecodeJson(response) end
    if type(response) ~= 'string' or response == '' then return nil, false end
    local ok, decoded = pcall(json.decode, response)
    if ok and type(decoded) == 'table' then return decoded, true end
    return nil, false
end

-- ============================================================================
-- CONFIG ACCESS
-- ============================================================================
-- A server upgrading this resource may still be running a config.lua from
-- before casting existed, so nothing here may assume the table is present.

local PresentationDefaults = {
    enabled = true,
    command = 'present',
    stopCommand = 'endpresentation',
    castDistance = 4.0
}

local MessageDefaults = {
    no_screen = 'Stand in front of a screen to cast a presentation.',
    no_presentations = 'You have no training presentations to cast.',
    cast_started = 'Casting "%s". Arrow keys change slide, Backspace ends it.',
    cast_stopped = 'Presentation ended.',
    cast_failed = 'Could not start that presentation. The reason is in the server console.',
    cast_unreachable = 'Could not reach FiveRoster. Tell an admin.',
    cast_denied = 'This server is not authorised to cast presentations.',
    cast_busy = 'That screen is already showing a presentation.',
    not_presenting = 'You are not casting a presentation.',
    unsupported = 'In-game presentations are not available on this FiveRoster instance.'
}

local function Setting(key)
    local configured = Config.Presentations and Config.Presentations[key]
    if configured ~= nil then return configured end
    return PresentationDefaults[key]
end

local function CastMessage(key)
    local messages = Config.Presentations and Config.Presentations.messages
    local configured = messages and messages[key]
    if configured ~= nil then return configured end
    return MessageDefaults[key] or key
end

local function IsCastingEnabled()
    return Setting('enabled') ~= false
end

local function AttendanceSetting(key, default)
    local attendance = Config.Presentations and Config.Presentations.attendance
    local configured = attendance and attendance[key]
    if configured ~= nil then return configured end
    return default
end

-- ============================================================================
-- STATE
-- ============================================================================

-- Live casts, keyed by screen key. One screen shows one deck.
local activeCasts = {}

-- Which screen each presenter is driving, keyed by player source, so a
-- disconnect can find their cast without scanning every screen.
local presenterScreens = {}

-- nil until we have asked once; false once an instance answers the casting
-- routes with a 404, which is how an older FiveRoster identifies itself.
local castingSupported = nil

local function ApiUrl(path)
    return Config.FiveRosterURL .. path
end

local function Notify(src, message)
    TriggerClientEvent('fiveroster:cast:notify', src, message)
end

-- The payload a client needs to render a cast. Deliberately not the token's
-- own URL plus anything else: a client gets exactly what it must draw.
local function CastPayload(cast)
    return {
        castUuid = cast.castUuid,
        screenKey = cast.screenKey,
        name = cast.name,
        castUrl = cast.castUrl,
        currentSlide = cast.currentSlide,
        slideCount = cast.slideCount,
        presenter = cast.presenter
    }
end

local function BroadcastStarted(cast)
    TriggerClientEvent('fiveroster:cast:started', -1, CastPayload(cast))
end

local function BroadcastSlide(cast)
    TriggerClientEvent('fiveroster:cast:slide', -1, cast.screenKey, cast.currentSlide)
end

local function BroadcastStopped(cast)
    TriggerClientEvent('fiveroster:cast:stopped', -1, cast.screenKey)
end

-- ============================================================================
-- FIVEROSTER API
-- ============================================================================

-- A 404 on a casting route means this instance predates the feature. Any other
-- failure is transient and must not permanently disable the controls.
-- A failed cast is exceptional and the message the player gets cannot say much
-- without leaking instance detail to everyone in earshot, so the reason is
-- always printed to the server console, debug logging on or not. Losing it was
-- the difference between "could not start that presentation" and knowing that
-- the API key is wrong.
local function ReportApiFailure(what, url, statusCode, response)
    local detail = ''

    if type(response) == 'string' and response ~= '' then
        detail = ': ' .. response:gsub('%s+', ' '):sub(1, 300)
    end

    if statusCode == 0 then
        print(('^1[FiveRoster]^7 %s could not reach %s. Check Config.FiveRosterURL and that the server can make outbound requests.'):format(what, url))
        return
    end

    print(('^1[FiveRoster]^7 %s failed: HTTP %s from %s%s'):format(what, tostring(statusCode), url, detail))

    if statusCode == 401 or statusCode == 403 then
        print('^3[FiveRoster]^7 That is an authentication failure. Check the API key in server/config.lua.')
    elseif statusCode == 404 then
        print('^3[FiveRoster]^7 That route does not exist on this instance. In-game presentations need a newer FiveRoster.')
    end
end

-- What to tell the player. An instance that explains itself is quoted, since
-- it is their own FiveRoster and the wording will mean more than ours; the
-- reply is kept short and plain so a stray error page cannot land in a
-- notification.
local function ApiFailureMessage(statusCode, data)
    local reported = type(data) == 'table' and (data.error or data.message) or nil

    if type(reported) == 'string' and reported ~= '' and #reported <= 120 and not reported:find('[<>]') then
        return reported
    end

    if statusCode == 0 then return CastMessage('cast_unreachable') end
    if statusCode == 404 then return CastMessage('unsupported') end
    if statusCode == 401 or statusCode == 403 then return CastMessage('cast_denied') end
    if type(statusCode) == 'number' and statusCode >= 500 then return CastMessage('cast_unreachable') end

    return CastMessage('cast_failed')
end

local function NoteSupport(statusCode)
    if statusCode == 404 then
        if castingSupported ~= false then
            print('^3[FiveRoster]^7 This FiveRoster instance does not support in-game presentations')
        end
        castingSupported = false
    elseif statusCode and statusCode >= 200 and statusCode < 500 then
        castingSupported = true
    end
end

local function FetchPresentations(discordId, callback)
    local url = ApiUrl('/api/v1/fivem/presentations?discord_id=' .. discordId)

    DebugLog('api_request', 'GET %s', url)

    PerformHttpRequest(url, function(statusCode, response)
        NoteSupport(statusCode)
        DebugLog('api_response', 'Presentations status: %s', tostring(statusCode))

        local data = DecodeJson(response)

        if statusCode ~= 200 then
            ReportApiFailure('Listing presentations', url, statusCode, response)
            callback(false, nil, statusCode, data)
            return
        end

        if data and data.success and type(data.presentations) == 'table' then
            callback(true, data.presentations)
            return
        end

        -- A 200 that does not decode is a proxy or a login page answering in
        -- FiveRoster's place, which is worth saying out loud.
        ReportApiFailure('Listing presentations', url, statusCode, response)
        callback(false, nil, statusCode, data)
    end, 'GET', '', ApiHeaders())
end

local function StartCastRequest(discordId, presentationUuid, playerName, screenLabel, callback)
    local url = ApiUrl('/api/v1/fivem/cast')
    local body = {
        discord_id = discordId,
        presentation_uuid = presentationUuid,
        presenter_name = playerName,
        screen_label = screenLabel,
        server_identifier = GetConvar('sv_hostname', 'Unknown Server')
    }

    DebugLog('api_request', 'POST %s (presentation %s)', url, tostring(presentationUuid))

    PerformHttpRequest(url, function(statusCode, response)
        NoteSupport(statusCode)
        DebugLog('api_response', 'Cast start status: %s', tostring(statusCode))

        local data = DecodeJson(response)

        if statusCode ~= 200 and statusCode ~= 201 then
            ReportApiFailure('Starting a cast', url, statusCode, response)
            callback(false, nil, statusCode, data)
            return
        end

        if data and data.success and type(data.cast) == 'table' then
            local cast = data.cast

            -- A cast with no URL renders as a blank screen, which reads as a
            -- broken resource rather than a backend that answered oddly.
            if type(cast.cast_url) ~= 'string' or cast.cast_url == '' then
                print(('^1[FiveRoster]^7 Starting a cast: %s accepted the request but returned no cast_url.'):format(url))
                callback(false, nil, statusCode, data)
                return
            end

            callback(true, cast)
            return
        end

        ReportApiFailure('Starting a cast', url, statusCode, response)
        callback(false, nil, statusCode, data)
    end, 'POST', json.encode(body), ApiHeaders())
end

-- Fire-and-forget calls: a dropped slide report must never stall the screen,
-- because the clients have already been told to move.
local function PostCast(castUuid, path, body)
    if not castUuid then return end

    PerformHttpRequest(ApiUrl('/api/v1/fivem/cast/' .. castUuid .. path), function(statusCode)
        DebugLog('api_response', 'Cast %s status: %s', path, tostring(statusCode))
    end, 'POST', json.encode(body or {}), ApiHeaders())
end

-- ============================================================================
-- CAST LIFECYCLE
-- ============================================================================

local function EndCast(cast, reason)
    if not cast then return end

    activeCasts[cast.screenKey] = nil
    if cast.presenter then
        presenterScreens[cast.presenter] = nil
    end

    PostCast(cast.castUuid, '/stop', {})
    BroadcastStopped(cast)

    DebugLog('cast', 'Ended cast %s on %s (%s)', tostring(cast.castUuid), tostring(cast.screenKey), reason or 'stopped')
end

local function EndCastForPlayer(src, reason)
    local screenKey = presenterScreens[src]
    if not screenKey then return false end

    EndCast(activeCasts[screenKey], reason)
    return true
end

-- ============================================================================
-- CLIENT EVENTS
-- ============================================================================

-- A client asking what it should be drawing. Sent on join and on resource
-- restart, so a player who arrives mid-briefing still sees the right slide.
RegisterNetEvent('fiveroster:cast:requestState', function()
    local src = source
    if not IsCastingEnabled() then return end

    local casts = {}
    for _, cast in pairs(activeCasts) do
        casts[#casts + 1] = CastPayload(cast)
    end

    TriggerClientEvent('fiveroster:cast:state', src, casts)
end)

-- The picker: which presentations may this player cast?
RegisterNetEvent('fiveroster:cast:requestPresentations', function()
    local src = source

    if not IsCastingEnabled() then
        Notify(src, CastMessage('unsupported'))
        return
    end

    if castingSupported == false then
        Notify(src, CastMessage('unsupported'))
        return
    end

    local discordId = ResolveDiscordId(src)
    if not discordId then
        Notify(src, Config.Messages and Config.Messages.no_discord or 'No Discord ID linked.')
        return
    end

    FetchPresentations(discordId, function(ok, presentations, statusCode, data)
        if not ok then
            Notify(src, ApiFailureMessage(statusCode, data))
            return
        end

        if #presentations == 0 then
            Notify(src, CastMessage('no_presentations'))
            TriggerClientEvent('fiveroster:cast:presentations', src, {})
            return
        end

        TriggerClientEvent('fiveroster:cast:presentations', src, presentations)
    end)
end)

-- Start a cast. The client says which screen it is standing at; the server
-- decides whether that screen is free and who owns the result.
RegisterNetEvent('fiveroster:cast:start', function(presentationUuid, screenKey, screenLabel)
    local src = source

    if not IsCastingEnabled() then
        Notify(src, CastMessage('unsupported'))
        return
    end

    if type(presentationUuid) ~= 'string' or presentationUuid == '' then return end
    if type(screenKey) ~= 'string' or screenKey == '' then return end
    if type(screenLabel) ~= 'string' then screenLabel = nil end

    -- A screen already showing something is not taken over from under the
    -- presenter using it.
    local existing = activeCasts[screenKey]
    if existing and existing.presenter ~= src then
        Notify(src, CastMessage('cast_busy'))
        return
    end

    local discordId = ResolveDiscordId(src)
    if not discordId then
        Notify(src, Config.Messages and Config.Messages.no_discord or 'No Discord ID linked.')
        return
    end

    -- One presenter, one screen: whatever they left running elsewhere stops.
    -- Re-read the screen afterwards rather than reusing `existing`: if this
    -- player was already the one presenting here, that call has just closed it.
    EndCastForPlayer(src, 'started another cast')
    local stillRunning = activeCasts[screenKey]
    if stillRunning then
        EndCast(stillRunning, 'restarted')
    end

    local playerName = GetPlayerName(src)

    StartCastRequest(discordId, presentationUuid, playerName, screenLabel, function(ok, cast, statusCode, data)
        -- The presenter may have dropped while FiveRoster was answering.
        if not ok or not cast then
            Notify(src, ApiFailureMessage(statusCode, data))
            return
        end

        if GetPlayerName(src) == nil then
            PostCast(cast.cast_uuid, '/stop', {})
            return
        end

        local record = {
            castUuid = cast.cast_uuid,
            screenKey = screenKey,
            name = cast.name or 'Presentation',
            castUrl = cast.cast_url,
            currentSlide = cast.current_slide or 0,
            slideCount = cast.slide_count or 0,
            presenter = src,
            presenterDiscordId = discordId,
            startedAt = os.time()
        }

        activeCasts[screenKey] = record
        presenterScreens[src] = screenKey

        BroadcastStarted(record)
        Notify(src, string.format(CastMessage('cast_started'), record.name))

        DebugLog('cast', 'Started cast %s (%d slides) on %s', tostring(record.castUuid), record.slideCount, screenKey)
    end)
end)

-- Move the deck. Only the presenter may, and only within their own deck.
RegisterNetEvent('fiveroster:cast:step', function(step)
    local src = source
    local screenKey = presenterScreens[src]
    if not screenKey then return end

    local cast = activeCasts[screenKey]
    if not cast or cast.presenter ~= src then return end

    step = tonumber(step)
    if step ~= 1 and step ~= -1 then return end

    local target = cast.currentSlide + step
    if target < 0 then target = 0 end
    if cast.slideCount > 0 and target > cast.slideCount - 1 then
        target = cast.slideCount - 1
    end

    if target == cast.currentSlide then return end

    cast.currentSlide = target
    BroadcastSlide(cast)
    PostCast(cast.castUuid, '/slide', { slide = target })
end)

RegisterNetEvent('fiveroster:cast:stop', function()
    local src = source

    if not EndCastForPlayer(src, 'presenter stopped') then
        Notify(src, CastMessage('not_presenting'))
        return
    end

    Notify(src, CastMessage('cast_stopped'))
end)

-- Who is watching. Reported by the presenter's client, which is the one client
-- guaranteed to be near the screen; the server resolves the Discord IDs itself
-- so a client can never invent an attendee.
RegisterNetEvent('fiveroster:cast:attendance', function(sources)
    local src = source
    local screenKey = presenterScreens[src]
    if not screenKey then return end

    local cast = activeCasts[screenKey]
    if not cast or cast.presenter ~= src then return end
    if type(sources) ~= 'table' then return end
    if AttendanceSetting('enabled', true) == false then return end

    local attendees = {}
    local seen = {}

    for _, playerId in ipairs(sources) do
        local target = tonumber(playerId)
        -- Only players actually connected right now, and each of them once.
        if target and not seen[target] and GetPlayerName(target) ~= nil then
            seen[target] = true
            local discordId = ResolveDiscordId(target)
            if discordId then
                attendees[#attendees + 1] = {
                    discord_id = discordId,
                    name = GetPlayerName(target)
                }
            end
        end
    end

    if #attendees == 0 then return end

    PostCast(cast.castUuid, '/attendance', { attendees = attendees })
end)

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

-- A presenter who disconnects takes their cast with them: nobody else can
-- drive it, and leaving it up would keep booking training time for the room.
AddEventHandler('playerDropped', function()
    EndCastForPlayer(source, 'presenter disconnected')
end)

-- Casts do not survive a restart of this resource. The DUI surfaces are gone
-- from every client anyway, so the backend rows are closed rather than left to
-- time out.
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    for _, cast in pairs(activeCasts) do
        PostCast(cast.castUuid, '/stop', {})
    end

    activeCasts = {}
    presenterScreens = {}
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if not IsCastingEnabled() then
        print('^3[FiveRoster]^7 In-game presentations disabled by config')
        return
    end

    print('^2[FiveRoster]^7 In-game presentations enabled (/' .. tostring(Setting('command')) .. ')')
end)

-- ============================================================================
-- EXPORTS
-- ============================================================================

-- Casts currently running, keyed by screen key. Lets another resource show a
-- briefing on a HUD, or refuse to teleport someone out of one.
exports('GetActiveCasts', function()
    local casts = {}
    for screenKey, cast in pairs(activeCasts) do
        casts[screenKey] = CastPayload(cast)
    end
    return casts
end)

exports('IsPresenting', function(source)
    return presenterScreens[source] ~= nil
end)

exports('StopPresenting', function(source)
    return EndCastForPlayer(source, 'stopped by another resource')
end)

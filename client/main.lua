--[[
    ============================================================================
    FiveRoster for FiveM - Client Script
    ============================================================================

    This script handles:
    - NUI (tablet interface) management
    - Tablet prop and animation
    - Shift tracking state on client side
    - Communication with server for sessions and shifts

    Exports provided:
    - HasActiveShift() : boolean
    - GetActiveShift() : table or nil
    - StartShift(rosterUuid, flagId) : boolean
    - EndShift() : boolean
    - PauseShift() : boolean
    - ResumeShift() : boolean
    - ToggleShiftPause() : boolean
    - IsShiftPaused() : boolean
    - GetShiftDuration() : number or nil
    - IsShiftPauseSupported() : boolean

    Events triggered:
    - fiveroster:onShiftStarted (shiftData)
    - fiveroster:onShiftEnded (shiftData)
    - fiveroster:onShiftPaused (shiftData)
    - fiveroster:onShiftResumed (shiftData)

    A paused shift is still an active shift: HasActiveShift() stays true and
    GetActiveShift() keeps returning the shift while the player is on a break.

    Documentation: https://docs.fiveroster.com/fivem
    ============================================================================
]]

-- ============================================================================
-- STATE VARIABLES
-- ============================================================================

local isNUIOpen = false
local tabletObject = nil
local currentShift = nil
local shiftPauseSupported = true
-- Set once the server has told us this player's shift state at least once.
-- Until then the client must not claim the player is off duty.
local shiftStateSynced = false

-- Config fallbacks. A server upgrading this resource may still be running its
-- own customised config.lua from before breaks existed, so nothing below may
-- assume the new tables or message keys are present.
local PauseDefaults = {
    enabled = true,
    pauseCommand = 'shiftpause',
    resumeCommand = 'shiftresume',
    toggleCommand = 'shiftbreak',
    toggleKey = ''
}

local HudDefaults = {
    enabled = false,
    x = 0.015,
    y = 0.88,
    scale = 0.35,
    showRosterName = true,
    onDutyLabel = 'ON DUTY',
    onBreakLabel = 'ON BREAK'
}

local MessageDefaults = {
    shift_paused = 'Shift paused. You are on a break.',
    shift_resumed = 'Break over. Your shift is running again.',
    shift_already_paused = 'You are already on a break.',
    shift_already_running = 'Your shift is already running.',
    shift_not_active = 'You are not currently on shift.',
    shift_pause_unavailable = 'Shift breaks are not available on this FiveRoster instance.'
}

local function PauseSetting(key)
    local configured = Config.ShiftPause and Config.ShiftPause[key]
    if configured ~= nil then return configured end
    return PauseDefaults[key]
end

local function HudSetting(key)
    local configured = Config.ShiftHUD and Config.ShiftHUD[key]
    if configured ~= nil then return configured end
    return HudDefaults[key]
end

local function Msg(key)
    local configured = Config.Messages and Config.Messages[key]
    if configured ~= nil then return configured end
    return MessageDefaults[key] or key
end

local function IsPauseEnabled()
    return PauseSetting('enabled') ~= false
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Debug logging helper
local function DebugLog(category, message, ...)
    if not Config.Debug or not Config.Debug.enabled then return end

    local prefix = '^3[FiveRoster:Client]^7'
    local categoryTag = '^5[' .. category:upper() .. ']^7'

    if select('#', ...) > 0 then
        print(string.format('%s %s %s', prefix, categoryTag, string.format(message, ...)))
    else
        print(string.format('%s %s %s', prefix, categoryTag, message))
    end
end

-- Notification helper - supports multiple notification systems
local function Notify(message, type)
    type = type or 'info'

    if Config.NotifySystem == 'ox_lib' and GetResourceState('ox_lib') == 'started' then
        exports['ox_lib']:notify({
            title = 'FiveRoster',
            description = message,
            type = type
        })
    elseif Config.NotifySystem == 'esx' and GetResourceState('es_extended') == 'started' then
        TriggerEvent('esx:showNotification', message)
    elseif Config.NotifySystem == 'qbcore' and GetResourceState('qb-core') == 'started' then
        TriggerEvent('QBCore:Notify', message, type)
    else
        -- Native GTA notification
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(message)
        EndTextCommandThefeedPostTicker(false, true)
    end
end

-- Create tablet prop and play animation
local function CreateTablet()
    if not Config.UseTablet then return end

    local playerPed = PlayerPedId()

    -- Load animation dictionary
    RequestAnimDict(Config.TabletDict)
    while not HasAnimDictLoaded(Config.TabletDict) do
        Wait(10)
    end

    -- Load tablet model
    local modelHash = GetHashKey(Config.TabletModel)
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(10)
    end

    -- Play animation
    TaskPlayAnim(playerPed, Config.TabletDict, Config.TabletAnim, 8.0, -8.0, -1, 49, 0, false, false, false)

    -- Create and attach tablet prop
    local boneIndex = GetPedBoneIndex(playerPed, 28422) -- Right hand
    tabletObject = CreateObject(modelHash, 0.0, 0.0, 0.0, true, true, true)
    AttachEntityToEntity(tabletObject, playerPed, boneIndex, 0.0, 0.0, 0.03, 0.0, 0.0, 0.0, true, true, false, true, 1, true)

    SetModelAsNoLongerNeeded(modelHash)
end

-- Remove tablet and stop animation
local function RemoveTablet()
    local playerPed = PlayerPedId()

    -- Delete tablet prop
    if tabletObject and DoesEntityExist(tabletObject) then
        DeleteEntity(tabletObject)
        tabletObject = nil
    end

    -- Stop animation
    StopAnimTask(playerPed, Config.TabletDict, Config.TabletAnim, 1.0)
    ClearPedTasks(playerPed)
    ClearPedTasksImmediately(playerPed)
end

-- Open NUI
local function OpenNUI(embedUrl)
    if isNUIOpen then return end

    isNUIOpen = true
    FiveRosterTabletOpen = true
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    CreateTablet()

    SendNUIMessage({
        action = 'open',
        url = embedUrl
    })

    DebugLog('nui', 'Opened NUI with URL: %s', embedUrl)
end

-- Close NUI
local function CloseNUI()
    -- Always release focus even if state is out of sync
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    FiveRosterTabletOpen = false

    if not isNUIOpen then return end

    isNUIOpen = false

    RemoveTablet()

    SendNUIMessage({
        action = 'close'
    })

    DebugLog('nui', 'Closed NUI')

    -- Ensure focus is released
    CreateThread(function()
        Wait(100)
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        ClearPedTasksImmediately(PlayerPedId())
    end)
end

-- NUI Callbacks
RegisterNUICallback('close', function(_, cb)
    CloseNUI()
    cb('ok')
end)

RegisterNUICallback('closeEsc', function(_, cb)
    CloseNUI()
    cb('ok')
end)

RegisterNUICallback('loaded', function(_, cb)
    DebugLog('nui', 'NUI content loaded')
    cb('ok')
end)

RegisterNUICallback('error', function(data, cb)
    DebugLog('nui', 'NUI error occurred')
    Notify(Config.Messages.error, 'error')
    CloseNUI()
    cb('ok')
end)

-- ============================================================================
-- SHIFT STATE
-- ============================================================================

-- Shift payloads reach the client in two shapes: snake_case from the tablet
-- (NUI) and camelCase from the server's tracking table. Normalise to one table
-- that carries both spellings so any resource already reading either keeps
-- working, and so break state is always present.
local function NormalizeShift(data)
    if type(data) ~= 'table' then return nil end

    local shift = {
        shift_id = data.shift_id or data.shiftId or data.id,
        roster_uuid = data.roster_uuid or data.rosterUuid,
        roster_name = data.roster_name or data.rosterName,
        started_at = data.started_at or data.startedAt,
        is_paused = (data.is_paused or data.isPaused) == true,
        paused_at = data.paused_at or data.pausedAt,
        paused_seconds = data.paused_seconds or data.pausedSeconds or 0,
        pause_count = data.pause_count or data.pauseCount or 0,
        duration_seconds = data.duration_seconds or data.durationSeconds or 0,
        formatted_duration = data.formatted_duration or data.formattedDuration or data.duration_formatted
    }

    -- Wall clock at which duration_seconds was last true, so a running shift
    -- can be extrapolated locally and a paused one cannot drift.
    shift.duration_synced_at = GetGameTimer()

    -- camelCase aliases
    shift.shiftId = shift.shift_id
    shift.rosterUuid = shift.roster_uuid
    shift.rosterName = shift.roster_name
    shift.startedAt = shift.started_at
    shift.isPaused = shift.is_paused
    shift.pausedAt = shift.paused_at
    shift.pausedSeconds = shift.paused_seconds
    shift.pauseCount = shift.pause_count
    shift.durationSeconds = shift.duration_seconds
    shift.durationSyncedAt = shift.duration_synced_at

    return shift
end

-- Worked seconds on the current shift. Frozen while on a break: the server
-- freezes duration_seconds too, so counting up locally would drift and then
-- jump backwards on the next sync.
local function GetShiftDurationSeconds()
    if not currentShift then return nil end

    local base = currentShift.duration_seconds or 0
    if currentShift.is_paused then return base end

    local syncedAt = currentShift.duration_synced_at or GetGameTimer()
    return base + math.max(0, math.floor((GetGameTimer() - syncedAt) / 1000))
end

local function FormatDuration(seconds)
    if not seconds then return '0m' end

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if hours > 0 then
        return string.format('%dh %02dm', hours, minutes)
    end

    return string.format('%dm', minutes)
end

-- Handle shift started from NUI
RegisterNUICallback('shiftStarted', function(data, cb)
    DebugLog('shift', 'Shift started: %s', json.encode(data))

    currentShift = NormalizeShift(data)

    -- Notify server
    TriggerServerEvent('fiveroster:shiftStarted', data)

    -- Trigger client event for other resources
    TriggerEvent('fiveroster:onShiftStarted', currentShift)

    Notify('Shift started!', 'success')
    cb('ok')
end)

-- Handle shift ended from NUI
RegisterNUICallback('shiftEnded', function(data, cb)
    DebugLog('shift', 'Shift ended: %s', json.encode(data))

    local endedShift = {
        shift_id = data.shift_id,
        roster_uuid = data.roster_uuid,
        duration_seconds = data.duration_seconds
    }

    currentShift = nil

    -- Notify server
    TriggerServerEvent('fiveroster:shiftEnded', endedShift)

    -- Trigger client event for other resources
    TriggerEvent('fiveroster:onShiftEnded', endedShift)

    local duration = data.duration_formatted or 'Unknown'
    Notify('Shift ended. Duration: ' .. duration, 'success')
    cb('ok')
end)

-- Handle a break started from the tablet's Pause button. The web app has
-- already told the backend; this keeps the game client from carrying on as
-- though the player were still working.
RegisterNUICallback('shiftPaused', function(data, cb)
    DebugLog('shift', 'Shift paused from tablet: %s', json.encode(data or {}))

    shiftPauseSupported = true

    if currentShift then
        currentShift.duration_seconds = (data and data.duration_seconds) or currentShift.duration_seconds
        currentShift.durationSeconds = currentShift.duration_seconds
        currentShift.duration_synced_at = GetGameTimer()
        currentShift.durationSyncedAt = currentShift.duration_synced_at
        currentShift.is_paused = true
        currentShift.isPaused = true
    else
        -- Break reported for a shift we were not tracking (started on the web
        -- dashboard, or the resource restarted). Adopt it rather than ignore it.
        currentShift = NormalizeShift(data)
        if currentShift then
            currentShift.is_paused = true
            currentShift.isPaused = true
        end
    end

    TriggerServerEvent('fiveroster:shiftPaused', data or {})
    TriggerEvent('fiveroster:onShiftPaused', currentShift)

    Notify(Msg('shift_paused'), 'info')
    cb('ok')
end)

-- Handle a break ended from the tablet's Resume button
RegisterNUICallback('shiftResumed', function(data, cb)
    DebugLog('shift', 'Shift resumed from tablet: %s', json.encode(data or {}))

    shiftPauseSupported = true

    if currentShift then
        currentShift.duration_seconds = (data and data.duration_seconds) or currentShift.duration_seconds
        currentShift.durationSeconds = currentShift.duration_seconds
        currentShift.duration_synced_at = GetGameTimer()
        currentShift.durationSyncedAt = currentShift.duration_synced_at
        currentShift.is_paused = false
        currentShift.isPaused = false
    else
        currentShift = NormalizeShift(data)
        if currentShift then
            currentShift.is_paused = false
            currentShift.isPaused = false
        end
    end

    TriggerServerEvent('fiveroster:shiftResumed', data or {})
    TriggerEvent('fiveroster:onShiftResumed', currentShift)

    Notify(Msg('shift_resumed'), 'success')
    cb('ok')
end)

-- Receive shift tracking status from server
RegisterNetEvent('fiveroster:shiftTracking', function(isActive, shiftData)
    shiftStateSynced = true

    if isActive and shiftData then
        currentShift = NormalizeShift(shiftData)
        DebugLog('shift', 'Shift tracking active: %s (paused: %s)',
            currentShift.roster_name or 'Unknown', tostring(currentShift.is_paused))
    else
        currentShift = nil
        DebugLog('shift', 'Shift tracking inactive')
    end
end)

-- Server tells us the break state changed (command, keybind, export, or
-- another resource). Never auto-resumes - it only reflects what came back.
RegisterNetEvent('fiveroster:shiftPauseChanged', function(isPaused, shiftData, info)
    info = info or {}

    if shiftData then
        currentShift = NormalizeShift(shiftData)
    elseif currentShift then
        currentShift.is_paused = isPaused
        currentShift.isPaused = isPaused
        currentShift.duration_synced_at = GetGameTimer()
        currentShift.durationSyncedAt = currentShift.duration_synced_at
    end

    DebugLog('shift', 'Break state changed: paused=%s already=%s',
        tostring(isPaused), tostring(info.alreadyInState))

    if info.alreadyInState then
        -- The shift was already in this state. The backend deliberately left
        -- the running break alone rather than restarting it, so this is
        -- informational, never an error.
        Notify(isPaused and Msg('shift_already_paused') or Msg('shift_already_running'), 'info')
    else
        Notify(isPaused and Msg('shift_paused') or Msg('shift_resumed'), isPaused and 'info' or 'success')
    end

    TriggerEvent(isPaused and 'fiveroster:onShiftPaused' or 'fiveroster:onShiftResumed', currentShift)
end)

-- Server tells us whether the pause control should exist at all
RegisterNetEvent('fiveroster:shiftPauseSupported', function(supported)
    shiftPauseSupported = supported ~= false
    DebugLog('shift', 'Shift breaks supported: %s', tostring(shiftPauseSupported))
end)

-- This FiveRoster instance has no break routes. Hide the control rather than
-- erroring: everything else about the shift keeps working.
RegisterNetEvent('fiveroster:shiftPauseUnavailable', function(message)
    shiftPauseSupported = false
    DebugLog('shift', 'Shift breaks unavailable: %s', message or 'no reason given')
    Notify(Msg('shift_pause_unavailable'), 'info')
end)

-- Server found no open shift for an action that needed one
RegisterNetEvent('fiveroster:shiftNotActive', function()
    shiftStateSynced = true
    currentShift = nil
    Notify(Msg('shift_not_active'), 'error')
end)

-- Export to check if player has active shift.
-- A paused shift is still active - a break is not a clock-out.
exports('HasActiveShift', function()
    return currentShift ~= nil
end)

-- Export to get active shift data
exports('GetActiveShift', function()
    return currentShift
end)

-- Export to check whether the active shift is on a break
exports('IsShiftPaused', function()
    return currentShift ~= nil and currentShift.is_paused == true
end)

-- Export for worked seconds on the current shift (frozen while on a break)
exports('GetShiftDuration', function()
    return GetShiftDurationSeconds()
end)

-- Export to check whether breaks are usable on this server/instance
exports('IsShiftPauseSupported', function()
    return IsPauseEnabled() and shiftPauseSupported
end)

-- Export to start a shift (triggers server-side API call)
-- Usage: exports['fiveroster']:StartShift(rosterUuid, flagId)
-- Returns immediately, shift status will be updated via events
exports('StartShift', function(rosterUuid, flagId)
    if currentShift then
        Notify('You already have an active shift on ' .. (currentShift.roster_name or 'another roster'), 'error')
        return false
    end

    if not rosterUuid then
        Notify('Roster UUID is required', 'error')
        return false
    end

    TriggerServerEvent('fiveroster:startShiftExternal', rosterUuid, flagId)
    return true
end)

-- Export to end current shift (triggers server-side API call)
-- Usage: exports['fiveroster']:EndShift()
-- Returns immediately, shift status will be updated via events
-- Works the same on a paused shift: the backend closes the open break itself.
exports('EndShift', function()
    if not currentShift then
        Notify(Msg('shift_not_active'), 'error')
        return false
    end

    TriggerServerEvent('fiveroster:endShiftExternal')
    return true
end)

-- ============================================================================
-- SHIFT BREAKS
-- ============================================================================

-- Shared guard for the pause/resume entry points.
-- Returns false (and notifies) when a break cannot be requested right now.
local function CanRequestPause()
    if not IsPauseEnabled() or not shiftPauseSupported then
        -- Informational, not an error: the instance simply has no breaks.
        Notify(Msg('shift_pause_unavailable'), 'info')
        return false
    end

    -- Only claim the player is off duty once the server has actually told us
    -- so. Before the first sync the server is asked and answers definitively.
    if shiftStateSynced and not currentShift then
        Notify(Msg('shift_not_active'), 'error')
        return false
    end

    return true
end

-- Start a break on the current shift
local function RequestPause()
    if not CanRequestPause() then return false end

    TriggerServerEvent('fiveroster:pauseShiftExternal')
    return true
end

-- End the break on the current shift
local function RequestResume()
    if not CanRequestPause() then return false end

    TriggerServerEvent('fiveroster:resumeShiftExternal')
    return true
end

-- Toggle the break state of the current shift
local function RequestTogglePause()
    if not CanRequestPause() then return false end

    TriggerServerEvent('fiveroster:toggleShiftPauseExternal')
    return true
end

-- Usage: exports['fiveroster']:PauseShift()
exports('PauseShift', RequestPause)

-- Usage: exports['fiveroster']:ResumeShift()
exports('ResumeShift', RequestResume)

-- Usage: exports['fiveroster']:ToggleShiftPause()
exports('ToggleShiftPause', RequestTogglePause)

-- Handle shift started externally (from MDT or other resources)
RegisterNetEvent('fiveroster:shiftStartedExternal', function(shiftData)
    DebugLog('shift', 'Shift started externally: %s', json.encode(shiftData))

    currentShift = NormalizeShift(shiftData)

    -- Trigger client event for other resources
    TriggerEvent('fiveroster:onShiftStarted', currentShift)

    Notify('Shift started on ' .. ((currentShift and currentShift.roster_name) or 'roster'), 'success')
end)

-- Handle shift ended externally (from MDT or other resources)
RegisterNetEvent('fiveroster:shiftEndedExternal', function(shiftData)
    DebugLog('shift', 'Shift ended externally: %s', json.encode(shiftData))

    currentShift = nil

    -- Trigger client event for other resources
    TriggerEvent('fiveroster:onShiftEnded', {
        shift_id = shiftData.id,
        roster_uuid = shiftData.roster_uuid,
        duration_seconds = shiftData.duration_seconds,
        duration_formatted = shiftData.duration_formatted
    })

    local duration = shiftData.duration_formatted or 'Unknown'
    Notify('Shift ended. Duration: ' .. duration, 'success')
end)

-- Handle shift operation error
RegisterNetEvent('fiveroster:shiftError', function(message)
    DebugLog('shift', 'Shift error: %s', message)
    Notify(message or 'An error occurred', 'error')
end)

-- Request session and open FiveRoster
local function OpenFiveRoster()
    if isNUIOpen then
        CloseNUI()
        return
    end

    Notify(Config.Messages.loading, 'info')
    DebugLog('session', 'Requesting session from server')

    TriggerServerEvent('fiveroster:requestSession')
end

-- Receive session from server
RegisterNetEvent('fiveroster:sessionCreated', function(embedUrl, rosterCount)
    DebugLog('session', 'Session created, roster count: %d', rosterCount or 0)
    OpenNUI(embedUrl)

    -- Sync any active shift the player already has on the backend (e.g. started
    -- on the web dashboard) so in-game shift state/tracking stays accurate.
    TriggerServerEvent('fiveroster:syncActiveShift')
end)

-- Session error
RegisterNetEvent('fiveroster:sessionError', function(message)
    DebugLog('session', 'Session error: %s', message or 'Unknown')
    Notify(message or Config.Messages.session_error, 'error')
end)

-- Register commands
RegisterCommand(Config.CommandName, function()
    OpenFiveRoster()
end, false)

-- Register command aliases
for _, alias in ipairs(Config.CommandAliases or {}) do
    RegisterCommand(alias, function()
        OpenFiveRoster()
    end, false)
end

-- Backup close command in case NUI gets stuck
RegisterCommand('closeroster', function()
    CloseNUI()
end, false)

-- Break commands: /shiftpause, /shiftresume and a /shiftbreak toggle.
-- Registered only when breaks are enabled in config; if the FiveRoster
-- instance turns out not to support them, the commands say so rather than
-- erroring, and every other control keeps working.
if IsPauseEnabled() then
    local pauseCommand = PauseSetting('pauseCommand')
    local resumeCommand = PauseSetting('resumeCommand')
    local toggleCommand = PauseSetting('toggleCommand')

    if pauseCommand and pauseCommand ~= '' then
        RegisterCommand(pauseCommand, function()
            RequestPause()
        end, false)
    end

    if resumeCommand and resumeCommand ~= '' then
        RegisterCommand(resumeCommand, function()
            RequestResume()
        end, false)
    end

    if toggleCommand and toggleCommand ~= '' then
        RegisterCommand(toggleCommand, function()
            RequestTogglePause()
        end, false)

        local toggleKey = PauseSetting('toggleKey')
        if toggleKey and toggleKey ~= '' then
            RegisterKeyMapping(toggleCommand, 'Toggle FiveRoster shift break', 'keyboard', toggleKey)
        end
    end
end

-- Keybinding registration (optional)
RegisterKeyMapping(Config.CommandName, 'Open FiveRoster', 'keyboard', '')

-- ============================================================================
-- SHIFT HUD
-- ============================================================================
-- Optional indicator. Three distinct states: hidden when off duty, on duty,
-- and on a break. A break must never read as being off duty.

local function DrawShiftText(text, x, y, scale, r, g, b)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, 255)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentSubstringPlayerName(text)
    DrawText(x, y)
end

CreateThread(function()
    if not HudSetting('enabled') then return end

    local x = HudSetting('x')
    local y = HudSetting('y')
    local scale = HudSetting('scale')

    while true do
        if currentShift then
            local paused = currentShift.is_paused == true
            local label = paused and HudSetting('onBreakLabel') or HudSetting('onDutyLabel')
            local text = label .. '  ' .. FormatDuration(GetShiftDurationSeconds())

            if HudSetting('showRosterName') and currentShift.roster_name then
                text = currentShift.roster_name .. '  |  ' .. text
            end

            if paused then
                -- Amber, and the duration is frozen because the server froze it
                DrawShiftText(text, x, y, scale, 245, 176, 66)
            else
                DrawShiftText(text, x, y, scale, 120, 220, 130)
            end

            Wait(0)
        else
            -- Off duty: nothing drawn at all
            Wait(1000)
        end
    end
end)

-- Resource cleanup
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    if isNUIOpen then
        CloseNUI()
    end
end)

-- Pull the player's shift state (including any break) from FiveRoster shortly
-- after the client comes up. This covers both a player joining and a resource
-- restart, and is what makes a reconnect while on a break show the break
-- instead of resuming it.
CreateThread(function()
    if Config.ShiftSync and Config.ShiftSync.onPlayerLoad == false then return end

    local delay = (Config.ShiftSync and Config.ShiftSync.playerLoadDelay) or 5000
    Wait(delay)

    TriggerServerEvent('fiveroster:requestPauseSupport')
    TriggerServerEvent('fiveroster:syncActiveShift')
end)

-- Print startup message
CreateThread(function()
    Wait(1000)
    print('^3[FiveRoster]^7 Client loaded. Use /' .. Config.CommandName .. ' to open.')
end)

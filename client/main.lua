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

    Events triggered:
    - fiveroster:onShiftStarted (shiftData)
    - fiveroster:onShiftEnded (shiftData)

    Documentation: https://docs.fiveroster.com/fivem
    ============================================================================
]]

-- ============================================================================
-- STATE VARIABLES
-- ============================================================================

local isNUIOpen = false
local tabletObject = nil
local currentShift = nil

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
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    CreateTablet()

    SendNUIMessage({
        action = 'open',
        url = embedUrl
    })

    DebugLog('nui', 'Opened NUI with URL: %s', embedUrl)
end

-- Close NUI (idempotent; always releases focus even when state is out of sync)
local function CloseNUI()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })

    if not isNUIOpen then return end

    isNUIOpen = false

    RemoveTablet()

    DebugLog('nui', 'Closed NUI')

    CreateThread(function()
        Wait(100)
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        ClearPedTasksImmediately(PlayerPedId())
    end)
end

-- Watchdog: force-release focus if it stays captured while NUI is closed.
CreateThread(function()
    while true do
        Wait(1000)
        if not isNUIOpen and (IsNuiFocused() or IsNuiFocusKeepingInput()) then
            SetNuiFocus(false, false)
            SetNuiFocusKeepInput(false)
            DebugLog('nui', 'Watchdog released stuck NUI focus')
        end
    end
end)

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

-- Handle shift started from NUI
RegisterNUICallback('shiftStarted', function(data, cb)
    DebugLog('shift', 'Shift started: %s', json.encode(data))

    currentShift = {
        shift_id = data.shift_id,
        roster_uuid = data.roster_uuid,
        roster_name = data.roster_name,
        started_at = data.started_at
    }

    -- Notify server
    TriggerServerEvent('fiveroster:shiftStarted', currentShift)

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

-- Receive shift tracking status from server
RegisterNetEvent('fiveroster:shiftTracking', function(isActive, shiftData)
    if isActive and shiftData then
        currentShift = shiftData
        DebugLog('shift', 'Shift tracking active: %s', shiftData.rosterName or 'Unknown')
    else
        currentShift = nil
        DebugLog('shift', 'Shift tracking inactive')
    end
end)

-- Export to check if player has active shift
exports('HasActiveShift', function()
    return currentShift ~= nil
end)

-- Export to get active shift data
exports('GetActiveShift', function()
    return currentShift
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
exports('EndShift', function()
    if not currentShift then
        Notify('You are not currently on shift', 'error')
        return false
    end

    TriggerServerEvent('fiveroster:endShiftExternal')
    return true
end)

-- Handle shift started externally (from MDT or other resources)
RegisterNetEvent('fiveroster:shiftStartedExternal', function(shiftData)
    DebugLog('shift', 'Shift started externally: %s', json.encode(shiftData))

    currentShift = {
        shift_id = shiftData.shiftId,
        roster_uuid = shiftData.rosterUuid,
        roster_name = shiftData.rosterName,
        started_at = shiftData.startedAt
    }

    -- Trigger client event for other resources
    TriggerEvent('fiveroster:onShiftStarted', currentShift)

    Notify('Shift started on ' .. (shiftData.rosterName or 'roster'), 'success')
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

-- Keybinding registration (optional)
RegisterKeyMapping(Config.CommandName, 'Open FiveRoster', 'keyboard', '')

-- Resource cleanup
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    if isNUIOpen then
        CloseNUI()
    end
end)

-- Print startup message
CreateThread(function()
    Wait(1000)
    print('^3[FiveRoster]^7 Client loaded. Use /' .. Config.CommandName .. ' to open.')
end)

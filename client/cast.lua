--[[
    ============================================================================
    FiveRoster for FiveM - Presentation Casting (Client)
    ============================================================================

    Draws a FiveRoster training presentation onto a screen in the world and
    lets the presenter click through it without leaving the game.

    Each screen is an ordinary prop carrying a named render target. The deck is
    a browser surface (a DUI) whose texture is painted onto that render target
    every frame while somebody is close enough to read it.

    The server owns the slide index. This script renders what it is told and
    asks for changes; it never advances a deck on its own.

    A NOTE ON RENDER TARGETS
    ------------------------
    The game links a render target to a MODEL, not to one prop. Every prop of
    that model that is on screen shows the cast. Give a briefing screen its own
    model if your map has that TV everywhere.

    Documentation: https://docs.fiveroster.com/fivem
    ============================================================================
]]

-- ============================================================================
-- CONFIG ACCESS
-- ============================================================================
-- A server upgrading this resource may still be running a config.lua from
-- before casting existed, so nothing here may assume the table is present.

local PresentationDefaults = {
    enabled = true,
    command = 'present',
    stopCommand = 'endpresentation',
    debugCommand = 'screeninfo',
    adjustCommand = 'castfit',
    commandKey = '',
    nextKey = 175,
    prevKey = 174,
    stopKey = 177,
    castDistance = 6.0,
    viewDistance = 20.0,
    showSlideCounter = true,
    maxScreens = 2
}

local ResolutionDefault = { width = 1280, height = 720 }

-- Offered in order by the live adjuster, so a screen whose panel is not 16:9
-- can be matched without editing the config first.
local ResolutionPresets = {
    { width = 1920, height = 1080 },
    { width = 1600, height = 900 },
    { width = 1280, height = 720 },
    { width = 1024, height = 576 },
    { width = 854, height = 480 },
    { width = 640, height = 360 },
    { width = 1024, height = 768 },
    { width = 800, height = 600 },
    { width = 1024, height = 1024 },
    { width = 512, height = 512 }
}

-- How the browser surface is laid onto the render target. The game gives no
-- way to ask a render target its shape, so a panel that is not the shape of
-- the page ends up stretched or cropped and only the person looking at it can
-- say by how much. These are the numbers /castfit writes.
local DisplayDefault = { scaleX = 1.0, scaleY = 1.0, offsetX = 0.0, offsetY = 0.0 }

-- Every vanilla prop worth trying as a screen. A model only becomes castable
-- once a render target actually links to it, so an entry the game does not
-- have, or one whose shader carries no render target, costs nothing but is
-- never offered. That makes a broad list safe: guessing wrong is silent.
--
-- No render target name is given here on purpose. It is probed per model at
-- discovery time against RenderTargetNameDefaults, so a model added later
-- needs nothing but its name.
local ScreenModelDefaults = {
    -- Flatscreen TVs. The four the resource has always supported come first.
    { model = 'prop_tv_flat_01' },
    { model = 'prop_tv_flat_01b' },
    { model = 'prop_tv_flat_02' },
    { model = 'prop_tv_flat_03' },
    { model = 'prop_tv_flat_03b' },
    { model = 'prop_tv_flat_michael' },

    -- Older and set-dressing TVs.
    { model = 'prop_tv_01' },
    { model = 'prop_tv_02' },
    { model = 'prop_tv_03' },
    { model = 'prop_tv_04' },
    { model = 'prop_tv_05' },
    { model = 'prop_tv_06' },
    { model = 'prop_tv_07' },
    { model = 'prop_tv_08' },
    { model = 'prop_tv_09' },
    { model = 'prop_tv_10' },
    { model = 'prop_tv_stand' },
    { model = 'prop_cs_tv_stand' },
    { model = 'prop_trailer_tv' },

    -- Interior TVs from the safehouses and clubhouses.
    { model = 'v_res_tt_tv' },
    { model = 'v_res_j_tv' },
    { model = 'v_res_m_tv' },
    { model = 'v_club_officetv' },
    { model = 'v_res_d_tv' },

    -- Monitors and office screens, for briefing rooms built out of desks.
    { model = 'prop_monitor_01a' },
    { model = 'prop_monitor_01b' },
    { model = 'prop_monitor_01c' },
    { model = 'prop_monitor_01d' },
    { model = 'prop_monitor_02' },
    { model = 'prop_monitor_03' },
    { model = 'prop_monitor_w_large' },
    { model = 'hei_prop_hei_monitor_01a' },
    { model = 'prop_laptop_01a' },
    { model = 'prop_laptop_lester' },
    { model = 'prop_laptop_lester2' },

    -- Projector screens and boards.
    { model = 'prop_cs_project_screen_01' },
    { model = 'prop_projector_01' },
    { model = 'prop_flatscreen_overlay' }
}

-- Render target names tried against a model, in order, until one links. Every
-- vanilla TV uses 'tvscreen'; a streamed prop uses whatever name its author
-- baked in, which goes in Config.Presentations.renderTargetNames.
local RenderTargetNameDefaults = { 'tvscreen' }

local MessageDefaults = {
    no_screen = 'No castable screen here. Run /screeninfo to see what is nearby.',
    no_presentations = 'You have no training presentations to cast.',
    cast_stopped = 'Presentation ended.',
    cast_failed = 'Could not start that presentation.',
    not_presenting = 'You are not casting a presentation.',
    close_tablet_first = 'Close the tablet before casting a presentation.'
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

local function Resolution()
    local configured = Config.Presentations and Config.Presentations.resolution
    return {
        width = (configured and tonumber(configured.width)) or ResolutionDefault.width,
        height = (configured and tonumber(configured.height)) or ResolutionDefault.height
    }
end


-- A screen entry is addressed by a name that must be identical on every
-- client, because it goes into the screen key. Normally that is the model
-- name. A prop whose name nobody knows can be configured as a raw hash
-- instead, and is then addressed as '#<hash>'.
local function NormaliseScreenEntry(entry)
    if type(entry) ~= 'table' then return nil end

    local model, hash = entry.model, nil

    if type(model) == 'string' and model ~= '' then
        hash = GetHashKey(model)
    elseif type(model) == 'number' then
        hash = model
        model = ('#%d'):format(hash)
    elseif type(entry.hash) == 'number' then
        hash = entry.hash
        model = ('#%d'):format(hash)
    else
        return nil
    end

    return {
        model = model,
        hash = hash,
        label = entry.label,
        coords = entry.coords,
        heading = entry.heading,
        renderTarget = entry.renderTarget,
        resolution = entry.resolution,
        display = entry.display
    }
end

local function NormaliseScreenEntries(list)
    local out = {}
    for _, entry in ipairs(list) do
        local normalised = NormaliseScreenEntry(entry)
        if normalised then out[#out + 1] = normalised end
    end
    return out
end

local screenModelCache, screenModelSource = nil, nil

local function ScreenModels()
    local configured = Config.Presentations and Config.Presentations.screenModels
    local source = (type(configured) == 'table' and #configured > 0) and configured or ScreenModelDefaults

    -- Normalising every call would hash a few dozen strings on every discovery
    -- sweep, so the result is kept until the config table itself changes.
    if screenModelSource ~= source then
        screenModelCache = NormaliseScreenEntries(source)
        screenModelSource = source
    end

    return screenModelCache
end

-- Model hash -> entry, for turning a prop found in the world back into a
-- configured screen.
local screenModelIndex, screenModelIndexSource = nil, nil

local function ScreenModelIndex()
    local models = ScreenModels()

    if screenModelIndexSource ~= models then
        screenModelIndex = {}
        for _, entry in ipairs(models) do
            screenModelIndex[entry.hash] = entry
        end
        screenModelIndexSource = models
    end

    return screenModelIndex
end

local function RenderTargetNames()
    local configured = Config.Presentations and Config.Presentations.renderTargetNames
    if type(configured) == 'table' and #configured > 0 then return configured end
    return RenderTargetNameDefaults
end

local fixedScreenCache, fixedScreenSource = nil, nil

local function FixedScreens()
    local configured = Config.Presentations and Config.Presentations.fixedScreens
    if type(configured) ~= 'table' then return {} end

    if fixedScreenSource ~= configured then
        fixedScreenCache = NormaliseScreenEntries(configured)
        fixedScreenSource = configured
    end

    return fixedScreenCache
end

-- The hash for a model name as it appears in a screen key, including the
-- '#<hash>' form used for props configured by hash.
local function ModelHashFor(modelName)
    if type(modelName) ~= 'string' then return nil end

    local literal = modelName:match('^#(-?%d+)$')
    if literal then return tonumber(literal) end

    return GetHashKey(modelName)
end

-- Live adjustments, by model name. Held only for this session: /castfit prints
-- what to paste into config.lua rather than writing anything, because a client
-- cannot write to the server's config and a screen everybody sees should not be
-- reshaped permanently by whoever last presented at it.
local displayOverrides = {}

local function ConfiguredEntryFor(modelName)
    for _, entry in ipairs(FixedScreens()) do
        if entry.model == modelName then return entry end
    end

    for _, entry in ipairs(ScreenModels()) do
        if entry.model == modelName then return entry end
    end

    return nil
end

-- The resolution the browser surface for a screen is built at. Per model
-- first, then the global setting.
local function ResolutionFor(modelName)
    local override = displayOverrides[modelName]
    if override and override.width and override.height then
        return { width = override.width, height = override.height }
    end

    local entry = ConfiguredEntryFor(modelName)
    local configured = entry and entry.resolution

    if configured and tonumber(configured.width) and tonumber(configured.height) then
        return { width = tonumber(configured.width), height = tonumber(configured.height) }
    end

    return Resolution()
end

-- How that surface is drawn onto the panel, global then per model then live.
local function DisplayFor(modelName)
    local display = {
        scaleX = DisplayDefault.scaleX,
        scaleY = DisplayDefault.scaleY,
        offsetX = DisplayDefault.offsetX,
        offsetY = DisplayDefault.offsetY
    }

    local function apply(source)
        if type(source) ~= 'table' then return end
        for key in pairs(display) do
            local value = tonumber(source[key])
            if value then display[key] = value end
        end
    end

    apply(Config.Presentations and Config.Presentations.display)

    local entry = ConfiguredEntryFor(modelName)
    apply(entry and entry.display)
    apply(displayOverrides[modelName])

    return display
end

local function AttendanceSetting(key, default)
    local attendance = Config.Presentations and Config.Presentations.attendance
    local configured = attendance and attendance[key]
    if configured ~= nil then return configured end
    return default
end

local function IsCastingEnabled()
    return Setting('enabled') ~= false
end

local function CastDebug(message, ...)
    if not Config.Debug or not Config.Debug.enabled then return end
    if select('#', ...) > 0 then
        print(('^3[FiveRoster:Cast]^7 ' .. message):format(...))
    else
        print('^3[FiveRoster:Cast]^7 ' .. message)
    end
end

-- ============================================================================
-- SCREEN KEYS
-- ============================================================================
-- A cast is addressed by its screen, and every client has to arrive at the
-- same name for the same screen without being told. Prop coordinates come from
-- the map and are identical everywhere, so the key is built from the model and
-- the rounded position, and carries enough to find the screen again.

local function ScreenKey(modelName, coords)
    return ('%s|%.2f|%.2f|%.2f'):format(modelName, coords.x, coords.y, coords.z)
end

local function ParseScreenKey(key)
    if type(key) ~= 'string' then return nil end

    local modelName, x, y, z = key:match('^(.-)|(-?%d+%.?%d*)|(-?%d+%.?%d*)|(-?%d+%.?%d*)$')
    if not modelName then return nil end

    return {
        model = modelName,
        coords = vector3(tonumber(x), tonumber(y), tonumber(z))
    }
end

-- The render target name a model was configured with, if any.
local function ConfiguredRenderTargetFor(modelName)
    for _, entry in ipairs(FixedScreens()) do
        if entry.model == modelName and entry.renderTarget then
            return entry.renderTarget
        end
    end

    for _, entry in ipairs(ScreenModels()) do
        if entry.model == modelName and entry.renderTarget then
            return entry.renderTarget
        end
    end

    return nil
end

-- Model name -> render target name, or false once a model has been shown not
-- to carry one. Probing costs a register and a link, so it is done once.
local probedRenderTargets = {}

-- Whether a render target name links to a model. The game refuses the link
-- unless the model's shader actually references that name, which is the only
-- way to ask a model what render target it carries.
local function RenderTargetLinks(name, modelHash)
    local registeredHere = false

    if not IsNamedRendertargetRegistered(name) then
        RegisterNamedRendertarget(name, false)
        registeredHere = true
    end

    if not IsNamedRendertargetLinked(modelHash) then
        LinkNamedRendertarget(modelHash)
    end

    if IsNamedRendertargetLinked(modelHash) then return true end

    -- Nothing else is using this name, so leave the slot as it was found.
    if registeredHere then ReleaseNamedRendertarget(name) end

    return false
end

-- The render target baked into a given model. A configured name is trusted
-- and used as-is; anything else is probed against the candidate names.
local function RenderTargetFor(modelName)
    local configured = ConfiguredRenderTargetFor(modelName)
    if configured then return configured end

    local cached = probedRenderTargets[modelName]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end

    local modelHash = ModelHashFor(modelName)
    if not modelHash or not IsModelInCdimage(modelHash) then
        probedRenderTargets[modelName] = false
        return nil
    end

    for _, name in ipairs(RenderTargetNames()) do
        if RenderTargetLinks(name, modelHash) then
            probedRenderTargets[modelName] = name
            CastDebug('Model %s carries render target %s', modelName, name)
            return name
        end
    end

    probedRenderTargets[modelName] = false
    CastDebug('Model %s carries none of the known render targets', modelName)

    return nil
end

-- ============================================================================
-- STATE
-- ============================================================================

-- Live casts as the server sees them, keyed by screen key.
local casts = {}

-- The screen this player is presenting on, if any.
local presentingScreenKey = nil

-- Screens spawned from Config.Presentations.fixedScreens, so they can be
-- cleaned up on stop rather than left behind in the world.
local spawnedScreens = {}

-- Browser surfaces. Creating one is expensive and a runtime texture dictionary
-- name cannot be reused once taken, so surfaces are pooled for the lifetime of
-- the resource and re-pointed at a new URL instead of being rebuilt.
local surfacePool = {}
local surfacesByScreen = {}

-- Render targets currently registered, keyed by render target name.
local activeRenderTargets = {}

local pickerOpen = false

-- ============================================================================
-- NOTIFICATIONS
-- ============================================================================

local function Notify(message, kind)
    kind = kind or 'info'

    if Config.NotifySystem == 'ox_lib' and GetResourceState('ox_lib') == 'started' then
        exports['ox_lib']:notify({ title = 'FiveRoster', description = message, type = kind })
    elseif Config.NotifySystem == 'esx' and GetResourceState('es_extended') == 'started' then
        TriggerEvent('esx:showNotification', message)
    elseif Config.NotifySystem == 'qbcore' and GetResourceState('qb-core') == 'started' then
        TriggerEvent('QBCore:Notify', message, kind)
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(message)
        EndTextCommandThefeedPostTicker(false, true)
    end
end

RegisterNetEvent('fiveroster:cast:notify', function(message)
    if type(message) == 'string' and message ~= '' then
        Notify(message)
    end
end)

-- ============================================================================
-- BROWSER SURFACES
-- ============================================================================

-- Declared ahead of AcquireSurface, which gives a surface back when a screen
-- asks for a resolution the one it holds was not built at.
local ReleaseSurface

-- A DUI's resolution is fixed when it is created, so a surface can only be
-- handed to a screen that wants the same one. A free surface of the wrong size
-- is destroyed and rebuilt rather than stretched, which is the whole point of
-- letting a screen choose its own resolution.
local function BuildSurface(index, url, resolution)
    local txdName = ('fiveroster_cast_%d_%dx%d'):format(index, resolution.width, resolution.height)

    local dui = CreateDui(url, resolution.width, resolution.height)
    if not dui then return nil end

    local txd = CreateRuntimeTxd(txdName)
    CreateRuntimeTextureFromDuiHandle(txd, 'screen', GetDuiHandle(dui))

    return {
        dui = dui,
        txd = txd,
        txdName = txdName,
        txnName = 'screen',
        width = resolution.width,
        height = resolution.height
    }
end

local function AcquireSurface(screenKey, url, resolution)
    resolution = resolution or Resolution()

    local existing = surfacesByScreen[screenKey]
    if existing then
        -- The presenter changed the resolution under a live cast. Rebuild
        -- rather than carry on at the old size.
        if existing.width ~= resolution.width or existing.height ~= resolution.height then
            ReleaseSurface(screenKey)
        else
            if existing.url ~= url then
                SetDuiUrl(existing.dui, url)
                existing.url = url
            end
            return existing
        end
    end

    local function claim(surface)
        surface.screenKey = screenKey
        surface.url = url
        surface.syncedSlide = nil
        SetDuiUrl(surface.dui, url)
        surfacesByScreen[screenKey] = surface
        return surface
    end

    -- Reuse a surface nothing is showing on before building another one.
    for _, surface in ipairs(surfacePool) do
        if not surface.screenKey and surface.width == resolution.width and surface.height == resolution.height then
            return claim(surface)
        end
    end

    -- Nothing free at this size. Rebuild a free one rather than grow the pool.
    for index, surface in ipairs(surfacePool) do
        if not surface.screenKey then
            DestroyDui(surface.dui)
            local rebuilt = BuildSurface(index, url, resolution)
            if not rebuilt then
                table.remove(surfacePool, index)
                return nil
            end
            surfacePool[index] = rebuilt
            return claim(rebuilt)
        end
    end

    local maxScreens = tonumber(Setting('maxScreens')) or PresentationDefaults.maxScreens
    if #surfacePool >= maxScreens then
        CastDebug('Surface pool exhausted (%d in use), not rendering %s', #surfacePool, screenKey)
        return nil
    end

    local index = #surfacePool + 1
    local surface = BuildSurface(index, url, resolution)
    if not surface then return nil end

    surfacePool[index] = surface
    CastDebug('Created browser surface %s for %s', surface.txdName, screenKey)

    return claim(surface)
end

function ReleaseSurface(screenKey)
    local surface = surfacesByScreen[screenKey]
    if not surface then return end

    surfacesByScreen[screenKey] = nil
    surface.screenKey = nil
    surface.url = nil
    surface.syncedSlide = nil

    -- The surface stays in the pool; pointing it at a blank page stops it
    -- painting and stops any video on the slide from playing on.
    SetDuiUrl(surface.dui, 'about:blank')

    CastDebug('Released browser surface for %s', screenKey)
end

local function SendToSurface(screenKey, payload)
    local surface = surfacesByScreen[screenKey]
    if not surface then return end

    SendDuiMessage(surface.dui, json.encode(payload))
end

local function DestroyAllSurfaces()
    for screenKey in pairs(surfacesByScreen) do
        surfacesByScreen[screenKey] = nil
    end

    for _, surface in ipairs(surfacePool) do
        if surface.dui then
            DestroyDui(surface.dui)
        end
    end

    surfacePool = {}
end

-- ============================================================================
-- RENDER TARGETS
-- ============================================================================

-- Several screen models can share one render target name ('tvscreen' is the
-- name every vanilla TV uses), so the linked models are tracked as a set. An
-- earlier version kept only the last model, which made two screens re-link the
-- same target against each other on every frame.
local function AcquireRenderTarget(name, modelName)
    local existing = activeRenderTargets[name]
    if existing and existing.models[modelName] then
        return existing.renderId
    end

    local modelHash = ModelHashFor(modelName)
    if not modelHash or not IsModelInCdimage(modelHash) then
        CastDebug('Model %s is not in the game files, cannot cast to it', modelName)
        return nil
    end

    if not IsNamedRendertargetRegistered(name) then
        RegisterNamedRendertarget(name, false)
    end

    if not IsNamedRendertargetLinked(modelHash) then
        LinkNamedRendertarget(modelHash)
    end

    local renderId = GetNamedRendertargetRenderId(name)
    if renderId == 0 then
        CastDebug('Render target %s did not resolve for %s', name, modelName)
        return nil
    end

    if existing then
        existing.renderId = renderId
        existing.models[modelName] = true
    else
        activeRenderTargets[name] = { renderId = renderId, models = { [modelName] = true } }
    end

    return renderId
end

-- Releasing a named render target does not repaint the panel: whatever was
-- drawn last stays on it, so ending a briefing left the final slide sitting on
-- the TV forever. The target has to be painted over while it is still held.
-- Black is what an off TV looks like, and is the only thing we can put there —
-- the game does not hand back whatever the panel showed before it was linked.
local BlankFrames = 4

-- Render target name -> frames of black still owed before it is released.
local blankingRenderTargets = {}

local function ScheduleBlank(name)
    if not name then return end
    if not activeRenderTargets[name] then return end
    blankingRenderTargets[name] = BlankFrames
end

-- Every render target name a cast still needs, so a screen going dark does not
-- blank another briefing that happens to share its model.
local function RenderTargetsInUse()
    local inUse = {}

    for _, cast in pairs(casts) do
        if cast.screen then
            local name = RenderTargetFor(cast.screen.model)
            if name then inUse[name] = true end
        end
    end

    return inUse
end

local function ReleaseRenderTarget(name)
    if IsNamedRendertargetRegistered(name) then
        ReleaseNamedRendertarget(name)
    end

    activeRenderTargets[name] = nil
    blankingRenderTargets[name] = nil
end

local function ReleaseRenderTargets()
    for name in pairs(activeRenderTargets) do
        ReleaseRenderTarget(name)
    end

    activeRenderTargets = {}
    blankingRenderTargets = {}
end

-- Paint the black frames that are owed, then let the target go. Called from the
-- render loop, which is the only place with frames to spend.
local function DrawBlanking()
    if next(blankingRenderTargets) == nil then return false end

    local inUse = RenderTargetsInUse()

    for name, remaining in pairs(blankingRenderTargets) do
        local target = activeRenderTargets[name]

        if inUse[name] or not target then
            -- A new cast claimed the screen back, or it is already gone.
            blankingRenderTargets[name] = nil
        elseif remaining <= 0 then
            ReleaseRenderTarget(name)
        else
            SetTextRenderId(target.renderId)
            SetScriptGfxDrawOrder(4)
            DrawRect(0.5, 0.5, 1.0, 1.0, 0, 0, 0, 255)
            SetTextRenderId(GetDefaultScriptRendertargetRenderId())
            blankingRenderTargets[name] = remaining - 1
        end
    end

    return next(blankingRenderTargets) ~= nil
end

-- ============================================================================
-- SCREEN DISCOVERY
-- ============================================================================

-- How far a ped standing at `coords` is from a screen prop. A wall-mounted TV
-- reports its origin at the centre of the panel, well above head height, so
-- the raw distance between two points punishes a player who is squarely in
-- front of a screen mounted high. The vertical gap is discounted to the part
-- that is genuinely out of reach, which keeps a briefing-room TV castable from
-- where you would actually stand to present.
local VerticalAllowance = 2.5

local function ScreenDistance(coords, screenCoords)
    local flat = #(vector2(coords.x, coords.y) - vector2(screenCoords.x, screenCoords.y))
    local vertical = math.abs(coords.z - screenCoords.z) - VerticalAllowance

    if vertical <= 0.0 then return flat end

    return math.sqrt((flat * flat) + (vertical * vertical))
end

-- A prop is only a screen if a render target actually links to its model.
-- Checking here rather than at cast time means a listed model the game has no
-- render target for is never offered, so the picker cannot open onto a screen
-- that would then fail to draw.
local function ScreenFromEntry(entry, screenCoords, distance)
    local renderTarget = entry.renderTarget or RenderTargetFor(entry.model)
    if not renderTarget then return nil end

    return {
        model = entry.model,
        coords = screenCoords,
        label = entry.label,
        renderTarget = renderTarget,
        distance = distance
    }
end

-- Every castable prop within `radius`, nearest first.
--
-- Three passes, because no single one of them sees everything. The object pool
-- holds props the engine has spawned, which is most of them but not props
-- baked into an interior. GetClosestObjectOfType reaches some of those, and
-- only ever returns one prop per model. Whatever the player is actually
-- looking at is picked up by the aim probe even when it sits outside the
-- radius the other two searched.
local function ScreensInRange(coords, radius)
    local found, seen = {}, {}

    local function consider(entry, screenCoords)
        local distance = ScreenDistance(coords, screenCoords)
        if distance > radius then return end

        local key = ScreenKey(entry.model, screenCoords)
        if seen[key] then return end

        local screen = ScreenFromEntry(entry, screenCoords, distance)
        if not screen then return end

        screen.key = key
        seen[key] = true
        found[#found + 1] = screen
    end

    -- Fixed screens first, so a deliberately placed briefing screen wins a tie
    -- against a stray TV that happens to be the same distance away.
    for _, entry in ipairs(FixedScreens()) do
        if entry.coords then consider(entry, entry.coords) end
    end

    local index = ScreenModelIndex()

    for _, object in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(object) then
            local entry = index[GetEntityModel(object)]
            if entry then consider(entry, GetEntityCoords(object)) end
        end
    end

    for _, entry in ipairs(ScreenModels()) do
        local object = GetClosestObjectOfType(coords.x, coords.y, coords.z, radius, entry.hash, false, false, false)
        if object ~= 0 and DoesEntityExist(object) then
            consider(entry, GetEntityCoords(object))
        end
    end

    table.sort(found, function(a, b) return a.distance < b.distance end)

    return found
end

-- The screen the player is aiming at, if it is one. Standing in front of a TV
-- and looking at it is the clearest statement of intent there is, so it is
-- honoured out to a longer reach than the proximity search uses.
local function CameraDirection()
    local rotation = GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local level = math.abs(math.cos(pitch))

    return vector3(-math.sin(yaw) * level, math.cos(yaw) * level, math.sin(pitch))
end

local function ScreenUnderAim(reach)
    local camera = GetGameplayCamCoord()
    local target = camera + (CameraDirection() * reach)
    local handle = StartShapeTestRay(camera.x, camera.y, camera.z, target.x, target.y, target.z, 16, PlayerPedId(), 4)
    local _, hit, _, _, entity = GetShapeTestResult(handle)

    if hit == 0 or not entity or entity == 0 or not DoesEntityExist(entity) then return nil end

    local entry = ScreenModelIndex()[GetEntityModel(entity)]
    if not entry then return nil end

    local screenCoords = GetEntityCoords(entity)
    local screen = ScreenFromEntry(entry, screenCoords, ScreenDistance(GetEntityCoords(PlayerPedId()), screenCoords))
    if not screen then return nil end

    screen.key = ScreenKey(screen.model, screenCoords)

    return screen
end

-- The nearest castable screen to a position, or nil.
local function FindNearestScreen(coords, radius)
    local nearby = ScreensInRange(coords, radius)
    if nearby[1] then return nearby[1] end

    return ScreenUnderAim(radius * 2.0)
end

-- Spawn the screens this resource owns.
local function SpawnFixedScreens()
    for _, entry in ipairs(FixedScreens()) do
        if entry.model and entry.coords then
            local modelHash = entry.hash

            RequestModel(modelHash)
            local attempts = 0
            while not HasModelLoaded(modelHash) and attempts < 200 do
                Wait(10)
                attempts = attempts + 1
            end

            if HasModelLoaded(modelHash) then
                local object = CreateObject(modelHash, entry.coords.x, entry.coords.y, entry.coords.z, false, false, false)
                SetEntityHeading(object, entry.heading or 0.0)
                FreezeEntityPosition(object, true)
                SetEntityInvincible(object, true)
                spawnedScreens[#spawnedScreens + 1] = object
                SetModelAsNoLongerNeeded(modelHash)
            else
                CastDebug('Could not load fixed screen model %s', tostring(entry.model))
            end
        end
    end
end

local function RemoveFixedScreens()
    for _, object in ipairs(spawnedScreens) do
        if DoesEntityExist(object) then
            DeleteEntity(object)
        end
    end

    spawnedScreens = {}
end

-- ============================================================================
-- CAST STATE FROM THE SERVER
-- ============================================================================

local function ApplyCast(cast)
    if type(cast) ~= 'table' or type(cast.screenKey) ~= 'string' then return end

    -- Parsed once here rather than per frame in the render loop.
    cast.screen = ParseScreenKey(cast.screenKey)
    if not cast.screen then return end

    casts[cast.screenKey] = cast

    if cast.presenter == GetPlayerServerId(PlayerId()) then
        presentingScreenKey = cast.screenKey
    end
end

local function ClearCast(screenKey)
    if type(screenKey) ~= 'string' then return end

    local cast = casts[screenKey]

    casts[screenKey] = nil
    ReleaseSurface(screenKey)

    -- Wipe the panel before the render target goes, or the last slide stays on
    -- the TV. Removed from `casts` first, so a screen still showing another
    -- briefing on the same model keeps it.
    if cast and cast.screen then
        ScheduleBlank(RenderTargetFor(cast.screen.model))
    end

    if presentingScreenKey == screenKey then
        presentingScreenKey = nil
    end
end

RegisterNetEvent('fiveroster:cast:state', function(list)
    if type(list) ~= 'table' then return end

    for screenKey in pairs(casts) do
        ClearCast(screenKey)
    end

    for _, cast in ipairs(list) do
        ApplyCast(cast)
    end

    CastDebug('Synced %d active cast(s)', #list)
end)

RegisterNetEvent('fiveroster:cast:started', function(cast)
    ApplyCast(cast)
    CastDebug('Cast started on %s', tostring(cast and cast.screenKey))
end)

RegisterNetEvent('fiveroster:cast:slide', function(screenKey, index)
    local cast = casts[screenKey]
    if not cast then return end

    cast.currentSlide = index

    -- The page is already loaded on every screen in range, so a slide change is
    -- a message rather than a reload — the screen never blanks between slides.
    SendToSurface(screenKey, {
        type = 'fiveroster-cast',
        action = 'slide',
        index = index
    })

    local surface = surfacesByScreen[screenKey]
    if surface then
        surface.syncedSlide = index
    end
end)

RegisterNetEvent('fiveroster:cast:stopped', function(screenKey)
    ClearCast(screenKey)
    CastDebug('Cast stopped on %s', tostring(screenKey))
end)

-- ============================================================================
-- RENDERING
-- ============================================================================

-- Draw one cast's surface onto its screen. Runs every frame while the player
-- is close enough to read it.
local DrawBehindPawnMenu = rawget(_G, 'SetScriptGfxDrawBehindPawnmenu')
    or rawget(_G, 'SetScriptGfxDrawBehindPawnMenu')

local function DrawCast(screenKey, cast)
    local screen = cast.screen
    if not screen then return false end

    local renderTarget = RenderTargetFor(screen.model)
    if not renderTarget then return false end

    local surface = AcquireSurface(screenKey, cast.castUrl, ResolutionFor(screen.model))
    if not surface then return false end

    local renderId = AcquireRenderTarget(renderTarget, screen.model)
    if not renderId then return false end

    local display = DisplayFor(screen.model)

    SetTextRenderId(renderId)
    SetScriptGfxDrawOrder(4)
    if DrawBehindPawnMenu then DrawBehindPawnMenu(true) end

    -- Anything the page does not cover is black rather than whatever the panel
    -- last held, so shrinking the image reads as letterboxing and not as a
    -- half-cleared screen.
    if display.scaleX < 1.0 or display.scaleY < 1.0 or display.offsetX ~= 0.0 or display.offsetY ~= 0.0 then
        DrawRect(0.5, 0.5, 1.0, 1.0, 0, 0, 0, 255)
    end

    DrawSprite(surface.txdName, surface.txnName,
        0.5 + display.offsetX, 0.5 + display.offsetY,
        display.scaleX, display.scaleY,
        0.0, 255, 255, 255, 255)

    if DrawBehindPawnMenu then DrawBehindPawnMenu(false) end
    SetTextRenderId(GetDefaultScriptRendertargetRenderId())

    return true
end

-- Which casts are close enough to be worth a browser surface. Sorted nearest
-- first, so when more screens are in range than the pool can serve, the one the
-- player is actually looking at wins.
local function CastsInRange(coords)
    local viewDistance = tonumber(Setting('viewDistance')) or PresentationDefaults.viewDistance
    local inRange = {}

    for screenKey, cast in pairs(casts) do
        if cast.screen then
            local distance = #(coords - cast.screen.coords)
            if distance <= viewDistance then
                inRange[#inRange + 1] = { key = screenKey, cast = cast, distance = distance }
            end
        end
    end

    table.sort(inRange, function(a, b) return a.distance < b.distance end)

    return inRange
end

CreateThread(function()
    if not IsCastingEnabled() then return end

    while true do
        local coords = GetEntityCoords(PlayerPedId())
        local inRange = CastsInRange(coords)

        -- Anything that drifted out of range gives its surface back, so walking
        -- between two briefings does not strand a browser on the far one.
        for screenKey in pairs(surfacesByScreen) do
            local stillNear = false
            for _, entry in ipairs(inRange) do
                if entry.key == screenKey then
                    stillNear = true
                    break
                end
            end
            if not stillNear then
                ReleaseSurface(screenKey)
            end
        end

        -- Screens that have just stopped get their black frames whether or not
        -- anything else is being drawn, since that is the only thing standing
        -- between the presenter and a slide left on the wall.
        local stillBlanking = DrawBlanking()

        if #inRange == 0 then
            if stillBlanking then
                Wait(0)
            else
                -- Nothing to draw: idle cheaply rather than spinning every frame.
                if next(activeRenderTargets) ~= nil then
                    ReleaseRenderTargets()
                end
                Wait(500)
            end
        else
            for _, entry in ipairs(inRange) do
                DrawCast(entry.key, entry.cast)
            end
            Wait(0)
        end
    end
end)

-- A screen that has just come into range needs to be told which slide it is on:
-- the page opens on the cast's current slide, but the server may have moved on
-- between the page loading and the surface being ready.
CreateThread(function()
    if not IsCastingEnabled() then return end

    while true do
        Wait(1000)

        for screenKey, surface in pairs(surfacesByScreen) do
            local cast = casts[screenKey]
            if cast and surface.syncedSlide ~= cast.currentSlide then
                SendToSurface(screenKey, {
                    type = 'fiveroster-cast',
                    action = 'slide',
                    index = cast.currentSlide
                })
                surface.syncedSlide = cast.currentSlide
            end
        end
    end
end)

-- ============================================================================
-- PRESENTER CONTROLS
-- ============================================================================

-- Set by /castfit. Declared here because the deck controls below have to stand
-- down while the adjuster has the arrow keys.
local adjusting = false

CreateThread(function()
    if not IsCastingEnabled() then return end

    local nextKey = tonumber(Setting('nextKey')) or PresentationDefaults.nextKey
    local prevKey = tonumber(Setting('prevKey')) or PresentationDefaults.prevKey
    local stopKey = tonumber(Setting('stopKey')) or PresentationDefaults.stopKey

    while true do
        -- The adjuster borrows the same keys, so stepping the deck is suspended
        -- while it is open rather than doing both at once.
        if presentingScreenKey and not pickerOpen and not adjusting then
            local cast = casts[presentingScreenKey]

            if cast then
                if IsControlJustPressed(0, nextKey) then
                    TriggerServerEvent('fiveroster:cast:step', 1)
                elseif IsControlJustPressed(0, prevKey) then
                    TriggerServerEvent('fiveroster:cast:step', -1)
                elseif IsControlJustPressed(0, stopKey) then
                    TriggerServerEvent('fiveroster:cast:stop')
                end
            end

            Wait(0)
        else
            Wait(300)
        end
    end
end)

-- ============================================================================
-- FITTING A SCREEN
-- ============================================================================
-- A render target's shape is baked into the model and the game will not report
-- it, so a panel that is not the shape of the page comes out stretched or
-- cropped and no amount of guessing from here will fix it. The presenter can
-- see the screen, so they adjust it: /castfit takes over the arrow keys, and
-- leaving it prints the config to keep.

local AdjustStep = 0.02
local AdjustControls = {
    left = 174, right = 175, up = 172, down = 173,
    stretch = 21,      -- Left Shift: arrows resize instead of moving
    resolution = 246,  -- Y: next resolution preset
    reset = 182,       -- L: back to the configured values
    done = 177         -- Backspace: finish
}

local function AdjustedModel()
    local cast = presentingScreenKey and casts[presentingScreenKey]
    return cast and cast.screen and cast.screen.model or nil
end

-- Overrides start from whatever the screen is showing now, so entering the
-- adjuster never moves the image.
local function BeginAdjust(modelName)
    if displayOverrides[modelName] then return end

    local display = DisplayFor(modelName)
    local resolution = ResolutionFor(modelName)

    displayOverrides[modelName] = {
        scaleX = display.scaleX, scaleY = display.scaleY,
        offsetX = display.offsetX, offsetY = display.offsetY,
        width = resolution.width, height = resolution.height
    }
end

local function NextResolution(override)
    local current = 0

    for index, preset in ipairs(ResolutionPresets) do
        if preset.width == override.width and preset.height == override.height then
            current = index
            break
        end
    end

    local preset = ResolutionPresets[(current % #ResolutionPresets) + 1]
    override.width, override.height = preset.width, preset.height
end

-- What to paste into config.lua. Printed rather than saved: a client cannot
-- write the server's config, and a screen everyone can see should not be
-- reshaped for good by whoever presented at it last.
local function PrintAdjustment(modelName, override)
    local literal = modelName:match('^#(-?%d+)$') and modelName:sub(2) or ("'" .. modelName .. "'")

    print('^5[FiveRoster]^7 Screen settings. Put this in Config.Presentations.screenModels:')
    print(('  { model = %s,'):format(literal))
    print(('      resolution = { width = %d, height = %d },'):format(override.width, override.height))
    print(('      display = { scaleX = %.3f, scaleY = %.3f, offsetX = %.3f, offsetY = %.3f } },')
        :format(override.scaleX, override.scaleY, override.offsetX, override.offsetY))
    print('^3[FiveRoster]^7 Filling in screenModels replaces the built-in list, so keep the models you still want.')
end

local function DrawAdjustHint(override)
    local text = ('FITTING  %dx%d  scale %.2f x %.2f  offset %.2f, %.2f   [Arrows] move   [Shift+Arrows] stretch   [Y] resolution   [L] reset   [Backspace] done')
        :format(override.width, override.height, override.scaleX, override.scaleY, override.offsetX, override.offsetY)

    SetTextFont(4)
    SetTextScale(0.32, 0.32)
    SetTextColour(120, 220, 255, 230)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentSubstringPlayerName(text)
    DrawText(0.5, 0.89)
end

CreateThread(function()
    if not IsCastingEnabled() then return end

    while true do
        local modelName = adjusting and AdjustedModel() or nil

        if not modelName then
            adjusting = false
            Wait(300)
        else
            local override = displayOverrides[modelName]

            if not override then
                adjusting = false
            else
                local stretching = IsControlPressed(0, AdjustControls.stretch)

                if IsControlPressed(0, AdjustControls.left) then
                    if stretching then override.scaleX = math.max(0.05, override.scaleX - AdjustStep)
                    else override.offsetX = override.offsetX - AdjustStep end
                elseif IsControlPressed(0, AdjustControls.right) then
                    if stretching then override.scaleX = math.min(4.0, override.scaleX + AdjustStep)
                    else override.offsetX = override.offsetX + AdjustStep end
                end

                if IsControlPressed(0, AdjustControls.up) then
                    if stretching then override.scaleY = math.min(4.0, override.scaleY + AdjustStep)
                    else override.offsetY = override.offsetY - AdjustStep end
                elseif IsControlPressed(0, AdjustControls.down) then
                    if stretching then override.scaleY = math.max(0.05, override.scaleY - AdjustStep)
                    else override.offsetY = override.offsetY + AdjustStep end
                end

                if IsControlJustPressed(0, AdjustControls.resolution) then
                    NextResolution(override)
                end

                if IsControlJustPressed(0, AdjustControls.reset) then
                    displayOverrides[modelName] = nil
                    BeginAdjust(modelName)
                    override = displayOverrides[modelName]
                end

                if IsControlJustPressed(0, AdjustControls.done) then
                    adjusting = false
                    PrintAdjustment(modelName, override)
                    Notify('Screen settings printed to the console (F8).', 'success')
                else
                    DrawAdjustHint(override)
                end
            end

            Wait(0)
        end
    end
end)

-- The presenter's on-screen reminder of the controls and where they are in the
-- deck. Only the presenter sees it; everyone else just watches the screen.
local function DrawPresenterHint(cast)
    local text = ('%s   %d / %d   [Left/Right] change slide   [Backspace] end   /%s to fit the screen'):format(
        cast.name or 'Presentation',
        (cast.currentSlide or 0) + 1,
        math.max(cast.slideCount or 1, 1),
        tostring(Setting('adjustCommand'))
    )

    SetTextFont(4)
    SetTextScale(0.34, 0.34)
    SetTextColour(245, 197, 24, 220)
    SetTextOutline()
    SetTextCentre(true)
    SetTextEntry('STRING')
    AddTextComponentSubstringPlayerName(text)
    DrawText(0.5, 0.93)
end

CreateThread(function()
    if not IsCastingEnabled() then return end
    if Setting('showSlideCounter') == false then return end

    while true do
        if presentingScreenKey and casts[presentingScreenKey] then
            DrawPresenterHint(casts[presentingScreenKey])
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ============================================================================
-- ATTENDANCE
-- ============================================================================
-- Only the presenter reports, and only server IDs: the server resolves those
-- to Discord accounts itself, so nobody can be marked as having attended a
-- briefing they were not standing in.

CreateThread(function()
    if not IsCastingEnabled() then return end
    if AttendanceSetting('enabled', true) == false then return end

    local interval = tonumber(AttendanceSetting('interval', 30000)) or 30000
    local radius = tonumber(AttendanceSetting('distance', 15.0)) or 15.0

    -- Which cast the last report was for. A new cast reports at once rather
    -- than after a full interval, so the room is on record from slide one.
    local lastReportedCast = nil
    local elapsed = 0

    while true do
        Wait(1000)

        local cast = presentingScreenKey and casts[presentingScreenKey] or nil

        if not cast then
            lastReportedCast = nil
            elapsed = 0
        else
            elapsed = elapsed + 1000
            local isNewCast = lastReportedCast ~= cast.castUuid

            if isNewCast or elapsed >= interval then
                local screen = cast.screen

                if screen and screen.coords then
                    local watchers = {}

                    for _, playerIndex in ipairs(GetActivePlayers()) do
                        local ped = GetPlayerPed(playerIndex)
                        if DoesEntityExist(ped) and #(GetEntityCoords(ped) - screen.coords) <= radius then
                            watchers[#watchers + 1] = GetPlayerServerId(playerIndex)
                        end
                    end

                    if #watchers > 0 then
                        TriggerServerEvent('fiveroster:cast:attendance', watchers)
                    end
                end

                lastReportedCast = cast.castUuid
                elapsed = 0
            end
        end
    end
end)

-- ============================================================================
-- THE PICKER
-- ============================================================================

-- The screen the player was standing at when they opened the picker. Held so
-- the choice lands on that screen even if they shuffle a step while choosing.
local pendingScreen = nil

local function ClosePicker()
    if not pickerOpen then return end

    pickerOpen = false
    pendingScreen = nil

    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closePicker' })
end

local function OpenPresentationPicker()
    if not IsCastingEnabled() then return end

    -- Already presenting: the command ends the cast rather than stacking one.
    if presentingScreenKey then
        TriggerServerEvent('fiveroster:cast:stop')
        return
    end

    -- The tablet already holds NUI focus. Two overlays fighting over it leaves
    -- the player stuck with a cursor and no way to dismiss either.
    if FiveRosterTabletOpen then
        Notify(CastMessage('close_tablet_first'), 'error')
        return
    end

    local castDistance = tonumber(Setting('castDistance')) or PresentationDefaults.castDistance
    local screen = FindNearestScreen(GetEntityCoords(PlayerPedId()), castDistance)

    if not screen then
        Notify(CastMessage('no_screen'), 'error')
        return
    end

    pendingScreen = screen
    TriggerServerEvent('fiveroster:cast:requestPresentations')
end

RegisterNetEvent('fiveroster:cast:presentations', function(presentations)
    if type(presentations) ~= 'table' or #presentations == 0 then
        pendingScreen = nil
        return
    end

    if not pendingScreen then return end

    pickerOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openPicker',
        presentations = presentations,
        screenLabel = pendingScreen.label or 'Nearby screen'
    })
end)

RegisterNUICallback('castPresentation', function(data, cb)
    cb('ok')

    local uuid = data and data.presentation_uuid
    local screen = pendingScreen

    ClosePicker()

    if type(uuid) ~= 'string' or uuid == '' or not screen then return end

    TriggerServerEvent('fiveroster:cast:start', uuid, screen.key, screen.label or screen.model)
end)

RegisterNUICallback('closePicker', function(_, cb)
    ClosePicker()
    cb('ok')
end)

-- ============================================================================
-- DIAGNOSTICS
-- ============================================================================

-- Lists what is around the player and says, prop by prop, why it is or is not
-- castable. A TV that is not on the model list is the usual reason /present
-- reports no screen, and the game will not tell you a prop's model name, only
-- its hash — so the hash is printed in the form config accepts directly.
local function ReportNearbyScreens()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local radius = 15.0
    local index = ScreenModelIndex()

    local aimed = nil
    do
        local camera = GetGameplayCamCoord()
        local target = camera + (CameraDirection() * 25.0)
        local handle = StartShapeTestRay(camera.x, camera.y, camera.z, target.x, target.y, target.z, 16, ped, 4)
        local _, hit, _, _, entity = GetShapeTestResult(handle)
        if hit ~= 0 and entity and entity ~= 0 and DoesEntityExist(entity) then aimed = entity end
    end

    local rows, seen = {}, {}

    local function add(object)
        if seen[object] or not DoesEntityExist(object) then return end
        seen[object] = true

        local objectCoords = GetEntityCoords(object)
        rows[#rows + 1] = {
            hash = GetEntityModel(object),
            distance = ScreenDistance(coords, objectCoords),
            aimed = object == aimed
        }
    end

    if aimed then add(aimed) end

    for _, object in ipairs(GetGamePool('CObject')) do
        if ScreenDistance(coords, GetEntityCoords(object)) <= radius then add(object) end
    end

    table.sort(rows, function(a, b)
        if a.aimed ~= b.aimed then return a.aimed end
        return a.distance < b.distance
    end)

    -- Probing an unknown model registers and releases a render target, which
    -- would disturb a cast that is already running.
    local casting = next(activeRenderTargets) ~= nil

    print(('^5[FiveRoster]^7 %d prop(s) within %.1fm. Nearest first; the one you are looking at is marked.'):format(#rows, radius))
    if casting then
        print('^3[FiveRoster]^7 A cast is running, so unlisted models are not probed. Run this again once it has ended.')
    end

    local castable = 0

    for position, row in ipairs(rows) do
        if position > 20 then break end

        local entry = index[row.hash]
        local name = entry and entry.model or ('#%d'):format(row.hash)
        local marker = row.aimed and ' <- looking at this' or ''
        local verdict

        if entry then
            local renderTarget = RenderTargetFor(entry.model)
            if renderTarget then
                castable = castable + 1
                verdict = ('castable, render target "%s"'):format(renderTarget)
            else
                verdict = 'listed as a screen, but no render target links to it'
            end
        elseif casting then
            verdict = 'not on the screen list'
        else
            local renderTarget = RenderTargetFor(name)
            if renderTarget then
                verdict = ('NOT on the screen list, but render target "%s" links. Add { model = %d } to Config.Presentations.screenModels'):format(renderTarget, row.hash)
            else
                verdict = 'not a screen'
            end
        end

        print(('  %5.1fm  %-32s %s%s'):format(row.distance, name, verdict, marker))
    end

    if #rows > 20 then
        print(('  ... and %d more, not shown.'):format(#rows - 20))
    end

    print(('^5[FiveRoster]^7 %d castable screen(s) in range. /present reaches %.1fm.'):format(castable, tonumber(Setting('castDistance')) or PresentationDefaults.castDistance))

    Notify(('Screen report printed to the console (F8). %d castable screen(s) nearby.'):format(castable), castable > 0 and 'success' or 'error')
end

-- ============================================================================
-- COMMANDS
-- ============================================================================

CreateThread(function()
    if not IsCastingEnabled() then return end

    local adjustCommand = Setting('adjustCommand')
    if type(adjustCommand) == 'string' and adjustCommand ~= '' then
        RegisterCommand(adjustCommand, function()
            local modelName = AdjustedModel()

            if not modelName then
                Notify(CastMessage('not_presenting'), 'error')
                return
            end

            if adjusting then
                adjusting = false
                return
            end

            BeginAdjust(modelName)
            adjusting = true
        end, false)
    end

    local debugCommand = Setting('debugCommand')
    if type(debugCommand) == 'string' and debugCommand ~= '' then
        RegisterCommand(debugCommand, function()
            ReportNearbyScreens()
        end, false)
    end

    local command = Setting('command')
    if type(command) == 'string' and command ~= '' then
        RegisterCommand(command, function()
            OpenPresentationPicker()
        end, false)

        local key = Setting('commandKey')
        if type(key) == 'string' and key ~= '' then
            RegisterKeyMapping(command, 'Cast a FiveRoster presentation', 'keyboard', key)
        end
    end

    local stopCommand = Setting('stopCommand')
    if type(stopCommand) == 'string' and stopCommand ~= '' then
        RegisterCommand(stopCommand, function()
            if not presentingScreenKey then
                Notify(CastMessage('not_presenting'), 'error')
                return
            end
            TriggerServerEvent('fiveroster:cast:stop')
        end, false)
    end
end)

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

-- Ask what is already on the screens. Covers a player joining mid-briefing and
-- a resource restart with players still connected.
CreateThread(function()
    if not IsCastingEnabled() then return end

    Wait(3000)
    SpawnFixedScreens()
    TriggerServerEvent('fiveroster:cast:requestState')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    ClosePicker()
    DestroyAllSurfaces()

    -- Same reason as ending a cast: a released render target keeps its last
    -- frame, so restarting the resource would otherwise leave a slide on every
    -- screen it had been drawing to.
    for name in pairs(activeRenderTargets) do
        blankingRenderTargets[name] = BlankFrames
    end

    casts = {}

    for _ = 1, BlankFrames + 1 do
        if not DrawBlanking() then break end
        Wait(0)
    end

    ReleaseRenderTargets()
    RemoveFixedScreens()
end)

-- ============================================================================
-- EXPORTS
-- ============================================================================

exports('IsPresenting', function()
    return presentingScreenKey ~= nil
end)

exports('GetActiveCast', function()
    if not presentingScreenKey then return nil end
    return casts[presentingScreenKey]
end)

exports('StopPresenting', function()
    if not presentingScreenKey then return false end
    TriggerServerEvent('fiveroster:cast:stop')
    return true
end)

exports('OpenPresentationPicker', OpenPresentationPicker)

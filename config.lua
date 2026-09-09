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
    no_rosters = 'You are not enrolled in any rosters.',

    -- Shift break (pause/resume) messages.
    -- These are optional: if you are upgrading and kept your old config.lua,
    -- the resource falls back to these defaults automatically.
    shift_paused = 'Shift paused. You are on a break.',
    shift_resumed = 'Break over. Your shift is running again.',
    shift_already_paused = 'You are already on a break.',
    shift_already_running = 'Your shift is already running.',
    shift_not_active = 'You are not currently on shift.',
    shift_pause_unavailable = 'Shift breaks are not available on this FiveRoster instance.'
}

--[[
    ============================================================================
    SHIFT BREAKS (PAUSE / RESUME)
    ============================================================================
    Players can put a shift on a break without ending it. The shift stays open
    and keeps its ID, start time and division flag, but the clock stops and the
    break time is deducted from the hours the shift finally records.

    Requires a FiveRoster instance that exposes the shift pause/resume routes.
    Older instances are detected automatically and the controls are hidden.
]]
Config.ShiftPause = {
    enabled = true,                  -- Allow pausing/resuming shifts in-game

    pauseCommand = 'shiftpause',     -- /shiftpause  - start a break
    resumeCommand = 'shiftresume',   -- /shiftresume - end the break
    toggleCommand = 'shiftbreak',    -- /shiftbreak  - toggle break on/off

    -- Register a keybind for the toggle command (players rebind it in
    -- Settings > Key Bindings > FiveM). Leave empty for no default key.
    toggleKey = ''                   -- Example: 'B'
}

--[[
    ============================================================================
    SHIFT HUD
    ============================================================================
    Optional on-screen indicator showing whether the player is on duty or on a
    break, with the worked duration. The duration is frozen while on a break,
    matching the server, so it never drifts or jumps backwards.

    Disabled by default so it does not collide with an existing server HUD.
    Other resources can read the same state via the exports instead.
]]
Config.ShiftHUD = {
    enabled = false,          -- Set to true to draw the built-in indicator
    x = 0.015,                -- Screen position (0.0 - 1.0)
    y = 0.88,
    scale = 0.35,             -- Text scale
    showRosterName = true,    -- Include the roster name in the indicator
    onDutyLabel = 'ON DUTY',
    onBreakLabel = 'ON BREAK'
}

--[[
    ============================================================================
    SHIFT STATE SYNC
    ============================================================================
    The in-game shift state is re-read from FiveRoster so it reflects shifts
    (and breaks) started anywhere - the tablet, the web dashboard, or another
    server - and survives a resource restart.
]]
Config.ShiftSync = {
    onPlayerLoad = true,      -- Sync shortly after the player's client starts
    playerLoadDelay = 5000,   -- Delay in ms before that first sync
    afterPauseChange = true   -- Re-read full break totals after a tablet pause/resume
}

--[[
    ============================================================================
    DISCONNECT RECOVERY
    ============================================================================
    Shifts are ended the moment a player disconnects, however they leave - the
    in-game disconnect button, closing the game, an F8 console quit/disconnect,
    a timeout, or a kick.

    playerDropped is the fast path, but it is not a guarantee: it is never fired
    at all if the server crashes or is killed, and even when it fires the HTTP
    request can die with the process. So the open shifts and the ends still owed
    are written to a small state file in this resource's folder. Anything left
    over is settled on the next resource start, and a periodic sweep catches
    players who vanished without a disconnect we ever handled.

    Leave this enabled unless the resource folder is read-only.
]]
Config.ShiftRecovery = {
    enabled = true,                   -- Recover shifts left open by a lost disconnect
    reconcileInterval = 60000,        -- How often to sweep for vanished players (ms)
    maxRetryAttempts = 60,            -- Give up on one shift after this many sweeps
    stateFile = 'shift_state.json'    -- Written inside this resource's folder
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

--[[
    ============================================================================
    TRAINING PRESENTATIONS ON IN-GAME SCREENS
    ============================================================================
    Cast a FiveRoster training presentation onto a TV or monitor in the world
    and click through it in game, so a briefing can be run without anyone
    leaving the server.

    How it works:
      1. A presenter stands in front of a configured screen and runs /present.
      2. They pick one of the presentations their roster has on FiveRoster.
      3. The deck appears on the screen for everyone nearby, and the presenter
         drives it with the arrow keys.

    HOW SCREENS ARE MATCHED
    -----------------------
    Screens are ordinary GTA props that carry a named render target. Every
    vanilla TV, monitor and projector screen is recognised out of the box, and
    a prop only counts as a screen once a render target actually links to it,
    so a model that cannot display anything is never offered.

    If /present says there is no screen while you are stood at a TV, run
    /screeninfo. It prints every prop around you to the client console (F8) and
    says why each one is or is not castable, including the hash of a TV that is
    not on the list yet.

    The game links a render target to a MODEL, not to one prop, so every prop
    of that model showing on screen displays the cast at the same time. If your
    map has many TVs of the same model and you only want one of them to be
    castable, give the briefing screen its own model (a streamed prop, or one
    of the less common vanilla models) and list only that model in
    screenModels.
]]
Config.Presentations = {
    enabled = true,

    -- Commands. /present opens the picker at the nearest screen in range.
    command = 'present',
    stopCommand = 'endpresentation',

    -- Prints every prop around you to the client console (F8) and says, one by
    -- one, whether it can be cast to. Run this when /present says there is no
    -- screen: it names the model, or prints the hash of a TV this resource has
    -- never heard of so you can paste it straight into screenModels below.
    debugCommand = 'screeninfo',

    -- Run this while presenting to reframe the screen you are casting to.
    -- Arrow keys move the image, Shift and the arrows stretch it, Y steps
    -- through resolutions, L resets, Backspace finishes and prints the
    -- settings to the client console (F8) to paste into screenModels below.
    adjustCommand = 'castfit',

    -- Register a keybind for the picker (players rebind it in
    -- Settings > Key Bindings > FiveM). Leave empty for no default key.
    commandKey = '',

    -- Controls held by the presenter while a cast is running.
    -- Control IDs: https://docs.fivem.net/docs/game-references/controls/
    nextKey = 175,        -- Right arrow  - next slide
    prevKey = 174,        -- Left arrow   - previous slide
    stopKey = 177,        -- Backspace    - stop the cast

    -- How close the presenter must stand to a screen to start or drive a cast.
    -- Height is largely discounted, so a TV mounted above head height is still
    -- reachable from where you would stand to present at it. Looking straight
    -- at a screen also counts, out to twice this distance.
    castDistance = 6.0,

    -- How close anyone must be for the deck to be drawn on the screen at all.
    -- Keep this modest: each screen in range costs a browser surface.
    viewDistance = 20.0,

    -- Resolution of the browser surface drawn onto the screen. Higher is
    -- sharper and more expensive. A panel that is not 16:9 wants its own
    -- resolution, which is set per model in screenModels rather than here.
    resolution = { width = 1280, height = 720 },

    --[[
        FRAMING
        How the page is laid onto the panel. The shape of a render target is
        baked into the model and the game will not report it, so a panel that
        is not the shape of the page comes out stretched or cropped and only
        the person looking at it can say by how much.

        Rather than guess, cast to the screen and run /castfit. It prints the
        numbers to paste back here, or into a single model's entry in
        screenModels, which takes precedence over this.

        scaleX / scaleY  1.0 fills the panel. Below 1.0 leaves a black border.
        offsetX/offsetY  Shifts the image. 0.0 is centred.
    ]]
    display = { scaleX = 1.0, scaleY = 1.0, offsetX = 0.0, offsetY = 0.0 },

    -- How many screens a single client will draw at once. Each one is a
    -- browser surface, so raising this costs client performance. When more
    -- screens are in range than this allows, the nearest ones win.
    maxScreens = 2,

    -- Draw the deck name and slide counter along the bottom of the screen.
    showSlideCounter = true,

    --[[
        ATTENDANCE
        Who was standing in front of the screen is reported back to FiveRoster
        while the cast runs, so an in-game briefing appears in the presentation
        analytics next to portal views and counts towards the watcher's
        training record. Set enabled = false to cast without recording anyone.
    ]]
    attendance = {
        enabled = true,
        distance = 15.0,      -- Players within this range of the screen count
        interval = 30000,     -- How often attendance is reported (ms)
        requireLineOfSight = false
    },

    --[[
        SCREEN MODELS
        Any prop of one of these models becomes a castable screen.

        LEAVE THIS EMPTY unless you have a screen the resource does not already
        find. Empty means the built-in list is used, which covers every vanilla
        TV, monitor and projector screen worth casting to. Filling it in
        REPLACES that list rather than adding to it.

        You do not need to give a render target name. The name is baked into
        the model by the game, and the resource works out which one a model
        carries by trying the names in renderTargetNames below. Give one only
        to override the result.

        A prop whose model name you do not know can be added by hash, which is
        what /screeninfo prints:
            { model = -1234567890 },
            { model = 'my_streamed_tv', renderTarget = 'my_rt' },

        A screen whose panel is the wrong shape for the deck takes its own
        resolution and framing, which is what /castfit prints:
            { model = 'prop_monitor_01a',
              resolution = { width = 1024, height = 768 },
              display = { scaleX = 1.0, scaleY = 0.94, offsetX = 0.0, offsetY = 0.0 } },
    ]]
    screenModels = {
        -- Empty = use the built-in list of vanilla screens.
    },

    --[[
        RENDER TARGET NAMES
        Tried in order against a model until one links. Every vanilla screen
        uses 'tvscreen'. Add the name a streamed prop's author baked in if you
        want it found without listing it above.
    ]]
    renderTargetNames = {
        'tvscreen',
    },

    --[[
        FIXED SCREENS (optional)
        Screens this resource spawns and owns, for briefing rooms that have no
        TV in the map. Each entry spawns the prop on resource start and removes
        it on stop.

        Example:
        { label = 'PD Briefing Room',
          model = 'prop_tv_flat_01',
          renderTarget = 'tvscreen',
          coords = vector3(447.51, -974.14, 30.69),
          heading = 90.0 },
    ]]
    fixedScreens = {
        -- Add your own briefing screens here
    },

    messages = {
        no_screen = 'No castable screen here. Run /screeninfo to see what is nearby.',
        no_presentations = 'You have no training presentations to cast.',
        cast_started = 'Casting "%s". Arrow keys change slide, Backspace ends it.',
        cast_stopped = 'Presentation ended.',
        cast_failed = 'Could not start that presentation. The reason is in the server console.',
        cast_unreachable = 'Could not reach FiveRoster. Tell an admin.',
        cast_denied = 'This server is not authorised to cast presentations.',
        cast_busy = 'That screen is already showing a presentation.',
        not_presenting = 'You are not casting a presentation.',
        close_tablet_first = 'Close the tablet before casting a presentation.',
        unsupported = 'In-game presentations are not available on this FiveRoster instance.'
    }
}

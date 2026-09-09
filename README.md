# FiveRoster for FiveM

Official FiveRoster integration for FiveM servers. Allows players to access rosters, track shifts, and view documents directly in-game through a beautiful tablet interface.

![FiveRoster](https://fiveroster.com/assets/img/fiveroster_text_logo_yw.png)

## Features

- **In-Game Tablet UI** - Beautiful, immersive tablet interface with animations
- **Shift Tracking** - Players can start and end shifts directly in-game
- **Shift Breaks** - Pause and resume a shift without ending it; break time is deducted from recorded hours
- **Training Presentations on In-Game Screens** - Cast a FiveRoster training deck onto a TV and click through it in game; attendance is recorded back to FiveRoster
- **Auto Shift End** - Automatically ends shifts when players disconnect
- **Rank-to-Job Sync** - Automatically sync FiveRoster ranks to in-game jobs (ESX/QBCore/QBox)
- **Multi-Guild Support** - Connect multiple Discord servers (PD, EMS, Fire, etc.)
- **Multi-Roster Support** - Access all enrolled rosters from one interface
- **Document Viewer** - View server documents in-game
- **Framework Support** - Works with ESX, QBCore, QBox, or standalone FiveM
- **Multiple Notification Systems** - Native, ox_lib, ESX, or QBCore notifications
- **Developer Exports** - Full API for integration with MDTs and other resources

## Requirements

- FiveM Server (build 5181+)
- FiveRoster account with API access
- Players must have Discord linked to their FiveM account

## Installation

### 1. Download the Resource

Download the latest release and extract it to your `resources` folder:

```
resources/
└── fiveroster/
    ├── client/
    ├── server/
    ├── html/
    ├── config.lua
    └── fxmanifest.lua
```

### 2. Configure Your API Key(s)

```bash
# Copy the example config
cp server/config.lua.example server/config.lua

# Edit server/config.lua and add your API key(s)
```

**Getting your API key:**
1. Log in to [FiveRoster](https://fiveroster.com)
2. Go to **Server Settings** > **API Keys**
3. Click **Create API Key**
4. Copy the generated key
5. Paste it into `server/config.lua`

### 3. Add to Server Config

Add to your `server.cfg`:

```cfg
ensure fiveroster
```

### 4. Restart Your Server

Restart your FiveM server to load the resource.

## Configuration

### Shared Config (`config.lua`)

```lua
-- FiveRoster API URL (default is hosted service)
Config.FiveRosterURL = 'https://fiveroster.com'

-- Discord ID source: 'fivem', 'esx', 'qbcore', 'custom'
Config.DiscordSource = 'fivem'

-- Commands
Config.CommandName = 'rosters'           -- Main command
Config.CommandAliases = {'roster', 'fr'} -- Aliases

-- Notification system: 'native', 'ox_lib', 'esx', 'qbcore'
Config.NotifySystem = 'native'

-- Tablet animation
Config.UseTablet = true
```

### Server Config (`server/config.lua`)

#### Single Discord Server

If you have one Discord server:

```lua
ServerConfig.APIKey = 'YOUR_API_KEY_HERE'
```

#### Multiple Discord Servers

If your FiveM server uses multiple Discord servers (e.g., separate servers for PD, EMS, Fire):

```lua
-- Primary API key
ServerConfig.APIKey = 'YOUR_PD_API_KEY_HERE'

-- Additional API keys for other Discord servers
ServerConfig.APIKeys = {
    'YOUR_EMS_API_KEY_HERE',
    'YOUR_FIRE_API_KEY_HERE',
}
```

Players will automatically see rosters from **all** Discord servers they are a member of, combined into a single view.

> **Warning**: Never commit your API keys to version control!

## Commands

| Command | Description |
|---------|-------------|
| `/rosters` | Opens the FiveRoster tablet |
| `/roster` | Alias for /rosters |
| `/fr` | Alias for /rosters |
| `/shiftpause` | Start a break on your active shift |
| `/shiftresume` | End your break and start the clock again |
| `/shiftbreak` | Toggle the break on/off |
| `/present` | Cast a training presentation onto the screen you are standing at |
| `/endpresentation` | Stop the presentation you are casting |
| `/screeninfo` | List the props around you and whether each can be cast to |
| `/castfit` | Reframe the screen you are casting to, while the cast is running |

Break command names are configurable under `Config.ShiftPause`, along with an
optional keybind for the toggle. They are hidden automatically when the
FiveRoster instance does not support breaks.

Presentation command names are configurable under `Config.Presentations`.

## Multi-Guild Setup

Many FiveM communities use separate Discord servers for different departments:
- Los Santos Police Department Discord
- Los Santos EMS Discord
- Los Santos Fire Department Discord

FiveRoster supports this setup natively:

1. Create an API key in each Discord server's FiveRoster dashboard
2. Add all API keys to your `server/config.lua`:

```lua
ServerConfig.APIKey = 'pd_discord_api_key'

ServerConfig.APIKeys = {
    'ems_discord_api_key',
    'fire_discord_api_key',
}
```

3. When a player opens FiveRoster:
   - The resource checks all configured Discord servers
   - Shows rosters from every server the player is a member of
   - Combines everything into one seamless interface

## Shift Management

### How Shifts Work

1. Player opens FiveRoster with `/rosters`
2. If they have an active shift, it shows in the UI with an "End Shift" button
3. Players can start shifts from within a roster view
4. Shifts are tracked in real-time with duration display
5. When a player disconnects, their shift is automatically ended, however they
   leave and even if the server never sees a clean disconnect

### Shift Prevention

- Players can only have **one active shift at a time** across all rosters
- Attempting to start a second shift will show an error with the current roster name

### Ending Shifts on Disconnect

A shift is ended however the player leaves: the in-game disconnect, closing the
game, an F8 console `quit` or `disconnect`, a timeout, or a kick.

`playerDropped` is the fast path, but it is not a guarantee, so it is not relied
on alone:

- The player's Discord ID is cached when they join. By the time `playerDropped`
  runs, the framework player object is gone and their identifiers can already be
  unreadable, which previously left the resource with no way to identify whose
  shift to end.
- The end request retries connection errors, timeouts, rate limits and 5xx. A
  retry is abandoned if the player reconnects first, so a fresh shift is never
  closed by the session that just left.
- Open shifts, and the ends still owed, are written to `shift_state.json` in
  this resource's folder. If the server crashes or is killed, the next start
  settles whatever was left open.
- A sweep every 60 seconds catches players who vanished without a
  `playerDropped` that was ever acted on, and retries anything the backend has
  not confirmed.

Restarting only this resource ends nothing: the players are still connected, so
their shifts are simply picked back up and re-read from FiveRoster.

Tune or disable this under `Config.ShiftRecovery`. Disable it if the resource
folder is read-only; the resource detects an unwritable folder on its own, warns
once, and keeps ending shifts on disconnect without the recovery net.

`shift_state.json` is runtime state, not configuration. It holds Discord IDs and
shift IDs, never the API key, and can be deleted while the server is stopped.

### Shift Breaks

A shift can be put on a break without ending it. The shift stays open and keeps
its ID, start time and division flag, but the clock stops. Break time is
deducted from the hours the shift finally records, so anything reading shift
hours needs no changes.

- **A paused shift is still an active shift.** `HasActiveShift` keeps returning
  `true`, and every duty check in this resource keeps saying yes.
- **The displayed duration is frozen while paused.** The server freezes
  `duration_seconds`, so nothing counts up locally and then jumps backwards.
- **Asking for a break you are already on is not an error.** The local state is
  synced from the response and an informational message is shown. The running
  break is never restarted, so banked break time is never lost.
- **Ending a paused shift needs no special handling.** The end endpoint closes
  the open break itself and records the worked time. Disconnecting while on a
  break still ends the shift.
- **Breaks are never auto-resumed.** On reconnect or a resource restart the
  state is re-read from FiveRoster and reflected as-is.

Breaks can be started from the tablet, from `/shiftpause` and `/shiftresume`,
from a keybind, or from another resource through the exports below. All of them
go through the same backend endpoints, so the tablet and the game stay in step.

Older FiveRoster instances without the break routes are detected on the first
attempt (they answer with an HTML 404 rather than JSON) and the pause control is
hidden from then on. Everything else keeps working.

#### Optional HUD

`Config.ShiftHUD.enabled` draws a small on-screen indicator with three distinct
states: hidden when off duty, green **ON DUTY** with a ticking duration, and
amber **ON BREAK** with the duration frozen. It is off by default so it does not
collide with an existing server HUD.

## Training Presentations on In-Game Screens

Run a briefing without anyone leaving the server. A presenter stands in front of
a screen, picks one of their roster's FiveRoster training presentations, and the
deck appears on that screen for everybody nearby. The presenter clicks through
it with the arrow keys.

### Running a briefing

1. Stand within `castDistance` (4m by default) of a configured screen.
2. Run `/present`. A picker lists the presentations you can cast.
3. Choose one. It goes up on the screen for everyone within `viewDistance`.
4. **Left / Right arrow** change slide. **Backspace** ends the cast.

The server owns the slide index, so everybody watching sees the same slide, and
a player who walks in halfway through joins on the slide that is showing. Only
the presenter can move the deck.

### Which decks appear in the picker

Presentations belonging to a roster the presenter is on, where that roster has
training enabled on FiveRoster, and where the deck has at least one slide. Every
check happens on the FiveRoster side against the presenter's Discord account, so
a modified client cannot cast a deck its owner is not entitled to.

### Configuring screens

Screens are ordinary GTA props that carry a **named render target**. Every
vanilla TV, monitor and projector screen is recognised out of the box, so
`Config.Presentations.screenModels` is empty by default and most servers never
need to touch it.

A prop only counts as a screen once a render target actually links to its model,
which the resource works out by itself. A model that cannot display anything is
never offered, so `/present` will not open a picker onto a screen that would then
fail to draw.

#### When `/present` says there is no screen

Stand where you were and run `/screeninfo`. It prints every prop around you to
the client console (F8) and says, one by one, why each is or is not castable:

```
  3.0m  prop_tv_flat_02    castable, render target "tvscreen"     <- looking at this
  1.0m  #-1651888964       NOT on the screen list, but render target "tvscreen"
                           links. Add { model = -1651888964 } to
                           Config.Presentations.screenModels
  0.5m  prop_bin_01a       not a screen
```

The game will not tell you a prop's model name, only its hash, so the hash is
printed in the form the config accepts. Filling in `screenModels` **replaces**
the built-in list rather than adding to it, so include the vanilla models you
still want:

```lua
screenModels = {
    { model = 'prop_tv_flat_01' },
    { model = -1651888964 },                                  -- from /screeninfo
    { model = 'my_streamed_tv', renderTarget = 'my_rt' },     -- name known
}
```

#### When the slide is cropped, stretched or off-centre

The shape of a render target is baked into the model and the game will not
report it, so a panel that is not the shape of the deck comes out wrong and
nothing in the resource can work out by how much. You can see it, so you fix it.

Start the cast, then run `/castfit`:

| Key | Effect |
|-----|--------|
| Arrow keys | Move the image |
| Shift + arrow keys | Stretch it |
| `Y` | Step through resolutions |
| `L` | Back to the configured values |
| `Backspace` | Finish, and print the settings |

The deck stops responding to the arrow keys while you are fitting, and goes back
to normal when you finish. What it prints goes into that model's entry:

```lua
screenModels = {
    { model = 'prop_monitor_01a',
      resolution = { width = 1024, height = 768 },
      display = { scaleX = 1.0, scaleY = 0.94, offsetX = 0.0, offsetY = 0.0 } },
}
```

Adjustments are per model and last only for your session, since a client cannot
write the server's config and a screen everybody watches should not be reshaped
by whoever presented at it last. `Config.Presentations.display` sets a default
for every screen at once.

#### When the picker opens but the cast will not start

`Could not start that presentation` means FiveRoster refused the request. The
reason is printed to the **server** console, naming the status code, the URL and
what the instance said:

```
[FiveRoster] Starting a cast failed: HTTP 401 from https://.../api/v1/fivem/cast: {"error":"invalid api key"}
[FiveRoster] That is an authentication failure. Check the API key in server/config.lua.
```

The three usual causes are an API key that is missing or wrong (401 or 403), a
`Config.FiveRosterURL` the server cannot reach (no status code at all), and a
FiveRoster older than in-game presentations (404).

A render target name is optional. Names are tried from
`Config.Presentations.renderTargetNames` until one links, which is `tvscreen`
by default. Add your prop's name there and it is found without being listed at
all.

For a briefing room with no TV in the map, have this resource place one:

```lua
fixedScreens = {
    { label = 'PD Briefing Room',
      model  = 'prop_tv_flat_01',
      renderTarget = 'tvscreen',
      coords = vector3(447.51, -974.14, 30.69),
      heading = 90.0 },
}
```

> **Important:** the game links a render target to a **model**, not to one prop.
> Every prop of that model on screen shows the cast. If your map has that TV
> everywhere, give your briefing screen its own model — a streamed prop, or one
> of the less common vanilla TV models — and list only that one.

`Config.Presentations.maxScreens` (2 by default) caps how many screens are drawn
at once. Each one is a browser surface, so raising it costs client performance.

### Attendance

While a cast runs, whoever is standing within `attendance.distance` of the
screen is reported back to FiveRoster. Those players get a view record against
the presentation, so an in-game briefing shows up in the presentation analytics
alongside portal views and counts towards the watcher's training record.

Only the presenter's client reports, and it sends server IDs — the game server
resolves those to Discord accounts itself, so nobody can be marked as having
attended a briefing they were not standing in.

Time is credited per slide when the deck moves, and only to watchers reported at
the screen in the last two minutes, so somebody who walks out after slide two is
not recorded as having sat through the rest. Each slide change credits at most
60 seconds, so a screen left running overnight books a minute a slide rather
than eight hours.

Set `Config.Presentations.attendance.enabled = false` to cast without recording
anyone.

### When casting stops

A cast ends when the presenter stops it, disconnects, or the resource restarts.
FiveRoster also closes any cast that goes idle for 30 minutes, so a briefing
nobody ended does not stay open.

### Requirements

Needs a FiveRoster instance that exposes the casting routes. An older instance
answers them with a 404, which is detected on the first attempt; the commands
then say so rather than failing silently.

## Rank-to-Job Synchronization

Automatically sync FiveRoster ranks to in-game jobs and grades. When a player's rank changes on FiveRoster or they join the server, their in-game job is updated to match.

### Supported Frameworks

- **ESX** (`es_extended`)
- **QBCore** (`qb-core`)
- **QBox** (`qbx_core`)

### Setup

1. Enable job sync in `config.lua`:

```lua
Config.JobSync = {
    enabled = true,
    framework = 'esx',  -- 'esx', 'qbcore', or 'qbox'
    syncOnJoin = true,
    syncOnRankChange = true,
}
```

2. Get your rank UUIDs from FiveRoster:
   - Go to your roster on fiveroster.com
   - Click **Edit** on a rank
   - Click the **Copy Rank ID** button

3. Add rank mappings:

```lua
Config.JobSync = {
    enabled = true,
    framework = 'esx',
    syncOnJoin = true,
    syncOnRankChange = true,

    rankMappings = {
        -- Police Department
        ['abc123-def456-...'] = { job = 'police', grade = 0 },   -- Cadet
        ['ghi789-jkl012-...'] = { job = 'police', grade = 1 },   -- Officer
        ['mno345-pqr678-...'] = { job = 'police', grade = 2 },   -- Sergeant
        ['stu901-vwx234-...'] = { job = 'police', grade = 3 },   -- Lieutenant

        -- EMS (from different roster)
        ['ems-rank-uuid-1'] = { job = 'ambulance', grade = 0 },  -- EMT
        ['ems-rank-uuid-2'] = { job = 'ambulance', grade = 1 },  -- Paramedic
    },

    -- Optional: Set job for players not in any mapped rank
    fallbackJob = { job = 'unemployed', grade = 0 },

    -- Optional: Priority when player has multiple ranks
    rosterPriority = {
        'police-roster-uuid',   -- Police takes priority
        'ems-roster-uuid',      -- Then EMS
    }
}
```

### How It Works

1. **On Player Join**: When a player loads in, FiveRoster checks their ranks and sets their job accordingly
2. **On Rank Change**: When a rank change is detected, the player's job is automatically updated
3. **Priority System**: If a player has multiple ranks across rosters, the priority order determines which job they get

### Manual Sync Command

Admins can manually sync a player's job:

```
/syncjob [player_id]  -- From console
/syncjob              -- For yourself (in-game)
```

### Job Sync Exports

```lua
-- Manually trigger job sync for a player
exports['fiveroster']:SyncPlayerJob(source)

-- Get job mapping for a specific rank UUID
local mapping = exports['fiveroster']:GetJobForRank('rank-uuid-here')
if mapping then
    print('Job:', mapping.job, 'Grade:', mapping.grade)
end
```

### Job Sync Events

```lua
-- Triggered when a player's job is synced
AddEventHandler('fiveroster:onJobSynced', function(source, data)
    print('Player job synced:', GetPlayerName(source))
    print('Job:', data.job, 'Grade:', data.grade)
    print('Rank:', data.rankName, 'Roster:', data.rosterName)
end)
```

## Developer API

FiveRoster provides exports for integration with MDTs, CAD systems, and other resources.

### Server-Side Exports

#### Check if Player Has Active Shift

```lua
-- Returns: boolean
local hasShift = exports['fiveroster']:HasActiveShift(source)

if hasShift then
    print('Player is on shift')
end
```

#### Get Active Shift Data

```lua
-- Returns: table or nil
local shift = exports['fiveroster']:GetActiveShift(source)

if shift then
    print('Shift ID:', shift.shiftId)
    print('Roster:', shift.rosterName)
    print('Roster UUID:', shift.rosterUuid)
    print('Started At:', shift.startedAt)
    print('Discord ID:', shift.discordId)

    -- Break state (added in 1.3.0)
    print('On a break:', shift.isPaused)
    print('Break started at:', shift.pausedAt)
    print('Total break seconds:', shift.pausedSeconds)
    print('Breaks taken:', shift.pauseCount)
    print('Worked seconds:', shift.durationSeconds)
end
```

The shift is returned while the player is on a break too. `isPaused` tells the
two apart; a `nil` return means off duty.

#### Pause, Resume and Toggle a Break

```lua
-- callback receives (success, info)
-- info.shift          - the returned shift object
-- info.alreadyInState - the shift was already paused/running (not an error)
-- info.noActiveShift  - the player has no open shift
-- info.unsupported    - this FiveRoster instance has no break routes
-- info.message        - human-readable message

exports['fiveroster']:PauseShift(source, function(success, info)
    if success and info.alreadyInState then
        print('Already on a break - nothing changed')
    elseif success then
        print('Break started')
    end
end)

exports['fiveroster']:ResumeShift(source, function(success, info) end)
exports['fiveroster']:ToggleShiftPause(source, function(success, info) end)
```

#### Check Break State

```lua
-- Returns: boolean. NOT the opposite of HasActiveShift - a paused player is
-- still on duty.
local onBreak = exports['fiveroster']:IsShiftPaused(source)

-- Worked seconds, frozen while on a break. Returns nil when off duty.
local worked = exports['fiveroster']:GetShiftDuration(source)

-- Whether breaks are usable on this server and FiveRoster instance
local canPause = exports['fiveroster']:IsShiftPauseSupported()
```

#### Start a Shift

```lua
-- Parameters: source, rosterUuid, flagId (optional), callback
-- The callback receives (success, data)

exports['fiveroster']:StartShift(source, 'roster-uuid-here', nil, function(success, data)
    if success then
        print('Shift started!')
        print('Roster:', data.roster_name)
        print('Shift ID:', data.id)
        print('Started At:', data.started_at)
    else
        print('Error:', data) -- Error message string
    end
end)

-- With a division/flag ID:
exports['fiveroster']:StartShift(source, 'roster-uuid-here', 123, function(success, data)
    -- ...
end)
```

#### End a Shift

```lua
-- Parameters: source, callback
-- The callback receives (success, data)

exports['fiveroster']:EndShift(source, function(success, data)
    if success then
        print('Shift ended!')
        print('Duration:', data.duration_formatted) -- e.g., "2h 30m"
        print('Duration (seconds):', data.duration_seconds)
        print('Roster:', data.roster_name)
    else
        print('Error:', data) -- Error message string
    end
end)
```

#### Get Player's Available Rosters

```lua
-- Parameters: source, callback
-- The callback receives (success, rosters)

exports['fiveroster']:GetPlayerRosters(source, function(success, rosters)
    if success then
        for _, roster in ipairs(rosters) do
            print('Roster:', roster.name)
            print('UUID:', roster.roster_uuid)
            print('Shifts Enabled:', roster.shift_tracking_enabled)
        end
    else
        print('Error:', rosters)
    end
end)
```

### Client-Side Exports

#### Check if Player Has Active Shift

```lua
-- Returns: boolean
local hasShift = exports['fiveroster']:HasActiveShift()
```

#### Get Active Shift Data

```lua
-- Returns: table or nil
local shift = exports['fiveroster']:GetActiveShift()

if shift then
    print('Roster:', shift.roster_name)
    print('Started:', shift.started_at)

    -- Break state (added in 1.3.0)
    print('On a break:', shift.is_paused)
    print('Total break seconds:', shift.paused_seconds)
    print('Worked seconds:', shift.duration_seconds)
end
```

Both `snake_case` and `camelCase` keys are present on the returned table, so
code written against either spelling keeps working.

#### Start a Shift (Client)

```lua
-- Parameters: rosterUuid, flagId (optional)
-- Triggers server-side API call, result comes via events

exports['fiveroster']:StartShift('roster-uuid-here', nil)
```

#### End Current Shift (Client)

```lua
-- Triggers server-side API call, result comes via events
-- Works the same on a paused shift: the backend closes the open break itself.

exports['fiveroster']:EndShift()
```

#### Pause, Resume and Toggle a Break (Client)

```lua
-- Trigger server-side API calls, result comes via events
exports['fiveroster']:PauseShift()
exports['fiveroster']:ResumeShift()
exports['fiveroster']:ToggleShiftPause()

-- Returns: boolean. A paused player is still on duty.
local onBreak = exports['fiveroster']:IsShiftPaused()

-- Worked seconds, frozen while on a break. Returns nil when off duty.
local worked = exports['fiveroster']:GetShiftDuration()

-- Hide your own pause control when this returns false
local canPause = exports['fiveroster']:IsShiftPauseSupported()
```

#### Presentation Casting (Client)

```lua
-- Is this player currently casting a presentation?
local presenting = exports['fiveroster']:IsPresenting()

-- The cast this player is driving, or nil.
-- { castUuid, screenKey, name, castUrl, currentSlide, slideCount, presenter }
local cast = exports['fiveroster']:GetActiveCast()

-- Stop casting. Returns false when the player was not presenting.
exports['fiveroster']:StopPresenting()

-- Open the picker at the nearest screen, e.g. from your own interaction menu.
exports['fiveroster']:OpenPresentationPicker()
```

#### Presentation Casting (Server)

```lua
-- Every cast running right now, keyed by screen key.
local casts = exports['fiveroster']:GetActiveCasts()

for screenKey, cast in pairs(casts) do
    print(cast.name, cast.currentSlide + 1, 'of', cast.slideCount)
end

-- Is a given player presenting, and stop them if so.
local presenting = exports['fiveroster']:IsPresenting(source)
exports['fiveroster']:StopPresenting(source)
```

## Events

FiveRoster triggers events that other resources can listen to.

### Server-Side Events

```lua
-- Triggered when a player starts a shift
AddEventHandler('fiveroster:onShiftStarted', function(source, shiftData)
    print('Player started shift:', GetPlayerName(source))
    print('Roster:', shiftData.rosterName)
    print('Shift ID:', shiftData.shiftId)
end)

-- Triggered when a player ends a shift
AddEventHandler('fiveroster:onShiftEnded', function(source, shiftData)
    print('Player ended shift:', GetPlayerName(source))
    print('Duration:', shiftData.durationSeconds, 'seconds')
    -- shiftData.reason may be: 'manual', 'player_disconnect', 'external_resource'
end)

-- Triggered when a player starts a break. The shift is still active.
AddEventHandler('fiveroster:onShiftPaused', function(source, shiftData)
    print('Player went on a break:', GetPlayerName(source))
    print('Breaks taken:', shiftData.pauseCount)
end)

-- Triggered when a player ends a break
AddEventHandler('fiveroster:onShiftResumed', function(source, shiftData)
    print('Player is working again:', GetPlayerName(source))
    print('Total break seconds:', shiftData.pausedSeconds)
end)
```

### Client-Side Events

```lua
-- Triggered when the local player starts a shift
AddEventHandler('fiveroster:onShiftStarted', function(shiftData)
    print('You started a shift on', shiftData.roster_name)
end)

-- Triggered when the local player ends a shift
AddEventHandler('fiveroster:onShiftEnded', function(shiftData)
    print('Shift ended. Duration:', shiftData.duration_formatted)
end)

-- Triggered when the local player starts a break. Still on duty.
AddEventHandler('fiveroster:onShiftPaused', function(shiftData)
    print('On a break since', shiftData.paused_at)
end)

-- Triggered when the local player ends a break
AddEventHandler('fiveroster:onShiftResumed', function(shiftData)
    print('Working again on', shiftData.roster_name)
end)
```

## Example: MDT Integration

Here's an example of integrating FiveRoster shifts with a police MDT:

```lua
-- server/main.lua

-- Clock in command
RegisterCommand('clockin', function(source, args)
    local rosterUuid = 'your-police-roster-uuid'

    -- Check if already on shift
    if exports['fiveroster']:HasActiveShift(source) then
        TriggerClientEvent('mdt:notify', source, 'You are already on duty!')
        return
    end

    -- Start the shift
    exports['fiveroster']:StartShift(source, rosterUuid, nil, function(success, data)
        if success then
            TriggerClientEvent('mdt:notify', source, 'You are now 10-41 (On Duty)')
            -- Update your MDT status, spawn police vehicle, etc.
            TriggerClientEvent('mdt:setDutyStatus', source, true)
        else
            TriggerClientEvent('mdt:notify', source, 'Error: ' .. data)
        end
    end)
end, false)

-- Clock out command
RegisterCommand('clockout', function(source)
    if not exports['fiveroster']:HasActiveShift(source) then
        TriggerClientEvent('mdt:notify', source, 'You are not on duty!')
        return
    end

    exports['fiveroster']:EndShift(source, function(success, data)
        if success then
            TriggerClientEvent('mdt:notify', source,
                'You are now 10-42 (Off Duty). Shift duration: ' .. data.duration_formatted)
            TriggerClientEvent('mdt:setDutyStatus', source, false)
        else
            TriggerClientEvent('mdt:notify', source, 'Error: ' .. data)
        end
    end)
end, false)

-- Listen for shifts started/ended via the FiveRoster tablet
AddEventHandler('fiveroster:onShiftStarted', function(source, shiftData)
    -- Sync with your MDT
    TriggerClientEvent('mdt:setDutyStatus', source, true)
end)

AddEventHandler('fiveroster:onShiftEnded', function(source, shiftData)
    -- Sync with your MDT
    TriggerClientEvent('mdt:setDutyStatus', source, false)
end)
```

## Framework Support

### FiveM Native (Default)

Uses FiveM's built-in Discord identifier. Players must have Discord linked to their FiveM account at [cfx.re](https://cfx.re).

```lua
Config.DiscordSource = 'fivem'
```

### ESX

Uses ESX's identity system with automatic fallback to FiveM identifiers.

```lua
Config.DiscordSource = 'esx'
```

### QBCore

Uses QBCore's player metadata with automatic fallback to FiveM identifiers.

```lua
Config.DiscordSource = 'qbcore'
```

### Custom Export

Use a custom export from another resource:

```lua
Config.DiscordSource = 'custom'
Config.CustomDiscordExport = {
    resource = 'my_identity_resource',
    export = 'GetPlayerDiscordId'
}
```

Your export should accept `source` and return the Discord ID as a string:

```lua
-- In my_identity_resource/server.lua
exports('GetPlayerDiscordId', function(source)
    -- Your logic here
    return '123456789012345678'
end)
```

## Troubleshooting

### "No API keys configured"

Edit `server/config.lua` and add your FiveRoster API key(s).

### "Discord not linked"

Players need to link their Discord to their FiveM account:
1. Go to [cfx.re](https://cfx.re)
2. Log in with FiveM account
3. Link Discord account in settings

### "Not in guild"

Players must be members of at least one of your configured Discord servers.

### "No rosters found"

Players must be enrolled in at least one roster:
1. Go to your FiveRoster dashboard
2. Open a roster
3. Add the player to a rank

### Tablet not showing

1. Check that the resource started without errors
2. Verify `Config.UseTablet = true` in config.lua
3. Check the F8 console for errors

### Presentation does not appear on the screen

- Is the prop's model listed in `Config.Presentations.screenModels`, with the
  right `renderTarget` name? `tvscreen` is correct for vanilla TVs.
- Are you within `viewDistance` of it? Nothing is drawn beyond that range.
- Turn on `Config.Debug.enabled` and look for `[FiveRoster:Cast]` lines. "Render
  target did not resolve" means the model has no render target by that name.

### The presentation shows on every TV in the building

Expected: the game links a render target to a **model**, not to one prop. Give
your briefing screen its own model and list only that one in `screenModels`.

### `/present` says there is no screen nearby

You must be within `castDistance` (4m by default) of a prop whose model is in
`screenModels`, or of one of your `fixedScreens`.

### The picker is empty

The presenter must be on a roster that has training enabled on FiveRoster, and
that roster must have at least one presentation with at least one slide.

### Debug Mode

Enable debug logging to troubleshoot issues:

```lua
Config.Debug = {
    enabled = true,
    logAPIRequests = true,
    logAPIResponses = true,
    logSessionCreation = true
}
```

## Support

- **Documentation**: [docs.fiveroster.com](https://docs.fiveroster.com)
- **Discord**: [discord.gg/FtZ57TGE64](https://discord.gg/FtZ57TGE64)
- **Website**: [fiveroster.com](https://fiveroster.com)

## License

Copyright (c) FiveRoster. All rights reserved.

This software is provided for use with FiveRoster services only. Redistribution or modification without permission is prohibited.

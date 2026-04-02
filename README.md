# FiveRoster for FiveM

Official FiveRoster integration for FiveM servers. Allows players to access rosters, track shifts, and view documents directly in-game through a beautiful tablet interface.

![FiveRoster](https://fiveroster.com/assets/img/fiveroster_text_logo_yw.png)

## Features

- **In-Game Tablet UI** - Beautiful, immersive tablet interface with animations
- **Shift Tracking** - Players can start and end shifts directly in-game
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
5. When a player disconnects, their shift is automatically ended

### Shift Prevention

- Players can only have **one active shift at a time** across all rosters
- Attempting to start a second shift will show an error with the current roster name

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
end
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
end
```

#### Start a Shift (Client)

```lua
-- Parameters: rosterUuid, flagId (optional)
-- Triggers server-side API call, result comes via events

exports['fiveroster']:StartShift('roster-uuid-here', nil)
```

#### End Current Shift (Client)

```lua
-- Triggers server-side API call, result comes via events

exports['fiveroster']:EndShift()
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

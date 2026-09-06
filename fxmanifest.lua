fx_version 'cerulean'
game 'gta5'

name 'fiveroster'
author 'FiveRoster'
description 'Official FiveRoster integration for FiveM - In-game roster management and shift tracking'
version '1.4.0'
repository 'https://github.com/FiveRoster/fiveroster-fivem'

lua54 'yes'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua',
    'client/cast.lua'
}

-- server/cast.lua reads a handful of helpers main.lua hands it, so it must
-- load after main.lua.
server_scripts {
    'server/config.lua',
    'server/main.lua',
    'server/cast.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

-- Requires FiveM server build 5181 or higher
dependencies {
    '/server:5181'
}

-- Exports for other resources
exports {
    -- Client exports
    'HasActiveShift',
    'GetActiveShift',
    'StartShift',
    'EndShift',
    'PauseShift',
    'ResumeShift',
    'ToggleShiftPause',
    'IsShiftPaused',
    'GetShiftDuration',
    'IsShiftPauseSupported',

    -- In-game presentation casting
    'IsPresenting',
    'GetActiveCast',
    'StopPresenting',
    'OpenPresentationPicker'
}

server_exports {
    -- Server exports
    'HasActiveShift',
    'GetActiveShift',
    'StartShift',
    'EndShift',
    'PauseShift',
    'ResumeShift',
    'ToggleShiftPause',
    'IsShiftPaused',
    'GetShiftDuration',
    'IsShiftPauseSupported',
    'GetPlayerRosters',
    'SyncPlayerJob',
    'GetJobForRank',

    -- In-game presentation casting
    'GetActiveCasts',
    'IsPresenting',
    'StopPresenting'
}

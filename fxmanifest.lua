fx_version 'cerulean'
game 'gta5'

name 'fiveroster'
author 'FiveRoster'
description 'Official FiveRoster integration for FiveM - In-game roster management and shift tracking'
version '1.1.0'
repository 'https://github.com/FiveRoster/fiveroster-fivem'

lua54 'yes'

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/config.lua',
    'server/main.lua'
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
    'EndShift'
}

server_exports {
    -- Server exports
    'HasActiveShift',
    'GetActiveShift',
    'StartShift',
    'EndShift',
    'GetPlayerRosters'
}

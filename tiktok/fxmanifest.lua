fx_version 'cerulean'
description 'TikTok Arena – Attack & Defend'
author 'NotedDevelopment'
version '1.0.0'

lua54 'yes'
games { 'gta5' }

ui_page 'web/build/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/utils.lua',
    'client/labels.lua',
    'client/peds.lua',
    'client/convoy.lua',
    'client/menu.lua',
    'client/client.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/waves.lua',
    'server/server.lua',
    'server/convoy.lua',
}

files {
    'web/build/index.html',
    'web/build/**/*',
}

dependencies {
    'ox_lib',
    'oxmysql',
}

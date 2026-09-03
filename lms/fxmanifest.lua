fx_version 'cerulean'
description 'Last Man Standing – Bolingbroke Prison Brawl'
author 'NotedDevelopment'
version '1.0.0'

lua54 'yes'
games { 'gta5' }

ui_page 'web/build/index.html'

shared_scripts {
    'config.lua',
}

client_scripts {
    'client/utils.lua',
    'client/labels.lua',
    'client/peds.lua',
    'client/client.lua',
}

server_scripts {
    'server/server.lua',
}

files {
    'web/build/index.html',
    'web/build/**/*',
}

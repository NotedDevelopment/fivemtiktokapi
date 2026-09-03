fx_version 'cerulean'
game 'gta5'
node_version '22'

author 'tiktokapi'
description 'TikTok LIVE integration API for FiveM'
version '1.0.0'

server_scripts {
    'server/dist/tiktok.js',
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

lua54 'yes'

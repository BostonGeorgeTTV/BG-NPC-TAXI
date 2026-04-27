fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'BostonGeorgeTTV'
description 'NPC Taxi for ESX + ox_lib'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

ui_page 'html/index.html'

client_scripts {
    'client.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/tassometro.png'
}

server_scripts {
    '@es_extended/imports.lua',
    'server.lua'
}

dependencies {
    'es_extended',
    'ox_lib'
}

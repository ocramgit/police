fx_version 'cerulean'
game 'gta5'

author 'QBCore Custom'
description 'Cops vs Robbers Minigame'
version '2.0.0'

shared_scripts {
    'config.lua',
}

server_scripts {
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

dependencies {
    'qb-core',
}

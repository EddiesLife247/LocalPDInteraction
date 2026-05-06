fx_version 'cerulean'
game 'gta5'

author 'YourName'
description 'Advanced Police Interaction Script'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}


client_scripts {
    'config.lua',
    'client/main.lua',
    'client/functions/core_utils.lua',
    'client/functions/dispatch.lua',
    'client/functions/data_generation.lua',
    'client/functions/traffic_stop.lua',
    'client/functions/scenarios.lua',
    'client/functions/interactions.lua',
    'client/functions/menus.lua',
    'client/threads.lua',
    'client/network.lua',
    'client/commands.lua'
}

server_scripts {
    'server/main.lua'
}


dependencies {
    'ox_lib',
    'ox_target'
}

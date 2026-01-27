local skynet = require "skynet"

skynet.start(function()
    skynet.dispatch("lua", function(_,_, command, ...)
        local f = CMD[command]
        if f then
            skynet.ret(skynet.pack(f(...)))
        else
            skynet.error("invalid cmd. cmd:%s", command)
        end
    end)
end)

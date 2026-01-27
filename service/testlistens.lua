local skynet = require "skynet"
local socket = require "skynet.socket"

skynet.start(function()
    local listenfd = socket.listen("0.0.0.0", 9999)
    socket.start(listenfd , function(id, addr)
        skynet.fork(function()
            socket.start(id)
            while true do
                local response = socket.readline(id)
                if response then
                    skynet.error("msg: %s", response)
                else
                    socket.close(id)
                    return
                end
            end
        end)
    end)
end)

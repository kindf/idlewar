local skynet = require "skynet"
require "skynet.manager"
local CMD = require "gate.gate_msg"
local SOCKET = require "gate.gate_socket"

skynet.start(function()
    skynet.dispatch("lua", function(_, _, cmd, subcmd, ...)
        if cmd == "socket" then
            local f = SOCKET[subcmd]
            f(...)
        else
            local f = assert(CMD[cmd])
            skynet.ret(skynet.pack(f(subcmd, ...)))
        end
    end)
    skynet.register(".gatewatchdog")
end)

local skynet = require "skynet"
local ServiceHelper = require "public.service_helper"
local CMD = ServiceHelper.CMD
CMD.DispatchClientMessage = ServiceHelper.DispatchClientMessage

function CMD.start(account, fd)
    math.randomseed(os.time())
end

function CMD.restart()
end

skynet.start(function()
    ServiceHelper.RegisterClientMessageHandler()
    skynet.dispatch("lua", function(_,_, command, ...)
        ServiceHelper.DispatchCmd(command, ...)
    end)
end)

local skynet = require "skynet"
local GateMgr = require "gate.gate_mgr"
local CMD = {}

function CMD.start()
    GateMgr:Init("0.0.0.0", skynet.getenv("gate_port"))
end

CMD.VerifyToken = function(...) GateMgr:VerifyToken(...) end
CMD.SetConnectionGaming = function(...) GateMgr:SetConnectionGaming(...) end
CMD.SendClientMessage = function(...) GateMgr:SendMessage(...) end
CMD.KickPlayer = function(...) GateMgr:CloseFd(...) end
CMD.EnterGame = GateMgr.EnterGame

return CMD

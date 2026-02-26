local skynet = require "skynet"
local GateMgr = require "gate.gate_mgr"
local CMD = {}

function CMD.start()
    GateMgr.Init("0.0.0.0", skynet.getenv("gate_port"))
end

CMD.VerifyToken = GateMgr.VerifyToken
CMD.SetConnectionGaming = GateMgr.SetConnectionGaming
CMD.SendClientMessage = GateMgr.SendClientMessage

return CMD

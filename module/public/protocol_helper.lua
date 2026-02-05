local lfs = require "lfs"
local pb = require "pb"
local Logger = require "public.logger"
local ProtocolHelper = {}

local protocolHandler = {}
function ProtocolHelper.RegisterProtocolHandler(protoId, handler)
    assert(not protocolHandler[protoId], "协议处理函数重复注册 pid:"..protoId)
    protocolHandler[protoId] = {
        handler = handler,
        type = "protocol",
    }
end

function ProtocolHelper.RegisterRpcHandler(protoId, respProtoId, handler)
    assert(not protocolHandler[protoId], "协议处理函数重复注册 pid:"..protoId)
    protocolHandler[protoId] = {
        handler = handler,
        type = "rpc",
        respProtoId = respProtoId,
    }
end

function ProtocolHelper.GetProtocolHandler(protoId)
    return protocolHandler[protoId]
end

function ProtocolHelper.RegisterProtocol()
    local root_path = lfs.currentdir()
    local pb_path = root_path.."/proto/pb/"
    for file in lfs.dir(pb_path) do
        local attr = lfs.attributes(pb_path..file)
        if attr.mode == "file" and string.match(file, ".pb") then
            pb.loadfile(pb_path..file)
        end
    end
end

function ProtocolHelper.UnpackHeader(msg)
    local msgId = string.unpack(">h", msg, 1)
    local buffMsg = msg:sub(3)
    return msgId, buffMsg
end

return ProtocolHelper

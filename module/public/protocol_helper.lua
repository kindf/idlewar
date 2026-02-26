local lfs = require "lfs"
local Pb = require "pb"
local Pids = require "proto.pids"
local Logger = require "public.logger"
local ProtocolHelper = {}
local sformat = string.format

local protocolHandler = {}
function ProtocolHelper.RegisterProtocolHandler(protoId, handler)
    assert(not protocolHandler[protoId], "协议处理函数重复注册 pid:"..protoId)
    protocolHandler[protoId] = {
        handler = handler,
        type = "protocol",
    }
end

function ProtocolHelper.RegisterRpcHandler(protoName, respProtoName, handler)
    local protoId = assert(Pids[protoName], sformat("不存在的协议 protoName:%s", protoName))
    local respProtoId = assert(Pids[respProtoName], sformat("不存在的协议 respProtoName:%s", respProtoName))
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
            Pb.loadfile(pb_path..file)
        end
    end
end

function ProtocolHelper.UnpackHeader(msg)
    local msgId = string.unpack(">H", msg, 1)
    local buffMsg = msg:sub(3)
    return msgId, buffMsg
end

local lenLimit = 65535 - 4
local spack = string.pack
function ProtocolHelper.Encode(respName, resp)
    local ret, msg = pcall(Pb.encode, respName, resp)
    assert(ret, sformat("消息编码失败 err:", msg))
    local bodyLen = #msg
    assert(bodyLen <= lenLimit, "消息长度超出限制")
    local pack = spack(">H c"..bodyLen, Pids[respName], msg)
    return pack
end

return ProtocolHelper

local skynet = require "skynet"
require "skynet.manager"
local ClusterHelper = require "public.cluster_helper"
local Pids = require "proto.pids"
local ProtocolHelper = require "public.protocol_helper"
local Logger = require "public.logger"
local pb = require "pb"

local ServiceHelper = {}

ServiceHelper.CMD = {}

-- 分发 Gate 转发过来的消息
function ServiceHelper.DispatchClientMessage(fd, protoId, protoBody)
    local protoName = Pids[protoId]
    assert(protoName, "不存在的协议 protoId:" .. protoId)
    local msg = pb.decode(protoName, protoBody)
    local handler = ProtocolHelper.GetProtocolHandler(protoId)
    if not handler then
        return Logger.Error("协议处理函数不存在 protoId:" .. protoId)
    end
    if handler.type == "protocol" then
        local ret, err = pcall(handler.handler, msg)
        if not ret then
            Logger.Error(err)
        end
    else
        local resp = {}
        local ret, err = pcall(handler.handler, msg, resp)
        if not ret then
            Logger.Error(err)
        end
        ClusterHelper.SendClientMessage(fd, handler.respProtoId, resp)
    end
    Logger.Debug("协议转发成功 protoId:%s", protoId)
end

function ServiceHelper.DispatchCmd(cmd, ...)
    local f = ServiceHelper.CMD[cmd]
    if f then
        skynet.ret(skynet.pack(f(...)))
    else
        skynet.error("invalid cmd. cmd:%s", cmd)
    end
end

return ServiceHelper

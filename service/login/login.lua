local skynet = require "skynet.manager"
local ProtocolHelper = require "public.protocol_helper"
local Logger = require "public.logger"
local RetCode = require "proto.retcode"
local Pb = require "pb"

local CMD = {}

function CMD.CheckVersion()
    return true
end

function CMD.CheckAuth(msg)
    local ret, req = pcall(Pb.decode, "login.c2s_login_auth", msg)
    local resp = {
        retCode = RetCode.SUCCESS,
        loginToken = nil,
        account = nil,
    }
    repeat
        if not ret then
            resp.retCode = RetCode.PROTO_DECODE_ERROR
            Logger.Error("[CMD.CheckAuth] 协议解析失败 err:%s", req)
            break
        end
        -- TODO: sdk token认证
        local token = req.token
        local account = req.account

        local loginToken = string.format("loginToken:%s:%s:%s", account, os.time(), math.random(10000, 99999))
        resp.loginToken = loginToken
        resp.account = account
    until true
    return resp
end

function CMD.start()
    ProtocolHelper.RegisterProtocol()
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
        Logger.Debug("cmd:%s subcmd:%s", cmd, subcmd)
        local f = assert(CMD[cmd])
        skynet.ret(skynet.pack(f(subcmd, ...)))
    end)
    skynet.register(".login")
end)

--[[
--  1、验证账号密码
--]]
local skynet = require "skynet"
local ls = require "snax.loginserver"
local crypt = require "skynet.crypt"
local md5 = require "md5"
local watchdog = ...
-- 登录用户
local acc_list = {}


local stoping = false

local server = {
    host = "127.0.0.1",
    port = 9999,
    multilogin = false,
    name = "login_master",
}

local function parse_client_token(token)
    -- xxx@xxx:xxx
    return token:match("([^@]+)@([^:]+):(.+)")
end

-- if error, send client '401 Unauthorized'
function server.auth_handler(token)
    skynet.error("ljldebug auth_handler!!!!!!!!!!!!")
    local acc, hostid, old = parse_client_token(token)
    hostid = tonumber(hostid)
    old = tonumber(old)
    skynet.error("try acc auth. acc:", acc, "hostid:", hostid)

    if not hostid then
        error("invalid hostid in token:", token)
    end

    --  账号验证
    --assert(pwd == "password")
    --skynet.error(string.format("auth_handler: %s@%s:%s", acc, time, sign))
    return hostid, acc, old
end

-- if error, send client '403 Forbidden'
function server.login_handler(hostid, acc, secret, old)
    if stoping then
        error("login failed because server is stoping. acc:"..acc)
    end
    -- 传递给server acc以及secret
    local user = acc_list[acc]
    if user then
        skynet.error("account relogin. acc:", acc, "hostid:", hostid)
        skynet.call(watchdog, "lua", "acc_logout", user.hostid, acc, user.subid, 1)
        acc_list[acc] = nil
    else
        skynet.error("account login. acc:", acc, "hostid:", hostid, "old:", old)
    end

    local subid, redirect = skynet.call(watchdog, "lua", "acc_login", hostid, acc, secret, old, skynet.time())
    assert(subid)
    if redirect then
        return redirect, "redirect"
    end

    acc_list[acc] = {subid = subid, hostid = hostid}
    return subid
end

local CMD = {}
function server.command_handler(command, ...)
    local f = CMD[command]
    return f(...)
end

ls(server) --服务启动


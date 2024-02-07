local skynet = require "skynet"
local ls = require "snax.loginserver"
local watchdog = ...

-- 登录用户
local online_user = {}


local stoping = false

local server = {
    host = "127.0.0.1",
    port = skynet.getenv("login_port"),
    multilogin = false,
    name = "login_master",
}

function server.auth_handler(token)
    local s, acc, pwd = string.match(token, "([^@]+)@(.+):(.+)")
    skynet.error(string.format("try acc auth. server:%s, acc:%s, pwd:%s", s, acc, pwd))
    assert(pwd == "password", "Invalid password")
    return nil, acc
end

function server.login_handler(_, acc, _)
    if stoping then
        error("login failed because server is stoping. acc:"..acc)
    end
    local user = online_user[acc]
    if user then
        skynet.call(watchdog, "lua", "watchdog_logout", acc)
        online_user[acc] = nil
    else
        skynet.error("account login. acc:", acc)
    end

    local subid = skynet.call(watchdog, "lua", "watchdog_login", acc, skynet.time())
    assert(subid)

    online_user[acc] = {subid = subid}
    return subid
end

local CMD = {}

function CMD.logout(acc, subid)
    local u = online_user[acc]
    if u then
        online_user[acc] = nil
        skynet.error(string.format("%s@%s is logout", acc, subid))
    end
end

function server.command_handler(command, ...)
    local f = CMD[command]
    return f(...)
end

ls(server) --服务启动

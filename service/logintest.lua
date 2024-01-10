local skynet = require "skynet"
local socket = require "skynet.socket"
local crypt = require "skynet.crypt"

skynet.start(function()
    local sock = socket.open("127.0.0.1", 9999)
    -- token
    local token = "kindf:1:2"
    socket.write(sock, token)
end)

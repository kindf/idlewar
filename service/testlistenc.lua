local skynet = require "skynet"
local socket = require "skynet.socket"

local fd
local count = 1
local smap = { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"}
local function sendmsg()
    local msg = ""
    for _ = 1, 100 do
        msg = msg ..smap[math.random(1, 26)]
    end
    socket.write(fd, msg .. "count : " .. count.."\n")
    count = count + 1
end

local function connnecttest()
    sendmsg()
    skynet.timeout(100, function()
        skynet.error("hellllll\n")
        connnecttest()
    end)
end

skynet.start(function()
	skynet.fork(function()
        fd = socket.open("127.0.0.1", 9999)
        connnecttest()
	end)
end)

local lfs = require "lfs"
local pb = require "pb"
local user_namager = require "user.user.user_manager"
local netpack = require "skynet.netpack"
local skynet = require "skynet.manager"
local pname2pid = require "proto.pids"

local M = {}

--注册pb文件
local function register_pb()
    local root_path = lfs.currentdir()
    local pb_path = root_path.."/proto/pb/"
    for file in lfs.dir(pb_path) do
        local attr = lfs.attributes(pb_path..file)
        if attr.mode == "file" and string.match(file, ".pb") then
            pb.loadfile(pb_path..file)
        end
    end
end

function M.pack_rpc(pid, msg)
    return string.format("%s%s%s", string.char(pid >> 8), string.char(pid & 0xFF), msg)
end

function M.send_s2c_message(user, pname, t)
    local socket = require "skynet.socket"
    local fd = user_namager.get_fd(user)
    if not fd then
        skynet.error("send_msg error. not fd. uid:", user.uid)
    end
    local msg = pb.encode(pname, t)
    local pid = pname2pid[pname]
    local m = M.pack_rpc(pid, msg)
    socket.write(fd, netpack.pack(m))
end

function M.init_pb()
    register_pb()
end

return M

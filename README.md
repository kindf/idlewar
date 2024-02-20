#### idlewar
- 使用shkynet搭建的游戏服务器demo
- 暂时只有一个 skynet 进程 gameworld

#### 快速启动
- 配置好文件 etc/config.cfg
- sh start.sh gameworld

#### skynet 主要服务及作用
- login 服务：登录认证
- gate 服务：分发用户信息
- watchdog 服务：管理所有 gent 服务
- agent 服务：运行游戏主要逻辑，暂时只有两个
- mongodb 服务：连接 mongodb ，增删查改

#### 登录逻辑
- 客户端先连接上 login 服务，通过认证后，再连接上 gate 服务
- 客户端连接上 gate 服务后，发送第一个包会被转发到 watchdog 服务用于验证合法性
- 校验完成后，watchdog 服务将客户端分配到合适的 agent 服务
- 完成上述操作的客户端所发送的消息，会被 gate 服务转发到对应的 agent 服务

#### c库编译
- lua-protobuf库：
``` shell
cd lualib/lua-protobuf && gcc -O2 -shared -fPIC -I ../../skynet/3rd/lua pb.c -o pb.so && mv pb.so ../lib/ && cd ../../
```
- luafilesystem库：
``` shell
cd lualib/luafilesystem && gcc -shared -O2 -Wall -fPIC -I ../../skynet/3rd/lua src/lfs.c -o lfs.so && mv lfs.so ../lib/ && cd ../../
```

#### TODO
- ~~协议暂时只是简单的将 table 序列化，改用 protobuff~~
- 断线重连机制

.PHONY: all help allstart gamestart battlestart clientstart proto
all : help

help:
	@echo "make allstart: 启动所有节点"
	@echo "make gamestart: 启动game节点"
	@echo "make batlestart: 启动战斗节点"
	@echo "make clientstart: 启动测试节点"
	@echo "make proto: 编译pb文件"

gamestart:
	./skynet/skynet etc/config.gamenode

battlestart:
	./skynet/skynet etc/config.battlenode

allstart:
	./skynet/skynet etc/gamenode.cfg
	./skynet/skynet etc/battlenode.cfg

clientstart:
	./skynet/skynet etc/config.clientnode

proto:
	sh tool/proto.sh
	sh tool/gen_pids.sh

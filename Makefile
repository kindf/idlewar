.PHONY: all help start test proto
all : help

help:
	@echo "make start: 启动服务器"
	@echo "make test: 启动测试进程"
	@echo "make proto: 编译pb文件"

start:
	sh tool/start.sh gameworld

test:
	sh tool/start.sh test

proto:
	sh tool/proto.sh
	sh tool/gen_pids.sh

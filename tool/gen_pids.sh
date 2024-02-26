#!/bin/bash

# 配置你的protobuf文件的目录
PROTO_DIR="proto/proto"

# 输出的Lua文件
LUA_OUTPUT_FILE="proto/pids.lua"

# 临时文件存储之前生成的ID和哈希
TEMP_ID_FILE="proto/temp_ids.txt"

# 客户端和服务器的消息匹配关键字
CLIENT_PROTO_MATCH_KEY=c2s_
SERVER_PROTO_MATCH_KEY=s2c_

# 如果之前的临时ID文件存在，则读取它以保持ID的一致性
if [ -f "$TEMP_ID_FILE" ]; then
    source "$TEMP_ID_FILE"
else
    declare -A MESSAGE_IDS
    declare -A MESSAGE_HASHES
fi

# 更新或生成消息ID
update_or_generate_id() {
    local message_name=$1
    local message_id
    local message_hash

    # 如果已有ID，则使用旧ID；否则，生成新ID
    if [ -n "${MESSAGE_IDS[$message_name]}" ]; then
        message_id=${MESSAGE_IDS[$message_name]}
    else
        # 生成哈希值并尝试将其转换为16位ID
        message_hash=$(echo -n "$message_name" | cksum | cut -d ' ' -f1)
        message_id=$((message_hash & 0xFFFF))

        # 检查是否存在ID冲突
        while [[ -n "${MESSAGE_HASHES[$message_id]}" ]]; do
            # 如果发生冲突，尝试添加随机数来解决
            message_hash=$((message_hash + RANDOM))
            message_id=$((message_hash & 0xFFFF))
        done

        # 保存新的ID和哈希值
        MESSAGE_IDS[$message_name]=$message_id
        MESSAGE_HASHES[$message_id]=$message_name
    fi
}

for proto_file in $(find $PROTO_DIR -name '*.proto'); do
    echo "Processing $proto_file"
    # 提取每个文件中定义的消息名称
    package=`grep '^package[[:blank:]]' $proto_file | awk -F'[ ;]' '{print $2}'`
    for message_name in $(grep -oP 'message \K(\w+)' $proto_file); do
        # 为每个消息调用update_or_generate_id函数来分配或更新ID
        if [[ $message_name == $CLIENT_PROTO_MATCH_KEY* || $message_name == $SERVER_PROTO_MATCH_KEY* ]]; then
            update_or_generate_id "$package.$message_name"
        fi
    done
done

# 将MESSAGE_IDS数组中的内容输出到LUA_OUTPUT_FILE
echo "-- 本文件由脚本gen_pids.sh自动生成，禁止手动修改." > $LUA_OUTPUT_FILE
echo "return {" >> $LUA_OUTPUT_FILE
for key in "${!MESSAGE_IDS[@]}"; do
    echo "    [\"$key\"] = ${MESSAGE_IDS[$key]}," >> $LUA_OUTPUT_FILE
done
echo "}" >> $LUA_OUTPUT_FILE

# 将当前的MESSAGE_IDS和MESSAGE_HASHES保存到TEMP_ID_FILE中
declare -p MESSAGE_IDS > $TEMP_ID_FILE
declare -p MESSAGE_HASHES >> $TEMP_ID_FILE

echo "Message IDs updated in $LUA_OUTPUT_FILE"


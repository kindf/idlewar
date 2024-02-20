#!/bin/bash

# 配置你的protobuf文件的目录
PROTO_DIR="./proto/proto"

# 输出的Lua文件
LUA_OUTPUT_FILE="./proto/message_ids.lua"

# 临时文件存储之前生成的ID和哈希
TEMP_ID_FILE="./proto/temp_ids.txt"

# 如果之前的临时ID文件存在，则读取它以保持ID的一致性
if [ -f "$TEMP_ID_FILE" ]; then
    source "$TEMP_ID_FILE"
else
    declare -A MESSAGE_IDS
    declare -A MESSAGE_HASHES
fi

# 初始化Lua文件
echo "-- 本文件又脚本gen_pids.sh自动生成，禁止手动修改." > "$LUA_OUTPUT_FILE"
echo "local M = {}" >> "$LUA_OUTPUT_FILE"

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

    # 输出Lua代码
    echo "M[\"$message_name\"] = $message_id" >> "$LUA_OUTPUT_FILE"
}

# 为每个proto文件生成或更新ID
for proto_file in "$PROTO_DIR"/*.proto; do
    # 获取不含路径和后缀的文件名作为消息名称
    ls proto/proto/*.proto | while read fname
    do
        package=`grep '^package[[:blank:]]' $fname | awk -F'[ ;]' '{print $2}'`
        grep '^message[[:blank:]]' $fname | awk -F'[ {]' '{print $2}' | while read line
        do
            if [[ $line == "c2s_"* || $line == "s2c_"* ]]; then
                message_name=$package"."$line
                update_or_generate_id "$message_name"
                echo generate $package"."$line pid succ.
            fi
        done
    done
done

# 完成Lua脚本文件
echo "return M" >> "$LUA_OUTPUT_FILE"

# 保存生成的ID和哈希到临时文件，以备后用
echo "declare -A MESSAGE_IDS=(" > "$TEMP_ID_FILE"
for key in "${!MESSAGE_IDS[@]}"; do
    echo "  [$key]=${MESSAGE_IDS[$key]}" >> "$TEMP_ID_FILE"
done
echo ")" >> "$TEMP_ID_FILE"

echo "declare -A MESSAGE_HASHES=(" >> "$TEMP_ID_FILE"
for key in "${!MESSAGE_HASHES[@]}"; do
    echo "  [$key]=${MESSAGE_HASHES[$key]}" >> "$TEMP_ID_FILE"
done
echo ")" >> "$TEMP_ID_FILE"

echo "Message IDs updated in $LUA_OUTPUT_FILE"


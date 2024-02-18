
cd proto/proto
for file in *
do
    protoc --descriptor_set_out=../pb/${file:0: -6}.pb ${file}
done

# # 删除旧pb文件
# rm -rf ../pb/*.pb

# mv *.pb ../pb/

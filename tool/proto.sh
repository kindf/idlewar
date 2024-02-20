cd proto/proto
for file in *
do
    proto_name=$(basename "$file" .proto)
    protoc --descriptor_set_out=../pb/${proto_name}.pb ${file}
    echo "protoc file succ. name: $file "
done

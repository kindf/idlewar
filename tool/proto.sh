cd proto/proto
for file in *
do
    protoc --descriptor_set_out=../pb/${file:0: -6}.pb ${file}
    echo "protoc file succ. name: $file "
done

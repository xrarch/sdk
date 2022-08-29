path=$(dirname $0)

make --directory=${path}/dfrt
make --directory=${path}/dfrt TARGET=fox32

${path}/install.sh ${path}/dfrt

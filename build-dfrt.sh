path=$(dirname $0)

make --directory=${path}/dfrt

${path}/install.sh ${path}/dfrt

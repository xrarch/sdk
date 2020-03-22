#!/bin/bash

path=$(dirname $0)
libname=$(basename $1)

mkdir -p ${path}/lib/${libname}
mkdir -p ${path}/headers/${libname}

cp -r $1/obj/*.o ${path}/lib/${libname}/
cp -r $1/headers/*.h ${path}/headers/${libname}/

echo "installed ${libname}"
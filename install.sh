#!/bin/bash

path=$(dirname $0)
libname=$(basename $1)

mkdir -p ${path}/headers/${libname}

shopt -s nullglob

for d in $1/obj/*/ ; do
    archname=$(basename $d)

    mkdir -p ${path}/lib/${archname}/${libname}/

    cp -r $d/*.o ${path}/lib/${archname}/${libname}/ 2>/dev/null
    cp -r $d/*.dll ${path}/lib/${archname}/${libname}/ 2>/dev/null
done

cp -r $1/headers/*.h ${path}/headers/${libname}/ 2>/dev/null

# echo "installed ${libname}"
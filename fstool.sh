#!/bin/bash

path=$(dirname $0)

os=$(uname)

if [ "$os" == "Darwin" ]; then
	FLAG="-bsd"
fi

${path}/lua.sh ${path}/fstool/fstool.lua $FLAG "$@"

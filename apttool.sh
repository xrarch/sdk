#!/bin/bash

path=$(dirname $0)

${path}/lua.sh ${path}/apttool/apttool.lua "$@"

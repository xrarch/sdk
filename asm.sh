#!/bin/bash

path=$(dirname $0)

${path}/lua.sh ${path}/asm/asm.lua "$@"

#!/bin/bash

if [[ $# < 2 ]]
then
	echo Not enough args
	exit 1
fi

sdk_path=$(dirname $0)
asm_file=`dirname $1`/`basename $1`.asm
${sdk_path}/lua.sh ${sdk_path}/dragonfruit/dragonc.lua $1 $asm_file || exit 1
${sdk_path}/asm.sh $asm_file $2
if [[ $3 != --keep-asm ]]
then
	rm $asm_file
fi

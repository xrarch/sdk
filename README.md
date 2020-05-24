# sdk

Cross-toolchain for the LIMNstation architecture, written in Lua because why not!

## Usage

Modify the `./lua.sh` shell script to use your LuaJIT executable.

Then the following scripts can be used as follows:

`./sdk/dragonc.sh [source file] [output binary]`

`./sdk/asm.sh [source file] [output binary]`

`./sdk/fsutil.sh [disk image] [command] ...`

`./sdk/link.sh [command] [...]`

# sdk

Small, somewhat crappy toolchain targeting the limn1k architecture.

## Usage

Modify the `./lua.sh` shell script to use your lua/luaJIT **5.1** executable.

Then the following scripts can be used as follows:

`./sdk/dragonc.sh [source file] [output binary]`

`./sdk/asm.sh [source file] [output binary]`

`./sdk/fsutil.sh [disk image] [command] ...`

`./sdk/link.sh [command] [...]`
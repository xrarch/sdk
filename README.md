# sdk

Cross-toolchain for the XR/17032 architecture, unjustifiably written in Lua. This toolchain is not good and is full of nigh-unreadable code from my junior year of high school; if you're looking for something to reference for writing something good, check back when the [native toolchain](https://github.com/xrarch/newsdk) exists, since that will actually have effort put into it.

## Usage

Modify the `./lua.sh` shell script to use your LuaJIT executable.

Then the following scripts can be used as follows:

`./sdk/dragonc.sh [source file] [output binary]`

`./sdk/asm.sh [source file] [output binary]`

`./sdk/fstool.sh [disk image] [command] ...`

`./sdk/link.sh [command] [...]`

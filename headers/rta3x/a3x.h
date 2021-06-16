extern a3xGets { buf max -- }

extern a3xPutc { c -- }

extern a3xPuts { s -- }

extern a3xGetc { -- c }

extern a3xAPIDevTree { -- root dcp }

extern a3xMalloc { sz -- ptr }

extern a3xCalloc { sz -- ptr }

extern a3xFree { ptr -- }

extern a3xDevTreeWalk { path -- node }

extern a3xDeviceParent { -- }

extern a3xDeviceSelectNode { node -- }

extern a3xDeviceSelect { path -- }

extern a3xDGetProperty { name -- value }

extern a3xDGetMethod { name -- ptr }

extern a3xDCallMethod { ... name -- out1 out2 out3 ok }

extern a3xDSetProperty { prop name -- }

extern a3xDeviceExit { -- }

extern a3xReturn { code -- }

extern a3xDCallMethodPtr { ptr -- }

extern a3xDevIteratorInit { -- iter }

extern a3xDevIterate { iterin -- iterout }

extern a3xDGetName { -- name }

extern a3xConsoleUserOut { -- }

extern a3xDGetCurrent { -- current }

externptr a3xCIPtr (* var *)

externptr a3xFwctx (* var *)

externptr a3xMyDevice (* var *)

const MEMORYFREE     1
const MEMORYRESERVED 2
const MEMORYBAD      3
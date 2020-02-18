.ds VNIX

.extern Main

_start:
;r4 contains fwctx
pushv r5, r4

;r0 contains pointer to API
pushv r5, r0

;r1 contains devnode
pushv r5, r1

;r2 contains args
pushv r5, r2

b Main
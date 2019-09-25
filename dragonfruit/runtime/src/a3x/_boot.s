.ds ANTE
.dl Entry

.extern Main

Entry:

push ivt

;push firmware context
pushv r5, sp

;r0 contains pointer to API
pushv r5, r0

;r1 contains devnode
pushv r5, r1

;r2 contains args
pushv r5, r2

b Main
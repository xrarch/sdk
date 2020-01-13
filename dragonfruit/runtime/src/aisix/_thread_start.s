.extern ThreadExit

_thread_start:
.global _thread_start
	;size of ThreadData structure
	addi r5, r0, 1028

	lrr.l r1, r0

	call .mock

	call ThreadExit

.mock:
	br r1
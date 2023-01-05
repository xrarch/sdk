.section text

;a0 - bit
;a1 - v
bitget:
.global bitget
	rsh  a0, a1, a0
	andi a0, a0, 1
	ret

;a0 - bit
;a1 - v
bitset:
.global bitset
	li   t0, 1
	lsh  t0, t0, a0
	or   a0, a1, t0
	ret

;a0 - bit
;a1 - v
bitclear:
.global bitclear
	li   t0, 1
	lsh  t0, t0, a0
	nor  t0, t0, t0
	and  a0, a1, t0
	ret
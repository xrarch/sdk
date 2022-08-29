.section text

;a0 - bit
;a1 - v
bitget:
.global bitget
	srl a1, a0
	and a1, 1
	mov a0, a1

	ret

;a0 - bit
;a1 - v
bitset:
.global bitset
	mov t0, 1
	sla t0, a0
	or  a1, t0
	mov a0, a1

	ret

;a0 - bit
;a1 - v
bitclear:
.global bitclear
	mov t0, 1
	sla t0, a0
	not t0
	and a1, t0
	mov a0, a1

	ret
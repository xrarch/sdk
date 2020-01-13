.extern _DF_DF0

_aisix_start:
.global _aisix_start
	add r5, r0, r1

	pushv r5, r0
	pushv r5, r1

	b _DF_DF0
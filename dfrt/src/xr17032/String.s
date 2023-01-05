.section text

;a0 - word
;a1 - size
;a2 - ptr
memset:
.global memset
	subi sp, sp, 4
	mov  long [sp], lr

	bne  a1, .gzero

	addi sp, sp, 4
	ret

.gzero:
	xori t1, a2, 3
	addi t1, t1, 1
	andi t1, t1, 3

	beq  t1, .fdone

	mov  t2, a0

	slt  t3, t1, a1
	bne  t3, .goodlen

	mov  t1, a1

.goodlen:
	sub  a1, a1, t1

.fu:
	mov  byte [a2], t2

	rshi t2, t2, 8

	addi a2, a2, 1
	subi t1, t1, 1
	bne  t1, .fu

.fdone:
	;ptr is now aligned

	rshi t1, a1, 6 ;do 64 bytes each loop

	beq  t1, .b64done

.b64:
	mov  long [a2], a0
	mov  long [a2 + 4], a0
	mov  long [a2 + 8], a0
	mov  long [a2 + 12], a0
	mov  long [a2 + 16], a0
	mov  long [a2 + 20], a0
	mov  long [a2 + 24], a0
	mov  long [a2 + 28], a0
	mov  long [a2 + 32], a0
	mov  long [a2 + 36], a0
	mov  long [a2 + 40], a0
	mov  long [a2 + 44], a0
	mov  long [a2 + 48], a0
	mov  long [a2 + 52], a0
	mov  long [a2 + 56], a0
	mov  long [a2 + 60], a0

	addi a2, a2, 64
	subi t1, t1, 1
	bne  t1, .b64

.b64done:
	andi t1, a1, 63

	rshi t1, t1, 2 ;do 4 bytes each loop

	beq  t1, .b4done

.b4:
	mov  long [a2], a0

	addi a2, a2, 4
	subi t1, t1, 1
	bne  t1, .b4

.b4done:
	andi t1, a1, 3 ;do 1 byte each loop

	beq  t1, .b1done

.b1:
	mov  byte [a2], a0

	rshi a0, a0, 8

	addi a2, a2, 1
	subi t1, t1, 1
	bne  t1, .b1

.b1done:
	addi sp, sp, 4
	ret

;a0 - sz
;a1 - src
;a2 - dest
memcpy:
.global memcpy
	subi sp, sp, 4
	mov  long [sp], lr

	beq  a0, .zerosize

	xor  t0, a1, a2

	andi t1, t0, 1
	beq  t1, .aligned_with_eachother

	b    .unaligned

.zerosize:
	addi sp, sp, 4
	ret

.aligned_with_eachother:
	xori t1, a1, 3
	addi t1, t1, 1
	andi t1, t1, 3

	beq  t1, .fdone

	slt  t3, t1, a0
	bne  t3, .goodlen

	mov  t1, a0

.goodlen:
	sub  a0, a0, t1

.fu:
	mov  t2, byte [a1]
	mov  byte [a2], t2

	addi a1, a1, 1
	addi a2, a2, 1
	subi t1, t1, 1
	bne  t1, .fu

.fdone:
	andi t1, t0, 3
	beq  t1, .aligned32

.aligned16:
	rshi t0, a0, 6 ;do 64 bytes each loop

	beq  t0, .copy16_by_64done

.copy16_by_64:
	mov  t1, int [a1]
	mov  t2, int [a1 + 2]
	mov  t3, int [a1 + 4]
	mov  t4, int [a1 + 6]

	mov  int [a2], t1
	mov  int [a2 + 2], t2
	mov  int [a2 + 4], t3
	mov  int [a2 + 6], t4

	mov  t1, int [a1 + 8]
	mov  t2, int [a1 + 10]
	mov  t3, int [a1 + 12]
	mov  t4, int [a1 + 14]

	mov  int [a2 + 8], t1
	mov  int [a2 + 10], t2
	mov  int [a2 + 12], t3
	mov  int [a2 + 14], t4

	mov  t1, int [a1 + 16]
	mov  t2, int [a1 + 18]
	mov  t3, int [a1 + 20]
	mov  t4, int [a1 + 22]

	mov  int [a2 + 16], t1
	mov  int [a2 + 18], t2
	mov  int [a2 + 20], t3
	mov  int [a2 + 22], t4

	mov  t1, int [a1 + 24]
	mov  t2, int [a1 + 26]
	mov  t3, int [a1 + 28]
	mov  t4, int [a1 + 30]

	mov  int [a2 + 24], t1
	mov  int [a2 + 26], t2
	mov  int [a2 + 28], t3
	mov  int [a2 + 30], t4

	mov  t1, int [a1 + 32]
	mov  t2, int [a1 + 34]
	mov  t3, int [a1 + 36]
	mov  t4, int [a1 + 38]

	mov  int [a2 + 32], t1
	mov  int [a2 + 34], t2
	mov  int [a2 + 36], t3
	mov  int [a2 + 38], t4

	mov  t1, int [a1 + 40]
	mov  t2, int [a1 + 42]
	mov  t3, int [a1 + 44]
	mov  t4, int [a1 + 46]

	mov  int [a2 + 40], t1
	mov  int [a2 + 42], t2
	mov  int [a2 + 44], t3
	mov  int [a2 + 46], t4

	mov  t1, int [a1 + 48]
	mov  t2, int [a1 + 50]
	mov  t3, int [a1 + 52]
	mov  t4, int [a1 + 54]

	mov  int [a2 + 48], t1
	mov  int [a2 + 50], t2
	mov  int [a2 + 52], t3
	mov  int [a2 + 54], t4

	mov  t1, int [a1 + 56]
	mov  t2, int [a1 + 58]
	mov  t3, int [a1 + 60]
	mov  t4, int [a1 + 62]

	mov  int [a2 + 56], t1
	mov  int [a2 + 58], t2
	mov  int [a2 + 60], t3
	mov  int [a2 + 62], t4

	addi a2, a2, 64
	addi a1, a1, 64
	subi t0, t0, 1
	bne  t0, .copy16_by_64

.copy16_by_64done:
	andi t0, a0, 63

	b    .copy_last_bytes

.aligned32:
	rshi t0, a0, 6 ;do 64 bytes each loop

	beq  t0, .copy32_by_64done

.copy32_by_64:
	mov  t1, long [a1]
	mov  t2, long [a1 + 4]
	mov  t3, long [a1 + 8]
	mov  t4, long [a1 + 12]

	mov  long [a2], t1
	mov  long [a2 + 4], t2
	mov  long [a2 + 8], t3
	mov  long [a2 + 12], t4

	mov  t1, long [a1 + 16]
	mov  t2, long [a1 + 20]
	mov  t3, long [a1 + 24]
	mov  t4, long [a1 + 28]

	mov  long [a2 + 16], t1
	mov  long [a2 + 20], t2
	mov  long [a2 + 24], t3
	mov  long [a2 + 28], t4

	mov  t1, long [a1 + 32]
	mov  t2, long [a1 + 36]
	mov  t3, long [a1 + 40]
	mov  t4, long [a1 + 44]

	mov  long [a2 + 32], t1
	mov  long [a2 + 36], t2
	mov  long [a2 + 40], t3
	mov  long [a2 + 44], t4

	mov  t1, long [a1 + 48]
	mov  t2, long [a1 + 52]
	mov  t3, long [a1 + 56]
	mov  t4, long [a1 + 60]

	mov  long [a2 + 48], t1
	mov  long [a2 + 52], t2
	mov  long [a2 + 56], t3
	mov  long [a2 + 60], t4

	addi a2, a2, 64
	addi a1, a1, 64
	subi t0, t0, 1
	bne  t0, .copy32_by_64

.copy32_by_64done:
	andi t0, a0, 63

	b    .copy_last_bytes

.unaligned:
	rshi t0, a0, 5 ;do 32 bytes each loop

	beq  t0, .copy8_by_32done

.copy8_by_32:
	mov  t1, byte [a1]
	mov  t2, byte [a1 + 1]
	mov  t3, byte [a1 + 2]
	mov  t4, byte [a1 + 3]

	mov  byte [a2], t1
	mov  byte [a2 + 1], t2
	mov  byte [a2 + 2], t3
	mov  byte [a2 + 3], t4

	mov  t1, byte [a1 + 4]
	mov  t2, byte [a1 + 5]
	mov  t3, byte [a1 + 6]
	mov  t4, byte [a1 + 7]

	mov  byte [a2 + 4], t1
	mov  byte [a2 + 5], t2
	mov  byte [a2 + 6], t3
	mov  byte [a2 + 7], t4

	mov  t1, byte [a1 + 8]
	mov  t2, byte [a1 + 9]
	mov  t3, byte [a1 + 10]
	mov  t4, byte [a1 + 11]

	mov  byte [a2 + 8], t1
	mov  byte [a2 + 9], t2
	mov  byte [a2 + 10], t3
	mov  byte [a2 + 11], t4

	mov  t1, byte [a1 + 12]
	mov  t2, byte [a1 + 13]
	mov  t3, byte [a1 + 14]
	mov  t4, byte [a1 + 15]

	mov  byte [a2 + 12], t1
	mov  byte [a2 + 13], t2
	mov  byte [a2 + 14], t3
	mov  byte [a2 + 15], t4

	mov  t1, byte [a1 + 16]
	mov  t2, byte [a1 + 17]
	mov  t3, byte [a1 + 18]
	mov  t4, byte [a1 + 19]

	mov  byte [a2 + 16], t1
	mov  byte [a2 + 17], t2
	mov  byte [a2 + 18], t3
	mov  byte [a2 + 19], t4

	mov  t1, byte [a1 + 20]
	mov  t2, byte [a1 + 21]
	mov  t3, byte [a1 + 22]
	mov  t4, byte [a1 + 23]

	mov  byte [a2 + 20], t1
	mov  byte [a2 + 21], t2
	mov  byte [a2 + 22], t3
	mov  byte [a2 + 23], t4

	mov  t1, byte [a1 + 24]
	mov  t2, byte [a1 + 25]
	mov  t3, byte [a1 + 26]
	mov  t4, byte [a1 + 27]

	mov  byte [a2 + 24], t1
	mov  byte [a2 + 25], t2
	mov  byte [a2 + 26], t3
	mov  byte [a2 + 27], t4

	mov  t1, byte [a1 + 28]
	mov  t2, byte [a1 + 29]
	mov  t3, byte [a1 + 30]
	mov  t4, byte [a1 + 31]

	mov  byte [a2 + 28], t1
	mov  byte [a2 + 29], t2
	mov  byte [a2 + 30], t3
	mov  byte [a2 + 31], t4

	addi a2, a2, 32
	addi a1, a1, 32
	subi t0, t0, 1
	bne  t0, .copy8_by_32

.copy8_by_32done:
	andi t0, a0, 31 ;do 1 byte each loop

.copy_last_bytes:
	beq  t0, .done

.b1:
	mov  t1, byte [a1]
	mov  byte [a2], t1

	addi a2, a2, 1
	addi a1, a1, 1
	subi t0, t0, 1
	bne  t0, .b1

.done:
	addi sp, sp, 4
	ret

;a0 - sz
;a1 - src
;a2 - dest
memcpy_backwards:
	subi sp, sp, 4
	mov  long [sp], lr

	beq  a0, .zerosize

	add  a1, a1, a0
	add  a2, a2, a0

	xor  t0, a1, a2

	andi t1, t0, 1
	beq  t1, .aligned_with_eachother

	b    .unaligned

.zerosize:
	addi sp, sp, 4
	ret

.aligned_with_eachother:
	andi t1, a1, 3

	beq  t1, .fdone

	slt  t3, t1, a0
	bne  t3, .goodlen

	mov  t1, a0

.goodlen:
	sub  a0, a0, t1

.fu:
	subi a1, a1, 1
	subi a2, a2, 1

	mov  t2, byte [a1]
	mov  byte [a2], t2

	subi t1, t1, 1
	bne  t1, .fu

.fdone:
	andi t1, t0, 3
	beq  t1, .aligned32

.aligned16:
	rshi t0, a0, 6 ;do 64 bytes each loop

	beq  t0, .copy16_by_64done

.copy16_by_64:
	subi a2, a2, 64
	subi a1, a1, 64

	mov  t1, int [a1 + 56]
	mov  t2, int [a1 + 58]
	mov  t3, int [a1 + 60]
	mov  t4, int [a1 + 62]

	mov  int [a2 + 56], t1
	mov  int [a2 + 58], t2
	mov  int [a2 + 60], t3
	mov  int [a2 + 62], t4

	mov  t1, int [a1 + 48]
	mov  t2, int [a1 + 50]
	mov  t3, int [a1 + 52]
	mov  t4, int [a1 + 54]

	mov  int [a2 + 48], t1
	mov  int [a2 + 50], t2
	mov  int [a2 + 52], t3
	mov  int [a2 + 54], t4

	mov  t1, int [a1 + 40]
	mov  t2, int [a1 + 42]
	mov  t3, int [a1 + 44]
	mov  t4, int [a1 + 46]

	mov  int [a2 + 40], t1
	mov  int [a2 + 42], t2
	mov  int [a2 + 44], t3
	mov  int [a2 + 46], t4

	mov  t1, int [a1 + 32]
	mov  t2, int [a1 + 34]
	mov  t3, int [a1 + 36]
	mov  t4, int [a1 + 38]

	mov  int [a2 + 32], t1
	mov  int [a2 + 34], t2
	mov  int [a2 + 36], t3
	mov  int [a2 + 38], t4

	mov  t1, int [a1 + 24]
	mov  t2, int [a1 + 26]
	mov  t3, int [a1 + 28]
	mov  t4, int [a1 + 30]

	mov  int [a2 + 24], t1
	mov  int [a2 + 26], t2
	mov  int [a2 + 28], t3
	mov  int [a2 + 30], t4

	mov  t1, int [a1 + 16]
	mov  t2, int [a1 + 18]
	mov  t3, int [a1 + 20]
	mov  t4, int [a1 + 22]

	mov  int [a2 + 16], t1
	mov  int [a2 + 18], t2
	mov  int [a2 + 20], t3
	mov  int [a2 + 22], t4

	mov  t1, int [a1 + 8]
	mov  t2, int [a1 + 10]
	mov  t3, int [a1 + 12]
	mov  t4, int [a1 + 14]

	mov  int [a2 + 8], t1
	mov  int [a2 + 10], t2
	mov  int [a2 + 12], t3
	mov  int [a2 + 14], t4

	mov  t1, int [a1]
	mov  t2, int [a1 + 2]
	mov  t3, int [a1 + 4]
	mov  t4, int [a1 + 6]

	mov  int [a2], t1
	mov  int [a2 + 2], t2
	mov  int [a2 + 4], t3
	mov  int [a2 + 6], t4

	subi t0, t0, 1
	bne  t0, .copy16_by_64

.copy16_by_64done:
	andi t0, a0, 63

	b    .copy_last_bytes

.aligned32:
	rshi t0, a0, 6 ;do 64 bytes each loop

	beq  t0, .copy32_by_64done

.copy32_by_64:
	subi a2, a2, 64
	subi a1, a1, 64

	mov  t1, long [a1 + 48]
	mov  t2, long [a1 + 52]
	mov  t3, long [a1 + 56]
	mov  t4, long [a1 + 60]

	mov  long [a2 + 48], t1
	mov  long [a2 + 52], t2
	mov  long [a2 + 56], t3
	mov  long [a2 + 60], t4

	mov  t1, long [a1 + 32]
	mov  t2, long [a1 + 36]
	mov  t3, long [a1 + 40]
	mov  t4, long [a1 + 44]

	mov  long [a2 + 32], t1
	mov  long [a2 + 36], t2
	mov  long [a2 + 40], t3
	mov  long [a2 + 44], t4

	mov  t1, long [a1 + 16]
	mov  t2, long [a1 + 20]
	mov  t3, long [a1 + 24]
	mov  t4, long [a1 + 28]

	mov  long [a2 + 16], t1
	mov  long [a2 + 20], t2
	mov  long [a2 + 24], t3
	mov  long [a2 + 28], t4

	mov  t1, long [a1]
	mov  t2, long [a1 + 4]
	mov  t3, long [a1 + 8]
	mov  t4, long [a1 + 12]

	mov  long [a2], t1
	mov  long [a2 + 4], t2
	mov  long [a2 + 8], t3
	mov  long [a2 + 12], t4

	subi t0, t0, 1
	bne  t0, .copy32_by_64

.copy32_by_64done:
	andi t0, a0, 63

	b    .copy_last_bytes

.unaligned:
	rshi t0, a0, 5 ;do 32 bytes each loop

	beq  t0, .copy8_by_32done

.copy8_by_32:
	subi a2, a2, 32
	subi a1, a1, 32

	mov  t1, byte [a1 + 28]
	mov  t2, byte [a1 + 29]
	mov  t3, byte [a1 + 30]
	mov  t4, byte [a1 + 31]

	mov  byte [a2 + 28], t1
	mov  byte [a2 + 29], t2
	mov  byte [a2 + 30], t3
	mov  byte [a2 + 31], t4

	mov  t1, byte [a1 + 24]
	mov  t2, byte [a1 + 25]
	mov  t3, byte [a1 + 26]
	mov  t4, byte [a1 + 27]

	mov  byte [a2 + 24], t1
	mov  byte [a2 + 25], t2
	mov  byte [a2 + 26], t3
	mov  byte [a2 + 27], t4

	mov  t1, byte [a1 + 20]
	mov  t2, byte [a1 + 21]
	mov  t3, byte [a1 + 22]
	mov  t4, byte [a1 + 23]

	mov  byte [a2 + 20], t1
	mov  byte [a2 + 21], t2
	mov  byte [a2 + 22], t3
	mov  byte [a2 + 23], t4

	mov  t1, byte [a1 + 16]
	mov  t2, byte [a1 + 17]
	mov  t3, byte [a1 + 18]
	mov  t4, byte [a1 + 19]

	mov  byte [a2 + 16], t1
	mov  byte [a2 + 17], t2
	mov  byte [a2 + 18], t3
	mov  byte [a2 + 19], t4

	mov  t1, byte [a1 + 12]
	mov  t2, byte [a1 + 13]
	mov  t3, byte [a1 + 14]
	mov  t4, byte [a1 + 15]

	mov  byte [a2 + 12], t1
	mov  byte [a2 + 13], t2
	mov  byte [a2 + 14], t3
	mov  byte [a2 + 15], t4

	mov  t1, byte [a1 + 8]
	mov  t2, byte [a1 + 9]
	mov  t3, byte [a1 + 10]
	mov  t4, byte [a1 + 11]

	mov  byte [a2 + 8], t1
	mov  byte [a2 + 9], t2
	mov  byte [a2 + 10], t3
	mov  byte [a2 + 11], t4

	mov  t1, byte [a1 + 4]
	mov  t2, byte [a1 + 5]
	mov  t3, byte [a1 + 6]
	mov  t4, byte [a1 + 7]

	mov  byte [a2 + 4], t1
	mov  byte [a2 + 5], t2
	mov  byte [a2 + 6], t3
	mov  byte [a2 + 7], t4

	mov  t1, byte [a1]
	mov  t2, byte [a1 + 1]
	mov  t3, byte [a1 + 2]
	mov  t4, byte [a1 + 3]

	mov  byte [a2], t1
	mov  byte [a2 + 1], t2
	mov  byte [a2 + 2], t3
	mov  byte [a2 + 3], t4

	subi t0, t0, 1
	bne  t0, .copy8_by_32

.copy8_by_32done:
	andi t0, a0, 31 ;do 1 byte each loop

.copy_last_bytes:
	beq  t0, .done

.b1:
	subi a2, a2, 1
	subi a1, a1, 1

	mov  t1, byte [a1]
	mov  byte [a2], t1

	subi t0, t0, 1
	bne  t0, .b1

.done:
	addi sp, sp, 4
	ret

memmove:
.global memmove
	slt t0, a1, a2
	bne t0, .backwards
	j   memcpy
.backwards:
	j   memcpy_backwards

;a0 - src
;a1 - dest
strcpy:
.global strcpy
	subi sp, sp, 4
	mov  long [sp], lr

	li   t2, 0

.loop:
	mov  t0, byte [a0 + t2]
	mov  byte [a1 + t2], t0
	addi t2, t2, 1
	bne  t0, .loop

	addi sp, sp, 4
	ret

;a0 - max
;a1 - src
;a2 - dest
strncpy:
.global strncpy
	subi sp, sp, 4
	mov  long [sp], lr

	li   t2, 0

.loop:
	beq  a0, .done
	mov  t0, byte [a1 + t2]
	mov  byte [a2 + t2], t0
	addi t2, t2, 1
	subi a0, a0, 1
	bne  t0, .loop

	addi sp, sp, 4
	ret

.done:
	mov  byte [a2 + t2], zero

	addi sp, sp, 4
	ret

;a0 - str2
;a1 - str1
;returns:
;a0 - eq
strcmp:
.global strcmp
	subi sp, sp, 4
	mov  long [sp], lr

	li   t2, 0

.loop:
	mov  t0, byte [a0 + t2]
	mov  t1, byte [a1 + t2]
	sub  t0, t0, t1
	bne  t0, .notequal
	addi t2, t2, 1
	bne  t1, .loop

	li   a0, 1

	addi sp, sp, 4
	ret

.notequal:
	li   a0, 0

	addi sp, sp, 4
	ret
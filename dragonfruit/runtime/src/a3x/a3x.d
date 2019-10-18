var a3xCIPtr 0
public a3xCIPtr

var a3xFwctx 0
public a3xFwctx

procedure a3xInit (* fwctx a3xCIPtr -- *)
	a3xCIPtr!
	a3xFwctx!
end

procedure a3xReturn (* code -- *)
	asm "

	popv r5, k0

	lri.l sp, a3xFwctx

	pop ivt

	ret

	"
end

asm "

;r30 - call num
_a3xCIC_Call:
	push r29
	lri.l r29, a3xCIPtr
	add r30, r30, r29
	lrr.l r30, r30

	call .e
	pop r29
	ret

.e:
	br r30

_a3xCIC_Putc === 0
_a3xCIC_Getc === 4
_a3xCIC_Gets === 8
_a3xCIC_DevTree === 16
_a3xCIC_Malloc === 20
_a3xCIC_Calloc === 24
_a3xCIC_Free === 28

_a3xCIC_DevTreeWalk === 32
_a3xCIC_DeviceParent === 36
_a3xCIC_DeviceSelectNode === 40
_a3xCIC_DeviceSelect === 44
_a3xCIC_DeviceDGetProperty === 48
_a3xCIC_DeviceDGetMethod === 52
_a3xCIC_DeviceDCallMethod === 56
_a3xCIC_DeviceExit === 60
_a3xCIC_DeviceDSetProperty === 64
_a3xCIC_DeviceDCallMethodPtr === 68

; buffer maxchars --
a3xGets:
.global a3xGets
	push r30

	li r30, _a3xCIC_Gets
	call _a3xCIC_Call

	pop r30
	ret

; char -- 
a3xPutc:
.global a3xPutc
	push r30

	li r30, _a3xCIC_Putc
	call _a3xCIC_Call

	pop r30
	ret

; -- char
a3xGetc:
.global a3xGetc
	push r30

	li r30, _a3xCIC_Getc
	call _a3xCIC_Call

	pop r30
	ret

; -- root dcp
a3xAPIDevTree:
.global a3xAPIDevTree
	push r30

	li r30, _a3xCIC_DevTree
	call _a3xCIC_Call

	pop r30
	ret

; sz -- ptr
a3xMalloc:
.global a3xMalloc
	push r30

	li r30, _a3xCIC_Malloc
	call _a3xCIC_Call

	pop r30
	ret

; sz -- ptr
a3xCalloc:
.global a3xCalloc
	push r30

	li r30, _a3xCIC_Calloc
	call _a3xCIC_Call

	pop r30
	ret

; ptr -- 
a3xFree:
.global a3xFree
	push r30

	li r30, _a3xCIC_Free
	call _a3xCIC_Call

	pop r30
	ret

; path -- node
a3xDevTreeWalk:
.global a3xDevTreeWalk
	push r30

	li r30, _a3xCIC_DevTreeWalk
	call _a3xCIC_Call

	pop r30
	ret

; --
a3xDeviceParent:
.global a3xDeviceParent
	push r30

	li r30, _a3xCIC_DeviceParent
	call _a3xCIC_Call

	pop r30
	ret

; node -- 
a3xDeviceSelectNode:
.global a3xDeviceSelectNode
	push r30

	li r30, _a3xCIC_DeviceSelectNode
	call _a3xCIC_Call

	pop r30
	ret

; path -- 
a3xDeviceSelect:
.global a3xDeviceSelect
	push r30

	li r30, _a3xCIC_DeviceSelect
	call _a3xCIC_Call

	pop r30
	ret

; name -- value
a3xDGetProperty:
.global a3xDGetProperty
	push r30

	li r30, _a3xCIC_DeviceDGetProperty
	call _a3xCIC_Call

	pop r30
	ret

; name -- ptr
a3xDGetMethod:
.global a3xDGetMethod
	push r30

	li r30, _a3xCIC_DeviceDGetMethod
	call _a3xCIC_Call

	pop r30
	ret

; name -- success
a3xDCallMethod:
.global a3xDCallMethod
	push r30

	li r30, _a3xCIC_DeviceDCallMethod
	call _a3xCIC_Call

	pop r30
	ret

; -- 
a3xDeviceExit:
.global a3xDeviceExit
	push r30

	li r30, _a3xCIC_DeviceExit
	call _a3xCIC_Call

	pop r30
	ret

; prop name --
a3xDSetProperty:
.global a3xDSetProperty
	push r30

	li r30, _a3xCIC_DeviceDSetProperty
	call _a3xCIC_Call

	pop r30
	ret

; ptr --
a3xDCallMethodPtr:
.global a3xDCallMethodPtr
	push r30

	li r30, _a3xCIC_DeviceDCallMethodPtr
	call _a3xCIC_Call

	pop r30
	ret

"



















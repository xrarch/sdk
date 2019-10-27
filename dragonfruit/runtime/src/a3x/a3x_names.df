#include "<df>/platform/a3x/a3x.h"

(* hack to keep names pretty *)

asm "

; char -- 
Putc:
.global Putc
	b a3xPutc

; -- char
Getc:
.global Getc
	b a3xGetc

; sz -- ptr
Malloc:
.global Malloc
	b a3xMalloc

; sz -- ptr
Calloc:
.global Calloc
	b a3xCalloc

; ptr -- 
Free:
.global Free
	b a3xFree

"
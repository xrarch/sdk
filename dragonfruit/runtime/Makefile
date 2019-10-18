GENERICDFILES := $(shell find ./src/generic -type f -name '*.d')
GENERICSFILES := $(shell find ./src/generic -type f -name '*.s')
GENERICOBJ    := $(GENERICDFILES:.d=.o)
GENERICSOBJ   := $(GENERICSFILES:.s=.o)

A3XDFILES := $(shell find ./src/a3x -type f -name '*.d')
A3XSFILES := $(shell find ./src/a3x -type f -name '*.s')
A3XOBJ    := $(A3XDFILES:.d=.o)
A3XSOBJ   := $(A3XSFILES:.s=.o)

DC  =  ../../dragonc.sh
AS  =  ../../asm.sh
LD  =  ../../link.sh link

LIBS = lib/generic/lib.o lib/a3x/lib.o

all: $(LIBS)

lib/generic/lib.o: $(GENERICOBJ) $(GENERICSOBJ)
	$(LD) lib/generic/lib.o $(GENERICOBJ) $(GENERICSOBJ)

lib/a3x/lib.o: $(A3XOBJ)
	$(LD) lib/a3x/lib.o $(A3XOBJ)
	$(AS) ./src/a3x/_start.s ./src/a3x/_start.o
	$(AS) ./src/a3x/_boot.s ./src/a3x/_boot.o
	cp ./src/a3x/_start.o ./lib/a3x/_start.o
	cp ./src/a3x/_boot.o ./lib/a3x/_boot.o

%.o: %.d
	$(DC) $< $@

%.o: %.s
	$(AS) $< $@

cleanup:
	rm $(GENERICOBJ) $(GENERICSOBJ) $(A3XOBJ) $(A3XSOBJ)

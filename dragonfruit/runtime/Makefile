GENERICDFILES := $(shell find ./src/libsa -type f -name '*.df')
GENERICSFILES := $(shell find ./src/libsa -type f -name '*.s')
GENERICOBJ    := $(GENERICDFILES:.df=.o)
GENERICSOBJ   := $(GENERICSFILES:.s=.o)

A3XDFILES := $(shell find ./src/liba3x -type f -name '*.df')
A3XSFILES := $(shell find ./src/liba3x -type f -name '*.s')
A3XOBJ    := $(A3XDFILES:.df=.o)
A3XSOBJ   := $(A3XSFILES:.s=.o)

AISIXDFILES := $(shell find ./src/libaisix -type f -name '*.df')
AISIXSFILES := $(shell find ./src/libaisix -type f -name '*.s')
AISIXOBJ    := $(AISIXDFILES:.df=.o)
AISIXSOBJ   := $(AISIXSFILES:.s=.o)

DC  =  ../../dragonc.sh
AS  =  ../../asm.sh
LD  =  ../../link.sh link

LIBS = lib/libsa/lib.o lib/liba3x/lib.o lib/libaisix/lib.o

all: $(LIBS)

lib/libsa/lib.o: $(GENERICOBJ) $(GENERICSOBJ)
	$(LD) lib/libsa/lib.o $(GENERICOBJ) $(GENERICSOBJ)
	$(AS) ./src/libsa/_i6l_start.s ./src/libsa/_i6l_start.o
	cp ./src/libsa/_i6l_start.o ./lib/libsa/_i6l_start.o

lib/liba3x/lib.o: $(A3XOBJ)
	$(LD) lib/liba3x/lib.o $(A3XOBJ)
	$(AS) ./src/liba3x/_boot.s ./src/liba3x/_boot.o
	cp ./src/liba3x/_boot.o ./lib/liba3x/_boot.o
	cp ./src/liba3x/a3x.o ./lib/liba3x/a3x.o

lib/libaisix/lib.o: $(AISIXOBJ) $(AISIXSOBJ)
	$(LD) lib/libaisix/lib.o $(AISIXOBJ) $(AISIXSOBJ)

%.o: %.df
	$(DC) $< $@

%.o: %.s
	$(AS) $< $@

cleanup:
	rm $(GENERICOBJ) $(GENERICSOBJ) $(A3XOBJ) $(A3XSOBJ) $(AISIXOBJ) $(AISIXSOBJ)

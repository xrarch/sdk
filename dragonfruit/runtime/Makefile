GENERICDFILES := $(shell find ./src/generic -type f -name '*.d')
GENERICSFILES := $(shell find ./src/generic -type f -name '*.s')
GENERICOBJ    := $(GENERICDFILES:.d=.o)
GENERICSOBJ   := $(GENERICSFILES:.s=.o)

DC  =  ../../dragonc.sh
AS  =  ../../asm.sh
LD  =  ../../link.sh link

all: $(GENERICOBJ) $(GENERICSOBJ)
	$(LD) lib/generic.o $(GENERICOBJ) $(GENERICSOBJ)

%.o: %.d
	$(DC) $< $@

%.o: %.s
	$(AS) $< $@
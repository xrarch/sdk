DFILES := $(shell find ./src -type f -name "*.df")
SFILES := $(shell find ./src -type f -name "*.s")
OBJ    := $(DFILES:.df=.o)
SOBJ   := $(SFILES:.s=.o)

DC  =  ../dragonc.sh
AS  =  ../asm.sh
LD  =  ../link.sh link

all: obj/dfrt.f.o

obj/dfrt.f.o: $(OBJ) $(SOBJ)
	$(LD) -f obj/dfrt.f.o $(OBJ) $(SOBJ)

%.o: %.df
	$(DC) $< $@ incdir=./headers/

%.o: %.s
	$(AS) $< $@

cleanup:
	rm -f $(OBJ) $(SOBJ) obj/dfrt.f.o
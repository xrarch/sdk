TARGET := limn2600

DFILES := $(shell find ./src -type f -name "*.df")
SFILES := $(shell find ./src/$(TARGET)/ -type f -name "*.s")
OBJ    := $(DFILES:.df=.o)
SOBJ   := $(SFILES:.s=.o)

DC  =  ../dragonc.sh
AS  =  ../asm.sh
LD  =  ../link.sh link

all: obj/$(TARGET)/dfrt.f.o

obj/$(TARGET)/dfrt.f.o: $(OBJ) $(SOBJ)
	mkdir -p obj/$(TARGET)
	$(LD) -f obj/$(TARGET)/dfrt.f.o $(OBJ) $(SOBJ)

%.o: %.df
	$(DC) target=$(TARGET) $< $@ incdir=./headers/

%.o: %.s
	$(AS) target=$(TARGET) $< $@

cleanup:
	rm -f $(OBJ) $(SOBJ) obj/*/dfrt.f.o
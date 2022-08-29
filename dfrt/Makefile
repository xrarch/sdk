ifndef TARGET
	TARGET := limn2600
endif

DFILES := $(wildcard ./src/*.df ./src/$(TARGET)/*.df)
SFILES := $(wildcard ./src/$(TARGET)/*.s)
OBJ    := $(DFILES:.df=.$(TARGET).o)
SOBJ   := $(SFILES:.s=.$(TARGET).o)

DC  =  ../dragonc.sh
AS  =  ../asm.sh
LD  =  ../link.sh link

all: obj/$(TARGET)/dfrt.f.o

obj/$(TARGET)/dfrt.f.o: $(OBJ) $(SOBJ)
	mkdir -p obj/$(TARGET)
	$(LD) -f obj/$(TARGET)/dfrt.f.o $(OBJ) $(SOBJ)

%.$(TARGET).o: %.df
	$(DC) target=$(TARGET) $< $@ incdir=./headers/

%.$(TARGET).o: %.s
	$(AS) target=$(TARGET) $< $@

cleanup:
	rm -f $(OBJ) $(SOBJ) obj/*/dfrt.f.o
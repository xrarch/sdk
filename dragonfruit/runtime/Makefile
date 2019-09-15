VPATH = src:include:object

lib.o: rt.o list.o tree.o
	../../link.sh link object/lib.o src/rt.o src/list.o src/tree.o

rt.o: Runtime.d
	../../dragonc-nolib.sh src/Runtime.d src/rt.o

list.o: List.d
	../../dragonc-nolib.sh src/List.d src/list.o

tree.o: Tree.d
	../../dragonc-nolib.sh src/Tree.d src/tree.o
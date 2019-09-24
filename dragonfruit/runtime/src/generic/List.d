#include "<df>/const.h"
#include "<df>/list.h"

extern Free
extern Malloc
extern Calloc

(* stolen and ported to dragonfruit from toaruos list.c *)

(* any new procedures should be updated in <df>/list.h *)

procedure ListLength (* list -- length *)
	List_Length + @
end

procedure ListHead (* list -- head *)
	List_Head + @
end

procedure ListTail (* list -- tail *)
	List_Tail + @
end

procedure ListNodeOwner (* node -- owner *)
	ListNode_Owner + @
end

procedure ListNodePrev (* node -- prev *)
	ListNode_Prev + @
end

procedure ListNodeNext (* node -- next *)
	ListNode_Next + @
end

procedure ListNodeValue (* node -- value *)
	ListNode_Value + @
end

procedure ListDestroy (* list -- *)
	auto list
	list!

	auto n
	list@ List_Head + @ n!

	while (n@ 0 ~=)
		n@ ListNode_Value + @ Free
		n@ ListNode_Next + @ n!
	end
end

procedure ListFree (* list -- *)
	auto list
	list!

	auto n
	list@ List_Head + @ n!

	while (n@ 0 ~=)
		auto s
		n@ ListNode_Next + @ s!
		n@ Free
		s@ n!
	end
end

procedure ListAppend (* node list -- *)
	auto list
	list!

	auto node
	node!

	0 node@ ListNode_Next + !
	list@ node@ ListNode_Owner + !

	if (list@ List_Length + @ 0 ==)
		node@ list@ List_Head + !
		node@ list@ List_Tail + !
		0 node@ ListNode_Prev + !
		0 node@ ListNode_Next + !
		1 list@ List_Length + !
		return
	end

	node@ list@ List_Tail + @ ListNode_Next + !
	list@ List_Tail + @ node@ ListNode_Prev + !
	node@ list@ List_Tail + !
	list@ List_Length + dup @ 1 + swap !
end

procedure ListInsert1 (* item list -- node *)
	auto list
	list!

	auto item
	item!

	auto node
	ListNode_SIZEOF Malloc node!
	item@ node@ ListNode_Value + !
	0 node@ ListNode_Next + !
	0 node@ ListNode_Prev + !
	0 node@ ListNode_Owner + !
	node@ list@ ListAppend

	node@
end

procedure ListInsert (* item list -- *)
	ListInsert1 drop
end

procedure ListCreate (* -- list *)
	auto out
	List_SIZEOF Malloc out!

	0 out@ List_Head + !
	0 out@ List_Tail + !
	0 out@ List_Length + !

	out@
end

procedure ListTakeHead (* list -- head *)
	auto list
	list!

	0 list@ ListRemoveRR
end

procedure ListRemoveRR (* index list -- ref *)
	auto list
	list!

	auto index
	index!

	if (index@ list@ List_Length + @ >) ERR return end

	auto n
	list@ List_Head + @ n!

	auto i
	0 i!

	while (i@ index@ <)
		n@ ListNode_Next + @ n!
		i@ 1 + i!
	end

	n@ list@ ListDelete

	n@
end

procedure ListRemove (* index list -- *)
	ListRemoveRR drop
end

procedure ListDelete (* node list -- *)
	auto list
	list!

	auto node
	node!

	if (node@ list@ List_Head + @ ==)
		node@ ListNode_Next + @ list@ List_Head + !
	end
	if (node@ list@ List_Tail + @ ==)
		node@ ListNode_Prev + @ list@ List_Tail + !
	end
	if (node@ ListNode_Prev + @ 0 ~=)
		node@ ListNode_Next + @
		node@ ListNode_Prev + @ ListNode_Next + !
	end
	if (node@ ListNode_Next + @ 0 ~=)
		node@ ListNode_Prev + @
		node@ ListNode_Next + @ ListNode_Prev + !
	end

	0 node@ ListNode_Prev + !
	0 node@ ListNode_Next + !
	0 node@ ListNode_Owner + !

	list@ List_Length + dup @ 1 - swap !
end

procedure ListFind (* value list -- item *)
	auto list
	list!

	auto value
	value!

	auto n
	list@ List_Head + @ n!

	auto i
	0 i!

	while (n@ 0 ~=)
		if (n@ ListNode_Value + @ value@ ==)
			i@ return
		end

		i@ 1 + i!
		n@ ListNode_Next + @ n!
	end
end
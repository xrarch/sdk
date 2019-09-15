#include "<df>/const.h"
#include "<df>/list.h"

extern Calloc
extern Malloc
extern Free

(* stolen and ported to dragonfruit from toaruos tree.c *)

(* any new procedures or changes to structs should be updated in <df>/tree.h *)

struct TreeNode
	4 Value
	4 Children
	4 Parent
endstruct

struct Tree
	4 Nodes
	4 Root
endstruct

procedure TreeNodes (* tree -- nodes *)
	Tree_Nodes + @
end

procedure TreeRoot (* tree -- root *)
	Tree_Root + @
end

procedure TreeNodeValue (* node -- value *)
	TreeNode_Value + @
end

procedure TreeNodeParent (* node -- parent *)
	TreeNode_Parent + @
end

procedure TreeNodeChildren (* node -- children *)
	TreeNode_Children + @
end

procedure TreeCreate (* -- tree *)
	auto out
	Tree_SIZEOF Calloc out!

	0 out@ Tree_Nodes + !
	0 out@ Tree_Root + !

	out@
end

procedure TreeSetRoot (* value tree -- node *)
	auto tree
	tree!

	auto value
	value!

	auto root
	value@ TreeNodeCreate root!

	root@ tree@ Tree_Root + !
	1 tree@ Tree_Nodes + !

	root@
end

procedure TreeNodeDestroy (* node -- *)
	auto node
	node!

	auto n
	node@ TreeNode_Children + @ List_Head + @ n!
	while (n@ 0 ~=)
		n@ ListNode_Value + @ TreeNodeDestroy

		n@ ListNode_Next + @ n!
	end

	node@ TreeNode_Value + @ Free
end

procedure TreeDestroy (* tree -- *)
	auto tree
	tree!

	if (tree@ Tree_Root + @ 0 ~=)
		tree@ Tree_Root + @ TreeNodeDestroy
	end
end

procedure TreeNodeFree (* node -- *)
	auto node
	node!

	if (node@ 0 ==)
		return
	end

	auto n
	node@ TreeNode_Children + @ List_Head + @ n!
	while (n@ 0 ~=)
		n@ ListNode_Value + @ TreeNodeFree

		n@ ListNode_Next + @ n!
	end

	node@ Free
end

procedure TreeFree (* tree -- *)
	auto tree
	tree!

	tree@ Tree_Root + @ TreeNodeFree
end

procedure TreeNodeCreate (* value -- *)
	auto value
	value!

	auto out
	TreeNode_SIZEOF Calloc out!

	value@ out@ TreeNode_Value + !
	ListCreate out@ TreeNode_Children + !
	0 out@ TreeNode_Parent + !

	out@
end

procedure TreeInsertChildNode (* node parent tree -- *)
	auto tree
	tree!

	auto parent
	parent!

	auto node
	node!

	node@ parent@ TreeNode_Children + @ ListInsert
	parent@ node@ TreeNode_Parent + !
	tree@ Tree_Nodes + dup @ 1 + swap !
end

procedure TreeInsertChild (* value parent tree -- node *)
	auto out

	auto tree
	tree!

	auto parent
	parent!

	auto value
	value!

	value@ TreeNodeCreate out!
	out@ parent@ tree@ TreeInsertChildNode
	out@
end

procedure TreeNodeGetValue (* node -- value *)
	TreeNode_Value + @
end
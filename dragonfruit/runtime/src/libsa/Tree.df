#include "<df>/const.h"
#include "<df>/list.h"
#include "<df>/tree.h"

extern Calloc
extern Malloc
extern Free

(* stolen and ported to dragonfruit from toaruos tree.c *)

(* any new procedures should be updated in <df>/tree.h *)

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

procedure TreeCreate { -- out }
	Tree_SIZEOF Calloc out!

	0 out@ Tree_Nodes + !
	0 out@ Tree_Root + !
end

procedure TreeSetRoot { value tree -- root }
	value@ TreeNodeCreate root!

	root@ tree@ Tree_Root + !
	1 tree@ Tree_Nodes + !
end

procedure TreeNodeDestroy { node -- }
	auto n
	node@ TreeNode_Children + @ List_Head + @ n!
	while (n@ 0 ~=)
		n@ ListNode_Value + @ TreeNodeDestroy

		n@ ListNode_Next + @ n!
	end

	node@ TreeNode_Value + @ Free
end

procedure TreeDestroy { tree -- }
	if (tree@ Tree_Root + @ 0 ~=)
		tree@ Tree_Root + @ TreeNodeDestroy
	end
end

procedure TreeNodeFree { node -- }
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

procedure TreeFree { tree -- }
	tree@ Tree_Root + @ TreeNodeFree
end

procedure TreeNodeCreate { value -- }
	auto out
	TreeNode_SIZEOF Calloc out!

	value@ out@ TreeNode_Value + !
	ListCreate out@ TreeNode_Children + !
	0 out@ TreeNode_Parent + !

	out@
end

procedure TreeInsertChildNode { node parent tree -- }
	node@ parent@ TreeNode_Children + @ ListInsert
	parent@ node@ TreeNode_Parent + !
	1 tree@ Tree_Nodes + +=
end

procedure TreeInsertChild { value parent tree -- node }
	value@ TreeNodeCreate node!
	node@ parent@ tree@ TreeInsertChildNode
end

procedure TreeNodeGetValue (* node -- value *)
	TreeNode_Value + @
end
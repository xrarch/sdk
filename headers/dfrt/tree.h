struct TreeNode
	4 Value
	4 Children
	4 Parent
endstruct

struct Tree
	4 Nodes
	4 Root
endstruct

extern TreeNodes { tree -- nodes }

extern TreeRoot { tree -- root }

extern TreeNodeValue { node -- value }

extern TreeNodeParent { node -- parent }

extern TreeNodeChildren { node -- children }

extern TreeCreate { -- tree }

extern TreeSetRoot { value tree -- root }

extern TreeNodeDestroy { node -- }

extern TreeDestroy { tree -- }

extern TreeNodeFree { node -- }

extern TreeFree { tree -- }

extern TreeNodeCreate { value -- node }

extern TreeInsertChildNode { node parent tree -- }

extern TreeInsertChild { value parent tree -- node }

extern TreeNodeGetValue { node -- value }
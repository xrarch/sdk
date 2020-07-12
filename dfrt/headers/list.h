struct ListNode
	4 Next
	4 Prev
	4 Value
	4 Owner
endstruct

struct List
	4 Head
	4 Tail
	4 Length
endstruct

extern ListLength { list -- length }

extern ListHead { list -- head }

extern ListTail { list -- tail }

extern ListNodeOwner { node -- owner }

extern ListNodePrev { node -- prev }

extern ListNodeNext { node -- next }

extern ListNodeValue { node -- value }

extern ListDestroy { list -- }

extern ListAppend { node list -- }

extern ListInsert1 { item list -- node }

extern ListInsert { item list -- }

extern ListCreate { -- list }

extern ListTakeHead { list -- head }

extern ListRemoveRR { index list -- ref }

extern ListRemove { index list -- }

extern ListDelete { node list -- }

extern ListFind { value list -- item }
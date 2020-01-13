extern Exit (* ret -- *)

extern Abort (* ... fstr -- *)

extern Yield (* -- *)

extern ServiceByName (* name -- pid *)

extern GetPID (* -- pid *)

extern NewThread (* pc -- ret *)

extern AtomicLock (* lock -- *)

extern Spinlock (* lock -- *)

extern Wait (* pid -- ret *)

extern ThreadExit (* -- *)
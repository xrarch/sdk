extern abs { v -- absv }

extern max { n1 n2 -- max }

extern min { n1 n2 -- min }

extern itoa { n buf -- }

extern strdup { str -- allocstr }

extern reverse { str -- }

extern memcpy { dest src size -- }

extern memset { ptr size word -- }

extern strcmp { str1 str2 -- eq }

extern strncmp { str1 str2 n -- eq }

extern strlen { str -- size }

extern strtok { str buf del -- next }

extern strzero { str -- }

extern strntok { str buf del n -- next }

extern strcpy { dest src -- }

extern strncpy { dest src max -- }

extern strcat { dest src -- }

extern strncat { dest src max -- }

extern atoi { str -- n }

extern Puts { s -- }

extern Printf { ... fmt -- }

extern VPrintf { argvt argcn fmt -- }

extern VFPrintf { argvt argcn fmt fd -- }

extern FPrintf { ... fmt fd -- }

extern Malloc { size -- ptr }

extern Calloc { size -- ptr }

extern Free { ptr -- }

extern Gets { s max -- }

extern Putc { c -- }

extern FPutc { fd c -- }

extern FPuts { fd s -- }

extern Getc { -- c }

extern iserr { v -- err }

extern addoverflow { n1 n2 -- overflow res }

extern bitget { v bit -- bitout }

extern bitset { v bit -- valout }

extern bitclear { v bit -- valout }
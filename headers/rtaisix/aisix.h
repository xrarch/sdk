extern Main { ... -- ret }

extern Abort { ... fmt -- }

extern FPutc { fd c -- }

extern Open { path mode -- fd }

extern Close { fd -- ok }

extern Write { buf len fd -- bytes }

extern Read { buf len fd -- bytes }

extern Spawn { ... path -- pid }

extern VSpawn { argcn argvt path -- pid }

extern Exit { ret -- }

extern FDup { fd1 -- fd2 }

extern SetTTYIgnore { ign -- ok }

extern Readline { s max -- eof }

extern NewProcess { path fd0 fd1 fd2 mode udatavec udatac -- pid }

const STDIN 0
const STDOUT 1
const STDERR 2

const O_READ 1
const O_WRITE 2
const O_RW (O_READ O_WRITE |)

const NP_INHERIT 0
const NP_SPECIFY 1

const TTYI_ALL 0
const TTYI_IGN 1
const TTYI_CHILD_ALL 0x100
const TTYI_CHILD_IGN 0x200

struct UDVec
	4 Ptr
	4 Size
endstruct

const	EPERM	1
const	ENOENT	2
const	ESRCH	3
const	EINTR	4
const	EIO		5
const	ENXIO	6
const	E2BIG	7
const	ENOEXEC	8
const	EBADF	9
const	ECHILD	10
const	EAGAIN	11
const	ENOMEM	12
const	EACCES	13
const	ENOTBLK	15
const	EBUSY	16
const	EEXIST	17
const	EXDEV	18
const	ENODEV	19
const	ENOTDIR	20
const	EISDIR	21
const	EINVAL	22
const	ENFILE	23
const	EMFILE	24
const	ENOTTY	25
const	ETXTBSY	26
const	EFBIG	27
const	ENOSPC	28
const	ESPIPE	29
const	EROFS	30
const	EMLINK	31
const	EPIPE	32
const	EFAULT	33

const	-EPERM	-1
const	-ENOENT	-2
const	-ESRCH	-3
const	-EINTR	-4
const	-EIO	-5
const	-ENXIO	-6
const	-E2BIG	-7
const	-ENOEXEC	-8
const	-EBADF	-9
const	-ECHILD	-10
const	-EAGAIN	-11
const	-ENOMEM	-12
const	-EACCES	-13
const	-ENOTBLK	-15
const	-EBUSY	-16
const	-EEXIST	-17
const	-EXDEV	-18
const	-ENODEV	-19
const	-ENOTDIR	-20
const	-EISDIR	-21
const	-EINVAL	-22
const	-ENFILE	-23
const	-EMFILE	-24
const	-ENOTTY	-25
const	-ETXTBSY	-26
const	-EFBIG	-27
const	-ENOSPC	-28
const	-ESPIPE	-29
const	-EROFS	-30
const	-EMLINK	-31
const	-EPIPE	-32
const	-EBADSYS	-33

externptr ErrorNames
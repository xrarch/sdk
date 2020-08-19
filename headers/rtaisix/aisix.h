extern Main { ... -- ret }

extern Abort { ... fmt -- }

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

extern Wait { -- pid ret }

extern SetUID { uid -- ok }

extern GetPID { -- pid }

extern GetUID { -- uid }

extern GetEUID { -- euid }

extern ReadDir { dirent fd -- ok }

extern PStat { stat path -- ok }

extern FStat { stat fd -- ok }

extern Chdir { path -- ok }

struct Stat
	4 Mode
	4 UID
	4 GID
	4 Size
	4 Type
	4 ATime
	4 MTime
	4 CTime
	32 Reserved
endstruct

const STDIN 0
const STDOUT 1
const STDERR 2

const O_READ 1
const O_WRITE 2
const O_RW (O_READ O_WRITE |)
const O_TRUNC 4

const NP_INHERIT 0
const NP_SPECIFY 1

const VNODE_FILE 1
const VNODE_DIR 2
const VNODE_CHAR 3
const VNODE_BLOCK 4

const WORLD_X 1
const WORLD_W 2
const WORLD_R 4

const GROUP_X 8
const GROUP_W 16
const GROUP_R 32

const OWNER_X 64
const OWNER_W 128
const OWNER_R 256

const SUID 512

const XMASK 73

const TTYI_ALL 0
const TTYI_IGN 1
const TTYI_CHILD_ALL 0x100
const TTYI_CHILD_IGN 0x200

struct UDVec
	4 Ptr
	4 Size
endstruct

struct Dirent
	256 Name
	32 Reserved
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
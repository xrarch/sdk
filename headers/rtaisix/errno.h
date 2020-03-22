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
const	-EFAULT	-33

table aisix_errno
	"Operation succeeded"
	"Operation not permitted"
	"No such file or directory"
	"No such process"
	"Interrupted system call"
	"I/O error"
	"Missing device"
	"Argument list too long"
	"Exec format error"
	"Bad file number"
	"No child processes"
	"Try again"
	"Out of memory"
	"Permission denied"
	"Not supported by device"
	"Device or resource busy"
	"File exists"
	"Cross-device link"
	"No such device"
	"Not a directory"
	"Is a directory"
	"Invalid argument"
	"File table overflow"
	"Too many open files"
	"Not a typewriter"
	"Text file busy"
	"File too large"
	"No space left on device"
	"Illegal seek"
	"Read-only filesystem"
	"Too many links"
	"Broken pipe"
	"Bad address"
endtable
#include "hev-socks5-tunnel.h"
#include <sys/kern_control.h>
#include <sys/sys_domain.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/ucred.h>
#include <net/if_utun.h>
#include <sys/ioctl.h>

// Макрос _IOWR в Swift не импортируется
static const unsigned long BYPEN_CTLIOCGINFO = CTLIOCGINFO;

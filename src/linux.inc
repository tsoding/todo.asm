SYS_read equ 0
SYS_write equ 1
SYS_exit equ 60
SYS_socket equ 41
SYS_accept equ 43
SYS_bind equ 49
SYS_listen equ 50
SYS_close equ 3
SYS_setsockopt equ 54

AF_INET equ 2
SOCK_STREAM equ 1
INADDR_ANY equ 0

SOL_SOCKET = 1
SO_REUSEADDR = 2
SO_REUSEPORT = 15

SOL_TCP = 6
TCP_NODELAY = 1

STDOUT equ 1
STDERR equ 2

EXIT_SUCCESS equ 0
EXIT_FAILURE equ 1

macro funcall2 func, a, b
{
    mov rdi, a
    mov rsi, b
    call func
}

macro funcall4 func, a, b, c, d
{
    mov rdi, a
    mov rsi, b
    mov rdx, c
    mov r10, d
    call func
}

macro syscall1 number, a
{
    mov rax, number
    mov rdi, a
    syscall
}

macro syscall2 number, a, b
{
    mov rax, number
    mov rdi, a
    mov rsi, b
    syscall
}

macro syscall3 number, a, b, c
{
    mov rax, number
    mov rdi, a
    mov rsi, b
    mov rdx, c
    syscall
}

macro syscall5 number, a, b, c, d, e
{
    mov rax, number
    mov rdi, a
    mov rsi, b
    mov rdx, c
    mov r10, d
    mov r8,  e
    syscall
}

macro write fd, buf, count
{
    syscall3 SYS_write, fd, buf, count
}

macro read fd, buf, count
{
    syscall3 SYS_read, fd, buf, count
}

macro close fd
{
    syscall1 SYS_close, fd
}

;; int socket(int domain, int type, int protocol);
macro socket domain, type, protocol
{
    mov rax, SYS_socket
    mov rdi, domain
    mov rsi, type
    mov rdx, protocol
    syscall
}

;; int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen);
macro bind sockfd, addr, addrlen
{
    syscall3 SYS_bind, sockfd, addr, addrlen
}

;;       int listen(int sockfd, int backlog);
macro listen sockfd, backlog
{
    syscall2 SYS_listen, sockfd, backlog
}

;; int accept(int sockfd, struct sockaddr *addr, socklen_t *addrlen);
macro accept sockfd, addr, addrlen
{
    syscall3 SYS_accept, sockfd, addr, addrlen
}

macro exit code
{
    mov rax, SYS_exit
    mov rdi, code
    syscall
}

struc servaddr_in
{
    .sin_family dw 0
    .sin_port   dw 0
    .sin_addr   dd 0
    .sin_zero   dq 0
}

; int setsockopt(int sockfd, int level, int optname, const void *optval, socklen_t optlen);
macro setsockopt sockfd, level, optname, optval, optlen
{
    syscall5 SYS_setsockopt, sockfd, level, optname, optval, optlen
}

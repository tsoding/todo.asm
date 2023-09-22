format ELF64 executable

include "linux.inc"

MAX_CONN equ 5
REQUEST_CAP equ 128*1024
TODO_SIZE equ 256
TODO_CAP equ 256

segment readable executable

include "memory.inc"

entry main
main:
    mov [todo_end_offset], 0

    write STDOUT, start, start_len

    write STDOUT, socket_trace_msg, socket_trace_msg_len
    socket AF_INET, SOCK_STREAM, 0
    cmp rax, 0
    jl .fatal_error
    mov qword [sockfd], rax

    setsockopt [sockfd], SOL_SOCKET, SO_REUSEADDR, enable, 4
    cmp rax, 0
    jl .fatal_error

    setsockopt [sockfd], SOL_SOCKET, SO_REUSEPORT, enable, 4
    cmp rax, 0
    jl .fatal_error

    write STDOUT, bind_trace_msg, bind_trace_msg_len
    mov word [servaddr.sin_family], AF_INET
    mov word [servaddr.sin_port], 14619
    mov dword [servaddr.sin_addr], INADDR_ANY
    bind [sockfd], servaddr.sin_family, sizeof_servaddr
    cmp rax, 0
    jl .fatal_error

    write STDOUT, listen_trace_msg, listen_trace_msg_len
    listen [sockfd], MAX_CONN
    cmp rax, 0
    jl .fatal_error

.next_request:
    write STDOUT, accept_trace_msg, accept_trace_msg_len
    accept [sockfd], cliaddr.sin_family, cliaddr_len
    cmp rax, 0
    jl .fatal_error

    mov qword [connfd], rax

    read [connfd], request, REQUEST_CAP
    cmp rax, 0
    jl .fatal_error
    mov [request_len], rax

    mov [request_cur], request

    write STDOUT, [request_cur], [request_len]

    funcall4 starts_with, [request_cur], [request_len], get, get_len
    cmp rax, 0
    jg .handle_get_method

    funcall4 starts_with, [request_cur], [request_len], post, post_len
    cmp rax, 0
    jg .handle_post_method

    funcall4 starts_with, [request_cur], [request_len], put, put_len
    cmp rax, 0
    jg .handle_put_method

    funcall4 starts_with, [request_cur], [request_len], delete, delete_len
    cmp rax, 0
    jg .handle_delete_method

    jmp .serve_error_405

.handle_get_method:
    add [request_cur], get_len
    sub [request_len], get_len

    funcall4 starts_with, [request_cur], [request_len], index_route, index_route_len
    call starts_with
    cmp rax, 0
    jg .serve_index_page

    funcall4 starts_with, [request_cur], [request_len], index_route_alt, index_route_alt_len
    call starts_with
    cmp rax, 0
    jg .process_get_new_todo

    jmp .serve_error_404

.handle_post_method:
    add [request_cur], post_len
    sub [request_len], post_len

    funcall4 starts_with, [request_cur], [request_len], index_route, index_route_len
    cmp rax, 0
    jg .process_post_new_todo
    jmp .serve_error_404

.handle_put_method:
    add [request_cur], put_len
    sub [request_len], put_len
    jmp .serve_error_405

.handle_delete_method:
    add [request_cur], delete_len
    sub [request_len], delete_len

    cmp [request_len], 0
    jle .serve_error_400

    mov rbx, [request_cur]
    mov al, byte [rbx]
    cmp al, '/'
    jne .serve_error_400
    add [request_cur], 1
    sub [request_len], 1

    cmp [request_len], 0
    jle .serve_error_404

    mov rdi, [request_cur]
    mov rsi, [request_len]
    call parse_uint
    mov rdi, rax
    call delete_todo
    jmp .serve_index_page

.serve_index_page:
    write [connfd], index_page_response, index_page_response_len
    write [connfd], index_page_header, index_page_header_len
    call render_todos_as_html
    write [connfd], index_page_footer, index_page_footer_len
    close [connfd]
    jmp .next_request

.serve_error_400:
    write [connfd], error_400, error_400_len
    close [connfd]
    jmp .next_request

.serve_error_404:
    write [connfd], error_404, error_404_len
    close [connfd]
    jmp .next_request

.serve_error_405:
    write [connfd], error_405, error_405_len
    close [connfd]
    jmp .next_request

.process_post_new_todo:
    call drop_http_header
    cmp rax, 0
    je .serve_error_400

    funcall2 add_todo, [request_cur], [request_len]
    jmp .serve_index_page

.process_get_new_todo:
    write STDOUT, alt_trace_msg, alt_trace_msg_len

    mov rdi, request+get_len
    mov rsi, [request_len]
    sub rsi, get_len
    mov rdx, 32
    call find_char
    cmp rax, 0
    je .invalid_header ;; I have no idea if this is correct sry

    mov rdi, request+get_len+7
    mov rsi, rax
    sub rsi, request+get_len+7
    call add_todo
    jmp .serve_index_page

.invalid_header:
xor rax, rax
ret

.shutdown:
    write STDOUT, ok_msg, ok_msg_len
    close [connfd]
    close [sockfd]
    exit 0

.fatal_error:
    write STDERR, error_msg, error_msg_len
    close [connfd]
    close [sockfd]
    exit 1

drop_http_header:
.next_line:
    funcall4 starts_with, [request_cur], [request_len], clrs, 2
    cmp rax, 0
    jg .reached_end

    funcall3 find_char, [request_cur], [request_len], 10
    cmp rax, 0
    je .invalid_header

    mov rsi, rax
    sub rsi, [request_cur]
    inc rsi
    add [request_cur], rsi
    sub [request_len], rsi

    jmp .next_line

.reached_end:
    add [request_cur], 2
    sub [request_len], 2
    mov rax, 1
    ret

.invalid_header:
    xor rax, rax
    ret

;; rdi - size_t index
delete_todo:
   mov rax, TODO_SIZE
   mul rdi
   cmp rax, [todo_end_offset]
   jge .overflow

   ;; ****** ****** ******
   ;; ^      ^             ^
   ;; dst    src           end
   ;;
   ;; count = end - src

   mov rdi, todo_begin
   add rdi, rax
   mov rsi, todo_begin
   add rsi, rax
   add rsi, TODO_SIZE
   mov rdx, todo_begin
   add rdx, [todo_end_offset]
   sub rdx, rsi
   call memcpy

   sub [todo_end_offset], TODO_SIZE
.overflow:
   ret

;; rdi - void *buf
;; rsi - size_t count
add_todo:
   ;; Check for TODO capacity overflow
   cmp qword [todo_end_offset], TODO_SIZE*TODO_CAP
   jge .capacity_overflow

   ;; Truncate strings longer than 255
   ;; TODO: use conditional move instead?
   ;; TODO: the truncation limit should somehow depend on the TODO_SIZE
   cmp rsi, 0xFF
   jle .do_not_truncate
   mov rsi, 0xFF
.do_not_truncate:
   push rdi ;; void *buf [rsp+8]
   push rsi ;; size_t count [rsp]

   ;; +*******
   ;;  ^
   ;;  rdi
   mov rdi, todo_begin
   add rdi, [todo_end_offset]
   mov rdx, [rsp]
   mov byte [rdi], dl
   inc rdi
   mov rsi, [rsp+8]
   call memcpy

   add [todo_end_offset], TODO_SIZE

   pop rsi
   pop rdi
.capacity_overflow:
   ret

render_todos_as_html:
    push todo_begin
.next_todo:
    mov rax, [rsp]
    mov rbx, todo_begin
    add rbx, [todo_end_offset]
    cmp rax, rbx
    jge .done

    write [connfd], todo_header, todo_header_len

    mov rax, SYS_write
    mov rdi, [connfd]
    mov rsi, [rsp]
    xor rdx, rdx
    mov dl, byte [rsi]
    inc rsi
    syscall

    write [connfd], todo_footer, todo_footer_len
    mov rax, [rsp]
    add rax, TODO_SIZE
    mov [rsp], rax
    jmp .next_todo
.done:
    pop rax
    ret

;; db - 1 byte
;; dw - 2 byte
;; dd - 4 byte
;; dq - 8 byte

segment readable writeable

enable dd 1
sockfd dq -1
connfd dq -1
servaddr servaddr_in
sizeof_servaddr = $ - servaddr.sin_family
cliaddr servaddr_in
cliaddr_len dd sizeof_servaddr

clrs db 13, 10

error_400 db "HTTP/1.1 400 Bad Request", 13, 10
             db "Content-Type: text/html; charset=utf-8", 13, 10
             db "Connection: close", 13, 10
             db 13, 10
             db "<h1>Bad Request</h1>", 10
error_400_len = $ - error_400

error_404 db "HTTP/1.1 404 Not found", 13, 10
             db "Content-Type: text/html; charset=utf-8", 13, 10
             db "Connection: close", 13, 10
             db 13, 10
             db "<h1>Page not found</h1>", 10
error_404_len = $ - error_404

error_405 db "HTTP/1.1 405 Method Not Allowed", 13, 10
             db "Content-Type: text/html; charset=utf-8", 13, 10
             db "Connection: close", 13, 10
             db 13, 10
             db "<h1>Method not Allowed</h1>", 10
error_405_len = $ - error_405

index_page_response db "HTTP/1.1 200 OK", 13, 10
                    db "Content-Type: text/html; charset=utf-8", 13, 10
                    db "Connection: close", 13, 10
                    db 13, 10
index_page_response_len = $ - index_page_response
index_page_header db "<h1>To-Do</h1>", 10
                  db "<ul>", 10
index_page_header_len = $ - index_page_header
index_page_footer db "</ul>", 10
                  db "<form method='get'>", 10
                  db "  <input type='text' name='todo'>", 10
                  db "  <input type='submit', value='add'>", 10
                  db "</form>", 10
index_page_footer_len = $ - index_page_footer
todo_header db "  <li>"
todo_header_len = $ - todo_header
todo_footer db "</li>", 10
todo_footer_len = $ - todo_footer

get db "GET "
get_len = $ - get
post db "POST "
post_len = $ - post
put db "PUT "
put_len = $ - put
delete db "DELETE "
delete_len = $ - delete

index_route db "/ "
index_route_len = $ - index_route
index_route_alt db "/"
index_route_alt_len = $ - index_route_alt

include "messages.inc"

request_len rq 1
request_cur rq 1
request     rb REQUEST_CAP

;; ********************
;; ^
;;       ^
todo_begin rb TODO_SIZE*TODO_CAP
todo_end_offset rq 1

;; Routes:
;; GET /
;; POST /<text>
;; DELETE /<id>

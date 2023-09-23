format ELF64 executable

include "linux.inc"

MAX_CONN equ 5
REQUEST_CAP equ 128*1024
TODO_SIZE equ 256
TODO_CAP equ 256

segment readable executable

include "utils.inc"

entry main
main:
    call load_todos

    funcall2 write_cstr, STDOUT, start

    funcall2 write_cstr, STDOUT, socket_trace_msg
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

    funcall2 write_cstr, STDOUT, bind_trace_msg
    mov word [servaddr.sin_family], AF_INET
    mov word [servaddr.sin_port], 14619
    mov dword [servaddr.sin_addr], INADDR_ANY
    bind [sockfd], servaddr.sin_family, sizeof_servaddr
    cmp rax, 0
    jl .fatal_error

    funcall2 write_cstr, STDOUT, listen_trace_msg
    listen [sockfd], MAX_CONN
    cmp rax, 0
    jl .fatal_error

.next_request:
    funcall2 write_cstr, STDOUT, accept_trace_msg
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

    jmp .serve_error_405

.handle_get_method:
    add [request_cur], get_len
    sub [request_len], get_len

    funcall4 starts_with, [request_cur], [request_len], index_route, index_route_len
    call starts_with
    cmp rax, 0
    jg .serve_index_page

    jmp .serve_error_404

.handle_post_method:
    add [request_cur], post_len
    sub [request_len], post_len

    funcall4 starts_with, [request_cur], [request_len], index_route, index_route_len
    cmp rax, 0
    jg .process_add_or_delete_todo_post

    funcall4 starts_with, [request_cur], [request_len], shutdown_route, shutdown_route_len
    cmp rax, 0
    jg .process_shutdown

    jmp .serve_error_404

.process_shutdown:
    funcall2 write_cstr, [connfd], shutdown_response
    jmp .shutdown

.process_add_or_delete_todo_post:
    call drop_http_header
    cmp rax, 0
    je .serve_error_400

    funcall4 starts_with, [request_cur], [request_len], todo_form_data_prefix, todo_form_data_prefix_len
    cmp rax, 0
    jg .add_new_todo_and_serve_index_page

    funcall4 starts_with, [request_cur], [request_len], delete_form_data_prefix, delete_form_data_prefix_len
    cmp rax, 0
    jg .delete_todo_and_serve_index_page

    jmp .serve_error_400

.serve_index_page:
    funcall2 write_cstr, [connfd], index_page_response
    funcall2 write_cstr, [connfd], index_page_header
    call render_todos_as_html
    funcall2 write_cstr, [connfd], index_page_footer
    close [connfd]
    jmp .next_request

.serve_error_400:
    funcall2 write_cstr, [connfd], error_400
    close [connfd]
    jmp .next_request

.serve_error_404:
    funcall2 write_cstr, [connfd], error_404
    close [connfd]
    jmp .next_request

.serve_error_405:
    funcall2 write_cstr, [connfd], error_405
    close [connfd]
    jmp .next_request

.add_new_todo_and_serve_index_page:
    add [request_cur], todo_form_data_prefix_len
    sub [request_len], todo_form_data_prefix_len

    funcall2 add_todo, [request_cur], [request_len]
    call save_todos
    jmp .serve_index_page

.delete_todo_and_serve_index_page:
    add [request_cur], delete_form_data_prefix_len
    sub [request_len], delete_form_data_prefix_len

    funcall2 parse_uint, [request_cur], [request_len]
    mov rdi, rax
    call delete_todo
    call save_todos
    jmp .serve_index_page

.shutdown:
    funcall2 write_cstr, STDOUT, ok_msg
    close [connfd]
    close [sockfd]
    exit 0

.fatal_error:
    funcall2 write_cstr, STDERR, error_msg
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

load_todos:
   ;; [rsp+8] - fd
   ;; [rsp]   - st_size

   sub rsp, 16
   mov qword [rsp+8], -1
   mov qword [rsp], 0

   open todo_db_file_path, O_RDONLY, 0
   cmp rax, 0
   jl .error
   mov [rsp+8], rax

   fstat64 [rsp+8], statbuf
   cmp rax, 0
   jl .error

   mov rax, statbuf
   add rax, stat64.st_size
   mov rax, [rax]
   mov [rsp], rax

   ;; Check if the size of db is divisible by TODO_SIZE
   mov rcx, TODO_SIZE
   div rcx
   cmp rdx, 0
   jne .error

   ;; Truncate the size to supported TODO_CAP
   mov rcx, TODO_CAP*TODO_SIZE
   mov rax, [rsp]
   cmp rax, rcx
   cmovg rax, rcx
   mov [rsp], rax

   ;; Read the entire db from file system
   read [rsp+8], todo_begin, [rsp]
   mov rax, [rsp]
   mov [todo_end_offset], rax

.error:
   close [rsp+8]
   add rsp, 16
   ret

save_todos:
   open todo_db_file_path, O_CREAT or O_WRONLY or O_TRUNC, 420
   cmp rax, 0
   jl .fail
   push rax
   write qword [rsp], todo_begin, [todo_end_offset]
   close qword [rsp]
   pop rax
.fail:
   ret

;; TODO: sanitize the input to prevent XSS
;; rdi - void *buf
;; rsi - size_t count
add_todo:
   ;; Check for TODO capacity overflow
   cmp qword [todo_end_offset], TODO_SIZE*TODO_CAP
   jge .capacity_overflow

   ;; Truncate strings longer than 255
   mov rax, 0xFF
   cmp rsi, rax
   cmovg rsi, rax

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
   mov rax, 0
   ret
.capacity_overflow:
   mov rax, 1
   ret

render_todos_as_html:
    push 0
    push todo_begin
.next_todo:
    mov rax, [rsp]
    mov rbx, todo_begin
    add rbx, [todo_end_offset]
    cmp rax, rbx
    jge .done

    funcall2 write_cstr, [connfd], todo_header
    funcall2 write_cstr, [connfd], delete_button_prefix
    funcall2 write_uint, [connfd], [rsp+8]
    funcall2 write_cstr, [connfd], delete_button_suffix

    mov rax, SYS_write
    mov rdi, [connfd]
    mov rsi, [rsp]
    xor rdx, rdx
    mov dl, byte [rsi]
    inc rsi
    syscall

    funcall2 write_cstr, [connfd], todo_footer
    mov rax, [rsp]
    add rax, TODO_SIZE
    mov [rsp], rax
    inc qword [rsp+8]
    jmp .next_todo
.done:
    pop rax
    pop rax
    ret

segment readable writeable

enable dd 1
sockfd dq -1
connfd dq -1
servaddr servaddr_in
sizeof_servaddr = $ - servaddr.sin_family
cliaddr servaddr_in
cliaddr_len dd sizeof_servaddr

clrs db 13, 10

error_400            db "HTTP/1.1 400 Bad Request", 13, 10
                     db "Content-Type: text/html; charset=utf-8", 13, 10
                     db "Connection: close", 13, 10
                     db 13, 10
                     db "<h1>Bad Request</h1>", 10
                     db "<a href='/'>Back to Home</a>", 10
                     db 0
error_404            db "HTTP/1.1 404 Not found", 13, 10
                     db "Content-Type: text/html; charset=utf-8", 13, 10
                     db "Connection: close", 13, 10
                     db 13, 10
                     db "<h1>Page not found</h1>", 10
                     db "<a href='/'>Back to Home</a>", 10
                     db 0
error_405            db "HTTP/1.1 405 Method Not Allowed", 13, 10
                     db "Content-Type: text/html; charset=utf-8", 13, 10
                     db "Connection: close", 13, 10
                     db 13, 10
                     db "<h1>Method not Allowed</h1>", 10
                     db "<a href='/'>Back to Home</a>", 10
                     db 0
index_page_response  db "HTTP/1.1 200 OK", 13, 10
                     db "Content-Type: text/html; charset=utf-8", 13, 10
                     db "Connection: close", 13, 10
                     db 13, 10
                     db 0
index_page_header    db "<h1>To-Do</h1>", 10
                     db "<ul>", 10
                     db 0
index_page_footer    db "  <li>", 10
                     db "    <form style='display: inline' method='post' action='/' enctype='text/plain'>", 10
                     db "        <input style='width: 25px' type='submit' value='+'>", 10
                     db "        <input type='text' name='todo' autofocus>", 10
                     db "    </form>", 10
                     db "  </li>", 10
                     db "</ul>", 10
                     db "<form method='post' action='/shutdown'>", 10
                     db "    <input type='submit' value='shutdown'>", 10
                     db "</form>", 10
                     db 0
todo_header          db "  <li>"
                     db 0
todo_footer          db "</li>", 10
                     db 0
delete_button_prefix db "<form style='display: inline' method='post' action='/'>"
                     db "<button style='width: 25px' type='submit' name='delete' value='"
                     db 0
delete_button_suffix db "'>x</button></form> "
                     db 0
shutdown_response    db "HTTP/1.1 200 OK", 13, 10
                     db "Content-Type: text/html; charset=utf-8", 13, 10
                     db "Connection: close", 13, 10
                     db 13, 10
                     db "<h1>Shutting down the server...</h1>", 10
                     db "Please close this tab"
                     db 0

todo_form_data_prefix db "todo="
todo_form_data_prefix_len = $ - todo_form_data_prefix
delete_form_data_prefix db "delete="
delete_form_data_prefix_len = $ - delete_form_data_prefix

get db "GET "
get_len = $ - get
post db "POST "
post_len = $ - post

index_route db "/ "
index_route_len = $ - index_route

shutdown_route db "/shutdown "
shutdown_route_len = $ - shutdown_route

start            db "INFO: Starting Web Server!", 10, 0
ok_msg           db "INFO: OK!", 10, 0
socket_trace_msg db "INFO: Creating a socket...", 10, 0
bind_trace_msg   db "INFO: Binding the socket...", 10, 0
listen_trace_msg db "INFO: Listening to the socket...", 10, 0
accept_trace_msg db "INFO: Waiting for client connections...", 10, 0
error_msg        db "FATAL ERROR!", 10, 0

todo_db_file_path db "todo.db", 0

request_len rq 1
request_cur rq 1
request     rb REQUEST_CAP

;; [todo][todo][todo][todo][todo][todo]...
;;             ^
todo_begin rb TODO_SIZE*TODO_CAP
todo_end_offset rq 1

statbuf rb sizeof_stat64

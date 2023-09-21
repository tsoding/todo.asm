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
    funcall2 add_todo, coffee, coffee_len
    funcall2 add_todo, tea, tea_len
    funcall2 add_todo, milk, milk_len

    write STDOUT, start, start_len

    write STDOUT, socket_trace_msg, socket_trace_msg_len
    socket AF_INET, SOCK_STREAM, 0
    cmp rax, 0
    jl .error
    mov qword [sockfd], rax

    write STDOUT, bind_trace_msg, bind_trace_msg_len
    mov word [servaddr.sin_family], AF_INET
    mov word [servaddr.sin_port], 14619
    mov dword [servaddr.sin_addr], INADDR_ANY
    bind [sockfd], servaddr.sin_family, sizeof_servaddr
    cmp rax, 0
    jl .error

    write STDOUT, listen_trace_msg, listen_trace_msg_len
    listen [sockfd], MAX_CONN
    cmp rax, 0
    jl .error

.next_request:
    write STDOUT, accept_trace_msg, accept_trace_msg_len
    accept [sockfd], cliaddr.sin_family, cliaddr_len
    cmp rax, 0
    jl .error

    mov qword [connfd], rax

    read [connfd], request, REQUEST_CAP
    cmp rax, 0
    jl .error
    mov [request_len], rax

    write STDOUT, request, [request_len]

    funcall4 starts_with, request, [request_len], get, get_len
    cmp rax, 0
    jg .handle_get_method

    funcall4 starts_with, request, [request_len], post, post_len
    cmp rax, 0
    jg .handle_post_method

    funcall4 starts_with, request, [request_len], put, put_len
    cmp rax, 0
    jg .handle_put_method

    write [connfd], response_405, response_405_len
    close [connfd]
    jmp .next_request

.handle_get_method:
    mov rdi, request + get_len
    mov rsi, [request_len]
    sub rsi, get_len
    mov rdx, index_route
    mov r10, index_route_len
    call starts_with
    cmp rax, 0
    jg .handle_get_index

    write [connfd], response_404, response_404_len
    close [connfd]
    jmp .next_request

.handle_post_method:
    write [connfd], post_method_response, post_method_response_len
    close [connfd]
    jmp .next_request

.handle_put_method:
    write [connfd], put_method_response, put_method_response_len
    close [connfd]
    jmp .next_request

.handle_get_index:
    write [connfd], index_page_response, index_page_response_len
    write [connfd], index_page_header, index_page_header_len
    call render_todos_as_html
    write [connfd], index_page_footer, index_page_footer_len
    close [connfd]
    jmp .next_request

.shutdown:
    write STDOUT, ok_msg, ok_msg_len
    close [connfd]
    close [sockfd]
    exit 0

.error:
    write STDERR, error_msg, error_msg_len
    close [connfd]
    close [sockfd]
    exit 1

;; rdi - buf
;; rsi - count
add_todo:
   ;; TODO: add check for todo capacity overflow

   ;; +*******
   ;;  ^
   ;;  rax
   mov rax, todo_begin
   add rax, [todo_end_offset]
   mov rbx, rsi
   mov byte [rax], bl
   inc rax

   ;; dst:   [rax]
   ;; src:   [rdi]
   ;; count: bl
.next_byte:
   cmp bl, 0
   jle .done
   mov cl, byte [rdi]
   mov byte[rax], cl
   inc rax
   inc rdi
   dec bl
   jmp .next_byte
.done:
   add [todo_end_offset], TODO_SIZE
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
    inc rsi
    xor rdx, rdx
    mov dl, byte [rsp]
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

sockfd dq -1
connfd dq -1
servaddr servaddr_in
sizeof_servaddr = $ - servaddr.sin_family
cliaddr servaddr_in
cliaddr_len dd sizeof_servaddr

response_404 db "HTTP/1.1 404 Not found", 13, 10
             db "Content-Type: text/html; charset=utf-8", 13, 10
             db "Connection: close", 13, 10
             db 13, 10
             db "<h1>Page not found</h1>", 10
response_404_len = $ - response_404

response_405 db "HTTP/1.1 405 Method Not Allowed", 13, 10
             db "Content-Type: text/html; charset=utf-8", 13, 10
             db "Connection: close", 13, 10
             db 13, 10
             db "<h1>Method not Allowed</h1>", 10
response_405_len = $ - response_405

index_page_response db "HTTP/1.1 200 OK", 13, 10
                    db "Content-Type: text/html; charset=utf-8", 13, 10
                    db "Connection: close", 13, 10
                    db 13, 10
index_page_response_len = $ - index_page_response
index_page_header db "<h1>TODO</h1>", 10
                  db "<ul>", 10
index_page_header_len = $ - index_page_header
index_page_footer db "</ul>", 10
index_page_footer_len = $ - index_page_footer
todo_header db "  <li>"
todo_header_len = $ - todo_header
todo_footer db "</li>", 10
todo_footer_len = $ - todo_footer

post_method_response db "HTTP/1.1 200 OK", 13, 10
                     db "Content-Type: text/html; charset=utf-8", 13, 10
                     db "Connection: close", 13, 10
                     db 13, 10
                     db "<h1>POST</h1>", 10
post_method_response_len = $ - post_method_response

put_method_response db "HTTP/1.1 200 OK", 13, 10
                    db "Content-Type: text/html; charset=utf-8", 13, 10
                    db "Connection: close", 13, 10
                    db 13, 10
                    db "<h1>PUT</h1>", 10
put_method_response_len = $ - put_method_response

get db "GET "
get_len = $ - get
post db "POST "
post_len = $ - post
put db "PUT "
put_len = $ - put

coffee db "coffee"
coffee_len = $ - coffee
tea db "tea"
tea_len = $ - tea
milk db "milk"
milk_len = $ - milk

index_route db "/ "
index_route_len = $ - index_route

include "messages.inc"

request_len rq 1
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

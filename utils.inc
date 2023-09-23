;; Generally useful utility functions

;; Write an integer to a file
;;   rdi - int fd
;;   rsi - uint64_t int x
write_uint:
    test rsi, rsi
    jz .base_zero

    mov rcx, 10     ;; 10 literal for division
    mov rax, rsi    ;; keeping track of rsi in rax cause it's easier to div it like that
    mov r10, 0      ;; counter of how many digits we already converted
.next_digit:
    test rax, rax
    jz .done
    mov rdx, 0
    div rcx
    add rdx, '0'
    dec rsp
    mov byte [rsp], dl
    inc r10
    jmp .next_digit
.done:
    write rdi, rsp, r10
    add rsp, r10
    ret
.base_zero:
    dec rsp
    mov byte [rsp], '0'
    write rdi, rsp, 1
    inc rsp
    ret

;; Write a NULL-terminated string to a file
;;   rdi - int fd
;;   rsi - const char *s
write_cstr:
    push rsi
    push rdi
    mov rdi, rsi
    call strlen

    mov rdx, rax
    mov rax, SYS_write
    pop rdi
    pop rsi
    syscall
    ret

;; Compute the length of a NULL-terminated string
;;   rdi - const char *s
strlen:
    push rdi
    xor rax, rax
.next_char:
    mov al, byte [rdi]
    cmp rax, 0
    je .done

    inc rdi
    jmp .next_char
.done:
    pop rsi
    sub rdi, rsi
    mov rax, rdi
    ret

;; Parse unsigned integer from a sized string
;;   rdi - void *buf
;;   rsi - size_t n
parse_uint:
    xor rax, rax
    xor rbx, rbx
    mov rcx, 10
.next_digit:
    cmp rsi, 0
    jle .done

    mov bl, byte [rdi]
    cmp rbx, '0'
    jl .done
    cmp rbx, '9'
    jg .done
    sub rbx, '0'

    mul rcx
    add rax, rbx

    inc rdi
    dec rsi
    jmp .next_digit
.done:
    ret

;; Copy a chunk of memory
;;   rdi - void *dst
;;   rsi - void *src
;;   rdx - size_t n
memcpy:
.next_byte:
   cmp rdx, 0
   jle .done

   mov al, byte [rsi]
   mov byte [rdi], al

   inc rdi
   inc rsi
   dec rdx

   jmp .next_byte
.done:
   ret


;; Find a character with a sized string
;;   rdi - void *buf
;;   rsi - size_t n
;;   rdx - char c
find_char:
   cmp rsi, 0
   jle .not_found

   mov al, byte [rdi]
   cmp dl, al
   je .found

   inc rdi
   dec rsi
   jmp find_char

.not_found:
   xor rax, rax
   ret
.found:
   mov rax, rdi
   ret

;; Check if text starts with the prefix (both strings are sized)
;;   rdi - void *text
;;   rsi - size_t text_len
;;   rdx - void *prefix
;;   r10 - size_t prefix_len
starts_with:
    xor rax, rax
    xor rbx, rbx
.next_char:
    cmp rsi, 0
    jle .done
    cmp r10,0
    jle .done

    mov al, byte [rdi]
    mov bl, byte [rdx]
    cmp rax, rbx
    jne .done

    dec rsi
    inc rdi
    dec r10
    inc rdx
    jmp .next_char

.done:
    cmp r10, 0
    je .yes
.no:
    mov rax, 0
    ret
.yes:
    mov rax, 1
    ret

;; Subroutines for working with memory

;; rdi - void *dst
;; rsi - void *src
;; rdx - size_t n
memcpy:
.next_byte:
   cmp rdx, 0
   jle .done

   mov al, byte [rsi]
   mov byte[rdi], al

   inc rdi
   inc rsi
   dec rdx

   jmp .next_byte
.done:
   ret


;; rdi - void *buf
;; rsi - size_t n
;; rdx - char c
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

;; rdi - void *text
;; rsi - size_t text_len
;; rdx - void *prefix
;; r10 - size_t prefix_len
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

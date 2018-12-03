; YaxOS string routines.
bits 16

; Compares two strings at DS:SI and ES:DI, sets ZF.
string.compare:
    push ax
    push si
    push di

.loop:
    ; Load two bytes, compare
    mov ah, [ds:si]
    mov al, [es:di]

    inc si
    inc di

    ; Equal?
    cmp ah, al
    jnz .return

    ; Zero?
    test ah, ah
    jnz .loop

    ; Return
.return:
    pop di
    pop si
    pop ax
    ret

; Finds the length of a string at ES:DI.
; Returns CX.
string.length:
    push ax
    push di
    xor cx, cx

.loop:
    ; Load a char
    mov al, [es:di]
    inc di

    ; Zero?
    test al, al
    jz .done

    inc cx
    jmp .loop

    ; Done
.done:
    pop di
    pop ax
    ret

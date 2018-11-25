; YaxOS console routines
bits 16

; Default screen size
SCREEN_WIDTH    equ 80
SCREEN_HEIGHT   equ 25


; Clears the screen.
console.clearScreen:
    push ax
    push bx
    push cx
    push dx

    ; Simply print SCREEN_HEIGHT newlines and go to 0, 0.
    mov cx, SCREEN_HEIGHT
.loop:
    call console.newline

    ; Next?
    dec cx
    jnz .loop

    ; int 10h, 0x02 - set cursor position
    mov ah, 0x02

    ; page = 0
    xor bh, bh

    ; row, col = 0, 0
    xor dx, dx
    int 10h

    ; Restore the registers, done
    pop dx
    pop cx
    pop bx
    pop ax

    ret


; Prints an ASCIIZ string at DS:SI.
console.print:
    ; Preserve AX and SI.
    push ax
    push si

    ; int 10h, 0x0e - print character
    mov ah, 0x0e

.loop:
    ; Load a byte at DS:SI
    lodsb

    ; If it's zero, then we're done.
    test al, al
    jz .done

    ; Print
    int 10h

    ; Loop
    jmp .loop

.done:
    ; Restore AX and SI
    pop si
    pop ax
    ret


; Prints a newline.
console.newline:
    push ax
    mov ax, 0x0e0d
    int 10h

    mov al, 0x0a
    int 10h

    pop ax
    ret


; Prints a hexadecimal number in EAX.
console.printHex:
    ; Preserve the registers
    push eax
    push edx
    push cx

    ; Preserve EAX
    mov edx, eax

    ; We need to print 8 hex digits.
    mov cx, 8

.digit:
    ; Shift EAX until AL contains the upper nibble of EDX.
    mov eax, edx
    shr eax, 28

    ; int 10h, 0x0e - print character
    mov ah, 0x0e

    ; ASCII digits
    add al, '0'

    ; Do we need to adjust AL?
    cmp al, 0x3a
    jnae .skipAdjust

    ; ASCII offset
    add al, 'a'-0x3a

.skipAdjust:
    ; Print the character
    int 10h

    ; Shift EDX to make the second nibble highest.
    shl edx, 4

    ; More digits?
    dec cx
    jnz .digit

    ; Done
    pop cx
    pop edx
    pop eax
    ret


; Prints a formatted string at DS:SI.
; EDX is used as the number if "%x" is encountered.
console.printf:
    ; Preserve EAX and SI.
    push eax
    push si

    ; int 10h, 0x0e - print a character
    mov ah, 0x0e
.loop:
    ; Load a character
    lodsb

    ; Zero?
    test al, al
    jz .done

    ; Percent
    cmp al, '%'
    jz .format

    ; Otherwise, just output it
    int 10h
    jmp .loop

.format:
    ; Load another character
    lodsb

    ; Is it an escaped percent sign?
    cmp al, '%'
    jz .percent

    ; %x (hex)
    cmp al, 'x'
    jz .hex

    ; Continue
    jmp .loop

.percent:
    ; Print a percent character
    mov al, '%'
    int 10h
    jmp .loop

.hex:
    ; Print a hexadecimal number
    push eax
    mov eax, edx
    call console.printHex
    pop eax
    jmp .loop

.done:
    ; Done, restore the registers
    pop si
    pop eax
    ret

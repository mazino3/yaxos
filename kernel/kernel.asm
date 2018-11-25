; YaxOS kernel
org 0
bits 16

; tohloo-loader has placed us at 17c0:0000.
jmp init

; Include the subroutines
%include "console.asm"
%include "kalloc.asm"

; Boot status
bootStatus:
    .driveNumber db 0

init:
    ; Initialize the segments
    mov ax, cs
    mov ds, ax

    ; Preserve the drive number
    mov [bootStatus.driveNumber], dl

    ; Init kalloc
    call kalloc.init

    ; Clear the screen
    call console.clearScreen

    xor edx, edx
    mov dl, [bootStatus.driveNumber]
    mov si, testMessage
    call console.printf

halt:
    ; Wait for an interrupt, halt again
    hlt
    jmp halt


testMessage db "Hello world from YaxOS! Drive number: %x.", 13, 10, 0

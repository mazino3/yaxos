; YaxOS kernel
org 0
bits 16

; tohloo-loader has placed us at 17c0:0000.
jmp init

; Include the subroutines
%include "console.asm"
%include "kalloc.asm"

init:
    ; Initialize the segments
    mov ax, cs
    mov ds, ax

    ; Init kalloc
    call kalloc.init

    ; Clear the screen
    call console.clearScreen

    mov edx, 0x1337cafe
    mov si, testMessage
    call console.printf

.loop:
    ; Try allocating memory
    mov cx, 1
    call kalloc.kalloc
    jc halt

    mov dx, fs
    shl edx, 16
    mov dx, di

    mov si, testMessage2
    call console.printf
    jmp .loop

halt:
    ; Wait for an interrupt, halt again
    hlt
    jmp halt


testMessage db "Hello world from YaxOS! Hex: %x.", 13, 10, 0
testMessage2 db "alloc seg:off %x.", 13, 10, 0

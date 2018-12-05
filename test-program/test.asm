; YaxOS test program
org 0

; Include the interrupt header.
%include "../include/interrupts.asm"

; Initialize the data segment
mov ax, cs
mov ds, ax

; console.print syscall
mov si, helloWorld
mov bp, CONSOLE_PRINT
int INTERRUPT_CONSOLE

; Return
retf


helloWorld db "Hello world from the YaxOS test program!", 13, 10, 0

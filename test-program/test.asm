; YaxOS test program
org 0

; Initialize the data segment
mov ax, cs
mov ds, ax

; console.print syscall
mov si, helloWorld
mov bp, 0
int 20h

; Return
retf


helloWorld db "Hello world from the YaxOS test program!", 13, 10, 0

; YaxOS test program
org 0

; Set the segments, etc
mov ax, cs
mov ds, ax

mov ah, 0x0e
mov al, 0x20

loop:
    int 10h
    inc al
    cmp al, 0x7f
    jnz loop

retf

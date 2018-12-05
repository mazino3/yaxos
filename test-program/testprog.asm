; YaxOS test program
org 0

; Include the interrupt header.
%include "../include/interrupts.asm"

; Initialize the data segments.
mov ax, cs
mov ds, ax
mov es, ax

; console.print syscall
mov si, helloWorld
mov bp, CONSOLE_PRINT
int INTERRUPT_CONSOLE

; Try listing the current directory
mov bp, SHELL_ENUM_INIT
int INTERRUPT_SHELL

; SI is the string to print, the filenames will be copied into ES:DI.
mov si, filenamePrefix
mov di, filename

; List files
listFiles:
    ; Next file
    mov bp, SHELL_ENUM_NEXT
    int INTERRUPT_SHELL
    jc return

    ; Print the filename
    mov bp, CONSOLE_PRINT
    int INTERRUPT_CONSOLE

    ; Print a newline
    mov bp, CONSOLE_NEWLINE
    int INTERRUPT_CONSOLE

    ; Next
    jmp listFiles
return:
    ; Return
    retf


helloWorld db "Hello world from the YaxOS test program!", 13, 10, 0
filenamePrefix db "Found file: "
filename times 13 db 0

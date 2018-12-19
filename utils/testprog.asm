; YaxOS test program
org 0

; Include the interrupt header.
%include "../include/interrupts.asm"

; Initialize the data segments.
mov ax, cs
mov ds, ax
mov es, ax

; Preserve BP (the command line pointer).
mov bx, bp

; console.print syscall
mov si, helloWorld
mov bp, CONSOLE_PRINT
int INTERRUPT_CONSOLE

; Print the command line if it exists
test bx, bx
jz noCommandLine

; Copy the command line from FS:BX if it exists.
mov si, commandLine
copyCommandLine:
    mov al, [fs:bx]
    mov [si], al
    inc bx
    inc si
    test al, al
    jnz copyCommandLine

; Print the command line
mov si, commandLinePrefix
int INTERRUPT_CONSOLE

mov bp, CONSOLE_NEWLINE
int INTERRUPT_CONSOLE

noCommandLine:

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

commandLinePrefix db "Command line: "
commandLine times 256 db 0

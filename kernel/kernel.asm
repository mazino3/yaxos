; YaxOS kernel
org 0
bits 16

; tohloo-loader has placed us at 17c0:0000.
KERNEL_SEGMENT equ 0x17c0

; Jump to the init code.
jmp kernel.init

; Include the subroutines
%include "console.asm"
%include "kalloc.asm"
%include "fat32.asm"
%include "shell.asm"

; Boot status
kernel.bootStatus:
    .driveNumber db 0

kernel.init:
    ; Initialize the segments
    mov ax, cs
    mov ds, ax
    mov es, ax

    ; Preserve the drive number
    mov [kernel.bootStatus.driveNumber], dl

    ; Init kalloc
    call kalloc.init

    ; Clear the screen
    call console.clearScreen

    ; Print the boot message
    mov si, kernel.bootMessage
    call console.print

    ; Register the system calls
    mov bl, 0x20
    mov dx, kernel.systemInterrupt
    call kernel.registerInterrupt

    mov bl, 0x21
    mov dx, kernel.consoleInterrupt
    call kernel.registerInterrupt

    ; Restore the drive number
    mov dl, [kernel.bootStatus.driveNumber]

.mount:
    ; Try allocating a context structure for working with FAT
    call fat32.context.alloc
    jc kernel.error

    ; Print the mount message
    mov si, kernel.mountMessage
    call console.print

    ; DL already contains the drive number we want, clear DH.
    xor dh, dh

.nextPart:
    ; Log
    mov si, kernel.readPartMessage
    call console.print

    ; Read the partition entry DH on drive DL.
    call fat32.readPartition
    jc kernel.error
    jz .skip

    ; Found!
    ; Preserve EDX
    mov ebx, edx

    ; Copy the LBA number into EDX for printf.
    mov edx, eax
    mov si, kernel.partFoundMessage
    call console.printf

    ; Restore EDX
    mov edx, ebx

    ; Try mounting the partition
    call fat32.mount
    jc .mountError

    mov si, kernel.mountSuccessMessage
    call console.print

    ; Initialize the shell
    call shell.init

    ; Jump into the shell
    jmp shell.mainLoop

    ; Next?
.skip:
    inc dh
    cmp dh, 4
    jnz .nextPart

.notFound:
    mov si, kernel.partNotFoundMessage
    call console.print
    jmp kernel.halt

.mountError:
    mov si, kernel.mountErrorMessage
    call console.print
    jmp kernel.halt

kernel.error:
    mov si, kernel.errorMessage
    call console.print

kernel.halt:
    ; Wait for an interrupt, halt again
    hlt
    jmp kernel.halt


; Registers an interrupt handler.
; BL is the interrupt number.
; DX is the CS offset.
kernel.registerInterrupt:
    push ax
    push bx
    push es

    ; Disable interrupts
    cli

    ; IVT segment
    mov ax, 0
    mov es, ax

    ; BH = 0
    xor bh, bh

    ; BX *= 4
    shl bx, 2

    ; Offset
    mov [es:bx], dx

    ; Segment
    mov [es:bx+2], cs

    ; Enable interrupts
    sti

    ; Done, return
    pop es
    pop bx
    pop ax
    ret

; The kernel system call
; BP specifies the function to call.
; 0 - kalloc
; 1 - kfree
kernel.systemInterrupt:
    ; Preserve DS
    push ds

    ; Set DS to the kernel segment.
    push word KERNEL_SEGMENT
    pop ds

    ; Which function?
    cmp bp, 0
    jz .kalloc
    cmp bp, 1
    jz .kfree

    ; Invalid, set carry.
    stc
.done:
    ; Restore DS
    pop ds
    iret

.kalloc:
    call kalloc.kalloc
    jmp .done
.kfree:
    call kalloc.kfree
    jmp .done


; The console I/O system call.
; BP specifies the function to call.
; 0 - print
; 1 - printf
; 2 - newline
; 3 - printChar
; 4 - readLine
kernel.consoleInterrupt:
    ; Which function?
    cmp bp, 0
    jz .print
    cmp bp, 1
    jz .printf
    cmp bp, 2
    jz .newline
    cmp bp, 3
    jz .printChar
    cmp bp, 4
    jz .readLine

    ; None of the above, set carry and return
    stc
    iret
.print:
    call console.print
    iret
.printf:
    call console.printf
    iret
.newline:
    call console.newline
    iret
.printChar:
    call console.printChar
    iret
.readLine:
    call console.readLine
    iret


kernel.bootMessage db "[+] kernel: booted!", 13, 10, 0
kernel.errorMessage db "[!] kernel: error, halting...", 13, 10, 0
kernel.mountMessage db "[+] kernel: looking for a partition...", 13, 10, 0
kernel.readPartMessage db "[.] kernel: reading partition", 13, 10, 0
kernel.partNotFoundMessage db "[!] kernel: no FAT32 partitions found!", 13, 10, 0
kernel.partFoundMessage db "[+] kernel: found a FAT32 partition at LBA %x, mounting...", 13, 10, 0
kernel.mountErrorMessage db "[!] kernel: couldn't mount the partition!", 13, 10, 0
kernel.mountSuccessMessage db "[+] kernel: mounted successfully", 13, 10, 0

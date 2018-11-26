; YaxOS kernel
org 0
bits 16

; tohloo-loader has placed us at 17c0:0000.
jmp init

; Include the subroutines
%include "console.asm"
%include "kalloc.asm"
%include "fat32.asm"

; Boot status
bootStatus:
    .driveNumber db 0

init:
    ; Initialize the segments
    mov ax, cs
    mov ds, ax
    mov es, ax

    ; Preserve the drive number
    mov [bootStatus.driveNumber], dl

    ; Init kalloc
    call kalloc.init

    ; Clear the screen
    call console.clearScreen

    ; Print the boot message
    mov si, bootMessage
    call console.print

.mount:
    ; Try allocating a context structure for working with FAT
    call fat32.context.alloc
    jc error

    ; Print the mount message
    mov si, mountMessage
    call console.print

    ; DL already contains the drive number we want, clear DH.
    xor dh, dh

.nextPart:
    ; Log
    mov si, readPartMessage
    call console.print

    ; Read the partition entry DH on drive DL.
    call fat32.readPartition
    jc error
    jz .skip

    ; Found!
    ; Preserve EDX
    mov ebx, edx

    ; Copy the LBA number into EDX for printf.
    mov edx, eax
    mov si, partFoundMessage
    call console.printf

    ; Restore EDX
    mov edx, ebx

    ; Try mounting the partition
    call fat32.mount
    jc .mountError

    ; Done, test
    mov eax, [fs:FATContext.rootCluster]
    call fat32.readFAT
    jc error

    mov edx, eax
    mov si, testMessage
    call console.printf
    jmp halt

    ; Next?
.skip:
    inc dh
    cmp dh, 4
    jnz .nextPart

.notFound:
    mov si, partNotFoundMessage
    call console.print
    jmp halt

.mountError:
    mov si, mountErrorMessage
    call console.print
    jmp halt


halt:
    ; Wait for an interrupt, halt again
    hlt
    jmp halt

error:
    ; Print the error message, halt
    mov si, errorMessage
    call console.print
    jmp halt


bootMessage db "[+] kernel: booted!", 13, 10, 0

errorMessage db "[!] kernel: error, halting...", 13, 10, 0
mountMessage db "[+] kernel: looking for a partition...", 13, 10, 0
readPartMessage db "[.] kernel: reading partition", 13, 10, 0
partNotFoundMessage db "[!] kernel: no FAT32 partitions found!", 13, 10, 0
partFoundMessage db "[+] kernel: found a FAT32 partition at LBA %x, mounting...", 13, 10, 0
mountErrorMessage db "[!] kernel: couldn't mount the partition!", 13, 10, 0

testMessage db "readFAT test: %x.", 13, 10, 0

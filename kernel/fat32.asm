; YaxOS - FAT32 driver
bits 16

; Partition structure
struc partition
    .boot       resb 1
    .startCHS   resb 3
    .systemId   resb 1
    .endCHS     resb 3
    .startLBA   resd 1
    .size       resd 1
endstruc

; Disk Address Packet
fat32._dap:
    .size       db 16
    .unused     db 0
    .numSectors dw 0
    .offset     dw 0
    .segment    dw 0
    .startLBA   dd 0
    .startLBAHi dd 0


; Reads the EAX'th sector from the drive DL into the memory at FS:0000.
; Returns with the carry set if the read was unsuccessful.
fat32.readSector:
    push eax
    push si

    ; Initialize the DAP
    mov [fat32._dap.startLBA], eax
    mov [fat32._dap.numSectors], word 1
    mov [fat32._dap.offset], word 0
    mov [fat32._dap.segment], fs
    mov si, fat32._dap

    ; int 13h, 0x42 - read sectors with DAP
    mov ah, 0x42
    int 13h

    pop si
    pop eax

    ret


; Checks if the DH'th partition on drive DL contains a FAT32 filesystem.
; Returns with the carry flag set on error.
; ZF is set if the partition type matches, clear otherwise.
fat32.checkPartition:
    push eax
    push bx
    push cx
    push fs

    ; Allocate a sector, make FS point to it.
    mov cx, 512
    call kalloc.kalloc

    ; On error, don't free memory that has not been allocated yet.
    jc .errorNoFree

    ; Read the first sector
    xor eax, eax
    call fat32.readSector
    jc .error

    ; Offset into the MBR
    xor bx, bx

    ; BX = DH*16, the size of a partition entry
    mov bl, dh
    shl bx, 4

    ; Offset to the partition entries
    add bx, 0x1be

    ; Read the system identifier of the partition.
    mov al, [fs:bx+partition.systemId]

.done:
    ; Free the buffer
    call kalloc.kfree

    ; Is the partition type FAT32 (set ZF).
    cmp al, 0x0c

    ; No carry
    clc

    jmp .return

.error:
    ; Release the memory we have allocated.
    call kalloc.kfree

.errorNoFree:
    stc

.return:
    pop fs
    pop cx
    pop bx
    pop eax
    ret

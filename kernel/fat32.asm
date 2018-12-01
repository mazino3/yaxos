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

; FAT32 BPB
struc FATBPB
    .jump               resb 3
    .oemId              resb 8
    .wBytesPerSector    resw 1
    .bSectorsPerCluster resb 1
    .wReservedSectors   resw 1
    .bNumFATs           resb 1
    .wNumRootEntries    resw 1
    .wTotalSectors      resw 1
    .bMediaDescriptor   resb 1
    .wSectorsPerFAT     resw 1
    .wSectorsPerTrack   resw 1
    .wNumHeads          resw 1
    .dHiddenSectors     resd 1
    .dTotalSectors      resd 1

    .dSectorsPerFAT     resd 1
    .wFlags             resw 1
    .wFATVersion        resw 1
    .dRootCluster       resd 1
    .wFSInfoSector      resw 1
    .wBackupBootSector  resw 1
    .reserved           resb 12
    .bDriveNumber       resb 1
    .bWinNTFlags        resb 1
    .bSignature         resb 1
    .dVolumeId          resd 1
    .volumeLabel        resb 11
    .systemId           resb 8
endstruc

; FAT32 context
struc FATContext
    .driveNumber        resb 1
    .sectorsPerCluster  resb 1
    .bytesPerCluster    resw 1
    .FATOffset          resd 1
    .dataOffset         resd 1
    .dirsPerCluster     resd 1
    .rootCluster        resd 1
    .size:
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


; Reads the EAX'th sector from the drive DL into the memory at FS:DI.
; Returns with the carry set if the read was unsuccessful.
fat32._readSector:
    push eax
    push si

    ; Initialize the DAP
    mov [fat32._dap.startLBA], eax
    mov [fat32._dap.numSectors], word 1
    mov [fat32._dap.offset], di
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
; EAX will contain the starting LBA of the partition if it's found, zero otherwise.
; CF will be set if either the allocation or the read has failed.
fat32.readPartition:
    push bx
    push cx
    push di
    push fs

    ; Allocate a sector, make FS point to it.
    mov cx, 512
    call kalloc.kalloc

    ; On error, don't free memory that has not been allocated yet.
    jc .errorNoFree

    ; Read the first sector
    xor eax, eax
    xor di, di
    call fat32._readSector
    jc .error

    ; Offset into the MBR
    xor bx, bx

    ; BX = DH*16, the size of a partition entry
    mov bl, dh
    shl bx, 4

    ; Offset to the partition entries
    add bx, 0x1be

    ; Read the system identifier of the partition.
    mov cl, [fs:bx+partition.systemId]

.done:
    ; EAX contains the starting LBA of the partition.
    mov eax, [fs:bx+partition.startLBA]

    ; Free the buffer
    call kalloc.kfree

    ; Is the partition type FAT32?
    cmp cl, 0x0c
    jnz .wrongType

    jmp .return

.error:
    ; Release the memory we have allocated.
    call kalloc.kfree

.errorNoFree:
    ; Set carry
    stc

.return:
    ; Set ZF according to EAX.
    or eax, eax

    pop fs
    pop di
    pop cx
    pop bx
    ret

.wrongType:
    ; No carry, EAX=0
    xor eax, eax
    jmp .return


; Allocates a FAT32 context structure.
; GS will point to the allocated structure on success, CF will be set otherwise.
fat32.context.alloc:
    push cx
    push fs

    ; Try allocating memory
    mov cx, FATContext.size
    call kalloc.kalloc

    ; Return with carry
    jc .return

    ; Store FS in GS
    push fs
    pop gs

.done:
    ; No carry
    clc

.return:
    ; Restore FS
    pop fs
    pop cx
    ret


; Frees a FAT32 context structure.
; GS should point to the allocated structure.
fat32.context.free:
    ; Preserve FS
    push fs

    ; Free the memory
    push gs
    pop fs
    call kalloc.kfree

    ; Restore FS
    pop fs
    ret


; Mounts a FAT32 filesystem.
; DL is the drive number and EAX is the starting LBA of the partition,
;  returned by fat32.readPartition.
; GS points to the FATContext structure that will be filled.
; CF is set on error.
fat32.mount:
    push eax
    push ebx
    push edx
    push cx
    push di
    push fs

    ; Allocate memory for the first sector of the partition
    mov cx, 512
    call kalloc.kalloc

    ; Allocation error (don't free memory)
    jc .errorNoFree

    ; Read the first sector of the partition
    xor di, di
    call fat32._readSector
    jc .error

    ; Store the drive number
    mov [gs:FATContext.driveNumber], dl

    ; Store the number of sectors per cluster
    mov al, [fs:FATBPB.bSectorsPerCluster]
    mov [gs:FATContext.sectorsPerCluster], al

    ; Find the FAT offset
    mov eax, [fs:FATBPB.dHiddenSectors]

    ; Add the number of reserved sectors
    xor ebx, ebx
    mov bx, [fs:FATBPB.wReservedSectors]
    add eax, ebx

    ; Store the value
    mov [gs:FATContext.FATOffset], eax
    mov ebx, eax

    ; Add the FAT lengths (CX * sectorsPerFAT)
    mov eax, [fs:FATBPB.dSectorsPerFAT]
    xor cx, cx
    mov cl, [fs:FATBPB.bNumFATs]

    ; EAX*CX -> EDX:EAX
    mul cx

    ; Add the previous offset
    add eax, ebx

    ; Store the value
    mov [gs:FATContext.dataOffset], eax

    ; Copy the root cluster number
    mov eax, [fs:FATBPB.dRootCluster]
    mov [gs:FATContext.rootCluster], eax

    ; Find the number of directory entries per cluster
    mov ax, [fs:FATBPB.bSectorsPerCluster]

    ; Multiply by 16 (directory entries per sector)
    mov cx, ax
    shl ax, 4

    ; Store
    mov [gs:FATContext.dirsPerCluster], ax

    ; Find the amount of bytes per cluster.
    ; Multiply CX (sectors per cluster) by 512 (the sector size)
    shl cx, 9

    ; Store
    mov [gs:FATContext.bytesPerCluster], cx

    ; Done
    clc
    jmp .return

.error:
    ; Free the memory allocated
    call kalloc.kfree

.errorNoFree:
    stc

.return:
    pop fs
    pop di
    pop cx
    pop edx
    pop ebx
    pop eax
    ret


; Reads a FAT entry for a given cluster.
; EAX contains the cluster number, GS points to the FATContext structure.
; Returns with CF set on error, otherwise EAX will contain the value read or 0 if the cluster is EOF.
fat32.readFAT:
    push bx
    push cx
    push dx
    push di
    push fs

    ; Allocate a sector for reading the FAT into (FS will point there).
    mov cx, 512
    call kalloc.kalloc
    jc .errorNoFree

    ; Find the correct sector of the FAT and the offset into that sector.

    ; Multiply EAX by 4 (the size of a FAT32 entry) and divide it by 512 (the size of a sector).
    shl eax, 2

    ; BX is the remainder
    mov bx, ax
    and bx, 0x1ff

    ; Divide by 512
    shr eax, 9

    ; Add the FAT offset
    add eax, [gs:FATContext.FATOffset]

    ; Read the sector
    mov dl, [gs:FATContext.driveNumber]
    xor di, di
    call fat32._readSector
    jc .error

    ; EAX contains the correct entry now.
    mov eax, [fs:bx]
    and eax, 0x0fffffff

    ; Is it the EOF value?
    cmp eax, 0x0ffffff8
    jnae .done

    ; EOF, clear EAX
    xor eax, eax

.done:
    ; Clear carry, no error.
    clc

.return:
    ; Restore the registers.
    pop fs
    pop di
    pop dx
    pop cx
    pop bx
    ret

.error:
    ; Free the memory we allocated.
    call kalloc.kfree

.errorNoFree:
    ; Set carry, done.
    stc
    jmp .return

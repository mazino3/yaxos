; YaxOS shell
bits 16

%include "string.asm"

; The commands can be up to 256 characters long.
SHELL_COMMAND_BUFFER_SIZE equ 256

; The current status of the shell
shell._status:
    .FATContextSegment       dw 0
    .currentDirectorySegment dw 0
    .currentDirectoryLength  dw 0
    .commandBufferSegment    dw 0


; Initializes the shell.
; GS points to the FATContext structure of the root partition.
shell.init:
    push eax
    push cx
    push si
    push fs

    ; Log
    mov si, shell.initMessage
    call console.print

    ; Preserve the FAT context segment
    mov [shell._status.FATContextSegment], gs

    ; Log
    mov si, shell.readRootMessage
    call console.print

    ; Read the root directory and make it the current one.
    mov eax, [gs:FATContext.rootCluster]
    call fat32.readClusterChain
    jc shell.error

    ; Update the status
    mov [shell._status.currentDirectorySegment], fs
    mov [shell._status.currentDirectoryLength], cx

    ; Allocate the buffers
    mov si, shell.allocMessage

    ; Allocate the command buffer
    mov cx, SHELL_COMMAND_BUFFER_SIZE
    call kalloc.kalloc
    jc shell.error

    mov [shell._status.commandBufferSegment], fs

    ; Init done
    mov si, shell.initDoneMessage
    call console.print

    ; Return
    pop fs
    pop si
    pop cx
    pop eax
    ret


; Reports an error and halts.
shell.error:
    mov si, shell.errorMessage
    call console.print
    jmp kernel.halt


; Lists the files in the current directory along with their attributes.
shell.listFiles:
    push ax
    push bx
    push cx
    push si
    push di
    push fs
    push gs

    ; Load the segments
    mov fs, [shell._status.currentDirectorySegment]
    mov gs, [shell._status.FATContextSegment]
    mov cx, [shell._status.currentDirectoryLength]

.loop:
    ; Another entry?
    test cx, cx
    jz .done

    ; If the filename starts with a zero, then there aren't any more entries.
    mov al, [fs:0]
    test al, al
    jz .done

    ; File entry
    mov [shell._filenameLine.type], byte '-'

    ; Is it a directory?
    mov al, [fs:FATDirEntry.attributes]
    test al, FAT_ATTRIBUTE_DIRECTORY
    jz .notDirectory

    ; Set the type character to '+'
    mov [shell._filenameLine.type], byte '+'

.notDirectory:
    ; Copy the filename
    xor si, si
    mov di, shell._filenameLine.filename
    mov bx, 11

    ; Copy BX bytes at FS:SI into DS:DI.
.nextByte:
    mov al, [fs:si]
    mov [di], al
    inc si
    inc di
    dec bx
    jnz .nextByte

    ; Print
    mov si, shell._filenameLine
    call console.print

    ; Next directory entry
    mov ax, fs
    add ax, FAT_SEGMENTS_PER_DIR_ENTRY
    mov fs, ax
    sub cx, FATDirEntry.size
    jmp .loop

.done:
    pop gs
    pop fs
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

shell._filenameLine:
    .type db 0
    db " "
    .filename times 11 db 0
    db 13, 10, 0


; Find a directory entry in the current directory whose filename matches that at DS:SI.
; Returns with CF set if the file has not been found, otherwise FS will point to the entry.
shell.findEntry:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push gs

    ; Load the segments
    mov fs, [shell._status.currentDirectorySegment]
    mov gs, [shell._status.FATContextSegment]
    mov cx, [shell._status.currentDirectoryLength]

    ; Preserve SI
    mov dx, si
.loop:
    ; More entries?
    test cx, cx
    jz .notFound

    ; Compare 11 bytes at DS:DX with FS:DI.
    mov si, dx
    xor di, di
    mov bx, 11
.compareLoop:
    mov ah, [si]
    mov al, [fs:di]
    inc si
    inc di

    cmp ah, al
    jnz .nextEntry

    ; More bytes?
    dec bx
    jnz .compareLoop

.found:
    ; Clear carry
    clc
    jmp .return

.notFound:
    ; Set carry
    stc
    jmp .return

.nextEntry:
    ; Next entry
    mov ax, fs
    add ax, FAT_SEGMENTS_PER_DIR_ENTRY
    mov fs, ax
    sub cx, FATDirEntry.size
    jmp .loop

.return:
    ; Return
    pop gs
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Change the current directory to that starting from cluster EAX.
shell.changeDirectory:
    push eax
    push cx
    push fs
    push gs

    ; Restore the segments.
    mov fs, [shell._status.currentDirectorySegment]
    mov gs, [shell._status.FATContextSegment]

    ; Free the cluster chain for the old directory.
    call kalloc.kfree

    ; If EAX is zero, replace it with the starting cluster of the root directory.
    test eax, eax
    jnz .skipRoot
    mov eax, [gs:FATContext.rootCluster]
.skipRoot:

    ; Read the cluster chain for the current directory.
    call fat32.readClusterChain

    ; If that fails, report error and halt
    jc shell.error

    ; Write the new segment address
    mov [shell._status.currentDirectorySegment], fs
    mov [shell._status.currentDirectoryLength], cx

    ; Return
    pop gs
    pop fs
    pop cx
    pop eax
    ret


; Reads a file (EAX is the starting cluster).
; ES will point to the buffer read.
shell.readFile:
    push fs
    push gs
    push cx

    ; Restore the FAT context segment.
    mov gs, [shell._status.FATContextSegment]

    ; Read the cluster chain
    call fat32.readClusterChain
    jc shell.error

    ; FS -> ES
    push fs
    pop es

    pop cx
    pop gs
    pop fs
    ret



; The main loop of the shell (get command, etc).
shell.mainLoop:
.waitCommand:
    mov si, shell.commandPrompt
    call console.print

    ; Read a command into the command buffer
    mov es, [shell._status.commandBufferSegment]
    xor di, di
    mov cx, SHELL_COMMAND_BUFFER_SIZE
    call console.readLine

    ; Find the first space character (BX will be zero if it's at the beginning or there are no spaces in the command).
    xor bx, bx
.findSpace:
    ; Load a character
    mov al, [es:bx]

    ; Space?
    cmp al, ' '
    jz .spaceFound

    ; Zero?
    cmp al, 0
    jz .spaceNotFound

    ; Loop
    inc bx
    jmp .findSpace

.spaceFound:
    ; Terminate the command where the space is.
    mov byte [es:bx], 0
    inc bx
    jmp .findSpaceDone
.spaceNotFound:
    ; Clear BX.
    xor bx, bx

.findSpaceDone:
    ; If the command is empty, try again
    cmp [es:di], byte 0
    jz .waitCommand

    ; Compare the commands
    mov si, shell.commandHelp
    call string.compare
    jz .commandHelp

    mov si, shell.commandLS
    call string.compare
    jz .commandLS

    mov si, shell.commandCD
    call string.compare
    jz .commandCD

    mov si, shell.commandCat
    call string.compare
    jz .commandCat

    mov si, shell.commandRun
    call string.compare
    jz .commandRun

    ; Invalid command
    mov si, shell.invalidCommandMessage
    call console.print

    jmp .waitCommand

.commandHelp:
    mov si, shell.helpMessage
    call console.print
    jmp .waitCommand

.commandLS:
    call shell.listFiles
    jmp .waitCommand

.commandCD:
    ; Change directory
    ; CD requires an argument.
    test bx, bx
    jz .noArgument

    ; Find the length of the directory name and test its length
    mov di, bx
    call string.length
    cmp cx, 11
    ja .filenameTooLong

    ; Copy and space-pad the directory name
    xor cx, cx
    mov si, shell._tempFilename
    mov di, bx
.copyFilenameLoop:
    mov al, [es:di]

    ; Zero?
    test al, al
    jz .copyFilenameDone

    mov [si], al
    inc di
    inc si
    inc cx
    jmp .copyFilenameLoop
.copyFilenameDone:
    ; How many spaces do we need?
    sub cx, 11
    neg cx

    ; Pad the directory name with spaces.
.spacePad:
    test cx, cx
    jz .spacePadDone
    mov [si], byte ' '
    inc si
    dec cx
    jmp .spacePad
.spacePadDone:
    mov si, shell._tempFilename
    call shell.findEntry
    jc .fileNotFound

    ; Test is it's a directory
    mov al, [fs:FATDirEntry.attributes]
    test al, FAT_ATTRIBUTE_DIRECTORY
    jz .notADirectory

    ; Done, change directory
    xor eax, eax
    mov ax, [fs:FATDirEntry.firstClusterHi]
    shl eax, 16
    mov ax, [fs:FATDirEntry.firstCluster]
    call shell.changeDirectory

    jmp .waitCommand

.commandCat:
    ; Print the contents of a file.
    mov di, bx
    call string.length

    ; Check the filename length
    cmp cx, 11
    jne .invalidFilename

    ; Copy the filename from ES:DI to DS:SI
    mov si, shell._tempFilename

    ; Copy the filename
.copyFilenameByteCat:
    mov al, [es:di]
    mov [si], al
    inc di
    inc si
    dec cx
    jnz .copyFilenameByteCat

    ; Find the file entry
    mov si, shell._tempFilename
    call shell.findEntry
    jc .fileNotFound

    mov al, [fs:FATDirEntry.attributes]
    test al, FAT_ATTRIBUTE_DIRECTORY
    jnz .fileExpected

    ; Find the starting cluster
    xor eax, eax
    mov ax, [fs:FATDirEntry.firstClusterHi]
    shl eax, 16
    mov ax, [fs:FATDirEntry.firstCluster]

    ; Preserve the size too.
    mov ecx, [fs:FATDirEntry.fileSize]
    cmp ecx, 65536
    jae .fileTooLarge

    ; Reads a file, ES points to the buffer
    call shell.readFile

    ; Print the contents
    xor si, si
.printLoop:
    mov al, [es:si]
    call console.printChar
    inc si
    dec cx
    jnz .printLoop

    ; Another newline
    call console.newline

    push es
    pop fs
    call kalloc.kfree

    ; TODO print file contents
    jmp .waitCommand

.commandRun:
    ; Execute a file.
    mov di, bx
    call string.length

    ; Check the filename length
    cmp cx, 11
    jne .invalidFilename

    ; Copy the filename from ES:DI to DS:SI
    mov si, shell._tempFilename

    ; Copy the filename
.copyFilenameByteRun:
    mov al, [es:di]
    mov [si], al
    inc di
    inc si
    dec cx
    jnz .copyFilenameByteRun

    ; Find the file entry
    mov si, shell._tempFilename
    call shell.findEntry
    jc .fileNotFound

    mov al, [fs:FATDirEntry.attributes]
    test al, FAT_ATTRIBUTE_DIRECTORY
    jnz .fileExpected

    ; Find the starting cluster
    xor eax, eax
    mov ax, [fs:FATDirEntry.firstClusterHi]
    shl eax, 16
    mov ax, [fs:FATDirEntry.firstCluster]

    ; Preserve the size too.
    mov ecx, [fs:FATDirEntry.fileSize]
    cmp ecx, 65536
    jae .fileTooLarge

    ; Reads a file, ES points to the buffer
    call shell.readFile

    ; Store ES in the far jump address
    mov [shell._farJump.offset], word 0
    mov [shell._farJump.segment], es

    ; Execute the file.
    pushad
    push ds
    push es
    push fs
    push gs
    call far [shell._farJump]
    pop gs
    pop fs
    pop es
    pop ds
    popad

    push es
    pop fs
    call kalloc.kfree

    ; TODO print file contents
    jmp .waitCommand



.noArgument:
    mov si, shell.noArgumentMessage
    call console.print
    jmp .waitCommand

.filenameTooLong:
    mov si, shell.filenameTooLongMessage
    call console.print
    jmp .waitCommand

.fileNotFound:
    mov si, shell.fileNotFoundMessage
    call console.print
    jmp .waitCommand

.notADirectory:
    mov si, shell.notADirectoryMessage
    call console.print
    jmp .waitCommand

.invalidFilename:
    mov si, shell.invalidFilenameMessage
    call console.print
    jmp .waitCommand

.fileExpected:
    mov si, shell.fileExpectedMessage
    call console.print
    jmp .waitCommand

.fileTooLarge:
    mov si, shell.fileTooLargeMessage
    call console.print
    jmp .waitCommand


; Temporary filename
shell._tempFilename times 11 db 0
shell._farJump:
    .offset  dw 0
    .segment dw 0

shell.errorMessage db "[!] shell: error, halting.", 13, 10, 0
shell.initMessage db "[+] shell: initializing...", 13, 10, 0
shell.readRootMessage db "[+] shell: reading root directory...", 13, 10, 0
shell.allocMessage db "[+] shell: allocating memory for buffers...", 13, 10, 0
shell.initDoneMessage db "[+] shell: initialization done.", 13, 10, 0

shell.fileNotFoundMessage db "error: file not found!", 13, 10, 0
shell.notADirectoryMessage db "error: not a directory.", 13, 10, 0
shell.fileExpectedMessage db "error: expected a file, but a directory name was given", 13, 10, 0

shell.commandPrompt db "YaxOS> ", 0
shell.invalidCommandMessage db "error: invalid command, type 'help' for a list.", 13, 10, 0
shell.noArgumentMessage db "error: this command requires an argument.", 13, 10, 0
shell.filenameTooLongMessage db "error: filename too long.", 13, 10, 0
shell.invalidFilenameMessage db "error: invalid filename.", 13, 10, 0
shell.fileTooLargeMessage db "error: the file is too large.", 13, 10, 0

shell.commandHelp db "help", 0
shell.commandLS db "ls", 0
shell.commandCD db "cd", 0
shell.commandCat db "cat", 0
shell.commandRun db "run", 0

shell.helpMessage db "Available commands: help, ls, cd, cat, run.", 13, 10, 0

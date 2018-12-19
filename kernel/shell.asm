; YaxOS shell
bits 16

%include "string.asm"

; The commands can be up to 256 characters long.
SHELL_COMMAND_BUFFER_SIZE equ 256

; The LS listing will pause after every 20 entries.
LS_LINES_PER_PAGE equ 20

; The signature of the shell status structure
SHELL_STATUS_SIGNATURE equ "Stat"


; The current status of the shell
shell._status:
    .FATContextSegment          dw 0
    .currentDirectorySegment    dw 0
    .currentDirectoryLength     dw 0
    .commandBufferSegment       dw 0
    .currentDirectoryEnumPos    dw 0
    .currentDirectoryEnumSeg    dw 0

    .prevDirectorySegment       dw 0
    .prevDirectoryLength        dw 0
    .prevDirectoryValid         db 0
    .freeCurrentDirectory       db 0

    .signature                  dd SHELL_STATUS_SIGNATURE


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

    ; Register the interrupt
    mov dx, shell.interrupt
    mov bl, 0x22
    call kernel.registerInterrupt

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

    ; The current directory can be freed.
    mov [shell._status.freeCurrentDirectory], byte 1

    ; No valid previous directory.
    mov [shell._status.prevDirectoryValid], byte 0

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


; Checks the shell status signature to detect corruption.
shell.checkSignature:
    cmp [shell._status.signature], dword SHELL_STATUS_SIGNATURE
    jnz .signatureError
    ret
.signatureError:
    mov si, .signatureErrorMessage
    jmp kernel.halt
.signatureErrorMessage db "shell: invalid signature of the status structure, halting...", 13, 10, 0

; Prepares to enumerate the current directory.
shell.enumDir.init:
    push ax

    ; Reset the enumeration position of the current directory.
    mov [shell._status.currentDirectoryEnumPos], word 0
    mov ax, [shell._status.currentDirectorySegment]
    mov [shell._status.currentDirectoryEnumSeg], ax

    pop ax
    ret

; Parses the next directory entry if it exists, otherwise returns with CF set.
; The return registers are set according to fat32.parseDirEntry.
shell.enumDir.nextEntry:
    push fs

.next:
    ; Are we at the end of the current directory?
    mov ax, [shell._status.currentDirectoryLength]
    cmp [shell._status.currentDirectoryEnumPos], ax
    jz .eof

    ; Set FS to the correct segment
    mov fs, [shell._status.currentDirectoryEnumSeg]

    ; Parse the directory entry
    call fat32.parseDirEntry

    ; EOF?
    jc .eof

    ; Increment the segment and the position
    add word [shell._status.currentDirectoryEnumSeg], FAT_SEGMENTS_PER_DIR_ENTRY
    add word [shell._status.currentDirectoryEnumPos], FATDirEntry.size

    ; If the entry has the volume label attribute set, ignore it.
    test bl, FAT_ATTRIBUTE_VOLUME_LABEL
    jnz .next

    ; No carry
    clc
.return:
    pop fs
    ret

.eof:
    ; Set carry, return
    stc
    jmp .return


; Lists the files in the current directory along with their attributes.
shell.listFiles:
    push eax
    push bx
    push ecx
    push si
    push dx

    ; Initialize the directory enumeration
    call shell.enumDir.init

    ; DX counts the entries printed.
    xor dx, dx

.nextEntry:
    ; Parse the directory entry at FS.
    mov si, .tempFilename
    call shell.enumDir.nextEntry
    jc .done

    ; Type character
    mov [.tempFilenameType], byte '-'

    ; BL contains the attributes.
    test bl, FAT_ATTRIBUTE_DIRECTORY
    jz .skipDirectory

    ; Change the type to '+'
    mov [.tempFilenameType], byte '+'

    ; Skip
.skipDirectory:
    ; Print the filename.
    mov si, .tempFilenameLine
    call console.print
    call console.newline

    ; Increment DX
    inc dx

    ; Should we pause now?
    cmp dx, LS_LINES_PER_PAGE
    jnz .noPause

    ; Pause
    call shell.pause

    ; Reset the line counter.
    xor dx, dx
.noPause:
    jmp .nextEntry

.done:
    ; Done, restore registers and exit.
    pop dx
    pop si
    pop ecx
    pop bx
    pop eax
    ret

.tempFilenameLine:
.tempFilenameType db 0
    db " "
.tempFilename times 13 db 0


; Find a directory entry in the current directory whose filename matches that at ES:DI.
; Returns with CF set if the file has not been found.
; EAX, ECX, BL will be set appropriately.
shell.findEntry:
    push si

    ; Initialize the directory enumeration context.
    call shell.enumDir.init

    ; The filename to compare with.
    mov si, .tempFilename

.loop:
    ; Read the directory entry.
    call shell.enumDir.nextEntry

    ; If EOF, stop
    jc .notFound

    ; Compare the filenames, return if they match.
    call string.compare
    jz .return

    ; Next entry
    jmp .loop

    ; Done, return
.done:
    ; No carry
    clc
.return:
    pop si
    ret
.notFound:
    ; Set carry
    stc
    jmp .return

.tempFilename times 13 db 0


; Change the current directory to the one referred to by ES:DI.
shell.changeDirectory:
    push eax
    push ecx
    push bx
    push fs
    push gs
    push si

    ; Is it the special root directory name?
    mov si, .rootDirectoryName
    call string.compare

    ; No, skip
    jnz .skipRootName

    ; Read the root cluster otherwise.
    xor eax, eax
    jmp .readClusters

.skipRootName:
    ; Search for a directory entry with a given name.
    call shell.findEntry
    jc .notFound

    ; Test is it's a directory.
    test bl, FAT_ATTRIBUTE_DIRECTORY
    jz .notADirectory

.readClusters:
    ; Restore the segments.
    mov fs, [shell._status.currentDirectorySegment]
    mov gs, [shell._status.FATContextSegment]

    ; Should the current directory be freed?
    cmp [shell._status.freeCurrentDirectory], byte 1
    jnz .skipFree

    ; Free the cluster chain for the old directory.
    call kalloc.kfree
.skipFree:

    ; If EAX is zero, replace it with the starting cluster of the root directory.
    test eax, eax
    jnz .skipRoot
    mov eax, [gs:FATContext.rootCluster]
.skipRoot:

    ; Read the cluster chain for the current directory.
    call fat32.readClusterChain

    ; If that fails, report error.
    jc .readError

    ; Write the new segment address
    mov [shell._status.currentDirectorySegment], fs
    mov [shell._status.currentDirectoryLength], cx

    ; The current directory can be freed.
    mov [shell._status.freeCurrentDirectory], byte 1

.done:
    ; No carry
    clc

    ; Return
.return:
    pop si
    pop gs
    pop fs
    pop bx
    pop ecx
    pop eax
    ret

.error:
    ; Set carry
    stc
    jmp .return

.notFound:
    mov si, .notFoundMessage
    call console.print
    jmp .error

.notADirectory:
    mov si, .notADirectoryMessage
    call console.print
    jmp .error

.readError:
    mov si, .readErrorMessage
    call console.print
    jmp shell.error

.notFoundMessage db "cd: directory not found.", 13, 10, 0
.notADirectoryMessage db "cd: not a directory.", 13, 10, 0
.readErrorMessage db "cd: read error, halting the shell.", 13, 10, 0
.rootDirectoryName db ":root", 0


; Preserve the current directory.
shell.preserveCurrentDirectory:
    push ax

    ; Make sure there was no directory preserved before
    cmp [shell._status.prevDirectoryValid], byte 1
    jz .prevError

    ; Don't free the current directory when changing, since we have preserved that.
    mov [shell._status.freeCurrentDirectory], byte 0

    ; Preserve the current directory
    mov ax, [shell._status.currentDirectorySegment]
    mov [shell._status.prevDirectorySegment], ax
    mov ax, [shell._status.currentDirectoryLength]
    mov [shell._status.prevDirectoryLength], ax

    ; Mark the previous directory valid.
    mov [shell._status.prevDirectoryValid], byte 1

    pop ax
    ret

.prevError:
    mov si, .prevErrorMessage
    call console.print
    jmp shell.error
.prevErrorMessage db "shell: already have a preserved directory", 13, 10, 0

; Restore the current directory.
shell.restoreCurrentDirectory:
    push ax
    push fs

    ; Check if a directory was preserved first
    cmp [shell._status.prevDirectoryValid], byte 1
    jnz .noPrevDirectory

    ; Free the current directory
    mov ax, [shell._status.currentDirectorySegment]
    mov fs, ax
    call kalloc.kfree

    ; Restore the current directory
    mov ax, [shell._status.prevDirectorySegment]
    mov [shell._status.currentDirectorySegment], ax
    mov ax, [shell._status.prevDirectoryLength]
    mov [shell._status.currentDirectoryLength], ax

    ; Invalidate the preserved directory
    mov [shell._status.prevDirectoryValid], byte 0

    pop fs
    pop ax
    ret
.noPrevDirectory:
    mov si, .prevErrorMessage
    call console.print
    jmp shell.error
.prevErrorMessage db "shell: no preserved directory to restore", 13, 10, 0


; Reads a file (ES:DI contains the filename).
; ES will point to the buffer read, CX bytes long.
shell.readFile:
    push eax
    push bx
    push fs
    push gs

    ; Search for a directory entry with a given name.
    call shell.findEntry
    jc .notFound

    ; Test is it's a directory.
    test bl, FAT_ATTRIBUTE_DIRECTORY
    jnz .fileExpected

    ; Empty?
    test cx, cx
    jz .emptyFile

    ; Restore the FAT context segment.
    mov gs, [shell._status.FATContextSegment]

    ; Read the cluster chain
    push cx
    call fat32.readClusterChain
    pop cx
    jc .readError

    ; FS -> ES
    push fs
    pop es

.emptyFile:
    ; No carry
    clc

.return:
    pop gs
    pop fs
    pop bx
    pop eax
    ret

.error:
    ; Set carry, return
    stc
    jmp .return

.notFound:
    mov si, .notFoundMessage
    call console.print
    jmp .error

.fileExpected:
    mov si, .fileExpectedMessage
    call console.print
    jmp .error

.readError:
    mov si, .readErrorMessage
    call console.print
    jmp .error

.notFoundMessage db "readFile: file not found.", 13, 10, 0
.fileExpectedMessage db "readFile: file expected.", 13, 10, 0
.readErrorMessage db "readFile: read error.", 13, 10, 0


; Changes the current directory according to the path specified in ES:DI.
shell.changeDirectoryPath:
    push ax
    push bx
    push dx
    push si
    push di

    ; BX points to the beginning of the current subdirectory name.
    mov bx, di

    ; Next slash character
.nextSlash:
    ; Load the next character
    mov al, [es:bx]
    inc bx

    ; Zero, the path is over
    cmp al, 0
    jz .found

    ; Slash?
    cmp al, '/'
    jz .found

    ; Skip
    jmp .nextSlash
.found:
    ; Terminate the path at the current slash.
    mov si, bx
    dec si
    mov [es:si], byte 0

    ; ES:DI points to the subdirectory name.
    call shell.changeDirectory
    jc .done

    ; The start of the next subdirectory name is at BX.
    mov di, bx

    ; If AL is not zero, continue.
    test al, al
    jnz .nextSlash
.done:
    pop di
    pop si
    pop dx
    pop bx
    pop ax
    ret


; Splits a path, changes the current directory and calls readFile on the actual filename.
; ES:DI points to the path (which will be modified).
shell.readFilePath:
    push ax
    push bx
    push dx
    push si

    mov bx, di
    mov dx, di

    ; Finds the last '/' character in the path.
.findLastSlash:
    ; Load a character
    mov al, [es:bx]
    inc bx

    ; Zero?
    cmp al, 0
    jz .findDone

    ; Slash?
    cmp al, '/'
    jnz .findLastSlash
.slashFound:
    ; Store the position of the current slash.
    mov dx, bx
    jmp .findLastSlash
.findDone:
    ; ES:DX points to the filename without the preceding path.
    ; ES:DI points to the directory path.

    ; Terminate the path before the filename.
    test dx, dx
    jz .noSlash

    mov si, dx
    dec si
    mov [es:si], byte 0
.noSlash:
    ; Is the directory name empty?
    cmp di, dx
    jz .skipChangeDirectory

    ; Preserve the current directory
    call shell.preserveCurrentDirectory

    ; Change the current directory.
    call shell.changeDirectoryPath
    jc .returnError

    ; Read the file
    mov di, dx
    call shell.readFile
    jc .returnError
    jmp .returnRestore

.skipChangeDirectory:
    ; Read the file.
    mov di, dx
    call shell.readFile
    jmp .return

.returnError:
    ; Set carry
    stc
.returnRestore:
    pushf
    call shell.restoreCurrentDirectory
    popf
.return:
    ; Restore the registers.
    pop si
    pop dx
    pop bx
    pop ax
    ret


; The main loop of the shell (get command, etc).
shell.mainLoop:
.waitCommand:
    mov si, shell.commandPrompt
    call console.print

    ; Read a command into the command buffer
    mov es, [shell._status.commandBufferSegment]
    xor di, di
    mov cx, SHELL_COMMAND_BUFFER_SIZE-1
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

    mov si, shell.commandHeap
    call string.compare
    jz .commandHeap

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
    ; Change the current directory.
    ; CD requires an argument.
    test bx, bx
    jz .noArgument

    ; Change the directory
    mov di, bx
    call shell.changeDirectoryPath

    jmp .waitCommand

.commandCat:
    ; cat requires an argument.
    test bx, bx
    jz .noArgument

    ; Read the file into ES.
    mov di, bx
    call shell.readFilePath

    ; On error, wait for the next command.
    jc .waitCommand

    xor di, di
.printChar:
    test cx, cx
    jz .printDone

    ; Print the character at ES:DI
    mov al, [es:di]
    inc di
    call console.printChar

    ; Next character
    dec cx
    jmp .printChar

.printDone:
    ; Release the memory the file was read into.

    ; ES -> FS
    push es
    pop fs
    call kalloc.kfree

    ; Newline
    call console.newline
    jmp .waitCommand

.commandRun:
    ; run requires an argument.
    test bx, bx
    jz .noArgument

    ; Terminate the filename at the first space
    mov bp, bx
.runTerminateFilename:
    ; End?
    cmp [es:bp], byte 0
    jz .runTerminateZero

    ; Space?
    cmp [es:bp], byte ' '
    jnz .runTerminateNext

    ; Terminate the string at the location of the space.
    mov [es:bp], byte 0
    inc bp
    jmp .runTerminateDone

.runTerminateNext:
    inc bp
    jmp .runTerminateFilename
.runTerminateZero:
    ; Clear BP (no arguments)
    xor bp, bp
.runTerminateDone:
    ; Preserve ES
    mov ax, es
    mov fs, ax

    ; Read the file into ES.
    mov di, bx
    call shell.readFilePath

    ; On error, wait for the next command.
    jc .waitCommand

    ; Test if the length is zero
    test cx, cx
    jz .emptyFile

    ; Jump into the loaded program
    ; FS:BP points to the command line if it exists.
    mov [.farJumpSegment], es

    pusha
    push ds
    push es
    call far [.farJump]
    pop es
    pop ds
    popa

    ; Free the memory allocated.

    ; ES -> FS
    push es
    pop fs

    call kalloc.kfree
    jmp .waitCommand

.commandHeap:
    ; Print the kalloc debug info.
    call kalloc.debug
    jmp .waitCommand

.noArgument:
    mov si, shell.noArgumentMessage
    call console.print
    jmp .waitCommand
.emptyFile:
    mov si, .emptyFileMessage
    call console.print
    jmp .waitCommand
.emptyFileMessage db "error: the file is empty!", 13, 10, 0

.farJump:
.farJumpOffset dw 0
.farJumpSegment dw 0


; The system call for shell functions.
; BP is the function number.
; 0 - enumDir.init
; 1 - enumDir.nextEntry
; 2 - findEntry
; 3 - readFile
; 4 - changeDirectory
; 5 - readFilePath
; 6 - changeDirectoryPath
shell.interrupt:
    ; Preserve DS and set it to the kernel data segment.
    push ds

    push word KERNEL_SEGMENT
    pop ds

    ; Check the signature of the shell structures.
    call shell.checkSignature

    cmp bp, 0
    jz .enumDirInit
    cmp bp, 1
    jz .enumDirNext
    cmp bp, 2
    jz .findEntry
    cmp bp, 3
    jz .readFile
    cmp bp, 4
    jz .changeDir
    cmp bp, 5
    jz .readFilePath
    cmp bp, 6
    jz .changeDirPath

    ; Set carry (invalid function).
    stc
.return:
    ; Restore DS
    pop ds

	; Return
	jmp kernel.iretCarry

.enumDirInit:
    call shell.enumDir.init
    jmp .return
.enumDirNext:
    ; Copy to ES:DI from a temporary buffer.
    push si
    mov si, .tempFilename
    call shell.enumDir.nextEntry

    ; On EOF, return
    jc .enumDirDone

    ; Copy the filename from the temporary buffer into ES:DI.
    call string.copy

    ; Clear carry
    clc
.enumDirDone:
    pop si
    jmp .return
.findEntry:
    call shell.findEntry
    jmp .return
.readFile:
    call shell.readFile
    jmp .return
.changeDir:
    call shell.changeDirectory
    jmp .return
.readFilePath:
    call shell.readFilePath
    jmp .return
.changeDirPath:
    call shell.changeDirectoryPath
    jmp .return

.tempFilename times 13 db 0


; Prints a message and waits for a keypress until returning.
shell.pause:
    push ax
    push si

    ; Print "Press any key to continue"
    mov si, .pauseMessage
    call console.print

    ; Wait for a keypress
    call console.waitKey

    pop si
    pop ax
    ret
.pauseMessage db "Press any key to continue...", 13, 10, 0


shell.errorMessage db "[!] shell: error, halting.", 13, 10, 0
shell.initMessage db "[+] shell: initializing...", 13, 10, 0
shell.readRootMessage db "[+] shell: reading root directory...", 13, 10, 0
shell.allocMessage db "[+] shell: allocating memory for buffers...", 13, 10, 0
shell.initDoneMessage db "[+] shell: initialization done.", 13, 10, 0

shell.commandPrompt db "YaxOS> ", 0
shell.invalidCommandMessage db "error: invalid command, type 'help' for a list.", 13, 10, 0
shell.noArgumentMessage db "error: this command requires an argument.", 13, 10, 0

shell.commandHelp db "help", 0
shell.commandLS db "ls", 0
shell.commandCD db "cd", 0
shell.commandCat db "cat", 0
shell.commandRun db "run", 0
shell.commandHeap db "heap", 0

shell.helpMessage db "Available commands: help, ls, cd, cat, run, heap.", 13, 10, 0

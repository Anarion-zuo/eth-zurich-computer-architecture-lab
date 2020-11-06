.text

    # data seg layout:
    # 0x10000000, 20, 40, 60: flags[0..3] (separate cache blocks).
    # 0x10080000..0x10900000: 64KB matrix A (4 byte elems, 128x128)
    # 0x10090000..0x10a00000: 64KB matrix B
    # 0x100a0000..0x10b00000: 64KB matrix C

    # initialize flags
    lui $a0, 0x1000
    sw $0, 0($a0)
    sw $0, 0x20($a0)
    sw $0, 0x40($a0)
    sw $0, 0x60($a0)

    # initialize matrices
    lui $a1, 0x1008
    li $t0, 16384
init1:
    sw $t0, 0($a1)
    addiu $a1, $a1, 4
    addiu $t0, $t0, -1
    bne $t0, $0, init1

    lui $a1, 0x1009
    li $t0, 16384
init2:
    sw $t0, 0($a1)
    addiu $a1, $a1, 4
    addiu $t0, $t0, -1
    bne $t0, $0, init2
    
    # start up CPUs
    addiu $s0, $0, 0 # thread ID

    addiu $v0, $0, 1 # fork to CPU 1
    syscall
    bne $v1, $0, cpu1 # v1==1 indicates we're on CPU 1
    addiu $v0, $0, 2
    syscall
    bne $v1, $0, cpu2
    addiu $v0, $0, 3
    syscall
    bne $v1, $0, cpu3
    j start

cpu1:
    addiu $s0, $0, 1 # thread ID
    j startslave
cpu2:
    addiu $s0, $0, 2 # thread ID
    j startslave
cpu3:
    addiu $s0, $0, 3 # thread ID
    j startslave

start:

    # produce output four elements at a time, synchronizing with slave threads
    # this is a braindead algorithm (each output element is fully independent
    # of the others hence we need only one barrier at the end) but it exercises
    # coherence well :-)

    lui $s0, 0x1008 # matrix A
    lui $s1, 0x1009 # matrix B
    lui $s2, 0x100a # matrix C

    lui $s3, 0x1000 # flag cache blocks
    li $s4, 1

    li $s5, 128 # col counter
    li $s6, 128 # row counter

start1:
    # dispatch slave threads

    # slave 1
    sw $s0, 4($s3) # A-ptr for slave 1
    sw $s1, 8($s3) # B-ptr for slave 1
    sw $s2, 12($s3) # C-ptr for slave 1
    sw $s4, 0($s3) # fire it off by flipping flag (must come last!)

    # slave 2
    addiu $s1, $s1, 4
    addiu $s2, $s2, 4
    sw $s0, 36($s3)
    sw $s1, 40($s3)
    sw $s2, 44($s3)
    sw $s4, 32($s3)

    # slave 3
    addiu $s1, $s1, 4
    addiu $s2, $s2, 4
    sw $s0, 68($s3)
    sw $s1, 72($s3)
    sw $s2, 76($s3)
    sw $s4, 64($s3)

    # now do our own
    addiu $s1, $s1, 4
    addiu $s2, $s2, 4
    addiu $a0, $s0, 0
    addiu $a1, $s1, 0
    addiu $a2, $s1, 0
    jal do_row

    addiu $s1, $s1, 4
    addiu $s2, $s2, 4

    # now wrap ptrs
    addiu $s5, $s5, -4
    bne $s5, $0, start2
    # next row: reset B-ptr, bump A-ptr
    lui $s1, 0x1009
    addiu $s0, $s0, 512
    li $s5, 128 # col counter
    # dec row counter
    addiu $s6, $s6, -1
start2:

    # synchronize on slave threads
    lw $t0, 0($s3)
    bne $t0, $0, start2
    lw $t1, 32($s3)
    bne $t0, $0, start2
    lw $t2, 64($s3)
    bne $t0, $0, start2

    # loop around
    bne $s6, $0, start1

    # now, take sum of all elements in C (this pulls all cache blocks back to CPU 0)

    lui $a0, 0x100a
    li $t0, 16384
    li $t1, 0
start3:
    lw $t2, 0($a0)
    addu $t1, $t1, $t2
    addiu $t0, $t0, -1
    addiu $a0, $a0, 4
    bne $t0, $0, start3

    # output sum of all elems
    li $v0, 11
    addiu $v1, $t1, 0
    syscall

    # end all slave threads
    li $t0, 2
    sw $t0, 0($s3)
    sw $t0, 32($s3)
    sw $t0, 64($s3)
    
    # done
    addiu $v0, $0, 10
    syscall
    
startslave:
    li $s1, 2
    lui $a3, 0x1000
    addiu $s0, $s0, -1
    sll $s0, $s0, 5 # (thread ID - 1) -> cache block number
    addu $a3, $a3, $s0  # a3 -> address of synchronization block
startslave1:
    lw $t0, 0($a3)
    beq $t0, $0, startslave1 # spin while flag == 0

    # if flag == 2, then exit thread
    beq $t0, $s1, startslave2

    # grab a0, a1, a2 params
    lw $a0, 4($a3)
    lw $a1, 8($a3)
    lw $a2, 12($a3)
    jal do_row

    # set flag to 0 to indicate finish and loop around
    sw $0, 0($a3)
    j startslave1

startslave2:
    addiu $v0, $0, 10 # exit thread syscall
    syscall

do_row:
    # input: a0 = matrix A row (stride by 4)
    #        a1 = matrix B col (stride by 512)
    #        a2 = matrix C out (single elem)
    li $t4, 128 # loop count
    li $t5, 0 # sum
do_row1:
    lw $t0, 0($a0)
    lw $t1, 0($a1)
    mult $t0, $t1
    mflo $t2
    addu $t5, $t5, $t2
    addiu $a0, $a0, 4
    addiu $a1, $a1, 512
    addiu $t4, $t4, -1
    bne $t4, $0, do_row1
    sw $t5, 0($a2)
    jr $ra

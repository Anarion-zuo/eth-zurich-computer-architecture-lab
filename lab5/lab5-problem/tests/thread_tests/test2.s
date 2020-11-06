.text

    # initialize counter
    lui $a0, 0x1000
    sw $0, 0($a0)
    
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
    j start
cpu2:
    addiu $s0, $0, 2 # thread ID
    j start
cpu3:
    addiu $s0, $0, 3 # thread ID
    j start

start:
    # all four CPUs come here, with thread ID (0 to 3) in $s0

    # bump counter and grab our value
    lui $a0, 0x1000
    lw $t0, 0($a0)
    addiu $t0, $t0, 1
    sw $t0, 0($a0)

    addiu $v0, $0, 11 # console-out syscall
    addu $v1, $t0, 0
    syscall

    addiu $v0, $0, 10
    syscall # end

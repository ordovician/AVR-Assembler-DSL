    ldi(r3, 4)
    ldi(r1, 2)
:loop
    add(r2, r1)
    dec(r3)
    brne(:loop)

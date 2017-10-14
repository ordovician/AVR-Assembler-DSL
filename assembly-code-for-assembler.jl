    ldi(r3, value(4))
    ldi(r1, value(2))
:loop
    add(r2, r1)
    dec(r3)
    brne(:loop)
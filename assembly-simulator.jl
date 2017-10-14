import Base: getindex, setindex!, show, +, -, *, /, <, >, ==, !=, >=, <=

const no_registers = 32
const amount_memory = UInt16(10)

# From ATtiny13 datasheet page 156
const SREG     = 0x3f
const TIMSK0   = 0x39
const TIFR0    = 0x38
const OCR0A    = 0x36
const TCCR0B   = 0x33
const TCNT0    = 0x32
const TCCR0A   = 0x2f
const OCR0B    = 0x29
const PORTB    = 0x18
const DDRB     = 0x17
const PINB     = 0x16

# SREG
const C  = 0 # Carry flag
const Z  = 1 # Zero flag  
const N  = 2 # Negative flag  
const V  = 3 # Two's complement  
const S  = 4 # For signed tests  
const H  = 5 # Half carry 
const T  = 6 # Transfer bit
const GI = 7 # Global interrupt Enable/Disable

# TIMSK0
const OCIE0B   = 3 
const OCIE0A   = 2
const TOIE0    = 1

# Variables for PIN numbers with: const PB0 = 0; const PB1 = 1 
for i in 0:7
    @eval const $(Symbol("PB", i)) = $i
end

# PORTB PORTB0, PORTB1 ... PORTB5
# PINB PINB0, PINB1 ... PINB5
for i = 0:5
    @eval const $(Symbol("PORTB", i)) = $i
    @eval const $(Symbol("PINB", i)) = $i
end

# Setting and Getting SREGs
for flag in collect("CZNVSHT")
    flag_bit = eval(Symbol(flag))   # Get which bit number the flag is at
    @eval begin
        $(Symbol("set_", flag))()    = cpu.io_regs[SREG] |= 1 << $flag_bit
        $(Symbol("get_", flag))()    = (cpu.io_regs[SREG] >> $flag_bit) & 0x01 
        $(Symbol("is_set_", flag))() = cpu.io_regs[SREG] & (1 << $flag_bit) != 0
        $(Symbol("clear_", flag))()  = cpu.io_regs[SREG] &= ~UInt8(1 << $flag_bit) 
    end
end


"""Register type to avoid accidentally using a number when meaning a register"""
mutable struct Register
   value::Int8
   
   Register() = new(0)
end

function tobyte(v::Integer)
    if v < 0
        Int8(v)
    else
        reinterpret(Int8, UInt8(v))
    end    
end     

# Create registers with: const r1 = Register(1); const r2 = Register(2)
for i in 1:no_registers
    @eval const $(Symbol("r", i-1)) = Register()
end

# Define aritmetic and boolean operations for registers
for op in [:+, :-, :*, :/, :>, :<, :(==), :(!=), :(<=), :(>=)]
    @eval $op(x::Register, y::Register) = $op(x.value, y.value)
end

for op in [:+, :-, :*, :/, :>, :<, :(==), :(!=), :(<=), :(>=)]
    @eval $op(x::Register, k::Integer) = $op(x.value, k)
    @eval $op(k::Integer, x::Register) = $op(k, x.value)
end


"""
Indirect Address Register type for X, Y, Z registers which are just composition of normal registers,
but which are used together when we need to deal with 16 bit numbers such as
addresses
"""
struct IARegister
    low::Register
    high::Register
end

# The indirect address registers X, Y, Z
const RX = IARegister(r27, r26)
const RY = IARegister(r29, r28) 
const RZ = IARegister(r31, r30)

function getindex(xs::Vector{Int8}, r::Register)
     xs[r.index]
end

function setindex!(xs::Vector{Int8}, x::Int8, r::Register)
     xs[r.index] = x
end

mutable struct CPU
   io_regs::Vector{UInt8}
   pc::Int16  # program counter
   sp::Int16  # stack pointer

   function CPU()
      new(zeros(UInt8, 64), 
          zero(UInt16),   # PC, program counter
          amount_memory)  # stack pointer
   end
end

is_bit_set(reg::Integer, bit::Integer) = reg & (1 << bit) != 0
value_of_bit(reg::Integer, bit::Integer) = (reg >> bit) & 0x01

function show(io::IO, cpu::CPU)
    println("Registers:")
    for i in 1:no_registers
       println(io, "  r$(i-1) = $(cpu.regs[i])") 
    end
    println("IO Registers:")
    println(io, "  ", cpu.io_regs)    
    # println(io, "Memory:")
    # println(io, "  ", cpu.mem)
    sreg = cpu.io_regs[SREG]
    for flag in collect("CZNVSHT")
        flag_bit = eval(Symbol(flag))   # Get which bit number the flag is at
        println(io, "$flag: $(value_of_bit(sreg, flag_bit))")
    end
end

"""Reset memory and registers to zero"""
function reset!()
   global cpu     = CPU()
   global mem     = zeros(UInt8, amount_memory)
   global code    = Expr[]
   global symbols = Dict{Symbol, Int16}()
end

function update_sreg(v::Int8)
    if v == 0
        set_Z()
    else
        clear_Z()
    end
    if is_bit_set(v, 7)
        set_N()
    else
        clear_N()
    end 
    if is_set_V() != is_set_N() # N ⊕ V, For signed tests, N xor V
        set_S()
    else
        clear_S()
    end   
end

##### Assembly Instructions (Naming conventions from AVR Manual) #####
"""LoaD Immediate.  Rd ← K"""
function ldi(Rd::Register, K::Integer)
    Rd.value = tobyte(K)
end

"""Copy Register. Rd ← Rr"""
function mov(Rd::Register, Rr::Register)
    Rd.value = Rr.value    
end

"""Add without carry. Rd ← Rd + Rr"""
function add(Rd::Register, Rr::Register)
    sum::Int8 =  Rd + Rr
    if (Rd >= 0 && Rr >= 0 && sum < 0) ||
       (Rd <  0 && Rr <  0 && sum > 0)
        set_V()
    else
        clear_V()
    end 
    Rd.value = sum
    update_sreg(sum)   
end

"""Increment. Rd←Rd+1"""
function inc(Rd::Register)
    Rd.value += 1
    update_sreg(Rd.value)
end

"""Decrement. Rd←Rd+1"""
function dec(Rd::Register)
    Rd.value -= 1
    update_sreg(Rd.value)
end

"""Logical AND. Rd ← Rd & Rr"""
function and(Rd::Register, Rr::Register)
    Rd.value &= Rr.value
    update_sreg(cpu.regs[Rd])   
end


"""Logical AND with Immediate. Rd ← Rd & K"""
function andi(Rd::Register, K::Integer)
    Rd.value &= tobyte(K)
    update_sreg(Rd.value)   
end

"""Clear Bit `b` in I/O Register `A`. I/O(A,b) ← 0"""
function cbi(A::Integer, b::Integer)
    assert(0 ≤ b ≤ 7)
    assert(0 ≤ A ≤ 31)
    cp.io_regs[A] &= ~UInt8(1 << b)
end

"""Set Bit `b` in I/O Register `A`. I/O(A,b) ← 1"""
function sbi(A::Integer, b::Integer)
    assert(0 ≤ b ≤ 7)
    assert(0 ≤ A ≤ 31)
    cp.io_regs[A] |= UInt8(1 << b)
end

"""Substract without carry. Rd ← Rd + Rr"""
function sub(Rd::Register, Rr::Register)
    Rd.value -= Rr.value
    update_sreg(Rd.value)   
end

"""Substract Immediate. Rd ← Rd + Rr"""
function subi(Rd::Register, K::Integer)
    Rd.value -= tobyte(K)
    update_sreg(Rd.value)   
end


"""Relative call to Subroutine. PC ← PC + k + 1"""
function rcall(k::Integer)
    # Store 8 bit return address on stack
    mem[cpu.sp] = cpu.pc
    cpu.sp -= 1
    
    cpu.pc += Int8(k)
end

"Relative call to Subroutine using label"
function rcall(label::Symbol)
    rcall(symbols[label] - cpu.pc)
end

""" Return from Subroutine"""
function ret()
    cpu.sp += 1
    cpu.pc = mem[cpu.sp]
end

"""Relative Jump. PC ← PC + k + 1"""
function rjmp(k::Integer)
    cpu.pc += Int8(k)
end

"""Push Register on Stack. STACK ← Rr"""
function push(Rr::Register)
    mem[cpu.sp] = Rr.value
    cpu.sp -= 1
end

"""Pop Register from Stack. Rd ← STACK"""
function pop(Rd::Register)
    cpu.sp += 1
    Rd.value = tobyte(mem[cpu.sp])
end

"Do nothing"
function nop()
    
end

function cp(Rd::Register, Rr::Register)
    diff = Rd - Rr
    update_sreg(diff)
    if abs(Rr.value) > abs(Rd.value)
        set_C()
    else
        clear_C()
    end
end

function breq(k::Integer)
    if is_set_Z()
        cpu.pc += Int8(k)
        # debug REMOVE
        # println("jumping to: $(cpu.pc+1) with offset $k")
    end       
end

function breq(label::Symbol)
    println("breq: $(symbols[label]) - $(cpu.pc) = $(symbols[label] - cpu.pc)")
    breq(symbols[label] - cpu.pc)
end

"""Branch if Not Equal. If Rd ≠ Rr (Z = 0) then PC ← PC + k + 1, else PC ← PC + 1"""
function brne(k::Integer)
    if !is_set_Z()
        cpu.pc += Int8(k)
        # debug REMOVE
        # println("jumping to: $(cpu.pc+1) with offset $k")
    end       
end

function brne(label::Symbol)
    # println("breq: $(symbols[label]) - $(cpu.pc) = $(symbols[label] - cpu.pc)")
    brne(symbols[label] - cpu.pc)
end


function brlo(k::Integer)
    if is_set_C()
        cpu.pc += Int8(k)
    end       
end

"""Branch if Less Than (Signed). Rd < Rr"""
function brlt(k::Integer)
    if is_set_C()
        cpu.pc += Int8(k)
    end       
end

##### End Assembly Instructions #####

function assemble_program{T}(expressions::Vector{T})
    pcode = Expr[]                  # storage of expressions representing program
    symbols = Dict{Symbol, Int16}() # Maps symbols to program location
    
    for exp in expressions
       if isa(exp, Expr) && exp.head == :call
           push!(pcode, exp)
       elseif isa(exp, QuoteNode) && isa(exp.value, Symbol)
           symbols[exp.value] = length(pcode)
       end
    end
    (pcode, symbols)    
end

function assemble_program(program::Expr)
    assemble_program(program.args)
end


function assemble_program(filename::String)
    expressions = map(parse, readlines(filename))
    assemble_program(expressions)
end

"""Run program defined in `pcode` on CPU `cpu`"""
function run_program(cpu::CPU, pcode::Vector{Expr})
     # safety mechanism to avoid running too many instructions
     # in case we screwed up our code and got a non terminating program
    const max_no_instructions = 100
    cpu.pc = 1                       # Set Program Counter to Start of Program
    for i in 1:max_no_instructions
        println("$(cpu.pc): $(pcode[cpu.pc])")
        eval(pcode[cpu.pc])          # Run a single assembly instruction
        cpu.pc += 1
        if cpu.pc > length(pcode)
            println("Out of bounds: $(cpu.pc), exiting program.")
            break
        end
    end
end

function assemble_program!(pcode, psymbols)
    empty!(code)
    empty!(symbols)
    append!(code, pcode)
    merge!(+, symbols, psymbols) # Doesn't matter if we select + since symbols empty
end

assemble_program!(program::Expr) = assemble_program!(assemble_program(program)...)
assemble_program!(filename::String) = assemble_program!(assemble_program(filename)...)

run_program!() = run_program(cpu, code)
    

# Program beginning
reset!()

# prog = quote
#    ldi(r3, 4)
#    ldi(r1, 2)
#    :loop
#    add(r2, r1)
#    dec(r3)
#    brne(:loop)
# end

# assemble_program!(prog)
# assemble_program!("assemcode.jl")
# run_program!()
# println(r2)
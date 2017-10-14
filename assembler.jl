import Base: print, getindex, endof

function asm(a...)
    parse(string("0b", a...)) :: UInt16
    # string("0b", a...)
end

struct Register
    bitpattern::String
end

print(io::IO, r::Register) = print(io, r.bitpattern)
getindex(v::Register, i) = v.bitpattern[i]
endof(r::Register) = 5
 
for i in 0:31
    @eval const $(Symbol("r", i)) = Register(bin($i, 5))
end

struct Value
    bitpattern::String
    Value(v::UInt8) = new(bin(v, 8))
end

function value(v::Integer)
    if v >= 0
        Value(UInt8(v))
    else
        Value(reinterpret(UInt8, Int8(v)))
    end 
end

print(io::IO, v::Value) = print(io, v.bitpattern)
getindex(v::Value, i) = v.bitpattern[i]
endof(v::Value) = 8

function assemble_program{T}(expressions::Vector{T})
    opcodes = Expr[]                  # storage of expressions representing program
    global symbols = Dict{Symbol, Int16}() # Maps symbols to program location
    
    # First pass to get labels
    for exp in expressions
       if isa(exp, Expr) && exp.head == :call
           push!(opcodes, exp)
       elseif isa(exp, QuoteNode) && isa(exp.value, Symbol)
           symbols[exp.value] = length(opcodes) - 1
       end
    end
    
    # Second pass using labels
    machinecode = UInt16[]
    global pc = 0
    for opcode in opcodes
        push!(machinecode, eval(opcode))
        pc += 1
    end
    machinecode 
end

function assemble_program(filename::String)
    expressions = map(parse, readlines(filename))
    assemble_program(expressions)
end

ldi(Rd::Register, K::Value)     = asm("110"    , K[1:4], Rd, K[5:8])
add(Rd::Register, Rr::Register) = asm("000011" , Rr[1] , Rd, Rr[2:end])
adc(Rd::Register, Rr::Register) = asm("000111" , Rr[1] , Rd, Rr[2:end])
dec(Rd::Register)               = asm("1001010", Rd    , "1010")
brne(K::Value)                  = asm("111101" , K[1:7], "001")

function brne(label::Symbol)
    brne(value(symbols[label] - pc))
end
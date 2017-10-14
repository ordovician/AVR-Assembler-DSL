# Julia DSL for AVR Assembly

This is not a complete implementation, but rather a proof of concept for one could implement a simulator and assembler for the AVR microprocessor as a DSL (doman specific language) in Julia.

What this means is that we are utilizing Julia syntax to make something that looks like a different languages, AVR assembly code in this case.

## Using the Simulator
Start the Julia REPL in your terminal like this:

    $ julia -i assembly-simulator.jl
    
Then you can assemble code:

    julia> assemble_program!("assembly-code-for-simulator.jl")
    
And finally run it:

    julia> run_program!()
    
I print out what is going on as you run the program so you can more easily see how it works:

    1: ldi(r3, 4)
    2: ldi(r1, 2)
    3: add(r2, r1)
    4: dec(r3)
    5: brne(:loop)
    3: add(r2, r1)
    4: dec(r3)
    5: brne(:loop)
    3: add(r2, r1)
    4: dec(r3)
    5: brne(:loop)
    3: add(r2, r1)
    4: dec(r3)
    5: brne(:loop)
    Out of bounds: 6, exiting program.

After you run the program the register `r2` should be 8, since you add 2, to it four times.

    julia> r2
    Register(8)
    
## Using the Assembler
The assembler has not been tested very much yet, but this is how you use it. Start the REPL:

    $ julia -i assembler.jl 
    
Then load and assemble a file:
    julia> assemble_program("assembly-code-for-assembler.jl")
    5-element Array{UInt16,1}:
     0xc034
     0xc012
     0x0c21
     0x943a
     0xf7f1
     
We could look at bit more in detail at the produced machine code by turning it into binary code:

    julia> map(code->bin(code, 16), ans)
    5-element Array{String,1}:
     "1100000000110100"
     "1100000000010010"
     "0000110000100001"
     "1001010000111010"
     "1111011111110001"
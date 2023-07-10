# RISCV-Processor-In-Verilog
This project is an implementation of a 32-bit single core RISCV processor (RV32I) in verilog, as part of my end semester project of the course of Microprocessor Systems.

**R** (Register), **I** (Immediate), **S** (Store), **B** (Branch), and **jump** type instructions are supported.

The following design was consulted (credit @Berkerly_EECS_61C_Fall_2021):
![image](https://github.com/MoonisAmir10/RISCV-Processor-In-Verilog/assets/135621767/27f7ebcf-5d47-4409-bcdc-6a7e30a38ca0)


Here are the following characteristics of this processor:

1- Capable of executing all RISC-V instructions in one cycle each

2- Has 5 phases of execution i.e. Instruction fetch, decode, execute, store in data memory, and write back.

3- Not all instructions are active in all phases.

4- The datapath is the “union” of all the units used by all the instructions and muxes provide the options.

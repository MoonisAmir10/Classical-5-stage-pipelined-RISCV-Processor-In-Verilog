# RISCV-Processor-In-Verilog
This project is an implementation of a 32-bit single core RISCV processor (RV32I) in verilog, as part of my end semester project of the course of EE-222 Microprocessor Systems.

The design was further pipelined in 5 stages, with hazard control and forwarding.

**R** (Register), **I** (Immediate), **S** (Store), **B** (Branch), and **jump** type instructions are supported.

The following design was consulted (credit: Digital Design and Computer Architecture Lecture Notes ©2021 Sarah Harris and David Harris):
![image](https://github.com/MoonisAmir10/RISCV-Processor-In-Verilog/assets/135621767/fedad04a-14c9-4a99-ac3d-4318e7d7374c)


Here are the following characteristics of this processor:

1- Capable of executing all RISC-V instructions in one cycle each

2- Has 5 phases of execution i.e. Instruction fetch, decode, execute, memory access, and write back.

3- Not all instructions are active in all phases.

4- The datapath is the “union” of all the units used by all the instructions and muxes provide the options.

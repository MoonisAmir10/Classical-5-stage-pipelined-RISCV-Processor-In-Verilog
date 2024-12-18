module ControlUnit(
input [6:0] funct7,
input [2:0] funct3,
input [2:0] funct3_EX,
input [6:0] opcode,
input [6:0] opcode_EX,
input breq_flag,
input brlt_flag,
input bge_flag,
output reg [3:0] alu_select,
output reg reg_write_en,
output reg [1:0]imm_sel,
output reg bsel,
output reg asel,
output reg dm_write_en,
output reg [1:0] wbsel,
output reg brun_en,
output reg pc_sel
);

always @(funct7 or funct3 or opcode or breq_flag or brlt_flag or bge_flag)
    begin
	 // Initialize all control signals to default values
  reg_write_en = 0;
  imm_sel = 2'b00;
  bsel = 0;
  asel = 0;
  wbsel = 2'b00;
  dm_write_en = 0;
  //pc_sel = 0;
  alu_select = 4'b0000;
  brun_en = 0;
  
        if(opcode == 7'b0110011) begin // R-type instructions

            reg_write_en = 1;
            imm_sel = 0; //dont care
            bsel = 0;
            asel = 0;
            wbsel = 2'b00;  
            dm_write_en = 0; 
           // pc_sel = 0;

            case(funct3)
                3'b000: begin
                         if(funct7 == 0)
                          alu_select = 4'b0000; // ADD
                         else if(funct7 == 32)
                          alu_select = 4'b0001; // SUB
                        end
                3'b110: alu_select = 4'b0110; // OR
                3'b111: alu_select = 4'b0111; // AND
                3'b001: alu_select = 4'b0100; // SLL
                3'b101: begin
                         if (funct7 == 0)
                          alu_select = 4'b0101; // SRL
                         else if(funct7 == 32)
                          alu_select = 4'b0011; // SRA
                        end
		          3'b010: alu_select = 4'b0010; // SLT
		          3'b100: alu_select = 4'b1000; // XOR
					 default: alu_select = 4'b0000;
            endcase

        end

        else if(opcode == 7'b0010011) begin //I-type instructions

            reg_write_en = 1;
            imm_sel = 1;
            bsel = 1;
            asel = 0;
            wbsel = 2'b00;
            dm_write_en = 0;
           // pc_sel = 0;

            case(funct3)
                3'b000: alu_select = 4'b0000; // ADDI
                3'b110: alu_select = 4'b0110; // ORI
                3'b111: alu_select = 4'b0111; // ANDI
                3'b001: alu_select = 4'b0100; // SLLI
                3'b101: begin
                         if (funct7 == 0)
                          alu_select = 4'b0101; // SRLI
                         else if(funct7 == 32)
                          alu_select = 4'b0011; // SRAI
                        end
		          3'b010: alu_select = 4'b0010; // SLTI
		          3'b100: alu_select = 4'b1000; // XORI
					 default: alu_select = 4'b0000;
            endcase

         end

         else if(opcode == 7'b0000011) begin //Load word
               
            reg_write_en = 1;
            imm_sel = 1;
            bsel = 1;
            asel = 0;
            wbsel = 2'b01;  
            dm_write_en = 0;
          //  pc_sel = 0;

            alu_select = 4'b0000; //Adding base + offset

         end

         else if(opcode == 7'b0100011) begin //Store word
               
            reg_write_en = 0; //no write back
            imm_sel = 0; //S-format imm generation
            bsel = 1; 
            asel = 0;
            wbsel = 2'b00; // Dont care 
            dm_write_en = 1;
          //  pc_sel = 0;

            alu_select = 4'b0000; //Adding base + offset

         end

         else if(opcode == 7'b1100011) begin //Branch
               
            reg_write_en = 0; 
            imm_sel = 2'b10; //for B-format imm generations
            bsel = 1; 
            asel = 1; //to select pc
            wbsel = 2'b00; // Dont care
            dm_write_en = 0; //dmem will be in read mode
            //pc_sel = 0;

            alu_select = 4'b0000; //Adding base + offset

         end
			
			else if(opcode == 7'b1100111) begin // JALR 
               
            reg_write_en = 1; // store pc + 4 in some reg
            imm_sel = 2'b01; // I type imm
            bsel = 1; 
            asel = 0;
            wbsel = 2'b10; // to store pc + 4
            dm_write_en = 0; // dmem in read mode
            //pc_sel = 1; // will jump

            alu_select = 4'b0000; // For rs1 + imm

         end

    end


// BRANCH & JUMP CONTROLLER
always@(*)
begin
  pc_sel = 0;  // initial set
if(opcode_EX == 7'b1100011) begin //Branch
              
            case(funct3_EX)
                3'b000: begin
                         if (breq_flag)
                           pc_sel = 1;
                        end
                3'b100: begin //signed comparison
                          brun_en = 0;
                         if (brlt_flag)
                           pc_sel = 1;
                        end
                3'b101: begin
                         if (bge_flag)
                           pc_sel = 1;
                        end
                3'b110: begin //unsigned comparison
                           brun_en = 1;
                         if (brlt_flag)
                           pc_sel = 1;
                        end
					 default:   pc_sel = 0;
             endcase

         end
else if(opcode_EX == 7'b1100111) begin // JALR
     pc_sel = 1; // will jump
end
end

endmodule

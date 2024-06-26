module hazard_unit(RegWriteM, RegWriteW, wbsel_E, pc_sel, RD_E, RD_M, RD_W, Rs1_D, Rs1_E, 
                   Rs2_D, Rs2_E, ForwardAE, ForwardBE, stallF, stallD, flushD, flushE);

    input RegWriteM, RegWriteW, pc_sel;
	 input [1:0] wbsel_E;
    input [4:0] RD_E, RD_M, RD_W, Rs1_D, Rs1_E, Rs2_D, Rs2_E;
    output reg [1:0] ForwardAE, ForwardBE;
	 output stallF, stallD, flushD, flushE;
	 
	 wire lwstall;
    
//    assign ForwardAE = (rst == 1'b0) ? 2'b00 : 
//                       ((RegWriteM == 1'b1) & (RD_M != 5'h00) & (RD_M == Rs1_E)) ? 2'b10 :
//                       ((RegWriteW == 1'b1) & (RD_W != 5'h00) & (RD_W == Rs1_E)) ? 2'b01 : 2'b00;
//                       
//    assign ForwardBE = (rst == 1'b0) ? 2'b00 : 
//                       ((RegWriteM == 1'b1) & (RD_M != 5'h00) & (RD_M == Rs2_E)) ? 2'b10 :
//                       ((RegWriteW == 1'b1) & (RD_W != 5'h00) & (RD_W == Rs2_E)) ? 2'b01 : 2'b00;


///// Forwarding Logic /////
always@(*)
begin
  if (((Rs1_E == RD_M) && RegWriteM) && (Rs1_E != 0))
      ForwardAE = 2'b10;
  else if (((Rs1_E == RD_W) && RegWriteW) && (Rs1_E != 0))
      ForwardAE = 2'b01;
  else
      ForwardAE = 2'b00;
end

always@(*)
begin
  if (((Rs2_E == RD_M) && RegWriteM) && (Rs2_E != 0))
      ForwardBE = 2'b10;
  else if (((Rs2_E == RD_W) && RegWriteW) && (Rs2_E != 0))
      ForwardBE = 2'b01;
  else
      ForwardBE = 2'b00;
end


/////// LW hazard control logic /////
assign lwstall = ((Rs1_D == RD_E) | (Rs2_D == RD_E)) & wbsel_E[0] & wbsel_E[1];

assign stallF = !(lwstall | pc_sel);

assign stallD = !(lwstall | pc_sel);

assign flushE = lwstall | pc_sel;


///// Brach and jump hazard control /////
assign flushD = pc_sel;

//assign stallF = 1'b1;
//assign stallD = 1'b1;
//assign flushD = 1'b0;
//assign flushE = 1'b0;

							  
endmodule
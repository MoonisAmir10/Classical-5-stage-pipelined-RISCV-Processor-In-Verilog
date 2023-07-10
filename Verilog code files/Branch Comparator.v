module branch_comparator(
input [31:0] inpA,
input [31:0] inpB,
input brun_en,
output reg breq_flag,
output reg brlt_flag,
output reg bge_flag
);

always @(*)
begin
  if (inpA == inpB) begin
     breq_flag <= 1;
     brlt_flag <= 0;
     bge_flag <= 0;
  end

  else if (inpA >= inpB) begin
     breq_flag <= 0;
     brlt_flag <= 0;
     bge_flag <= 0;
  end

  if ((brun_en == 1) && $unsigned(inpA) < $unsigned(inpB)) begin
     breq_flag <= 0;
     brlt_flag <= 1;
     bge_flag <= 0;
  end

  if ((brun_en == 0) && $signed(inpA) < $signed(inpB)) begin
     breq_flag <= 0;
     brlt_flag <= 1;
     bge_flag <= 0;
  end

end
endmodule

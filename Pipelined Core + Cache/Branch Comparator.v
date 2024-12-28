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
  // Initialize flags to default values
  breq_flag = 0;
  brlt_flag = 0;
  bge_flag = 0;

  if (inpA == inpB)
    breq_flag = 1;
  else if (($unsigned(inpA) < $unsigned(inpB)) && brun_en == 1)
      brlt_flag = 1;
  else if (($signed(inpA) < $signed(inpB)) && brun_en == 0)
      brlt_flag = 1;
  else if (inpA >= inpB)
    bge_flag = 1;
end

endmodule


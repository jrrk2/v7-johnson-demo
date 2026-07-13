// AUTO-GENERATED pip-fuzz harness (pipfuzz_gen.py)
module pipfuzz(input wire din, output wire dout);
  wire [3:0] mid, q;
  (* DONT_TOUCH="true" *) LUT1 #(.INIT(2'b10)) la0 (.I0(din), .O(mid[0]));
  (* DONT_TOUCH="true" *) LUT1 #(.INIT(2'b10)) lb0 (.I0(mid[0]), .O(q[0]));
  (* DONT_TOUCH="true" *) LUT1 #(.INIT(2'b10)) la1 (.I0(din), .O(mid[1]));
  (* DONT_TOUCH="true" *) LUT1 #(.INIT(2'b10)) lb1 (.I0(mid[1]), .O(q[1]));
  (* DONT_TOUCH="true" *) LUT1 #(.INIT(2'b10)) la2 (.I0(din), .O(mid[2]));
  (* DONT_TOUCH="true" *) LUT1 #(.INIT(2'b10)) lb2 (.I0(mid[2]), .O(q[2]));
  (* DONT_TOUCH="true" *) LUT1 #(.INIT(2'b10)) la3 (.I0(din), .O(mid[3]));
  (* DONT_TOUCH="true" *) LUT1 #(.INIT(2'b10)) lb3 (.I0(mid[3]), .O(q[3]));
  assign dout = ^q;
endmodule

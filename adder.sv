module adder( input [7:0]a, input [7:0]b,  input cin, output [8:0]sum, output cout);

wire [9:0] sum1;
assign  sum1 =  a+b+cin; 
assign cout = sum1[9];
assign sum = sum1[8:0];

endmodule


module tb_adder ();

reg [7:0] a, b;
reg cin;
wire [8:0] sum;
wire cout;

adder adder1( .a(a), .b(b), .cin(cin), .cout(cout), .sum(sum));

initial 
begin
	a = 10; b = 20; cin = 0;
	#10;
	a = 40; b = 9; cin = 0;
       	#10;
	a = 70; b = 12; cin = 0;
	#10;
	a = 32; b =16; cin = 0;
	#10;
	a = 40; b = 0; cin = 0;
	#10;
	$finish; 
end

endmodule
 

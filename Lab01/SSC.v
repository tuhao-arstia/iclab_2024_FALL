//############################################################################
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//   (C) Copyright Laboratory System Integration and Silicon Implementation
//   All Right Reserved
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   ICLAB 2024 Fall
//   Lab01 Exercise		: Snack Shopping Calculator
//   Author     		  : Yu-Hsiang Wang
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   File Name   : SSC.v
//   Module Name : SSC
//   Release version : V1.0 (Release Date: 2024-09)
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//############################################################################

module SSC(
    // Input signals
    card_num,
    input_money,
    snack_num,
    price, 
    // Output signals
    out_valid,
    out_change
);

//================================================================
//   INPUT AND OUTPUT DECLARATION                         
//================================================================
input [63:0] card_num;
input [8:0] input_money;
input [31:0] snack_num;
input [31:0] price;
output out_valid;
output [8:0] out_change;    

//================================================================
//    Wire & Registers 
//================================================================
reg out_valid_reg;
reg [8:0] out_change_reg;    
// Declare the wire/reg you would use in your circuit
// remember 
// wire for port connection and cont. assignment
// reg for proc. assignment

//card validation
wire    [3:0]   snum1, snum3, snum5, snum7, snum9, snum11, snum13, snum15;
wire    [3:0]   num1, num3, num5, num7, num9, num11, num13, num15;
wire    [4:0]   sum_l1_0, sum_l1_1, sum_l1_2, sum_l1_3, sum_l1_4, sum_l1_5, sum_l1_6, sum_l1_7;
wire    [5:0]   sum_l2_0, sum_l2_1, sum_l2_2, sum_l2_3;
wire    [6:0]   sum_l3_0, sum_l3_1;
wire    [7:0]   sum;

//sorting
wire    [7:0]   total7, total6, total5, total4, total3, total2, total1, total0;
wire    [7:0]   a7, a6, a5, a4, a3, a2, a1, a0;
wire    [7:0]   b7, b6, b5, b4, b3, b2, b1, b0;
wire    [7:0]   s7, c6, c5, c4, c3, c2, c1, s0;
wire    [7:0]   d5, d4, d3;
wire    [7:0]   e6, e4, e3;
wire    [7:0]   s6, s5, s4, s3;
wire    [7:0]   d2, e1, s1 ,s2;

//================================================================
//    DESIGN
//================================================================
//card validation
assign snum15 = {card_num[62:60],1'b0};
assign snum13 = {card_num[54:52],1'b0};
assign snum11 = {card_num[46:44],1'b0};
assign snum9  = {card_num[38:36],1'b0};
assign snum7  = {card_num[30:28],1'b0};
assign snum5  = {card_num[22:20],1'b0};
assign snum3  = {card_num[14:12],1'b0};
assign snum1  = {card_num[6:4]  ,1'b0};
assign num15 = (card_num[63:60]<4'd5) ? snum15 : snum15 - 'b1001;
assign num13 = (card_num[55:52]<4'd5) ? snum13 : snum13 - 'b1001;
assign num11 = (card_num[47:44]<4'd5) ? snum11 : snum11 - 'b1001;
assign num9  = (card_num[39:36]<4'd5) ? snum9  : snum9  - 'b1001;
assign num7  = (card_num[31:28]<4'd5) ? snum7  : snum7  - 'b1001;
assign num5  = (card_num[23:20]<4'd5) ? snum5  : snum5  - 'b1001;
assign num3  = (card_num[15:12]<4'd5) ? snum3  : snum3  - 'b1001;
assign num1  = (card_num[7:4]  <4'd5) ? snum1  : snum1  - 'b1001;

assign sum_l1_0 = card_num[59:56] + card_num[51:48];
assign sum_l1_1 = card_num[43:40] + card_num[35:32];
assign sum_l1_2 = card_num[27:24] + card_num[19:16];
assign sum_l1_3 = card_num[11:8] + card_num[3:0];
assign sum_l1_4 = num15 + num1;
assign sum_l1_5 = num5 + num7;
assign sum_l1_6 = num9 + num11;
assign sum_l1_7 = num3 + num13;

assign sum_l2_0 = sum_l1_0 + sum_l1_1;
assign sum_l2_1 = sum_l1_2 + sum_l1_3;
assign sum_l2_2 = sum_l1_4 + sum_l1_5;
assign sum_l2_3 = sum_l1_6 + sum_l1_7;

assign sum_l3_0 = sum_l2_0 + sum_l2_1;
assign sum_l3_1 = sum_l2_2 + sum_l2_3;

assign sum = sum_l3_0 + sum_l3_1;
//sorting network (19 cmps)
MUL mul1(.in2(snack_num[31:28]), .in1(price[31:28]), .out(total7));
MUL mul2(.in1(snack_num[27:24]), .in2(price[27:24]), .out(total6));
MUL mul3(.in1(snack_num[23:20]), .in2(price[23:20]), .out(total5));
MUL mul4(.in1(snack_num[19:16]), .in2(price[19:16]), .out(total4));
MUL mul5(.in1(snack_num[15:12]), .in2(price[15:12]), .out(total3));
MUL mul6(.in1(snack_num[11:8] ), .in2(price[11:8] ), .out(total2));
MUL mul7(.in1(snack_num[7:4]  ), .in2(price[7:4]  ), .out(total1));
MUL mul8(.in1(snack_num[3:0]  ), .in2(price[3:0]  ), .out(total0));

assign a7 = (total7 < total5) ? total5 : total7;
assign a5 = (total7 < total5) ? total7 : total5;

assign a6 = (total6 < total4) ? total4 : total6;
assign a4 = (total6 < total4) ? total6 : total4;
assign a3 = (total3 < total1) ? total1 : total3;
assign a1 = (total3 < total1) ? total3 : total1;
assign a2 = (total2 < total0) ? total0 : total2;
assign a0 = (total2 < total0) ? total2 : total0;
assign b7 = (a7 > a3) ? a7 : a3;
assign b3 = (a7 > a3) ? a3 : a7;
assign b6 = (a6 > a2) ? a6 : a2;
assign b2 = (a6 > a2) ? a2 : a6;
assign b5 = (a5 > a1) ? a5 : a1;
assign b1 = (a5 > a1) ? a1 : a5;
assign b4 = (a4 > a0) ? a4 : a0;
assign b0 = (a4 > a0) ? a0 : a4;
assign s7 = (b7 > b6) ? b7 : b6;
assign c6 = (b7 > b6) ? b6 : b7;
assign c5 = (b5 > b4) ? b5 : b4;
assign c4 = (b5 > b4) ? b4 : b5;
assign c3 = (b3 > b2) ? b3 : b2;
assign c2 = (b3 > b2) ? b2 : b3;
assign c1 = (b1 > b0) ? b1 : b0;
assign s0 = (b1 > b0) ? b0 : b1;
assign d5 = (c5 > c3) ? c5 : c3;
assign d3 = (c5 > c3) ? c3 : c5;
assign d4 = (c4 > c2) ? c4 : c2;
assign d2 = (c4 > c2) ? c2 : c4;
assign e6 = (c6 > d3) ? c6 : d3;
assign e3 = (c6 > d3) ? d3 : c6;
assign e4 = (d4 > c1) ? d4 : c1;
assign e1 = (d4 > c1) ? c1 : d4;
assign s6 = (e6 > d5) ? e6 : d5;
assign s5 = (e6 > d5) ? d5 : e6;
assign s4 = (e4 > e3) ? e4 : e3;
assign s3 = (e4 > e3) ? e3 : e4;
assign s2 = (d2 > e1) ? d2 : e1;
assign s1 = (d2 > e1) ? e1 : d2;
//output
always @(*) begin
    if((sum%10)==0)begin
        out_valid_reg = 1;
    end else begin
        out_valid_reg = 0;
    end
end
assign out_valid = out_valid_reg;

// you can try add 2's complement or just subtract to calculate the change
always @(*) begin
    if(input_money < s7 || (sum%10)!=0)begin
        out_change_reg = input_money;
    end else if((input_money -s7) < s6)begin
        out_change_reg = input_money -s7;
    end else if((input_money -s7 -s6) < s5)begin
        out_change_reg = input_money -s7 -s6;
    end else if((input_money -s7 -s6 -s5) < s4)begin
        out_change_reg = input_money -s7 -s6 -s5;
    end else if((input_money -s7 -s6 -s5 -s4) < s3)begin
        out_change_reg = input_money -s7 -s6 -s5 -s4;
    end else if((input_money -s7 -s6 -s5 -s4 -s3) < s2)begin
        out_change_reg = input_money -s7 -s6 -s5 -s4 -s3;
    end else if((input_money -s7 -s6 -s5 -s4 -s3 -s2) < s1)begin
        out_change_reg = input_money -s7 -s6 -s5 -s4 -s3 -s2;
    end else if((input_money -s7 -s6 -s5 -s4 -s3 -s2 -s1) < s0)begin
        out_change_reg = input_money -s7 -s6 -s5 -s4 -s3 -s2 -s1;
    end else begin
        out_change_reg = input_money -s7 -s6 -s5 -s4 -s3 -s2 -s1 -s0;
    end
end
assign out_change = out_change_reg;

endmodule

module CMPB (in1, in2, big, sml);
input [7:0] in1;
input [7:0] in2;
output[7:0] big;
output[7:0] sml;
assign big = (in1 > in2) ? in1 : in2;
assign sml = (in1 > in2) ? in2 : in1;
endmodule
module CMPS (in1, in2, big, sml);
input [7:0] in1;
input [7:0] in2;
output[7:0] big;
output[7:0] sml;
assign big = (in1 < in2) ? in2 : in1;
assign sml = (in1 < in2) ? in1 : in2;
endmodule

module MUL(in1, in2, out);
    input [3:0] in1, in2;
    output [7:0] out;
    wire [3:0] sft0;
    wire [4:0] sft1, sb1;
    wire [5:0] sft2, sb2;
    wire [6:0] sft3, sb3;
    assign sb1 = {in1,1'b0};
    assign sb2 = {in1,2'b00};
    assign sb3 = {in1,3'b000};
    assign sft0 = (in2[0])?in1:0;
    assign sft1 = (in2[1])?sb1:0;
    assign sft2 = (in2[2])?sb2:0;
    assign sft3 = (in2[3])?sb3:0;
    assign out = (sft0 + sft1) + (sft3 + sft2) ;
endmodule


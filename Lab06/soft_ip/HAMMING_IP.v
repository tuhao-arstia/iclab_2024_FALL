//############################################################################
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//    (C) Copyright System Integration and Silicon Implementation Laboratory
//    All Right Reserved
//		Date		: 2024/10
//		Version		: v1.0
//   	File Name   : HAMMING_IP.v
//   	Module Name : HAMMING_IP
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//############################################################################
module HAMMING_IP #(parameter IP_BIT = 8) (
    // Input signals
    IN_code,
    // Output signals
    OUT_code
);

// ===============================================================
// Input & Output
// ===============================================================
input [IP_BIT+4-1:0]  IN_code;

output reg [IP_BIT-1:0] OUT_code;

// ===============================================================
// Design
// ===============================================================
wire [IP_BIT+4-1:0] xor_out_0;
wire [IP_BIT+4-1:0] xor_out_1;
wire [IP_BIT+4-1:0] xor_out_2;
wire [IP_BIT+4-1:0] xor_out_3;
wire [3:0]  err_pos;
wire [IP_BIT+4-1:0] out_code_temp;

genvar i;
generate
    for(i = 0; i < IP_BIT+4 ; i = i + 1)begin: bf
        wire [3:0] binary_form;
        wire bit_3, bit_2, bit_1, bit_0;
        // starting from the MSB of IN_code to LSB of IN_code
        assign binary_form = (IN_code[IP_BIT+4-1-i] == 1) ? i+1 : 4'b0;
        assign bit_3 = binary_form[3];
        assign bit_2 = binary_form[2];
        assign bit_1 = binary_form[1];
        assign bit_0 = binary_form[0];
    end
endgenerate

generate
    for(i = 0; i < IP_BIT+4 ; i = i + 1)begin: xor_0
        if(i == 0)begin
            assign xor_out_0[0] = bf[0].bit_0;
        end else begin
            assign xor_out_0[i] = xor_out_0[i-1] ^ bf[i].bit_0;
        end
    end
endgenerate

generate
    for(i = 0; i < IP_BIT+4 ; i = i + 1)begin: xor_1
        if(i == 0)begin
            assign xor_out_1[0] = bf[0].bit_1;
        end else begin
            assign xor_out_1[i] = xor_out_1[i-1] ^ bf[i].bit_1;
        end
    end
endgenerate

generate
    for(i = 0; i < IP_BIT+4 ; i = i + 1)begin: xor_2
        if(i == 0)begin
            assign xor_out_2[0] = bf[0].bit_2;
        end else begin
            assign xor_out_2[i] = xor_out_2[i-1] ^ bf[i].bit_2;
        end
    end
endgenerate

generate
    for(i = 0; i < IP_BIT+4 ; i = i + 1)begin: xor_3
        if(i == 0)begin
            assign xor_out_3[0] = bf[0].bit_3;
        end else begin
            assign xor_out_3[i] = xor_out_3[i-1] ^ bf[i].bit_3;
        end
    end
endgenerate

assign err_pos = {xor_out_3[IP_BIT+4-1], xor_out_2[IP_BIT+4-1], xor_out_1[IP_BIT+4-1], xor_out_0[IP_BIT+4-1]};

generate
    for(i = 0; i < IP_BIT+4 ; i = i + 1)begin
        assign out_code_temp[IP_BIT+4-1-i] = (err_pos == i+1)? ~IN_code[IP_BIT+4-1-i]: IN_code[IP_BIT+4-1-i];
    end
endgenerate

always @(*) begin
    if(err_pos == 4'b0000)begin
        OUT_code = {IN_code[IP_BIT+4-3], IN_code[IP_BIT+4-5:IP_BIT+4-7], IN_code[IP_BIT+4-9:0]};
    end else begin
        OUT_code = {out_code_temp[IP_BIT+4-3], out_code_temp[IP_BIT+4-5:IP_BIT+4-7], out_code_temp[IP_BIT+4-9:0]};
    end
end

endmodule
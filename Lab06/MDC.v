//############################################################################
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//    (C) Copyright System Integration and Silicon Implementation Laboratory
//    All Right Reserved
//		Date		: 2024/9
//		Version		: v1.0
//   	File Name   : MDC.v
//   	Module Name : MDC
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//############################################################################

//synopsys translate_off
`include "HAMMING_IP.v"
//synopsys translate_on

module MDC(
    // Input signals
    clk,
	rst_n,
	in_valid,
    in_data, 
	in_mode,
    // Output signals
    out_valid, 
	out_data
);

// ===============================================================
// Input & Output Declaration
// ===============================================================
input clk, rst_n, in_valid;
input [14:0] in_data;
input [8:0] in_mode;
output reg out_valid;
output reg [206:0] out_data;

// parameter
parameter MODE_2 = 5'b00100;
parameter MODE_3 = 5'b00110;
parameter MODE_4 = 5'b10110;
integer i;

// global counter
reg [4:0] cnt ,ns_cnt;
// decoding wire
wire signed [10:0] decode_data;
wire signed [4:0]  decode_mode;

// input
reg signed  [10:0] data [0:7];
reg signed  [4:0]  mode;

// det elements
reg signed  [10:0] d1_1, d1_2, d1_3, d1_4;
reg signed  [10:0] d2_1, d2_2, d2_3, d2_4;
wire signed [21:0] ns_d1_out, ns_d2_out;

reg signed  [10:0] ms1_11, ms2_11;
reg signed  [21:0] ms1_22, ms2_22;
wire signed [32:0] ns_det3_mult_temp1, ns_det3_mult_temp2;

reg signed  [10:0] ml_11;
reg signed  [34:0] ml_35;
wire signed [45:0] ns_det4_mult_temp1;

// saving registers
reg signed  [21:0] det2_temp [0:5];
reg signed  [34:0] det3_temp [0:3];
reg signed  [47:0] det4_temp;

// ===============================================================
// Design
// ===============================================================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt <= 0;
    end else begin
        cnt <= ns_cnt;
    end
end
always @(*) begin
    if(cnt == 0 && !in_valid)begin
        ns_cnt = 0;
    end else if(cnt == 'd17)begin
        ns_cnt = 0;
    end else begin
        ns_cnt = cnt + 'd1;
    end
end

// decode
HAMMING_IP #(.IP_BIT(11))
        DATA(.IN_code(in_data), .OUT_code(decode_data));
HAMMING_IP #(.IP_BIT(5))
        MODE(.IN_code(in_mode), .OUT_code(decode_mode));

// seq. + comb. better or just seq. shifting
always @(posedge clk) begin
    if(in_valid)begin
        data[0] <= data[1];
        data[1] <= data[2];
        data[2] <= data[3];
        data[3] <= data[4];
        data[4] <= data[5];
        data[5] <= data[6];
        data[6] <= data[7];
        data[7] <= decode_data;
    end
end

always @(posedge clk) begin
    if(in_valid && cnt == 0)begin
        mode <= decode_mode;
    end
end
// calculate mult by order 4:
assign ns_det4_mult_temp1 = ml_11 * ml_35;
always @(*) begin
    if(mode == MODE_4 && (cnt == 'd13 || cnt == 'd15))begin
        ml_11 = ~data[7] + 11'sd1;
    end else if(mode == MODE_4 && (cnt == 'd14 || cnt == 'd16)) begin
        ml_11 = data[7];
    end else begin
        // for det 2x2
        ml_11 = data[3];
    end
end
always @(*) begin
    // ml_35 = 0;
    case (cnt)
        'd13:begin
            ml_35 = det3_temp[0];
        end
        'd14:begin
            ml_35 = det3_temp[1];
        end
        'd15:begin
            ml_35 = det3_temp[2];
        end
        'd16:begin
            ml_35 = det3_temp[3];
        end
        default:begin
            if(mode == MODE_3)begin
                // ml_35 = {{24{data[5][10]}}, data[5]};
                ml_35 = data[5];
            end else begin
                // ml_35 = {{24{data[6][10]}}, data[6]};
                ml_35 = data[6];
            end
        end
    endcase
end

// calculate det 2x2
wire signed [20:0] d1_temp14, d1_temp23, d2_temp14;
mult_11_11 D1_1(d1_1, d1_4, d1_temp14);
mult_11_11 D1_2(d1_2, d1_3, d1_temp23);
assign ns_d1_out = d1_temp14 - d1_temp23;

mult_11_11 D2_1(d2_1, d2_4, d2_temp14);
// use the largest mult: ns_det4_mult_temp1(needs truncation) = d2_2 * d2_3
assign ns_d2_out = d2_temp14 - $signed(ns_det4_mult_temp1[20:0]);

// det_2_2 D1(.in1(d1_1), .in2(d1_2), .in3(d1_3), .in4(d1_4), .out(ns_d1_out));
// det_2_2 D2(.in1(d2_1), .in2(d2_2), .in3(d2_3), .in4(d2_4), .out(ns_d2_out));
always @(*) begin
    d1_1 = 0;
    d2_1 = 0;
    // d2_1 = data[2];
    case (mode)
        MODE_2:begin
            d1_1 = data[2];
        end
        MODE_3:begin
            d1_1 = data[1];
            d2_1 = data[1];
        end
        MODE_4:begin
            case (cnt)
                'd6:begin
                    d1_1 = data[2];
                end
                'd7:begin
                    d1_1 = data[1];
                    d2_1 = data[2];
                end
                'd8:begin
                    d1_1 = data[0];
                    d2_1 = data[2];
                end
                'd9:begin
                    d1_1 = data[0];
                end
            endcase
        end
    endcase
end
always @(*) begin
    // d1_2 = 0;
    // d2_2 = 0;
    d1_2 = data[3];
    // d2_2 goes to ml_11
    // d2_2 = data[3]; 
    case (mode)
        // MODE_2:begin
            // d1_2 = data[3];
        // end 
        MODE_3:begin
            d1_2 = data[2];
            // d2_2 = data[3];
        end
        MODE_4:begin
            case (cnt)
                // 'd6:begin
                    // d1_2 = data[3];
                // end 
                // 'd7:begin
                    // d1_2 = data[3];
                    // d2_2 = data[3];
                // end
                // 'd8:begin
                    // d1_2 = data[3];
                    // d2_2 = data[3];
                // end
                'd9:begin
                    d1_2 = data[2];
                end
            endcase
        end
    endcase
end
always @(*) begin
    d1_3 = 0;
    // d2_3 = 0;
    // d2_3 goes to ml_35
    // d2_3 = data[6];
    case (mode)
        MODE_2:begin
            d1_3 = data[6];
        end 
        MODE_3:begin
            d1_3 = data[5];
            // d2_3 = data[5]; 
        end
        MODE_4:begin
            case (cnt)
                'd6:begin
                    d1_3 = data[6];
                end
                'd7:begin
                    d1_3 = data[5];
                    // d2_3 = data[6];
                end
                'd8:begin
                    d1_3 = data[4];
                    // d2_3 = data[6];
                end
                'd9:begin
                    d1_3 = data[4];
                end
            endcase
        end
    endcase
end
always @(*) begin
    // d1_4 = 0;
    // d2_4 = 0;
    d1_4 = data[7];
    d2_4 = data[7]; 
    case (mode)
        // MODE_2:begin
            // d1_4 = data[7];
        // end 
        MODE_3:begin
            d1_4 = data[6];
            // d2_4 = data[7];
        end
        MODE_4:begin
            case (cnt)
                // 'd6:begin
                    // d1_4 = data[7];
                // end
                // 'd7:begin
                    // d1_4 = data[7];
                    // d2_4 = data[7];
                // end
                // 'd8:begin
                    // d1_4 = data[7];
                    // d2_4 = data[7];
                // end
                'd9:begin
                    d1_4 = data[6];
                end
            endcase
        end
    endcase
end

always @(posedge clk) begin
    case (mode)
        MODE_2:begin
            case (cnt)
                'd6:begin
                    det2_temp[0] <= ns_d1_out;
                end
                'd7:begin
                    det2_temp[1] <= ns_d1_out;
                end
                'd8:begin
                    det2_temp[2] <= ns_d1_out;
                end
                'd10:begin
                    det2_temp[3] <= ns_d1_out;
                end
                'd11:begin
                    det2_temp[4] <= ns_d1_out;
                end
                'd12:begin
                    det2_temp[5] <= ns_d1_out;
                end
            endcase
        end 
        MODE_3:begin
            case (cnt)
                'd7, 'd11:begin
                    det2_temp[0] <= ns_d1_out;
                    det2_temp[1] <= ns_d2_out;
                end
                'd8, 'd12:begin
                    det2_temp[2] <= ns_d1_out;
                    det2_temp[3] <= ns_d2_out;
                end
                'd9, 'd13:begin
                    det2_temp[4] <= ns_d1_out;
                end
            endcase
        end
        MODE_4:begin
            case (cnt)
                'd6:begin
                    //ab
                    det2_temp[0] <= ns_d1_out;
                end 
                'd7:begin
                    //ac
                    det2_temp[1] <= ns_d1_out;
                    //bc
                    det2_temp[2] <= ns_d2_out;
                end
                'd8:begin
                    //ad
                    det2_temp[3] <= ns_d1_out;
                    //cd
                    det2_temp[4] <= ns_d2_out;
                end
                'd9:begin
                    //bd
                    det2_temp[5] <= ns_d1_out;
                end
            endcase
        end
        default:begin
            for(i = 0; i < 6; i = i + 1)begin
                det2_temp[i] <= 22'sd0;
            end
        end
    endcase
end

// calculate mult by order 3: MS1 for positive minors, MS2 for negative minors
mult_11x23 MS1(.in1(ms1_11), .in2(ms1_22), .out(ns_det3_mult_temp1));
mult_11x23 MS2(.in1(ms2_11), .in2(ms2_22), .out(ns_det3_mult_temp2));
always @(*) begin
    ms1_11 = 0;
    ms2_11 = 0;
    case (mode)
        MODE_3:begin
            ms1_11 = data[7];
            ms2_11 = ~data[7] + 11'sd1;
        end
        MODE_4:begin
            case (cnt)
                'd10:begin
                    ms1_11 = data[7];
                    ms2_11 = ~data[7] + 11'sd1;
                end
                'd11:begin
                    ms1_11 = ~data[7] + 11'sd1;
                    ms2_11 = ~data[7] + 11'sd1;
                end
                'd13:begin
                    //a3
                    ms1_11 = data[3];
                    //-b3
                    ms2_11 = ~data[4] + 11'sd1;
                end
                'd14:begin
                    //d3
                    ms1_11 = data[5];
                    //c3
                    ms2_11 = data[4];
                end
                'd9, 'd13:begin
                    ms1_11 = data[7];
                    ms2_11 = data[7];
                end
                // default:begin
                    // 'd9:a3, d12:d3
                    // ms1_11 = data[7];
                    // ms2_11 = data[7];
                // end 
            endcase
        end
    endcase
end
always @(*) begin
    ms1_22 = 0;
    ms2_22 = 0;
    case (mode)
        MODE_3:begin
            case (cnt)
                'd9, 'd12, 'd13, 'd16:begin
                    ms1_22 = det2_temp[2];
                end
                'd10, 'd14:begin
                    ms1_22 = det2_temp[4];
                    ms2_22 = det2_temp[1];
                end
                'd11, 'd15:begin
                    ms1_22 = det2_temp[0];
                    ms2_22 = det2_temp[3];
                end
            endcase
        end
        MODE_4:begin
            case (cnt)
                'd9:begin
                    // a3*cd
                    ms1_22 = det2_temp[4];
                    // a3*bc
                    ms2_22 = det2_temp[2];
                end
                'd10:begin
                    // b3*cd
                    ms1_22 = det2_temp[4];
                    // -b3*ad
                    ms2_22 = det2_temp[3];
                end
                'd11:begin
                    // -c3*bd
                    ms1_22 = det2_temp[5];
                    // -c3*ad
                    ms2_22 = det2_temp[3];
                end
                'd12:begin
                    // d3*bc
                    ms1_22 = det2_temp[2];
                    // d3*ac
                    ms2_22 = det2_temp[1];
                end
                'd13:begin
                    // a3*bd
                    ms1_22 = det2_temp[5];
                    // -b3*ac
                    ms2_22 = det2_temp[1];
                end
                'd14:begin
                    // d3*ab
                    ms1_22 = det2_temp[0];
                    // c3*ab
                    ms2_22 = det2_temp[0];
                end
            endcase
        end
    endcase
end

always @(posedge clk) begin
    case (mode)
        MODE_2:begin
            case (cnt)
                'd14:begin
                    det3_temp[0] <= $signed(ns_d1_out);
                end 
                'd15:begin
                    det3_temp[1] <= $signed(ns_d1_out);
                end
                'd16:begin
                    det3_temp[2] <= $signed(ns_d1_out);
                end
            endcase
        end 
        MODE_3:begin
            // jacky said tsu seu plus $signed()
            case (cnt)
                'd9:begin
                    det3_temp[0] <= $signed(ns_det3_mult_temp1);
                end
                'd10:begin
                    det3_temp[0] <= $signed(det3_temp[0]) + $signed(ns_det3_mult_temp2);
                    det3_temp[1] <= $signed(ns_det3_mult_temp1);
                end
                'd11:begin
                    det3_temp[0] <= $signed(det3_temp[0]) + $signed(ns_det3_mult_temp1);
                    det3_temp[1] <= $signed(det3_temp[1]) + $signed(ns_det3_mult_temp2);
                end
                'd12:begin
                    det3_temp[1] <= $signed(det3_temp[1]) + $signed(ns_det3_mult_temp1);
                end
                'd13:begin
                    det3_temp[2] <= $signed(ns_det3_mult_temp1);
                end
                'd14:begin
                    det3_temp[2] <= $signed(det3_temp[2]) + $signed(ns_det3_mult_temp2);
                    det3_temp[3] <= $signed(ns_det3_mult_temp1);
                end
                'd15:begin
                    det3_temp[2] <= $signed(det3_temp[2]) + $signed(ns_det3_mult_temp1);
                    det3_temp[3] <= $signed(det3_temp[3]) + $signed(ns_det3_mult_temp2);
                end
                'd16:begin
                    det3_temp[3] <= $signed(det3_temp[3]) + $signed(ns_det3_mult_temp1);
                end
            endcase
        end
        MODE_4:begin
            case (cnt)
                'd9:begin
                    det3_temp[1] <= $signed(ns_det3_mult_temp1);
                    det3_temp[3] <= $signed(ns_det3_mult_temp2);
                end
                'd10:begin
                    det3_temp[0] <= $signed(ns_det3_mult_temp1);
                    det3_temp[2] <= $signed(ns_det3_mult_temp2);
                end
                'd11, 'd12:begin
                    det3_temp[0] <= $signed(det3_temp[0]) + $signed(ns_det3_mult_temp1);
                    det3_temp[1] <= $signed(det3_temp[1]) + $signed(ns_det3_mult_temp2);
                end
                'd13, 'd14:begin
                    det3_temp[2] <= $signed(det3_temp[2]) + $signed(ns_det3_mult_temp1);
                    det3_temp[3] <= $signed(det3_temp[3]) + $signed(ns_det3_mult_temp2);
                end
            endcase
        end
        default:begin
            for(i = 0; i < 4; i = i + 1)begin
                det3_temp[i] <= 35'sd0;
            end
        end
    endcase
end

always @(posedge clk) begin
    case (cnt)
        // 'd13:begin
            // det4_temp <= $signed(ns_det4_mult_temp1);
        // end 
        'd13, 'd14, 'd15, 'd16:begin
            det4_temp <= $signed(det4_temp) + $signed(ns_det4_mult_temp1);
        end
        default:begin
            det4_temp <= 48'b0;
        end
    endcase
end
// output
always @(*) begin
    if(cnt == 'd17)begin
        out_valid = 1;
    end else begin
        out_valid = 0;
    end
end
always @(*) begin
    if(mode == MODE_2 && cnt == 'd17)begin
        out_data = {{1{det2_temp[0][21]}}, det2_temp[0], {1{det2_temp[1][21]}}, det2_temp[1], {1{det2_temp[2][21]}}, det2_temp[2], {1{det2_temp[3][21]}}, det2_temp[3], {1{det2_temp[4][21]}}, det2_temp[4], {1{det2_temp[5][21]}}, det2_temp[5], det3_temp[0][22:0], det3_temp[1][22:0], det3_temp[2][22:0]};
    end else if(mode == MODE_3 && cnt == 'd17)begin
        // out_data = 0;
        out_data = {3'b000, {16{det3_temp[0][34]}}, det3_temp[0][34:0], {16{det3_temp[1][34]}}, det3_temp[1][34:0], {16{det3_temp[2][34]}}, det3_temp[2][34:0], {16{det3_temp[3][34]}}, det3_temp[3][34:0]};
    end else if(mode == MODE_4 && cnt == 'd17)begin
        out_data = {{159{det4_temp[47]}}, det4_temp};
    end else begin
        out_data = 207'd0;
    end
end


endmodule

module mult_11_11(in1, in2, out);
input  signed [10:0] in1, in2;
output signed [20:0] out;
assign out = in1*in2;
endmodule
module add2_22_22(in1, in2, out);
input signed [20:0] in1, in2;
output signed [21:0] out;
assign out = in1 + in2;
endmodule

// det for 2x2 matrix 
module det_2_2(in1, in2, in3, in4, out);
input signed [10:0] in1, in2, in3, in4;
output signed [21:0] out;
wire signed [20:0] temp_14, temp_23;

//2's complement +1
// wire signed [10:0] opposite_in2;
// assign opposite_in2 = ~in2 + 11'sd1;
// mult_11_11 U_MUL_0(in1, in4, temp_14);
// mult_11_11 U_MUL_1(opposite_in2, in3, temp_23);
// add2_22_22 U_ADD_0(temp_14, temp_23, out);

//subtractor (better)
mult_11_11 U_MUL_0(in1, in4, temp_14);
mult_11_11 U_MUL_1(in2, in3, temp_23);
assign out = temp_14 - temp_23;
endmodule

module mult_11x23(in1, in2, out);
input signed [10:0] in1;
input signed [21:0] in2;
output signed [32:0] out;
assign out = in1 * in2;
endmodule
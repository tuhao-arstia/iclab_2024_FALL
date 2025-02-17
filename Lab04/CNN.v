//############################################################################
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//   (C) Copyright Laboratory System Integration and Silicon Implementation
//   All Right Reserved
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   ICLAB 2023 Fall
//   Lab04 Exercise		: Convolution Neural Network 
//   Author     		: Yu-Chi Lin (a6121461214.st12@nycu.edu.tw)
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   File Name   : CNN.v
//   Module Name : CNN
//   Release version : V1.0 (Release Date: 2024-10)
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//############################################################################

module CNN(
    //Input Port
    clk,
    rst_n,
    in_valid,
    Img,
    Kernel_ch1,
    Kernel_ch2,
	Weight,
    Opt,

    //Output Port
    out_valid,
    out
    );


//---------------------------------------------------------------------
//   PARAMETER
//---------------------------------------------------------------------
// IEEE floating point parameter
parameter inst_sig_width = 23;
parameter inst_exp_width = 8;
parameter inst_ieee_compliance = 0;
parameter inst_arch_type = 0;
parameter inst_arch = 0;
parameter inst_faithful_round = 0;
parameter FP_1 = 32'h3f800000;


input rst_n, clk, in_valid;
input [inst_sig_width+inst_exp_width:0] Img, Kernel_ch1, Kernel_ch2, Weight;
input Opt;

output reg	out_valid;
output reg [inst_sig_width+inst_exp_width:0] out;


//---------------------------------------------------------------------
//   Reg & Wires
//---------------------------------------------------------------------
integer i, j;
reg option, ns_option;

reg [2:0] x_img_cnt, y_img_cnt, ns_x_img_cnt, ns_y_img_cnt;

reg [inst_sig_width+inst_exp_width:0] img       [0:4][0:4];
reg [inst_sig_width+inst_exp_width:0] k1_1      [0:3];
reg [inst_sig_width+inst_exp_width:0] ns_k1_1   [0:3];
reg [inst_sig_width+inst_exp_width:0] k1_2      [0:3];
reg [inst_sig_width+inst_exp_width:0] ns_k1_2   [0:3];
reg [inst_sig_width+inst_exp_width:0] k1_3      [0:3];
reg [inst_sig_width+inst_exp_width:0] ns_k1_3   [0:3];
reg [inst_sig_width+inst_exp_width:0] k2_1      [0:3];
reg [inst_sig_width+inst_exp_width:0] ns_k2_1   [0:3];
reg [inst_sig_width+inst_exp_width:0] k2_2      [0:3];
reg [inst_sig_width+inst_exp_width:0] ns_k2_2   [0:3];
reg [inst_sig_width+inst_exp_width:0] k2_3      [0:3];
reg [inst_sig_width+inst_exp_width:0] ns_k2_3   [0:3];
reg [inst_sig_width+inst_exp_width:0] weight    [0:2][0:7];
reg [inst_sig_width+inst_exp_width:0] ns_weight [0:2][0:7];


// feature maps
reg [inst_sig_width+inst_exp_width:0] f_map_1   [0:5][0:5];
reg [inst_sig_width+inst_exp_width:0] f_map_2   [0:5][0:5];


reg [6:0] cnt ,ns_cnt;

//---------------------------------------------------------------------
// Design
//---------------------------------------------------------------------
// counter control
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
    end else if (cnt == 'd90) begin
        ns_cnt = 0;
    end else begin
        ns_cnt = cnt + 'd1;
    end
end

// receiving option
always @(posedge clk) begin
    option <= ns_option;
end
always @(*) begin
    if(in_valid && cnt == 0)begin
        ns_option = Opt;
    end else begin
        ns_option = option;
    end
end

// xy counters
always @(posedge clk) begin
    x_img_cnt <= ns_x_img_cnt;
    y_img_cnt <= ns_y_img_cnt;
end

always @(*) begin
    // not using fsm cause filling img is within WAIT and CONV
    if(in_valid)begin
        if(x_img_cnt == 3'd4)begin
            if(y_img_cnt == 3'd4)begin
                ns_x_img_cnt = 0;
                ns_y_img_cnt = 0;
            end else begin
                ns_x_img_cnt = 0;
                ns_y_img_cnt = y_img_cnt + 'd1;
            end
        end else begin
            ns_x_img_cnt = x_img_cnt + 'd1;
            ns_y_img_cnt = y_img_cnt;
        end
    end else begin
        ns_x_img_cnt = 0;
        ns_y_img_cnt = 0;
    end
end

// receiving img
always @(posedge clk) begin
    if(in_valid)begin
        img[y_img_cnt][x_img_cnt] <= Img;
    end
end

// receiving kernel
always @(posedge clk) begin
    for( i = 0; i < 4; i = i + 1)begin
        k1_1[i] <= ns_k1_1[i];
        k2_1[i] <= ns_k2_1[i];
        k1_2[i] <= ns_k1_2[i];
        k2_2[i] <= ns_k2_2[i];
        k1_3[i] <= ns_k1_3[i];
        k2_3[i] <= ns_k2_3[i];
    end
end
always @(*) begin
    for( i = 0; i < 4; i = i + 1)begin
        if(cnt == i)begin
            ns_k1_1[i] = Kernel_ch1;
            ns_k2_1[i] = Kernel_ch2;
        end else begin
            ns_k1_1[i] = k1_1[i];
            ns_k2_1[i] = k2_1[i];
        end
    end
    for( i = 0; i < 4; i = i + 1)begin
        if(cnt == (i+4))begin
            ns_k1_2[i] = Kernel_ch1;
            ns_k2_2[i] = Kernel_ch2;
        end else begin
            ns_k1_2[i] = k1_2[i];
            ns_k2_2[i] = k2_2[i];
        end
    end
    for( i = 0; i < 4; i = i + 1)begin
        if(cnt == (i+8))begin
            ns_k1_3[i] = Kernel_ch1;
            ns_k2_3[i] = Kernel_ch2;
        end else begin
            ns_k1_3[i] = k1_3[i];
            ns_k2_3[i] = k2_3[i];
        end
    end
end

// receiving weight
always @(posedge clk) begin
    weight[0][0] <= ns_weight[0][0];
    weight[0][1] <= ns_weight[0][1];
    weight[0][2] <= ns_weight[0][2];
    weight[0][3] <= ns_weight[0][3];
    weight[0][4] <= ns_weight[0][4];
    weight[0][5] <= ns_weight[0][5];
    weight[0][6] <= ns_weight[0][6];
    weight[0][7] <= ns_weight[0][7];
    weight[1][0] <= ns_weight[1][0];
    weight[1][1] <= ns_weight[1][1];
    weight[1][2] <= ns_weight[1][2];
    weight[1][3] <= ns_weight[1][3];
    weight[1][4] <= ns_weight[1][4];
    weight[1][5] <= ns_weight[1][5];
    weight[1][6] <= ns_weight[1][6];
    weight[1][7] <= ns_weight[1][7];
    weight[2][0] <= ns_weight[2][0];
    weight[2][1] <= ns_weight[2][1];
    weight[2][2] <= ns_weight[2][2];
    weight[2][3] <= ns_weight[2][3];
    weight[2][4] <= ns_weight[2][4];
    weight[2][5] <= ns_weight[2][5];
    weight[2][6] <= ns_weight[2][6];
    weight[2][7] <= ns_weight[2][7];
end
always @(*) begin
    ns_weight[0][0] = weight[0][1];
    ns_weight[0][1] = weight[0][2];
    ns_weight[0][2] = weight[0][3];
    ns_weight[0][3] = weight[0][4];
    ns_weight[0][4] = weight[0][5];
    ns_weight[0][5] = weight[0][6];
    ns_weight[0][6] = weight[0][7];
    ns_weight[0][7] = weight[1][0];
    ns_weight[1][0] = weight[1][1];
    ns_weight[1][1] = weight[1][2];
    ns_weight[1][2] = weight[1][3];
    ns_weight[1][3] = weight[1][4];
    ns_weight[1][4] = weight[1][5];
    ns_weight[1][5] = weight[1][6];
    ns_weight[1][6] = weight[1][7];
    ns_weight[1][7] = weight[2][0];
    ns_weight[2][0] = weight[2][1];
    ns_weight[2][1] = weight[2][2];
    ns_weight[2][2] = weight[2][3];
    ns_weight[2][3] = weight[2][4];
    ns_weight[2][4] = weight[2][5];
    ns_weight[2][5] = weight[2][6];
    ns_weight[2][6] = weight[2][7];
    if(cnt < 'd24)begin
        ns_weight[2][7] = Weight;
    end else begin
        ns_weight[2][7] = weight[0][0];
    end
end

// convolution sum
reg [inst_sig_width+inst_exp_width:0] conv_img_left  [0:3];
reg [inst_sig_width+inst_exp_width:0] conv_img_right [0:3];
reg [inst_sig_width+inst_exp_width:0] conv_kernel1   [0:3];
reg [inst_sig_width+inst_exp_width:0] conv_kernel2   [0:3];
reg [inst_sig_width+inst_exp_width:0] conv_product1_left_0, conv_product1_left_1, conv_product1_left_2, conv_product1_left_3;
reg [inst_sig_width+inst_exp_width:0] conv_product2_left_0, conv_product2_left_1, conv_product2_left_2, conv_product2_left_3;
reg [inst_sig_width+inst_exp_width:0] conv_product1_right_0, conv_product1_right_1, conv_product1_right_2, conv_product1_right_3;
reg [inst_sig_width+inst_exp_width:0] conv_product2_right_0, conv_product2_right_1, conv_product2_right_2, conv_product2_right_3;
wire[inst_sig_width+inst_exp_width:0] ns_conv_product1_left_0, ns_conv_product1_left_1, ns_conv_product1_left_2, ns_conv_product1_left_3;
wire[inst_sig_width+inst_exp_width:0] ns_conv_product2_left_0, ns_conv_product2_left_1, ns_conv_product2_left_2, ns_conv_product2_left3;
wire[inst_sig_width+inst_exp_width:0] ns_conv_product1_right_0, ns_conv_product1_right_1, ns_conv_product1_right_2, ns_conv_product1_right_3;
wire[inst_sig_width+inst_exp_width:0] ns_conv_product2_right_0, ns_conv_product2_right_1, ns_conv_product2_right_2, ns_conv_product2_right_3;

// sharing mult with fc layer
reg [inst_sig_width+inst_exp_width:0] div1, div2;

fp_mult M10( .inst_a(conv_img_left[0]) , .inst_b(conv_kernel1[0]), .z_inst(ns_conv_product1_left_0)  );
fp_mult M11( .inst_a(conv_img_left[1]) , .inst_b(conv_kernel1[1]), .z_inst(ns_conv_product1_left_1)  );
fp_mult M12( .inst_a(conv_img_left[2]) , .inst_b(conv_kernel1[2]), .z_inst(ns_conv_product1_left_2)  );
// sharing mult with fc layer
fp_mult M13( .inst_a(conv_img_left[3]) , .inst_b(conv_kernel1[3]), .z_inst(ns_conv_product1_left_3)  );
fp_mult M14( .inst_a(conv_img_right[0]), .inst_b(conv_kernel1[0]), .z_inst(ns_conv_product1_right_0) );
fp_mult M15( .inst_a(conv_img_right[1]), .inst_b(conv_kernel1[1]), .z_inst(ns_conv_product1_right_1) );
fp_mult M16( .inst_a(conv_img_right[2]), .inst_b(conv_kernel1[2]), .z_inst(ns_conv_product1_right_2) );
fp_mult M17( .inst_a(conv_img_right[3]), .inst_b(conv_kernel1[3]), .z_inst(ns_conv_product1_right_3) );


fp_mult M20( .inst_a(conv_img_left[0]) , .inst_b(conv_kernel2[0]), .z_inst(ns_conv_product2_left_0)  );
fp_mult M21( .inst_a(conv_img_left[1]) , .inst_b(conv_kernel2[1]), .z_inst(ns_conv_product2_left_1)  );
fp_mult M22( .inst_a(conv_img_left[2]) , .inst_b(conv_kernel2[2]), .z_inst(ns_conv_product2_left_2)  );
fp_mult M23( .inst_a(conv_img_left[3]) , .inst_b(conv_kernel2[3]), .z_inst(ns_conv_product2_left3)  );
// sharing mult with fc layer
fp_mult M24( .inst_a(conv_img_right[0]), .inst_b(conv_kernel2[0]), .z_inst(ns_conv_product2_right_0) );
fp_mult M25( .inst_a(conv_img_right[1]), .inst_b(conv_kernel2[1]), .z_inst(ns_conv_product2_right_1) );
fp_mult M26( .inst_a(conv_img_right[2]), .inst_b(conv_kernel2[2]), .z_inst(ns_conv_product2_right_2) );
// sharing mult with fc layer
fp_mult M27( .inst_a(conv_img_right[3]), .inst_b(conv_kernel2[3]), .z_inst(ns_conv_product2_right_3) );

always @(*) begin
    case (cnt)
        'd9, 'd34, 'd59:begin
            conv_img_left[0] = (option)? img[0][0]: 0;
            conv_img_left[1] = (option)? img[0][0]: 0;
            conv_img_left[2] = (option)? img[0][0]: 0;
            conv_img_left[3] = img[0][0];
        end
        'd10, 'd35, 'd60:begin
            conv_img_left[0] = (option)? img[0][1]: 0;
            conv_img_left[1] = (option)? img[0][2]: 0;
            conv_img_left[2] = img[0][1];
            conv_img_left[3] = img[0][2];
        end
        'd11, 'd36, 'd61:begin
            conv_img_left[0] = (option)? img[0][3]: 0;
            conv_img_left[1] = (option)? img[0][4]: 0;
            conv_img_left[2] = img[0][3];
            conv_img_left[3] = img[0][4];
        end
        'd12, 'd37, 'd62:begin
            conv_img_left[0] = (option)? img[0][0]: 0;
            conv_img_left[1] = img[0][0];
            conv_img_left[2] = (option)? img[1][0]: 0;
            conv_img_left[3] = img[1][0];
        end
        'd13, 'd38, 'd63:begin
            conv_img_left[0] = img[0][1];
            conv_img_left[1] = img[0][2];
            conv_img_left[2] = img[1][1];
            conv_img_left[3] = img[1][2];
        end
        'd14, 'd39, 'd64:begin
            conv_img_left[0] = img[0][3];
            conv_img_left[1] = img[0][4];
            conv_img_left[2] = img[1][3];
            conv_img_left[3] = img[1][4];
        end
        'd15, 'd40, 'd65:begin
            conv_img_left[0] = (option)? img[1][0]: 0;
            conv_img_left[1] = img[1][0];
            conv_img_left[2] = (option)? img[2][0]: 0;
            conv_img_left[3] = img[2][0];
        end
        'd16, 'd41, 'd66:begin
            conv_img_left[0] = img[1][1];
            conv_img_left[1] = img[1][2];
            conv_img_left[2] = img[2][1];
            conv_img_left[3] = img[2][2];
        end
        'd17, 'd42, 'd67:begin
            conv_img_left[0] = img[1][3];
            conv_img_left[1] = img[1][4];
            conv_img_left[2] = img[2][3];
            conv_img_left[3] = img[2][4];
        end
        'd18, 'd43, 'd68:begin
            conv_img_left[0] = (option)? img[2][0]: 0;
            conv_img_left[1] = img[2][0];
            conv_img_left[2] = (option)? img[3][0]: 0;
            conv_img_left[3] = img[3][0];
        end
        'd19, 'd44, 'd69:begin
            conv_img_left[0] = img[2][1];
            conv_img_left[1] = img[2][2];
            conv_img_left[2] = img[3][1];
            conv_img_left[3] = img[3][2];
        end
        'd20, 'd45, 'd70:begin
            conv_img_left[0] = img[2][3];
            conv_img_left[1] = img[2][4];
            conv_img_left[2] = img[3][3];
            conv_img_left[3] = img[3][4];
        end
        'd21, 'd46, 'd71:begin
            conv_img_left[0] = (option)? img[3][0]: 0;
            conv_img_left[1] = img[3][0];
            conv_img_left[2] = (option)? img[4][0]: 0;
            conv_img_left[3] = img[4][0];
        end
        'd22, 'd47, 'd72:begin
            conv_img_left[0] = img[3][0];
            conv_img_left[1] = img[3][1];
            conv_img_left[2] = img[4][0];
            conv_img_left[3] = img[4][1];
        end
        'd23, 'd48, 'd73:begin
            conv_img_left[0] = img[3][1];
            conv_img_left[1] = img[3][2];
            conv_img_left[2] = img[4][1];
            conv_img_left[3] = img[4][2];
        end
        'd24, 'd49, 'd74:begin
            conv_img_left[0] = img[3][2];
            conv_img_left[1] = img[3][3];
            conv_img_left[2] = img[4][2];
            conv_img_left[3] = img[4][3];
        end
        'd25, 'd50, 'd75:begin
            conv_img_left[0] = img[3][3];
            conv_img_left[1] = img[3][4];
            conv_img_left[2] = img[4][3];
            conv_img_left[3] = img[4][4];
        end
        'd26, 'd51, 'd76:begin
            conv_img_left[0] = img[3][4];
            conv_img_left[1] = (option)? img[3][4]: 0;
            conv_img_left[2] = img[4][4];
            conv_img_left[3] = (option)? img[4][4]: 0;
        end
        'd79, 'd80, 'd81, 'd82:begin
            // 79:0, 80:1, 81:2, 82:3
            conv_img_left[0] = div1;
            conv_img_left[1] = div1;
            conv_img_left[2] = div1;
            conv_img_left[3] = 0;
        end
        default:begin
            conv_img_left[0] = 0;
            conv_img_left[1] = 0;
            conv_img_left[2] = 0;
            conv_img_left[3] = 0;
        end
    endcase
end

always @(*) begin
    case (cnt)
        'd9, 'd34, 'd59:begin
            conv_img_right[0] = (option)? img[0][0]: 0;
            conv_img_right[1] = (option)? img[0][1]: 0;
            conv_img_right[2] = img[0][0];
            conv_img_right[3] = img[0][1];
        end
        'd10, 'd35, 'd60:begin
            conv_img_right[0] = (option)? img[0][2]: 0;
            conv_img_right[1] = (option)? img[0][3]: 0;
            conv_img_right[2] = img[0][2];
            conv_img_right[3] = img[0][3];
        end
        'd11, 'd36, 'd61:begin
            conv_img_right[0] = (option)? img[0][4]: 0;
            conv_img_right[1] = (option)? img[0][4]: 0;
            conv_img_right[2] = img[0][4];
            conv_img_right[3] = (option)? img[0][4]: 0;
        end
        'd12, 'd37, 'd62:begin
            conv_img_right[0] = img[0][0];
            conv_img_right[1] = img[0][1];
            conv_img_right[2] = img[1][0];
            conv_img_right[3] = img[1][1];
        end
        'd13, 'd38, 'd63:begin
            conv_img_right[0] = img[0][2];
            conv_img_right[1] = img[0][3];
            conv_img_right[2] = img[1][2];
            conv_img_right[3] = img[1][3];
        end
        'd14, 'd39, 'd64:begin
            conv_img_right[0] = img[0][4];
            conv_img_right[1] = (option)? img[0][4]: 0;
            conv_img_right[2] = img[1][4];
            conv_img_right[3] = (option)? img[1][4]: 0;
        end
        'd15, 'd40, 'd65:begin
            conv_img_right[0] = img[1][0];
            conv_img_right[1] = img[1][1];
            conv_img_right[2] = img[2][0];
            conv_img_right[3] = img[2][1];
        end
        'd16, 'd41, 'd66:begin
            conv_img_right[0] = img[1][2];
            conv_img_right[1] = img[1][3];
            conv_img_right[2] = img[2][2];
            conv_img_right[3] = img[2][3];
        end
        'd17, 'd42, 'd67:begin
            conv_img_right[0] = img[1][4];
            conv_img_right[1] = (option)? img[1][4]: 0;
            conv_img_right[2] = img[2][4];
            conv_img_right[3] = (option)? img[2][4]: 0;
        end
        'd18, 'd43, 'd68:begin
            conv_img_right[0] = img[2][0];
            conv_img_right[1] = img[2][1];
            conv_img_right[2] = img[3][0];
            conv_img_right[3] = img[3][1];
        end
        'd19, 'd44, 'd69:begin
            conv_img_right[0] = img[2][2];
            conv_img_right[1] = img[2][3];
            conv_img_right[2] = img[3][2];
            conv_img_right[3] = img[3][3];
        end
        'd20, 'd45, 'd70:begin
            conv_img_right[0] = img[2][4];
            conv_img_right[1] = (option)? img[2][4]: 0;
            conv_img_right[2] = img[3][4];
            conv_img_right[3] = (option)? img[3][4]: 0;
        end
        'd21, 'd46, 'd71:begin
            conv_img_right[0] = (option)? img[4][0]: 0;
            conv_img_right[1] = img[4][0];
            conv_img_right[2] = (option)? img[4][0]: 0;
            conv_img_right[3] = (option)? img[4][0]: 0;
        end
        'd22, 'd47, 'd72:begin
            conv_img_right[0] = img[4][0];
            conv_img_right[1] = img[4][1];
            conv_img_right[2] = (option)? img[4][0]: 0;
            conv_img_right[3] = (option)? img[4][1]: 0;
        end
        'd23, 'd48, 'd73:begin
            conv_img_right[0] = img[4][1];
            conv_img_right[1] = img[4][2];
            conv_img_right[2] = (option)? img[4][1]: 0;
            conv_img_right[3] = (option)? img[4][2]: 0;
        end
        'd24, 'd49, 'd74:begin
            conv_img_right[0] = img[4][2];
            conv_img_right[1] = img[4][3];
            conv_img_right[2] = (option)? img[4][2]: 0;
            conv_img_right[3] = (option)? img[4][3]: 0;
        end
        'd25, 'd50, 'd75:begin
            conv_img_right[0] = img[4][3];
            conv_img_right[1] = img[4][4];
            conv_img_right[2] = (option)? img[4][3]: 0;
            conv_img_right[3] = (option)? img[4][4]: 0;
        end
        'd26, 'd51, 'd76:begin
            conv_img_right[0] = img[4][4];
            conv_img_right[1] = (option)? img[4][4]: 0;
            conv_img_right[2] = (option)? img[4][4]: 0;
            conv_img_right[3] = (option)? img[4][4]: 0;
        end
        'd79, 'd80, 'd81, 'd82:begin
            // 79:4, 80:5, 81:6, 82:7
            conv_img_right[0] = div2;
            conv_img_right[1] = div2;
            conv_img_right[2] = div2;
            conv_img_right[3] = 0;
        end
        default:begin
            conv_img_right[0] = 0;
            conv_img_right[1] = 0;
            conv_img_right[2] = 0;
            conv_img_right[3] = 0;
        end
    endcase
end

always @(*) begin
    if(cnt > 'd8 && cnt <= 'd26)begin
        conv_kernel1[0] = k1_1[0];
        conv_kernel1[1] = k1_1[1];
        conv_kernel1[2] = k1_1[2];
        conv_kernel1[3] = k1_1[3];
        conv_kernel2[0] = k2_1[0];
        conv_kernel2[1] = k2_1[1];
        conv_kernel2[2] = k2_1[2];
        conv_kernel2[3] = k2_1[3];
    end else if(cnt > 'd33 && cnt <= 'd51)begin
        conv_kernel1[0] = k1_2[0];
        conv_kernel1[1] = k1_2[1];
        conv_kernel1[2] = k1_2[2];
        conv_kernel1[3] = k1_2[3];
        conv_kernel2[0] = k2_2[0];
        conv_kernel2[1] = k2_2[1];
        conv_kernel2[2] = k2_2[2];
        conv_kernel2[3] = k2_2[3];
    end else if(cnt > 'd58 && cnt <= 'd76)begin
        conv_kernel1[0] = k1_3[0];
        conv_kernel1[1] = k1_3[1];
        conv_kernel1[2] = k1_3[2];
        conv_kernel1[3] = k1_3[3];
        conv_kernel2[0] = k2_3[0];
        conv_kernel2[1] = k2_3[1];
        conv_kernel2[2] = k2_3[2];
        conv_kernel2[3] = k2_3[3];
    end else begin
        // 'd79, 'd80, 'd81, 'd82: fc layer acculumation
        conv_kernel1[0] = weight[2][1];
        conv_kernel1[1] = weight[0][1];
        conv_kernel1[2] = weight[1][1];
        conv_kernel1[3] = 0;
        conv_kernel2[0] = weight[2][5];
        conv_kernel2[1] = weight[0][5];
        conv_kernel2[2] = weight[1][5];
        conv_kernel2[3] = 0;
    end
end

always @(posedge clk) begin
    conv_product1_left_0  <= ns_conv_product1_left_0 ;
    conv_product1_left_1  <= ns_conv_product1_left_1 ;
    conv_product1_left_2  <= ns_conv_product1_left_2 ;
    conv_product1_left_3  <= ns_conv_product1_left_3 ;
    conv_product1_right_0 <= ns_conv_product1_right_0;
    conv_product1_right_1 <= ns_conv_product1_right_1;
    conv_product1_right_2 <= ns_conv_product1_right_2;
    conv_product1_right_3 <= ns_conv_product1_right_3;
    conv_product2_left_0  <= ns_conv_product2_left_0 ;
    conv_product2_left_1  <= ns_conv_product2_left_1 ;
    conv_product2_left_2  <= ns_conv_product2_left_2 ;
    conv_product2_left_3  <= ns_conv_product2_left3 ;
    conv_product2_right_0 <= ns_conv_product2_right_0;
    conv_product2_right_1 <= ns_conv_product2_right_1;
    conv_product2_right_2 <= ns_conv_product2_right_2;
    conv_product2_right_3 <= ns_conv_product2_right_3;
end
// pipeline
wire[inst_sig_width+inst_exp_width:0] ns_f_map_1_left, ns_f_map_1_right, ns_f_map_2_left, ns_f_map_2_right;
wire[inst_sig_width+inst_exp_width:0] net1, net2, net3, net4;
reg [inst_sig_width+inst_exp_width:0] f_map_1_left, f_map_1_right, f_map_2_left, f_map_2_right;
reg [inst_sig_width+inst_exp_width:0] share_sum1_in_a, share_sum1_in_b, share_sum1_in_c;
reg [inst_sig_width+inst_exp_width:0] share_sum2_in_a, share_sum2_in_b, share_sum2_in_c;
reg [inst_sig_width+inst_exp_width:0] share_sum3_in_a, share_sum3_in_b, share_sum3_in_c;
reg [inst_sig_width+inst_exp_width:0] z1, z2, z3;
wire[inst_sig_width+inst_exp_width:0] ns_z1, ns_z2, ns_z3;

// fp_sum3 CONV1_1 ( .inst_a(conv_product1_left_0), .inst_b(conv_product1_left_1), .inst_c(f_map_1[0][0]), .z_inst(net1) );
fp_sum3 CONV1_1 ( .inst_a(share_sum1_in_a), .inst_b(share_sum1_in_b), .inst_c(share_sum1_in_c), .z_inst(net1) );
always @(*) begin
    if((cnt > 'd9 && cnt <= 'd27) || (cnt > 'd34 && cnt <= 'd52) || (cnt > 'd59 && cnt <= 'd77) || (cnt > 'd79 && cnt <= 'd83))begin
        share_sum1_in_a = conv_product1_left_0;
    end else begin
        share_sum1_in_a = 0;
    end
    if((cnt > 'd9 && cnt <= 'd27) || (cnt > 'd34 && cnt <= 'd52) || (cnt > 'd59 && cnt <= 'd77))begin
        share_sum1_in_b = conv_product1_left_1;
    end else begin
        share_sum1_in_b = conv_product2_right_0;
    end
    if((cnt > 'd9 && cnt <= 'd27) || (cnt > 'd34 && cnt <= 'd52) || (cnt > 'd59 && cnt <= 'd77))begin
        share_sum1_in_c = f_map_1[0][0];
    end else begin
        share_sum1_in_c = z1;
    end
end
fp_sum3 CONV1_2 ( .inst_a(conv_product1_left_2), .inst_b(conv_product1_left_3), .inst_c(net1), .z_inst(ns_f_map_1_left) );

// fp_sum3 CONV2_1 ( .inst_a(conv_product1_right_0), .inst_b(conv_product1_right_1), .inst_c(f_map_1[0][1]), .z_inst(net2) );
fp_sum3 CONV2_1 ( .inst_a(share_sum2_in_a), .inst_b(share_sum2_in_b), .inst_c(share_sum2_in_c), .z_inst(net2) );
always @(*) begin
    if((cnt > 'd9 && cnt <= 'd27) || (cnt > 'd34 && cnt <= 'd52) || (cnt > 'd59 && cnt <= 'd77))begin
        share_sum2_in_a = conv_product1_right_0;
    end else begin
        share_sum2_in_a = conv_product1_left_1;
    end
    if((cnt > 'd9 && cnt <= 'd27) || (cnt > 'd34 && cnt <= 'd52) || (cnt > 'd59 && cnt <= 'd77))begin
        share_sum2_in_b = conv_product1_right_1;
    end else begin
        share_sum2_in_b = conv_product2_right_1;
    end
    if((cnt > 'd9 && cnt <= 'd27) || (cnt > 'd34 && cnt <= 'd52) || (cnt > 'd59 && cnt <= 'd77))begin
        share_sum2_in_c = f_map_1[0][1];
    end else begin
        share_sum2_in_c = z2;
    end
end
fp_sum3 CONV2_2 ( .inst_a(conv_product1_right_2), .inst_b(conv_product1_right_3), .inst_c(net2), .z_inst(ns_f_map_1_right) );

// fp_sum3 CONV3_1 ( .inst_a(conv_product2_left_0), .inst_b(conv_product2_left_1), .inst_c(f_map_2[0][0]), .z_inst(net3) );
fp_sum3 CONV3_1 ( .inst_a(share_sum3_in_a), .inst_b(share_sum3_in_b), .inst_c(share_sum3_in_c), .z_inst(net3) );
always @(*) begin
    if((cnt > 'd9 && cnt <= 'd27) || (cnt > 'd34 && cnt <= 'd52) || (cnt > 'd59 && cnt <= 'd77))begin
        share_sum3_in_a = conv_product2_left_0;
    end else begin
        share_sum3_in_a = conv_product1_left_2;
    end
    if((cnt > 'd9 && cnt <= 'd27) || (cnt > 'd34 && cnt <= 'd52) || (cnt > 'd59 && cnt <= 'd77))begin
        share_sum3_in_b = conv_product2_left_1;
    end else begin
        share_sum3_in_b = conv_product2_right_2;
    end
    if((cnt > 'd9 && cnt <= 'd27) || (cnt > 'd34 && cnt <= 'd52) || (cnt > 'd59 && cnt <= 'd77))begin
        share_sum3_in_c = f_map_2[0][0];
    end else begin
        share_sum3_in_c = z3;
    end
end
fp_sum3 CONV3_2 ( .inst_a(conv_product2_left_2), .inst_b(conv_product2_left_3), .inst_c(net3), .z_inst(ns_f_map_2_left) );

fp_sum3 CONV4_1 ( .inst_a(conv_product2_right_0), .inst_b(conv_product2_right_1), .inst_c(f_map_2[0][1]), .z_inst(net4) );
fp_sum3 CONV4_2 ( .inst_a(conv_product2_right_2), .inst_b(conv_product2_right_3), .inst_c(net4), .z_inst(ns_f_map_2_right) );


always @(posedge clk) begin
    if(cnt == 0)begin
        for( i = 0; i < 6; i = i + 1 )begin
            for( j = 0; j < 6; j = j + 1)begin
                f_map_1[i][j] <= 0;
                f_map_2[i][j] <= 0;
            end
        end
    end else if((cnt > 'd9 && cnt <= 'd27) || (cnt > 'd34 && cnt <= 'd52) || (cnt > 'd59 && cnt <= 'd77) ) begin
        f_map_1[0][0] <= f_map_1[0][2];
        f_map_1[0][1] <= f_map_1[0][3];
        f_map_1[0][2] <= f_map_1[0][4];
        f_map_1[0][3] <= f_map_1[0][5];
        f_map_1[0][4] <= f_map_1[1][0];
        f_map_1[0][5] <= f_map_1[1][1];
        f_map_1[1][0] <= f_map_1[1][2];
        f_map_1[1][1] <= f_map_1[1][3];
        f_map_1[1][2] <= f_map_1[1][4];
        f_map_1[1][3] <= f_map_1[1][5];
        f_map_1[1][4] <= f_map_1[2][0];
        f_map_1[1][5] <= f_map_1[2][1];
        f_map_1[2][0] <= f_map_1[2][2];
        f_map_1[2][1] <= f_map_1[2][3];
        f_map_1[2][2] <= f_map_1[2][4];
        f_map_1[2][3] <= f_map_1[2][5];
        f_map_1[2][4] <= f_map_1[3][0];
        f_map_1[2][5] <= f_map_1[3][1];
        f_map_1[3][0] <= f_map_1[3][2];
        f_map_1[3][1] <= f_map_1[3][3];
        f_map_1[3][2] <= f_map_1[3][4];
        f_map_1[3][3] <= f_map_1[3][5];
        f_map_1[3][4] <= f_map_1[4][0];
        f_map_1[3][5] <= f_map_1[4][1];
        f_map_1[4][0] <= f_map_1[4][2];
        f_map_1[4][1] <= f_map_1[4][3];
        f_map_1[4][2] <= f_map_1[4][4];
        f_map_1[4][3] <= f_map_1[4][5];
        f_map_1[4][4] <= f_map_1[5][0];
        f_map_1[4][5] <= f_map_1[5][1];
        f_map_1[5][0] <= f_map_1[5][2];
        f_map_1[5][1] <= f_map_1[5][3];
        f_map_1[5][2] <= f_map_1[5][4];
        f_map_1[5][3] <= f_map_1[5][5];
        f_map_1[5][4] <= ns_f_map_1_left;
        f_map_1[5][5] <= ns_f_map_1_right;

        f_map_2[0][0] <= f_map_2[0][2];
        f_map_2[0][1] <= f_map_2[0][3];
        f_map_2[0][2] <= f_map_2[0][4];
        f_map_2[0][3] <= f_map_2[0][5];
        f_map_2[0][4] <= f_map_2[1][0];
        f_map_2[0][5] <= f_map_2[1][1];
        f_map_2[1][0] <= f_map_2[1][2];
        f_map_2[1][1] <= f_map_2[1][3];
        f_map_2[1][2] <= f_map_2[1][4];
        f_map_2[1][3] <= f_map_2[1][5];
        f_map_2[1][4] <= f_map_2[2][0];
        f_map_2[1][5] <= f_map_2[2][1];
        f_map_2[2][0] <= f_map_2[2][2];
        f_map_2[2][1] <= f_map_2[2][3];
        f_map_2[2][2] <= f_map_2[2][4];
        f_map_2[2][3] <= f_map_2[2][5];
        f_map_2[2][4] <= f_map_2[3][0];
        f_map_2[2][5] <= f_map_2[3][1];
        f_map_2[3][0] <= f_map_2[3][2];
        f_map_2[3][1] <= f_map_2[3][3];
        f_map_2[3][2] <= f_map_2[3][4];
        f_map_2[3][3] <= f_map_2[3][5];
        f_map_2[3][4] <= f_map_2[4][0];
        f_map_2[3][5] <= f_map_2[4][1];
        f_map_2[4][0] <= f_map_2[4][2];
        f_map_2[4][1] <= f_map_2[4][3];
        f_map_2[4][2] <= f_map_2[4][4];
        f_map_2[4][3] <= f_map_2[4][5];
        f_map_2[4][4] <= f_map_2[5][0];
        f_map_2[4][5] <= f_map_2[5][1];
        f_map_2[5][0] <= f_map_2[5][2];
        f_map_2[5][1] <= f_map_2[5][3];
        f_map_2[5][2] <= f_map_2[5][4];
        f_map_2[5][3] <= f_map_2[5][5];
        f_map_2[5][4] <= ns_f_map_2_left;
        f_map_2[5][5] <= ns_f_map_2_right;
    end
end

// pipeline
reg [inst_sig_width+inst_exp_width:0] cmp1_1;
reg [inst_sig_width+inst_exp_width:0] cmp1_2;
reg [inst_sig_width+inst_exp_width:0] cmp1_3;
reg [inst_sig_width+inst_exp_width:0] cmp1_4;
reg [inst_sig_width+inst_exp_width:0] cmp1_temp1, cmp1_temp2;
reg [inst_sig_width+inst_exp_width:0] cmp2_1;
reg [inst_sig_width+inst_exp_width:0] cmp2_2;
reg [inst_sig_width+inst_exp_width:0] cmp2_3;
reg [inst_sig_width+inst_exp_width:0] cmp2_4;
reg [inst_sig_width+inst_exp_width:0] cmp2_temp1, cmp2_temp2;
reg [inst_sig_width+inst_exp_width:0] max1 [0:3];
reg [inst_sig_width+inst_exp_width:0] max2 [0:3];

fp_max CMP1_1( .inst_a(cmp1_1), .inst_b(cmp1_2), .max_inst(cmp1_temp1) );
fp_max CMP1_2( .inst_a(cmp1_3), .inst_b(cmp1_4), .max_inst(cmp1_temp2) );
fp_max CMP2_1( .inst_a(cmp2_1), .inst_b(cmp2_2), .max_inst(cmp2_temp1) );
fp_max CMP2_2( .inst_a(cmp2_3), .inst_b(cmp2_4), .max_inst(cmp2_temp2) );
always @(*) begin
    case (cnt)
        'd61, 'd70:begin
            cmp1_1 = f_map_1[5][4];
            cmp2_1 = f_map_2[5][4];
        end 
        'd62, 'd64, 'd65, 'd67, 'd68:begin
            cmp1_1 = max1[0];
            cmp2_1 = max2[0];
        end
        'd63, 'd72:begin
            cmp1_1 = f_map_1[5][3];
            cmp2_1 = f_map_2[5][3];
        end
        'd66, 'd69:begin
            cmp1_1 = max1[1];
            cmp2_1 = max2[1];
        end
        // 71 starts for bottom half
        'd71, 'd73, 'd74, 'd75:begin
            cmp1_1 = max1[2];
            cmp2_1 = max2[2];
        end
        'd76, 'd77, 'd78:begin
            cmp1_1 = max1[3];
            cmp2_1 = max2[3];
        end
        default:begin
            cmp1_1 = 0;
            cmp2_1 = 0;
        end
    endcase
end

always @(*) begin
    case (cnt)
        'd61, 'd70:begin
            cmp1_2 = f_map_1[5][5];
            cmp2_2 = f_map_2[5][5];
        end 
        default:begin
            // 'd62, 'd63, 'd64, 'd65, 'd66, 'd67, 'd68, 'd69, ,'d71 ,'d72, 'd73, 'd74, 'd75, 'd76, 'd77, 'd78:
            cmp1_2 = f_map_1[5][4];
            cmp2_2 = f_map_2[5][4];
        end
    endcase
end

always @(*) begin
    case (cnt)
        'd65, 'd68:begin
            cmp1_3 = max1[1];
            cmp2_3 = max2[1];
        end
        default:begin
            // 'd63, 'd64, 'd66, 'd67, 'd69, 'd72, 'd73, 'd74, 'd75, 'd76, 'd77, 'd78:
            cmp1_3 = cmp1_temp1;
            cmp2_3 = cmp2_temp1;
        end 
    endcase
end

always @(*) begin
    // 'd63, 'd64, 'd65, 'd66, 'd67, 'd68, 'd69, 'd72, 'd73, 'd74, 'd75, 'd76, 'd77, 'd78:
    cmp1_4 = f_map_1[5][5];
    cmp2_4 = f_map_2[5][5];
end

always @(posedge clk) begin
    case (cnt)
        'd61, 'd62, 'd65, 'd68:begin
            max1[0] <= cmp1_temp1;
            max2[0] <= cmp2_temp1;
        end
        'd64, 'd67:begin
            max1[0] <= cmp1_temp2;
            max2[0] <= cmp2_temp2;
        end
    endcase
end
always @(posedge clk) begin
    case (cnt)
        'd63, 'd65, 'd66, 'd68, 'd69:begin
            max1[1] <= cmp1_temp2;
            max2[1] <= cmp2_temp2;
        end
    endcase
end
always @(posedge clk) begin
    case (cnt)
        'd70, 'd71:begin
            max1[2] <= cmp1_temp1;
            max2[2] <= cmp2_temp1;
        end 
        'd73, 'd74, 'd75:begin
            max1[2] <= cmp1_temp2;
            max2[2] <= cmp2_temp2;
        end
    endcase
end
always @(posedge clk) begin
    case (cnt)
        'd72, 'd76, 'd77, 'd78:begin
            max1[3] <= cmp1_temp2;
            max2[3] <= cmp2_temp2;
        end 
    endcase
end
// activation
reg [inst_sig_width+inst_exp_width:0] max_pooling1, max_pooling2, exp_z1, exp_z2, exp_z3;
reg [inst_sig_width+inst_exp_width:0] exp   [0:1];
wire[inst_sig_width+inst_exp_width:0] ns_exp1, ns_exp2;

fp_exp EXP1( .inst_a(max_pooling1), .z_inst(ns_exp1));
fp_exp EXP2( .inst_a(max_pooling2), .z_inst(ns_exp2));

always @(*) begin
    case (cnt)
        'd76:begin
            if(option)begin
                // same as double the number in IEEE-754 
                max_pooling1 = {max1[0][31], (max1[0][30:23] + 1'b1), max1[0][22:0]};
                max_pooling2 = {max2[0][31], (max2[0][30:23] + 1'b1), max2[0][22:0]};
            end else begin
                max_pooling1 = max1[0];
                max_pooling2 = max2[0];
            end
        end 
        'd77:begin
            if(option)begin
                max_pooling1 = {max1[1][31], (max1[1][30:23] + 1'b1), max1[1][22:0]};
                max_pooling2 = {max2[1][31], (max2[1][30:23] + 1'b1), max2[1][22:0]};
            end else begin
                max_pooling1 = max1[1];
                max_pooling2 = max2[1];
            end
        end
        'd78:begin
            if(option)begin
                max_pooling1 = {max1[2][31], (max1[2][30:23] + 1'b1), max1[2][22:0]};
                max_pooling2 = {max2[2][31], (max2[2][30:23] + 1'b1), max2[2][22:0]};
            end else begin
                max_pooling1 = max1[2];
                max_pooling2 = max2[2];
            end
        end
        'd79:begin
            if(option)begin
                max_pooling1 = {max1[3][31], (max1[3][30:23] + 1'b1), max1[3][22:0]};
                max_pooling2 = {max2[3][31], (max2[3][30:23] + 1'b1), max2[3][22:0]};
            end else begin
                max_pooling1 = max1[3];
                max_pooling2 = max2[3];
            end
        end
        // sharing with soft max
        'd84:begin
            max_pooling1 = z1;
            max_pooling2 = z2;
        end
        'd85:begin
            max_pooling1 = z3;
            max_pooling2 = 0;
        end
        default:begin
            max_pooling1 = 0;
            max_pooling2 = 0;
        end
    endcase
end
always @(posedge clk) begin
    // if(cnt > 'd75 && cnt <= 'd79)begin
    exp[0] <= ns_exp1;
    exp[1] <= ns_exp2;
    // end
    if(cnt == 'd84)begin
        exp_z1 <= ns_exp1;
    end
    if(cnt == 'd84)begin
        exp_z2 <= ns_exp2;
    end
    if(cnt == 'd85)begin
        exp_z3 <= ns_exp1;
    end
end


reg [inst_sig_width+inst_exp_width:0] act1, act2, num;
reg [inst_sig_width+inst_exp_width:0] denom1, denom2, numer1, numer2, numer_sel, denom_sel;
wire[inst_sig_width+inst_exp_width:0] ns_denom1, ns_denom2, ns_numer1, ns_numer2;
reg [inst_sig_width+inst_exp_width:0] total;

fp_add DENOM1( .inst_a(act1), .inst_b(FP_1), .z_inst(ns_denom1) );
fp_add NUMER1( .inst_a(act1), .inst_b(num) , .z_inst(ns_numer1) );
fp_add DENOM2( .inst_a(act2), .inst_b(FP_1), .z_inst(ns_denom2) );
fp_add NUMER2( .inst_a(act2), .inst_b(num) , .z_inst(ns_numer2) );

always @(*) begin
    act1 = exp[0];
    act2 = exp[1];
end
always @(*) begin
    if(option)begin
        num = 32'hbf800000;
    end else begin
        num = 0;
    end
end

always @(posedge clk) begin
    //78,79,80,81: denom and numer are available
    numer1 <= ns_numer1;
    denom1 <= ns_denom1;
    numer2 <= ns_numer2;
    denom2 <= ns_denom2;
end


wire[inst_sig_width+inst_exp_width:0] ns_div1, ns_div2;
fp_div ACT_DIV1( .inst_a(numer_sel), .inst_b(denom_sel), .z_inst(ns_div1));
fp_div ACT_DIV2( .inst_a(numer2), .inst_b(denom2), .z_inst(ns_div2));
always @(*) begin
    case (cnt)
        'd78, 'd79, 'd80, 'd81:begin
            numer_sel = numer1;
        end 
        'd87:begin
            numer_sel = exp_z1;
        end
        'd88:begin
            numer_sel = exp_z2;
        end
        'd89:begin
            numer_sel = exp_z3;
        end
        default:begin
            numer_sel = 0;
        end
    endcase
end

always @(*) begin
    case (cnt)
        'd78, 'd79, 'd80, 'd81:begin
            denom_sel = denom1;
        end 
        'd87, 'd88, 'd89:begin
            denom_sel = total;
        end
        default:begin
            denom_sel = FP_1;
        end
    endcase
end

always @(posedge clk) begin
    // 79,80,81,82: div1 and div2 are available
    // 79 : div1 is 0, and div2 is 4
    // 80 : div1 is 1, and div2 is 5
    // 81 : div1 is 2, and div2 is 6
    // 82 : div1 is 3, and div2 is 7
    div1 <= ns_div1;
    div2 <= ns_div2;
end

// fully connected 
// using 3 sum3 ,considering sharing later
// 79: reset z1 z2 z3
// 80,81,82,83 : conv_sum(= fc mult) are available
// 84: z1, z2, z3 are available

// conv_product1_left_0: weight0 multiplication
// fp_sum3 FC1 ( .inst_a(conv_product1_left_0) , .inst_b(conv_product2_right_0) , .inst_c(z1) , .z_inst(ns_z1)  );
// ns_conv_product1_left_1: weight1 multiplication
// fp_sum3 FC2 ( .inst_a(conv_product1_left_1) , .inst_b(conv_product2_right_1) , .inst_c(z2) , .z_inst(ns_z2)  );
// ns_conv_product1_left_2: weight2 multiplication
// fp_sum3 FC3 ( .inst_a(conv_product1_left_2) , .inst_b(conv_product2_right_2) , .inst_c(z3) , .z_inst(ns_z3)  );

// soft max
reg [inst_sig_width+inst_exp_width:0] add1, add2;
wire[inst_sig_width+inst_exp_width:0] ns_add;
fp_add SM ( .inst_a(add1) , .inst_b(add2) , .z_inst(ns_add) );
always @(*) begin
    case (cnt)
        'd85:begin
            add1 = exp_z1;
            add2 = exp_z2;
        end 
        'd86:begin
            add1 = total;
            add2 = exp_z3;
        end
        default:begin
            add1 = 0;
            add2 = 0;
        end
    endcase
end
always @(posedge clk) begin
    // 87: total is available
    if(cnt == 'd85 || cnt == 'd86)begin
        total <= ns_add;
    end
end

always @(posedge clk ) begin
    if(cnt == 'd79)begin
        z1 <= 0;
        z2 <= 0;
        z3 <= 0;
    end else begin
        z1 <= net1;
        z2 <= net2;
        z3 <= net3;
    end
end

reg [inst_sig_width+inst_exp_width:0] out_temp;
always @(posedge clk) begin
    // if(cnt >= 'd87 && cnt <= 'd89)begin
    out_temp <= ns_div1;
    // end
end
// output
always @(*) begin
    if(cnt == 'd88 || cnt == 'd89 || cnt == 'd90)begin
        out_valid = 1;
    end else begin
        out_valid = 0;
    end
end
always @(*) begin
    if(cnt == 'd88 || cnt == 'd89 || cnt == 'd90)begin
        out = out_temp;
    end else begin
        out = 0;
    end
end

endmodule

//---------------------------------------------------------------------
// Module (IPs)
//---------------------------------------------------------------------
module fp_mult( inst_a, inst_b, z_inst );
parameter inst_sig_width = 23;
parameter inst_exp_width = 8;
parameter inst_ieee_compliance = 0;
input [inst_sig_width+inst_exp_width : 0] inst_a;
input [inst_sig_width+inst_exp_width : 0] inst_b;
output [inst_sig_width+inst_exp_width : 0] z_inst;
DW_fp_mult #(inst_sig_width, inst_exp_width, inst_ieee_compliance)
        U1 ( .a(inst_a), .b(inst_b), .rnd(3'b000), .z(z_inst) );
endmodule

module fp_sub( inst_a, inst_b, z_inst);
parameter inst_sig_width = 23;
parameter inst_exp_width = 8;
parameter inst_ieee_compliance = 0;
input [inst_sig_width+inst_exp_width:0] inst_a;
input [inst_sig_width+inst_exp_width:0] inst_b;
output [inst_sig_width+inst_exp_width:0] z_inst;
DW_fp_sub #(inst_sig_width, inst_exp_width, inst_ieee_compliance)
        U1 ( .a(inst_a), .b(inst_b), .rnd(3'b000), .z(z_inst) );
endmodule

module fp_add( inst_a, inst_b, z_inst );
parameter inst_sig_width = 23;
parameter inst_exp_width = 8;
parameter inst_ieee_compliance = 0;
input   [inst_sig_width+inst_exp_width:0]   inst_a;
input   [inst_sig_width+inst_exp_width:0]   inst_b;
output  [inst_sig_width+inst_exp_width:0]   z_inst;
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance)
        U1( .a(inst_a), .b(inst_b), .rnd(3'b000), .z(z_inst) );
endmodule

module fp_sum3( inst_a, inst_b, inst_c, z_inst );
parameter inst_sig_width = 23;
parameter inst_exp_width = 8;
parameter inst_ieee_compliance = 0;
input [inst_sig_width+inst_exp_width:0] inst_a;
input [inst_sig_width+inst_exp_width:0] inst_b;
input [inst_sig_width+inst_exp_width:0] inst_c;
wire [inst_sig_width+inst_exp_width:0] temp_ab;
output [inst_sig_width+inst_exp_width:0] z_inst;
DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance)
        U1 ( .a(inst_a), .b(inst_b), .rnd(3'b000), .z(temp_ab) );

DW_fp_add #(inst_sig_width, inst_exp_width, inst_ieee_compliance)
        U2 ( .a(inst_c), .b(temp_ab), .rnd(3'b000), .z(z_inst) );
endmodule

module fp_max( inst_a, inst_b, max_inst );
parameter inst_sig_width = 23;
parameter inst_exp_width = 8;
parameter inst_ieee_compliance = 0;
input [inst_sig_width+inst_exp_width:0] inst_a;
input [inst_sig_width+inst_exp_width:0] inst_b;
output [inst_sig_width+inst_exp_width:0] max_inst;
DW_fp_cmp #(inst_sig_width, inst_exp_width, inst_ieee_compliance)
        U1( .a(inst_a), .b(inst_b), .zctr(1'b0), .z1(max_inst) );
endmodule

module fp_div( inst_a, inst_b, z_inst );
parameter inst_sig_width = 23;
parameter inst_exp_width = 8;
parameter inst_ieee_compliance = 0;
parameter inst_faithful_round = 0;
input [inst_sig_width+inst_exp_width:0] inst_a;
input [inst_sig_width+inst_exp_width:0] inst_b;
output [inst_sig_width+inst_exp_width:0] z_inst;
// Instance of DW_fp_div
DW_fp_div #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_faithful_round) 
        U1( .a(inst_a), .b(inst_b), .rnd(3'b000), .z(z_inst) );
endmodule

module fp_exp( inst_a, z_inst );
parameter inst_sig_width = 23;
parameter inst_exp_width = 8;
parameter inst_ieee_compliance = 0;
parameter inst_arch = 0;
input [inst_sig_width+inst_exp_width:0] inst_a;
output [inst_sig_width+inst_exp_width:0] z_inst;
// Instance of DW_fp_exp
DW_fp_exp #(inst_sig_width, inst_exp_width, inst_ieee_compliance, inst_arch) 
        U1 ( .a(inst_a), .z(z_inst) );
endmodule
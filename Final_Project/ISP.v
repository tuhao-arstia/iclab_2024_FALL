module ISP(
    // Input Signals
    input clk,
    input rst_n,
    input in_valid,
    input [3:0] in_pic_no,
    input [1:0] in_mode,
    input [1:0] in_ratio_mode,

    // Output Signals
    output out_valid,
    output reg [7:0] out_data,
    
    // DRAM Signals
    // axi write address channel
    // src master
    output [3:0]  awid_s_inf,
    output [31:0] awaddr_s_inf,
    output [2:0]  awsize_s_inf,
    output [1:0]  awburst_s_inf,
    output [7:0]  awlen_s_inf,
    output        awvalid_s_inf,
    // src slave
    input         awready_s_inf,
    // -----------------------------
  
    // axi write data channel 
    // src master
    output [127:0] wdata_s_inf,
    output         wlast_s_inf,
    output         wvalid_s_inf,
    // src slave
    input          wready_s_inf,
  
    // axi write response channel 
    // src slave
    input [3:0]    bid_s_inf,
    input [1:0]    bresp_s_inf,
    input          bvalid_s_inf,
    // src master 
    output         bready_s_inf,
    // -----------------------------
  
    // axi read address channel 
    // src master
    output     [3:0]   arid_s_inf,
    output reg [31:0]  araddr_s_inf,
    output     [7:0]   arlen_s_inf,
    output     [2:0]   arsize_s_inf,
    output     [1:0]   arburst_s_inf,
    output reg         arvalid_s_inf,
    // src slave
    input          arready_s_inf,
    // -----------------------------
  
    // axi read data channel 
    // slave
    input [3:0]    rid_s_inf,
    input [127:0]  rdata_s_inf,
    input [1:0]    rresp_s_inf,
    input          rlast_s_inf,
    input          rvalid_s_inf,
    // master
    output reg     rready_s_inf
    
);

//==================================
//          Declaration
//==================================
integer i;
// DRAM FSM
parameter AXI_IDLE = 1'b0;
parameter AXI_READ = 1'b1;
reg         cs_axi, ns_axi;
reg [31:0]  ns_araddr;

// Dram delayed control signal
wire        r_handshake;
reg         r_handshake_delay;
reg         r_handshake_delay_2;
wire        r_last;
reg         r_last_delay;

// Dram Counter
reg [5:0]   cnt, ns_cnt;
reg [5:0]   cnt_channel, ns_cnt_channel;
reg [5:0]   cnt_channel_delay;


// Main FSM
parameter   DRAM = 3'b000;
parameter    PAT = 3'b001;
parameter   IDLE = 3'b010;
parameter   WAIT = 3'b011;
parameter  FOCUS = 3'b100;
parameter EXPOSE = 3'b101;
parameter     MM = 3'b110;
parameter    OUT = 3'b111;
reg [2:0]   cs, ns;

// pattern input
reg [1:0]   mode;
reg [1:0]   ratio;
reg [3:0]   pic_num;

// CLASSIFIER
// dram read data register
reg [127:0] dram_data;
wire[10:0]  classifier_info_out          [0:35];
// 22 bit adder input
reg [21:0]  info_conc                    [0:17];
reg [21:0]  classifier_info_out_conc     [0:17];
// 22 bit adder output(no overflow)
wire[21:0]  exp_channel_info_conc_temp   [0:17];

// expose info for accumlation
reg [21:0]  exp_channel_info_conc        [0:17];

// expose info for write into sram
reg [10:0]  exp_channel_info             [0:35];

// focus info (no need to keep)
reg [7:0]   focus_channel_info           [0:35];

// MAX and MIN
wire[7:0]   class_max;
wire[7:0]   class_min;
reg [7:0]   ns_max [0:47];
reg [7:0]   ns_min [0:47];
reg [7:0]   max [0:47];
reg [7:0]   min [0:47];
reg [9:0]   max_total, min_total;
reg [7:0]   max_avg, min_avg;
reg [7:0]   mm_out;

// AUTO-FOCUS
// extra row for grayscale calculation
reg [7:0]   grayscale_extra_row     [0:5];
// 6 * 8 bit adder output(including shift) : help auto-focus and auto-expose
reg [7:0]   focus_shift_data_offset [0:5];
reg [1:0]   focus_shamt;
// 6 * 8 bit adder output(including shift)
wire[7:0]   focus_shift_data      [0:5];

wire[7:0]   focus_shift_2_data    [0:5];

// focus_diff module: summation for 2x2, 4x4, 6x6
reg [7:0]   focus_diff_in         [0:5];
wire[7:0]   focus_diff_sum_22;
wire[9:0]   focus_diff_sum_44;
wire[10:0]  focus_diff_sum_66;
reg [9:0]   focus_sum_22;
reg [12:0]  focus_sum_44;
reg [13:0]  focus_sum_66;

// output
reg [7:0]   focus_out, ns_focus_out;
reg [7:0]   expose_out, ns_expose_out;

// auto-expose zero flag
reg         expose_zero_flag        [0:15];
reg         ns_expose_zero_flag     [0:15];
reg         expose_not_zero_flag    [0:15];
reg         ns_expose_not_zero_flag [0:15];
wire[43:0]  expose_ratioed_data;

// dirty bit for auto-focus
reg         focus_dirty             [0:15]; 
reg         ns_focus_dirty          [0:15];
reg [1:0]   focus_out_data          [0:15];

// dirty bit for auto-expose
reg         expose_dirty            [0:15];
reg         ns_expose_dirty         [0:15];
reg [7:0]   expose_out_data         [0:15];



// FSM for auto-expose
parameter   AE_DRAM_IDLE  = 3'b000;
parameter   AE_DRAM_WRITE = 3'b001;
parameter   AE_DRAM_STOP  = 3'b010;
parameter   AE_PAT        = 3'b011;
parameter   AE_IDLE       = 3'b100;
parameter   AE_READ       = 3'b101;
parameter   AE_RATIO      = 3'b110;
parameter   AE_WRITE      = 3'b111;
reg [2:0]   cs_ae, ns_ae;
reg [4:0]   cnt_ae, ns_cnt_ae;
reg [1:0]   cnt_ae_update, ns_cnt_ae_update;

// SRAM control for auto-expose
reg         web_expose, cs_expose;
reg [8:0]   addr_expose;
reg [8:0]   addr_expose_offset, ns_addr_expose_offset;
reg [43:0]  rdata_expose, wdata_expose;




// FSM for auto-focus
parameter    AF_DRAM_IDLE   = 3'b000;
parameter    AF_DRAM_WRITE  = 3'b001;
parameter    AF_PAT         = 3'b010;
parameter    AF_IDLE        = 3'b011;
parameter    AF_EXPOSE_READ = 3'b100;
parameter    AF_EXPOSE_WRITE= 3'b101;
parameter    AF_FOCUS_READ  = 3'b110;
reg [2:0]    cs_af, ns_af;
reg [4:0]    cnt_af, ns_cnt_af;
reg [1:0]    cnt_af_update, ns_cnt_af_update;

// SRAM control for auto-focus
reg          web_focus, cs_focus;
reg [8:0]    addr_focus;
reg [8:0]    addr_focus_offset, ns_addr_focus_offset;
reg [47:0]   rdata_focus, wdata_focus;

//==================================
//             Design
//==================================
//==================================
//            ZERO FLAG
//==================================
assign expose_ratioed_data = {exp_channel_info[3], exp_channel_info[2], exp_channel_info[1], exp_channel_info[0]};
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 16; i = i + 1)begin
            expose_zero_flag[i] <= 1'b0;
        end
    end else begin
        for(i = 0; i < 16; i = i + 1)begin
            expose_zero_flag[i] <= ns_expose_zero_flag[i];
        end
    end
end
always @(*) begin
    for(i = 0; i < 16; i = i + 1)begin
        ns_expose_zero_flag[i] = expose_zero_flag[i];
    end
    case (cs_ae)
        AE_WRITE:begin
            for(i = 0; i < 16; i = i + 1)begin
                if(pic_num == i)begin
                    if(expose_not_zero_flag[i] == 0 && expose_ratioed_data == 0)begin
                        ns_expose_zero_flag[i] = 1'b1;
                    end else begin
                        ns_expose_zero_flag[i] = 1'b0;
                    end
                end else begin
                    ns_expose_zero_flag[i] = expose_zero_flag[i];
                end
            end
        end
    endcase
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 16; i = i + 1)begin
            expose_not_zero_flag[i] <= 1'b0;
        end
    end else begin
        for(i = 0; i < 16; i = i + 1)begin
            expose_not_zero_flag[i] <= ns_expose_not_zero_flag[i];
        end
    end
end
always @(*) begin
    for(i = 0; i < 16; i = i + 1)begin
        ns_expose_not_zero_flag[i] = expose_not_zero_flag[i];
    end
    case (cs_ae)
        AE_IDLE:begin
            for(i = 0; i < 16; i = i + 1)begin
                ns_expose_not_zero_flag[i] = 1'b0;
            end
        end
        AE_WRITE:begin
            for(i = 0; i < 16; i = i + 1)begin
                if(pic_num == i)begin
                    if(expose_not_zero_flag[i] == 0 && expose_ratioed_data != 0)begin
                        ns_expose_not_zero_flag[i] = 1'b1;
                    end else begin
                        ns_expose_not_zero_flag[i] = expose_not_zero_flag[i];
                    end
                end else begin
                    ns_expose_not_zero_flag[i] = expose_not_zero_flag[i];
                end
            end
        end
    endcase
end
//==================================
//            DIRTY BIT
//==================================
// focus dirty bit
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 16; i = i + 1)begin
            focus_dirty[i] <= 1'b1;
        end
    end else begin
        for(i = 0; i < 16; i = i + 1)begin
            focus_dirty[i] <= ns_focus_dirty[i];
        end
    end
end
always @(*) begin
    for(i = 0; i < 16; i = i + 1)begin
        ns_focus_dirty[i] = focus_dirty[i];
    end
    case (cs)
        FOCUS:begin
            for(i = 0; i < 16; i = i + 1)begin
                if(pic_num == i)begin
                    ns_focus_dirty[i] = 1'b0;
                end else begin
                    ns_focus_dirty[i] = focus_dirty[i];
                end
            end
        end
        EXPOSE:begin
            for(i = 0; i < 16; i = i + 1)begin
                if(pic_num == i && ratio != 2)begin
                    ns_focus_dirty[i] = 1'b1;
                end else begin
                    ns_focus_dirty[i] = focus_dirty[i];
                end
            end
        end
    endcase
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 16; i = i + 1)begin
            focus_out_data[i] <= 2'd0;
        end
    end else if(cs == OUT) begin
        for(i = 0; i < 16; i = i + 1)begin
            if(pic_num == i)begin
                if(expose_zero_flag[i] == 1)begin
                    focus_out_data[i] <= 2'd0;
                end else begin
                    focus_out_data[i] <= focus_out;
                end
            end
        end
    end
end

// expose dirty bit
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 16; i = i + 1)begin
            expose_dirty[i] <= 1'b1;
        end
    end else begin
        for(i = 0; i < 16; i = i + 1)begin
            expose_dirty[i] <= ns_expose_dirty[i];
        end
    end
end
always @(*) begin
    for(i = 0; i < 16; i = i + 1)begin
        ns_expose_dirty[i] = expose_dirty[i];
    end
    case (cs)
        EXPOSE:begin
            for(i = 0; i < 16; i = i + 1)begin
                if(pic_num == i)begin
                    ns_expose_dirty[i] = 1'b0;
                end else begin
                    ns_expose_dirty[i] = expose_dirty[i];
                end
            end
        end
    endcase
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 16; i = i + 1)begin
            expose_out_data[i] <= 8'd0;
        end
    end else if(cs == OUT && mode == 1) begin
        for(i = 0; i < 16; i = i + 1)begin
            if(pic_num == i)begin
                expose_out_data[i] <= expose_out;
            end
        end
    end
end

//==================================
//            DRAM FSM
//==================================
// read data handshake and delayed control
assign r_handshake = rvalid_s_inf && rready_s_inf;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        r_handshake_delay <= 0;
        r_handshake_delay_2 <= 0;
    end else begin
        r_handshake_delay <= r_handshake;
        r_handshake_delay_2 <= r_handshake_delay;
    end
end
// read last data and delayed control
assign r_last = rlast_s_inf && rvalid_s_inf && rready_s_inf;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        r_last_delay <= 0;
    end else begin
        r_last_delay <= r_last;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cs_axi <= AXI_IDLE;
    end else begin
        cs_axi <= ns_axi;
    end
end
always @(*) begin
    ns_axi = cs_axi;
    case (cs_axi)
        AXI_IDLE:begin
            if(arvalid_s_inf && arready_s_inf && cnt_channel != 'd48)begin
                ns_axi = AXI_READ;
            end
        end
        AXI_READ:begin
            if(r_last_delay)begin
                ns_axi = AXI_IDLE;
            end
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_channel <= 0;
        cnt_channel_delay <= 0;
    end else begin
        cnt_channel <= ns_cnt_channel;
        cnt_channel_delay <= cnt_channel;
    end
end
always @(*) begin
    ns_cnt_channel = cnt_channel;
    case (cs_axi)
        AXI_READ:begin
            if(cnt_channel != 'd48 && cnt == 'd63 && r_handshake_delay)begin
                ns_cnt_channel = cnt_channel + 'd1;
            end else begin
                ns_cnt_channel = cnt_channel;
            end
        end 
    endcase
end

// Dram WRITE Setting
// axi write address channel
// src master: no need for write, so keep valid low
assign awid_s_inf    = 4'd0;
assign awaddr_s_inf  = 32'h10000;
assign awsize_s_inf  = 3'b100;
assign awburst_s_inf = 2'b01;
assign awlen_s_inf   = 8'd0;
assign awvalid_s_inf = 1'b0;

// axi write data channel 
// src master: no need for write, so keep low
assign wdata_s_inf = 128'b0;
assign wlast_s_inf = 1'b0;
assign wvalid_s_inf = 1'b0;

// axi write response channel 
// src master: no need for write, so keep low
assign bready_s_inf = 1'b0;

// Dram READ Setting
// axi read address channel 
// src master
assign arid_s_inf    = 4'd0;
assign arlen_s_inf   = 8'b11111111;
assign arsize_s_inf  = 3'b100;
assign arburst_s_inf = 2'b01;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        arvalid_s_inf <= 1'b0;
    end else begin
        case (cs_axi)
            AXI_IDLE:begin
                if(arready_s_inf || cnt_channel == 'd48)begin
                    arvalid_s_inf <= 1'b0;
                end else begin
                    arvalid_s_inf <= 1'b1;
                end
            end
            AXI_READ:begin
                arvalid_s_inf <= 1'b0;
            end
        endcase
    end
end 
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        araddr_s_inf <= 32'h10000;
    end else begin
        araddr_s_inf <= ns_araddr;
    end
end
always @(*) begin
    ns_araddr = araddr_s_inf;
    case (cs_axi)
        AXI_READ:begin
            if(r_last_delay)begin
                ns_araddr = {16'd1, (araddr_s_inf[15:12]+1'b1), 12'd0};
            end
        end
    endcase
end
// axi read data channel 
// master
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        rready_s_inf <= 1'b0;
    end else begin
        rready_s_inf <= (cs_axi)? 1'b1 : 1'b0;
        // case (cs_axi)
            // AXI_IDLE:begin
                // rready_s_inf <= 1'b0;
            // end
            // AXI_READ:begin
                // rready_s_inf <= 1'b1;
            // end
        // endcase
    end
end

// Dram Data Classification
// get data from dram
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        dram_data <= 0;
    end else begin
        case (cs_axi)
            AXI_READ:begin
                if(r_handshake)begin
                    dram_data <= rdata_s_inf;
                end
            end
        endcase
    end
end
// Classification
classifier C0(.clk(clk), .data_in(dram_data),
             .out_0(classifier_info_out[0]),  .out_1(classifier_info_out[1]),  .out_2(classifier_info_out[2]),  .out_3(classifier_info_out[3]),  .out_4(classifier_info_out[4]),  .out_5(classifier_info_out[5]),
             .out_6(classifier_info_out[6]),  .out_7(classifier_info_out[7]),  .out_8(classifier_info_out[8]),  .out_9(classifier_info_out[9]), .out_10(classifier_info_out[10]), .out_11(classifier_info_out[11]),
            .out_12(classifier_info_out[12]), .out_13(classifier_info_out[13]), .out_14(classifier_info_out[14]), .out_15(classifier_info_out[15]), .out_16(classifier_info_out[16]), .out_17(classifier_info_out[17]),
            .out_18(classifier_info_out[18]), .out_19(classifier_info_out[19]), .out_20(classifier_info_out[20]), .out_21(classifier_info_out[21]), .out_22(classifier_info_out[22]), .out_23(classifier_info_out[23]),
            .out_24(classifier_info_out[24]), .out_25(classifier_info_out[25]), .out_26(classifier_info_out[26]), .out_27(classifier_info_out[27]), .out_28(classifier_info_out[28]), .out_29(classifier_info_out[29]),
            .out_30(classifier_info_out[30]), .out_31(classifier_info_out[31]), .out_32(classifier_info_out[32]), .out_33(classifier_info_out[33]), .out_34(classifier_info_out[34]), .out_35(classifier_info_out[35]),
            .max(class_max), .min(class_min));

//==================================
//           MAX & MIN
//==================================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 48; i = i + 1)begin
            max[i] <= 8'd0;
            min[i] <= 8'd255;
        end
    end else begin
        if(r_handshake_delay_2)begin
            max[cnt_channel_delay] <= (class_max > max[cnt_channel_delay]) ? class_max : max[cnt_channel_delay];
            min[cnt_channel_delay] <= (class_min < min[cnt_channel_delay]) ? class_min : min[cnt_channel_delay];
        end else begin
            case (cs)
                PAT:begin
                    if(mode == 'd1)begin
                        if(ratio == 'd0)begin
                            max[pic_num*3  ] <= max[pic_num*3  ] >> 2;
                            max[pic_num*3+1] <= max[pic_num*3+1] >> 2;
                            max[pic_num*3+2] <= max[pic_num*3+2] >> 2;
                            min[pic_num*3  ] <= min[pic_num*3  ] >> 2;
                            min[pic_num*3+1] <= min[pic_num*3+1] >> 2;
                            min[pic_num*3+2] <= min[pic_num*3+2] >> 2;
                        end else if(ratio == 'd1)begin
                            max[pic_num*3  ] <= max[pic_num*3  ] >> 1;
                            max[pic_num*3+1] <= max[pic_num*3+1] >> 1;
                            max[pic_num*3+2] <= max[pic_num*3+2] >> 1;
                            min[pic_num*3  ] <= min[pic_num*3  ] >> 1;
                            min[pic_num*3+1] <= min[pic_num*3+1] >> 1;
                            min[pic_num*3+2] <= min[pic_num*3+2] >> 1;
                        end else if(ratio == 'd3)begin
                            max[pic_num*3  ] <= (max[pic_num*3  ] > 127)? 255 : max[pic_num*3  ] << 1;
                            max[pic_num*3+1] <= (max[pic_num*3+1] > 127)? 255 : max[pic_num*3+1] << 1;
                            max[pic_num*3+2] <= (max[pic_num*3+2] > 127)? 255 : max[pic_num*3+2] << 1;
                            min[pic_num*3  ] <= (min[pic_num*3  ] > 127)? 255 : min[pic_num*3  ] << 1;
                            min[pic_num*3+1] <= (min[pic_num*3+1] > 127)? 255 : min[pic_num*3+1] << 1;
                            min[pic_num*3+2] <= (min[pic_num*3+2] > 127)? 255 : min[pic_num*3+2] << 1;
                        end
                    end
                end
            endcase
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        max_total <= 10'd0;
        min_total <= 10'd0;
    end else begin
        case (cs)
            MM:begin
                max_total <= max[pic_num*3] + max[pic_num*3+1] + max[pic_num*3+2];
                min_total <= min[pic_num*3] + min[pic_num*3+1] + min[pic_num*3+2];
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        max_avg <= 8'd0;
        min_avg <= 8'd0;
    end else begin
        case (cs)
            MM:begin
                max_avg <= max_total / 3;
                min_avg <= min_total / 3;
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        mm_out <= 8'd0;
    end else begin
        case (cs)
            MM:begin
                mm_out <= (max_avg + min_avg)/2;
            end
        endcase
    end
end

// sharing 22 bit adder
assign exp_channel_info_conc_temp[0]  = info_conc[0]  + classifier_info_out_conc[0];
assign exp_channel_info_conc_temp[1]  = info_conc[1]  + classifier_info_out_conc[1];
assign exp_channel_info_conc_temp[2]  = info_conc[2]  + classifier_info_out_conc[2];
assign exp_channel_info_conc_temp[3]  = info_conc[3]  + classifier_info_out_conc[3];
assign exp_channel_info_conc_temp[4]  = info_conc[4]  + classifier_info_out_conc[4];
assign exp_channel_info_conc_temp[5]  = info_conc[5]  + classifier_info_out_conc[5];
assign exp_channel_info_conc_temp[6]  = info_conc[6]  + classifier_info_out_conc[6];
assign exp_channel_info_conc_temp[7]  = info_conc[7]  + classifier_info_out_conc[7];
assign exp_channel_info_conc_temp[8]  = info_conc[8]  + classifier_info_out_conc[8];
assign exp_channel_info_conc_temp[9]  = info_conc[9]  + classifier_info_out_conc[9];
assign exp_channel_info_conc_temp[10] = info_conc[10] + classifier_info_out_conc[10];
assign exp_channel_info_conc_temp[11] = info_conc[11] + classifier_info_out_conc[11];
assign exp_channel_info_conc_temp[12] = info_conc[12] + classifier_info_out_conc[12];
assign exp_channel_info_conc_temp[13] = info_conc[13] + classifier_info_out_conc[13];
assign exp_channel_info_conc_temp[14] = info_conc[14] + classifier_info_out_conc[14];
assign exp_channel_info_conc_temp[15] = info_conc[15] + classifier_info_out_conc[15];
assign exp_channel_info_conc_temp[16] = info_conc[16] + classifier_info_out_conc[16];
assign exp_channel_info_conc_temp[17] = info_conc[17] + classifier_info_out_conc[17];

// adder input combinational circuit
always @(*) begin
    // under main fsm: DRAM state
    for(i = 0; i < 18; i = i + 1)begin
        info_conc[i] = 22'd0;
    end
    case(cs)
        DRAM:begin
            for(i = 0; i < 18; i = i + 1)begin
                if(cnt == 'd0)begin
                    info_conc[i] = 22'd0;
                end else begin
                    info_conc[i] = exp_channel_info_conc[i];
                end
            end
        end
        FOCUS:begin
            info_conc[0] = focus_sum_22;
            info_conc[1] = focus_sum_44;
            info_conc[2] = focus_sum_66;
        end
        EXPOSE:begin
            case (cnt)
                'd9, 'd29, 'd49:begin
                    for(i = 0; i < 7; i = i + 1)begin
                        info_conc[i] = exp_channel_info[35];
                    end
                end
                'd10, 'd50:begin
                    info_conc[0] = 'd0;
                    info_conc[1] = 'd0;
                    info_conc[2] = exp_channel_info[5];
                    info_conc[3] = 'd0;
                    info_conc[4] = 'd0;
                    info_conc[5] = exp_channel_info[12];
                    info_conc[6] = exp_channel_info[13];
                    info_conc[7] = exp_channel_info[14];
                    info_conc[8] = 'd0;
                    info_conc[9] = 'd0;
                    info_conc[10] = exp_channel_info[23];
                    info_conc[11] = exp_channel_info[24];
                    info_conc[12] = exp_channel_info[25];
                    info_conc[13] = exp_channel_info[26];
                    info_conc[14] = exp_channel_info[27];
                    info_conc[15] = 'd0;
                end
                // GREEN
                'd30:begin
                    info_conc[0] = 'd0;
                    info_conc[1] = exp_channel_info[4];
                    info_conc[2] = exp_channel_info[5];
                    info_conc[3] = 'd0;
                    info_conc[4] = exp_channel_info[11];
                    info_conc[5] = exp_channel_info[12];
                    info_conc[6] = exp_channel_info[13];
                    info_conc[7] = exp_channel_info[14];
                    info_conc[8] = 'd0;
                    info_conc[9] = exp_channel_info[22];
                    info_conc[10] = exp_channel_info[23];
                    info_conc[11] = exp_channel_info[24];
                    info_conc[12] = exp_channel_info[25];
                    info_conc[13] = exp_channel_info[26];
                    info_conc[14] = exp_channel_info[27];
                    info_conc[15] = 'd0;
                end
                'd11, 'd31, 'd51:begin
                    info_conc[0] = exp_channel_info_conc[0];
                    info_conc[1] = exp_channel_info_conc[4];
                    info_conc[2] = exp_channel_info_conc[2];
                    info_conc[3] = exp_channel_info_conc[3];
                    info_conc[4] = exp_channel_info_conc[7];
                    info_conc[5] = exp_channel_info_conc[8];
                end
                'd12, 'd32, 'd52:begin
                    info_conc[0] = exp_channel_info_conc[0];
                    info_conc[1] = exp_channel_info_conc[2];
                    info_conc[2] = exp_channel_info_conc[3];
                end
                'd13, 'd53:begin
                    info_conc[0] = exp_channel_info_conc[1];
                    info_conc[1] = (exp_channel_info_conc[4] << 2);
                    info_conc[2] = (exp_channel_info_conc[14] << 4);
                end
                'd33:begin
                    info_conc[0] = (exp_channel_info_conc[1] << 1);
                    info_conc[1] = (exp_channel_info_conc[4] << 3);
                    info_conc[2] = (exp_channel_info_conc[14] << 5);
                end
                'd14, 'd34, 'd54:begin
                    info_conc[0] = exp_channel_info_conc[0];
                    info_conc[1] = exp_channel_info_conc[2];
                end
                'd15, 'd35, 'd55:begin
                    info_conc[0] = exp_channel_info_conc[0];
                end
                'd36, 'd56:begin
                    info_conc[0] = exp_channel_info_conc[17];
                end
            endcase
        end
    endcase
end
always @(*) begin
    for(i = 0; i < 18; i = i + 1)begin
        classifier_info_out_conc[i] = 22'd0;
    end
    // under main fsm: DRAM state
    case(cs)
        DRAM:begin
            classifier_info_out_conc[0] = {classifier_info_out[1], classifier_info_out[0]};
            classifier_info_out_conc[1] = {classifier_info_out[3], classifier_info_out[2]};
            classifier_info_out_conc[2] = {classifier_info_out[5], classifier_info_out[4]};
            classifier_info_out_conc[3] = {classifier_info_out[7], classifier_info_out[6]};
            classifier_info_out_conc[4] = {classifier_info_out[9], classifier_info_out[8]};
            classifier_info_out_conc[5] = {classifier_info_out[11], classifier_info_out[10]};
            classifier_info_out_conc[6] = {classifier_info_out[13], classifier_info_out[12]};
            classifier_info_out_conc[7] = {classifier_info_out[15], classifier_info_out[14]};
            classifier_info_out_conc[8] = {classifier_info_out[17], classifier_info_out[16]};
            classifier_info_out_conc[9] = {classifier_info_out[19], classifier_info_out[18]};
            classifier_info_out_conc[10] = {classifier_info_out[21], classifier_info_out[20]};
            classifier_info_out_conc[11] = {classifier_info_out[23], classifier_info_out[22]};
            classifier_info_out_conc[12] = {classifier_info_out[25], classifier_info_out[24]};
            classifier_info_out_conc[13] = {classifier_info_out[27], classifier_info_out[26]};
            classifier_info_out_conc[14] = {classifier_info_out[29], classifier_info_out[28]};
            classifier_info_out_conc[15] = {classifier_info_out[31], classifier_info_out[30]};
            classifier_info_out_conc[16] = {classifier_info_out[33], classifier_info_out[32]};
            classifier_info_out_conc[17] = {classifier_info_out[35], classifier_info_out[34]};
        end
        FOCUS:begin
            if(cnt == 'd17 || cnt == 'd18 || cnt == 'd23 || cnt == 'd24)begin
                classifier_info_out_conc[0] = focus_diff_sum_22;
            end
            if((cnt >= 'd16 && cnt < 'd20) || (cnt >= 'd22 && cnt < 'd26))begin
                classifier_info_out_conc[1] = focus_diff_sum_44;
            end
            if(cnt >= 'd15 && cnt < 'd27)begin
                classifier_info_out_conc[2] = focus_diff_sum_66;
            end
        end
        EXPOSE:begin
            case (cnt)
                'd9, 'd29, 'd49:begin
                    classifier_info_out_conc[0] = exp_channel_info[21];
                    classifier_info_out_conc[1] = exp_channel_info[22];
                    classifier_info_out_conc[2] = exp_channel_info[23];
                    classifier_info_out_conc[3] = exp_channel_info[24];
                    classifier_info_out_conc[4] = exp_channel_info[25];
                    classifier_info_out_conc[5] = exp_channel_info[26];
                    classifier_info_out_conc[6] = exp_channel_info[27];
                end
                'd10, 'd50:begin
                    // R and B
                    classifier_info_out_conc[0] = 'd0;
                    classifier_info_out_conc[1] = 'd0;
                    classifier_info_out_conc[2] = exp_channel_info[8];
                    classifier_info_out_conc[3] = exp_channel_info[9];
                    classifier_info_out_conc[4] = 'd0;
                    classifier_info_out_conc[5] = exp_channel_info[17];
                    classifier_info_out_conc[6] = exp_channel_info[18];
                    classifier_info_out_conc[7] = exp_channel_info[19];
                    classifier_info_out_conc[8] = exp_channel_info[20];
                    classifier_info_out_conc[9] = 'd0;
                    classifier_info_out_conc[10] = exp_channel_info[30];
                    classifier_info_out_conc[11] = exp_channel_info[31];
                    classifier_info_out_conc[12] = exp_channel_info[32];
                    classifier_info_out_conc[13] = exp_channel_info[33];
                    classifier_info_out_conc[14] = exp_channel_info[34];
                    classifier_info_out_conc[15] = exp_channel_info[35];
                end
                'd30:begin
                    // G
                    classifier_info_out_conc[0] = exp_channel_info[2];
                    classifier_info_out_conc[1] = exp_channel_info[7];
                    classifier_info_out_conc[2] = exp_channel_info[8];
                    classifier_info_out_conc[3] = exp_channel_info[9];
                    classifier_info_out_conc[4] = exp_channel_info[16];
                    classifier_info_out_conc[5] = exp_channel_info[17];
                    classifier_info_out_conc[6] = exp_channel_info[18];
                    classifier_info_out_conc[7] = exp_channel_info[19];
                    classifier_info_out_conc[8] = exp_channel_info[20];
                    classifier_info_out_conc[9] = exp_channel_info[29];
                    classifier_info_out_conc[10] = exp_channel_info[30];
                    classifier_info_out_conc[11] = exp_channel_info[31];
                    classifier_info_out_conc[12] = exp_channel_info[32];
                    classifier_info_out_conc[13] = exp_channel_info[33];
                    classifier_info_out_conc[14] = exp_channel_info[34];
                    classifier_info_out_conc[15] = exp_channel_info[35];
                end
                'd11, 'd31, 'd51:begin
                    classifier_info_out_conc[0] = exp_channel_info_conc[1];
                    classifier_info_out_conc[1] = exp_channel_info_conc[9];
                    classifier_info_out_conc[2] = exp_channel_info_conc[5];
                    classifier_info_out_conc[3] = exp_channel_info_conc[6];
                    classifier_info_out_conc[4] = exp_channel_info_conc[12];
                    classifier_info_out_conc[5] = exp_channel_info_conc[13];
                end
                'd12, 'd32, 'd52:begin
                    classifier_info_out_conc[0] = exp_channel_info_conc[1];
                    classifier_info_out_conc[1] = exp_channel_info_conc[10];
                    classifier_info_out_conc[2] = exp_channel_info_conc[11];
                end
                'd13, 'd53:begin
                    classifier_info_out_conc[0] = (exp_channel_info_conc[2] << 1);
                    classifier_info_out_conc[1] = (exp_channel_info_conc[5] << 3);
                    classifier_info_out_conc[2] = (exp_channel_info_conc[15] << 5);
                end
                'd33:begin
                    classifier_info_out_conc[0] = (exp_channel_info_conc[2] << 2);
                    classifier_info_out_conc[1] = (exp_channel_info_conc[5] << 4);
                    classifier_info_out_conc[2] = (exp_channel_info_conc[15] << 6);
                end
                'd14, 'd34, 'd54:begin
                    classifier_info_out_conc[0] = exp_channel_info_conc[1];
                    classifier_info_out_conc[1] = exp_channel_info_conc[3];
                end
                'd15, 'd35, 'd55:begin
                    classifier_info_out_conc[0] = exp_channel_info_conc[1];
                end
                'd16:begin
                    classifier_info_out_conc[0] = 'd0;
                end
                'd36, 'd56:begin
                    classifier_info_out_conc[0] = exp_channel_info_conc[0];
                end
            endcase
        end
    endcase
end

// update exp_channel_info_conc during r_handshake_delay 
// for dram classification calulation and auto-expose output calculation 
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 18; i = i + 1)begin
            exp_channel_info_conc[i] <= 0;
        end
    end else begin
        if(r_handshake_delay)begin
            for(i = 0; i < 18; i = i + 1)begin
                exp_channel_info_conc[i] <= exp_channel_info_conc_temp[i];
            end
        end else begin
            case (cs)
                PAT:begin
                    for(i = 0; i < 18; i = i + 1)begin
                        exp_channel_info_conc[i] <= 0;
                    end
                end
                EXPOSE:begin
                    case (cnt)
                        //R and B
                        //G
                        'd10, 'd30, 'd50:begin
                            for(i = 0; i < 16; i = i + 1)begin
                                exp_channel_info_conc[i] <= exp_channel_info_conc_temp[i];
                            end
                        end
                        'd11, 'd31, 'd51:begin
                            for(i = 0; i < 6; i = i + 1)begin
                                exp_channel_info_conc[i] <= exp_channel_info_conc_temp[i];
                            end
                        end
                        'd12, 'd32, 'd52:begin
                            for(i = 0; i < 3; i = i + 1)begin
                                exp_channel_info_conc[i] <= exp_channel_info_conc_temp[i];
                            end
                        end
                        'd13, 'd33, 'd53:begin
                            for(i = 1; i < 4; i = i + 1)begin
                                exp_channel_info_conc[i] <= exp_channel_info_conc_temp[i-1];
                            end
                        end
                        'd14, 'd34, 'd54:begin
                            for(i = 0; i < 2; i = i + 1)begin
                                exp_channel_info_conc[i] <= exp_channel_info_conc_temp[i];
                            end
                        end
                        'd15:begin
                            exp_channel_info_conc[17] <= exp_channel_info_conc_temp[0];
                        end
                        'd35, 'd55:begin
                            exp_channel_info_conc[0] <= exp_channel_info_conc_temp[0];
                        end
                        'd36, 'd56:begin
                            exp_channel_info_conc[17] <= exp_channel_info_conc_temp[0];
                        end
                    endcase
                end
            endcase
        end
    end
end

// EXPOSE: OUTPUT
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        expose_out <= 0;
    end else begin
        expose_out <= ns_expose_out;
    end
end
always @(*) begin
    ns_expose_out = exp_channel_info_conc[17] >> 10;
    case (cs)
        PAT:begin
            ns_expose_out = expose_out_data[pic_num];
        end
    endcase
end

// keep the exp_channel_info to write into sram
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 36; i = i + 1)begin
            exp_channel_info[i] <= 11'd0;
        end
    end else begin
        case(cs)
            DRAM:begin
                if(cnt == 'd63)begin
                    for(i = 0; i < 18; i = i + 1)begin
                        exp_channel_info[2*i] <= exp_channel_info_conc_temp[i][10:0];
                        exp_channel_info[2*i+1] <= exp_channel_info_conc_temp[i][21:11];
                    end
                end else if(cs_ae == AE_DRAM_WRITE)begin
                    for(i = 0; i < 32; i = i + 1)begin
                        exp_channel_info[i] <= exp_channel_info[i+4];
                    end
                    exp_channel_info[32] <= exp_channel_info[0];
                    exp_channel_info[33] <= exp_channel_info[1];
                    exp_channel_info[34] <= exp_channel_info[2];
                    exp_channel_info[35] <= exp_channel_info[3];
                end
            end
            PAT:begin
                for(i = 0; i < 36; i = i + 1)begin
                    exp_channel_info[i] <= 11'd0;
                end
            end
            EXPOSE:begin
                if(cnt == 'd9 || cnt == 'd29 || cnt == 'd49)begin
                    // ratio
                    case (ratio)
                        'd0:begin
                            // x0.25
                            exp_channel_info[0] <= exp_channel_info[5];
                            exp_channel_info[1] <= exp_channel_info[8];
                            exp_channel_info[2] <= exp_channel_info[9];
                            exp_channel_info[3] <= exp_channel_info[12];
                            exp_channel_info[4] <= exp_channel_info[13];
                            exp_channel_info[5] <= exp_channel_info[14];
                            exp_channel_info[6] <= exp_channel_info[17];
                            exp_channel_info[7] <= exp_channel_info[18];
                            exp_channel_info[8] <= exp_channel_info[19];
                            exp_channel_info[9] <= exp_channel_info[20];
                            exp_channel_info[10] <= exp_channel_info[23];
                            exp_channel_info[11] <= exp_channel_info[24];
                            exp_channel_info[12] <= exp_channel_info[25];
                            exp_channel_info[13] <= exp_channel_info[26];
                            exp_channel_info[14] <= exp_channel_info[27];
                            exp_channel_info[15] <= exp_channel_info[30];
                            exp_channel_info[16] <= exp_channel_info[31];
                            exp_channel_info[17] <= exp_channel_info[32];
                            exp_channel_info[18] <= exp_channel_info[33];
                            exp_channel_info[19] <= exp_channel_info[34];
                            exp_channel_info[20] <= exp_channel_info[35];
                            for(i = 21; i < 36; i = i + 1)begin
                                exp_channel_info[i] <= 11'd0;
                            end
                        end
                        'd1:begin
                            // x0.5
                            exp_channel_info[0] <= exp_channel_info[2];
                            exp_channel_info[1] <= exp_channel_info[4];
                            exp_channel_info[2] <= exp_channel_info[5];
                            exp_channel_info[3] <= exp_channel_info[7];
                            exp_channel_info[4] <= exp_channel_info[8];
                            exp_channel_info[5] <= exp_channel_info[9];
                            exp_channel_info[6] <= exp_channel_info[11];
                            exp_channel_info[7] <= exp_channel_info[12];
                            exp_channel_info[8] <= exp_channel_info[13];
                            exp_channel_info[9] <= exp_channel_info[14];
                            exp_channel_info[10] <= exp_channel_info[16];
                            exp_channel_info[11] <= exp_channel_info[17];
                            exp_channel_info[12] <= exp_channel_info[18];
                            exp_channel_info[13] <= exp_channel_info[19];
                            exp_channel_info[14] <= exp_channel_info[20];
                            exp_channel_info[15] <= exp_channel_info[22];
                            exp_channel_info[16] <= exp_channel_info[23];
                            exp_channel_info[17] <= exp_channel_info[24];
                            exp_channel_info[18] <= exp_channel_info[25];
                            exp_channel_info[19] <= exp_channel_info[26];
                            exp_channel_info[20] <= exp_channel_info[27];
                            exp_channel_info[21] <= exp_channel_info[29];
                            exp_channel_info[22] <= exp_channel_info[30];
                            exp_channel_info[23] <= exp_channel_info[31];
                            exp_channel_info[24] <= exp_channel_info[32];
                            exp_channel_info[25] <= exp_channel_info[33];
                            exp_channel_info[26] <= exp_channel_info[34];
                            exp_channel_info[27] <= exp_channel_info[35];
                            for(i = 28; i < 36; i = i + 1)begin
                                exp_channel_info[i] <= 11'd0;
                            end
                        end
                        'd3:begin
                            // x2
                            exp_channel_info[0] <= 11'd0;
                            exp_channel_info[1] <= 11'd0;
                            exp_channel_info[2] <= exp_channel_info[0];
                            exp_channel_info[3] <= 11'd0;
                            exp_channel_info[4] <= exp_channel_info[1];
                            exp_channel_info[5] <= exp_channel_info[2];
                            exp_channel_info[6] <= 11'd0;
                            exp_channel_info[7] <= exp_channel_info[3];
                            exp_channel_info[8] <= exp_channel_info[4];
                            exp_channel_info[9] <= exp_channel_info[5];
                            exp_channel_info[10] <= 11'd0;
                            exp_channel_info[11] <= exp_channel_info[6];
                            exp_channel_info[12] <= exp_channel_info[7];
                            exp_channel_info[13] <= exp_channel_info[8];
                            exp_channel_info[14] <= exp_channel_info[9];
                            exp_channel_info[15] <= 11'd0;
                            exp_channel_info[16] <= exp_channel_info[10];
                            exp_channel_info[17] <= exp_channel_info[11];
                            exp_channel_info[18] <= exp_channel_info[12];
                            exp_channel_info[19] <= exp_channel_info[13];
                            exp_channel_info[20] <= exp_channel_info[14];
                            exp_channel_info[21] <= 11'd0;
                            exp_channel_info[22] <= exp_channel_info[15];
                            exp_channel_info[23] <= exp_channel_info[16];
                            exp_channel_info[24] <= exp_channel_info[17];
                            exp_channel_info[25] <= exp_channel_info[18];
                            exp_channel_info[26] <= exp_channel_info[19];
                            exp_channel_info[27] <= exp_channel_info[20];
                            exp_channel_info[28] <= 11'd0;
                            // taking from sharing 22 bit adder
                            exp_channel_info[29] <= exp_channel_info_conc_temp[0][10:0];
                            exp_channel_info[30] <= exp_channel_info_conc_temp[1][10:0];
                            exp_channel_info[31] <= exp_channel_info_conc_temp[2][10:0];
                            exp_channel_info[32] <= exp_channel_info_conc_temp[3][10:0];
                            exp_channel_info[33] <= exp_channel_info_conc_temp[4][10:0];
                            exp_channel_info[34] <= exp_channel_info_conc_temp[5][10:0];
                            exp_channel_info[35] <= exp_channel_info_conc_temp[6][10:0];
                        end
                    endcase
                end else begin
                    for(i = 0; i < 32; i = i + 1)begin
                        exp_channel_info[i] <= exp_channel_info[i+4];
                    end
                    exp_channel_info[32] <= rdata_expose[10:0];
                    exp_channel_info[33] <= rdata_expose[21:11];
                    exp_channel_info[34] <= rdata_expose[32:22];
                    exp_channel_info[35] <= rdata_expose[43:33];
                end
            end
        endcase
    end
end

// update focus_channel_info during exact cnt duration
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 36; i = i + 1)begin
            focus_channel_info[i] <= 0;
        end
    end else begin
        case(cs)
            DRAM:begin
                case (cs_af)
                    AF_DRAM_IDLE:begin
                        case (cnt)
                            'd26, 'd28, 'd30, 'd32, 'd34, 'd36:begin
                                for(i = 0; i < 33; i = i + 1)begin
                                    focus_channel_info[i] <= focus_channel_info[i+3];
                                end
                                focus_channel_info[33] <= dram_data[111:104];
                                focus_channel_info[34] <= dram_data[119:112];
                                focus_channel_info[35] <= dram_data[127:120];
                            end
                            'd27, 'd29, 'd31, 'd33, 'd35, 'd37:begin
                                for(i = 0; i < 33; i = i + 1)begin
                                    focus_channel_info[i] <= focus_channel_info[i+3];
                                end
                                focus_channel_info[33] <= dram_data[7:0];
                                focus_channel_info[34] <= dram_data[15:8];
                                focus_channel_info[35] <= dram_data[23:16];
                            end
                        endcase
                    end
                    AF_DRAM_WRITE:begin
                        // shift to help write into focus sram
                        for(i = 0; i < 30; i = i + 1)begin
                            focus_channel_info[i] <= focus_channel_info[i+6];
                        end
                        focus_channel_info[30] <= focus_channel_info[0];
                        focus_channel_info[31] <= focus_channel_info[1];
                        focus_channel_info[32] <= focus_channel_info[2];
                        focus_channel_info[33] <= focus_channel_info[3];
                        focus_channel_info[34] <= focus_channel_info[4];
                        focus_channel_info[35] <= focus_channel_info[5];
                    end
                endcase
            end
            PAT:begin
                for(i = 0; i < 36; i = i + 1)begin
                    focus_channel_info[i] <= 0;
                end
            end
            FOCUS:begin
                if(cnt >= 'd1 && cnt < 'd19)begin
                    for(i = 0; i < 30; i = i + 1)begin
                        focus_channel_info[i] <= focus_channel_info[i+6];
                    end
                    focus_channel_info[30] <= focus_shift_data[0];
                    focus_channel_info[31] <= focus_shift_data[1];
                    focus_channel_info[32] <= focus_shift_data[2];
                    focus_channel_info[33] <= focus_shift_data[3];
                    focus_channel_info[34] <= focus_shift_data[4];
                    focus_channel_info[35] <= focus_shift_data[5];
                end
            end
            EXPOSE:begin
                if(ratio == 2'd3)begin
                    for(i = 0; i < 30; i = i + 1)begin
                        focus_channel_info[i] <= focus_channel_info[i+6];
                    end
                    focus_channel_info[30] <= focus_shift_2_data[0];
                    focus_channel_info[31] <= focus_shift_2_data[1];
                    focus_channel_info[32] <= focus_shift_2_data[2];
                    focus_channel_info[33] <= focus_shift_2_data[3];
                    focus_channel_info[34] <= focus_shift_2_data[4];
                    focus_channel_info[35] <= focus_shift_2_data[5];
                end else begin
                    for(i = 0; i < 30; i = i + 1)begin
                        focus_channel_info[i] <= focus_channel_info[i+6];
                    end
                    focus_channel_info[30] <= focus_shift_data[0];
                    focus_channel_info[31] <= focus_shift_data[1];
                    focus_channel_info[32] <= focus_shift_data[2];
                    focus_channel_info[33] <= focus_shift_data[3];
                    focus_channel_info[34] <= focus_shift_data[4];
                    focus_channel_info[35] <= focus_shift_data[5];
                end
            end
        endcase
    end
end
// FOCUS: calculate grayscale
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 6; i = i + 1)begin
            grayscale_extra_row[i] <= 0;
        end
    end else begin
        case (cs)
            PAT:begin
                for(i = 0; i < 6; i = i + 1)begin
                    grayscale_extra_row[i] <= 0;
                end
            end
            FOCUS:begin
                if(cnt >= 'd0 && cnt < 'd18)begin
                    grayscale_extra_row[0] <= rdata_focus[47:40];
                    grayscale_extra_row[1] <= rdata_focus[39:32];
                    grayscale_extra_row[2] <= rdata_focus[31:24];
                    grayscale_extra_row[3] <= rdata_focus[23:16];
                    grayscale_extra_row[4] <= rdata_focus[15:8];
                    grayscale_extra_row[5] <= rdata_focus[7:0];
                end
            end
            EXPOSE:begin
                if((cnt >= 'd0 && cnt < 'd6)||(cnt >= 'd12 && cnt < 'd18)||(cnt >= 'd24 && cnt < 'd30))begin
                    grayscale_extra_row[0] <= rdata_focus[47:40];
                    grayscale_extra_row[1] <= rdata_focus[39:32];
                    grayscale_extra_row[2] <= rdata_focus[31:24];
                    grayscale_extra_row[3] <= rdata_focus[23:16];
                    grayscale_extra_row[4] <= rdata_focus[15:8];
                    grayscale_extra_row[5] <= rdata_focus[7:0];
                end
            end
        endcase
    end
end
assign focus_shift_2_data[0] = (grayscale_extra_row[0] > 'd127 )? 'd255: (grayscale_extra_row[0] << 1);
assign focus_shift_2_data[1] = (grayscale_extra_row[1] > 'd127 )? 'd255: (grayscale_extra_row[1] << 1);
assign focus_shift_2_data[2] = (grayscale_extra_row[2] > 'd127 )? 'd255: (grayscale_extra_row[2] << 1);
assign focus_shift_2_data[3] = (grayscale_extra_row[3] > 'd127 )? 'd255: (grayscale_extra_row[3] << 1);
assign focus_shift_2_data[4] = (grayscale_extra_row[4] > 'd127 )? 'd255: (grayscale_extra_row[4] << 1);
assign focus_shift_2_data[5] = (grayscale_extra_row[5] > 'd127 )? 'd255: (grayscale_extra_row[5] << 1);
assign focus_shift_data[0] = (grayscale_extra_row[0] >> focus_shamt) + focus_shift_data_offset[0];
assign focus_shift_data[1] = (grayscale_extra_row[1] >> focus_shamt) + focus_shift_data_offset[1];
assign focus_shift_data[2] = (grayscale_extra_row[2] >> focus_shamt) + focus_shift_data_offset[2];
assign focus_shift_data[3] = (grayscale_extra_row[3] >> focus_shamt) + focus_shift_data_offset[3];
assign focus_shift_data[4] = (grayscale_extra_row[4] >> focus_shamt) + focus_shift_data_offset[4];
assign focus_shift_data[5] = (grayscale_extra_row[5] >> focus_shamt) + focus_shift_data_offset[5];
always @(*) begin
    focus_shamt = 2'd0;
    case (cs)
        FOCUS:begin
            if(cnt >= 'd7 && cnt < 'd13)begin
                focus_shamt = 2'd1;
            end else begin
                focus_shamt = 2'd2;
            end
        end
        EXPOSE:begin
            if(ratio == 2'b00)begin
                focus_shamt = 2'd2;
            end else if(ratio == 2'b01)begin
                focus_shamt = 2'd1;
            end else begin
                focus_shamt = 2'd0;
            end
        end
    endcase
end
always @(*) begin
    focus_shift_data_offset[0] = 0;
    focus_shift_data_offset[1] = 0;
    focus_shift_data_offset[2] = 0;
    focus_shift_data_offset[3] = 0;
    focus_shift_data_offset[4] = 0;
    focus_shift_data_offset[5] = 0;
    case (cs)
        FOCUS:begin
            focus_shift_data_offset[0] = focus_channel_info[0];
            focus_shift_data_offset[1] = focus_channel_info[1];
            focus_shift_data_offset[2] = focus_channel_info[2];
            focus_shift_data_offset[3] = focus_channel_info[3];
            focus_shift_data_offset[4] = focus_channel_info[4];
            focus_shift_data_offset[5] = focus_channel_info[5];
        end
    endcase
end

// FOCUS: calculate sum for 2x2, 4x4, 6x6
focus_diff F0(.clk(clk),
            .in0(focus_diff_in[0]), .in1(focus_diff_in[1]), .in2(focus_diff_in[2]),
            .in3(focus_diff_in[3]), .in4(focus_diff_in[4]), .in5(focus_diff_in[5]),
            .out_22(focus_diff_sum_22), .out_44(focus_diff_sum_44), .out_66(focus_diff_sum_66));

always @(*) begin
    focus_diff_in[0] = 0;
    focus_diff_in[1] = 0;
    focus_diff_in[2] = 0;
    focus_diff_in[3] = 0;
    focus_diff_in[4] = 0;
    focus_diff_in[5] = 0;
    case (cs)
        FOCUS:begin
            if(cnt >= 'd14 && cnt < 'd20)begin
                focus_diff_in[0] = focus_channel_info[30];
                focus_diff_in[1] = focus_channel_info[31];
                focus_diff_in[2] = focus_channel_info[32];
                focus_diff_in[3] = focus_channel_info[33];
                focus_diff_in[4] = focus_channel_info[34];
                focus_diff_in[5] = focus_channel_info[35];
            end else if(cnt == 'd20)begin
                focus_diff_in[0] = focus_channel_info[0];
                focus_diff_in[1] = focus_channel_info[6];
                focus_diff_in[2] = focus_channel_info[12];
                focus_diff_in[3] = focus_channel_info[18];
                focus_diff_in[4] = focus_channel_info[24];
                focus_diff_in[5] = focus_channel_info[30];
            end else if(cnt == 'd21)begin
                focus_diff_in[0] = focus_channel_info[1];
                focus_diff_in[1] = focus_channel_info[7];
                focus_diff_in[2] = focus_channel_info[13];
                focus_diff_in[3] = focus_channel_info[19];
                focus_diff_in[4] = focus_channel_info[25];
                focus_diff_in[5] = focus_channel_info[31];
            end else if(cnt == 'd22)begin
                focus_diff_in[0] = focus_channel_info[2];
                focus_diff_in[1] = focus_channel_info[8];
                focus_diff_in[2] = focus_channel_info[14];
                focus_diff_in[3] = focus_channel_info[20];
                focus_diff_in[4] = focus_channel_info[26];
                focus_diff_in[5] = focus_channel_info[32];
            end else if(cnt == 'd23)begin
                focus_diff_in[0] = focus_channel_info[3];
                focus_diff_in[1] = focus_channel_info[9];
                focus_diff_in[2] = focus_channel_info[15];
                focus_diff_in[3] = focus_channel_info[21];
                focus_diff_in[4] = focus_channel_info[27];
                focus_diff_in[5] = focus_channel_info[33];
            end else if(cnt == 'd24)begin
                focus_diff_in[0] = focus_channel_info[4];
                focus_diff_in[1] = focus_channel_info[10];
                focus_diff_in[2] = focus_channel_info[16];
                focus_diff_in[3] = focus_channel_info[22];
                focus_diff_in[4] = focus_channel_info[28];
                focus_diff_in[5] = focus_channel_info[34];
            end else if(cnt == 'd25)begin
                focus_diff_in[0] = focus_channel_info[5];
                focus_diff_in[1] = focus_channel_info[11];
                focus_diff_in[2] = focus_channel_info[17];
                focus_diff_in[3] = focus_channel_info[23];
                focus_diff_in[4] = focus_channel_info[29];
                focus_diff_in[5] = focus_channel_info[35];
            end
        end
    endcase
end

// FOCUS: accumulation of difference in 2x2 matrix
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        focus_sum_22 <= 0;
    end else begin
        case(cs)
            PAT:begin
                focus_sum_22 <= 0;
            end
            FOCUS:begin
                if(cnt == 'd17 || cnt == 'd18 || cnt == 'd23 || cnt == 'd24)begin
                    focus_sum_22 <= exp_channel_info_conc_temp[0][9:0];
                end else if(cnt == 'd25)begin
                    focus_sum_22 <= focus_sum_22 >> 2;
                end
            end
        endcase
    end
end
// FOCUS: accumulation of difference in 4x4 matrix
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        focus_sum_44 <= 0;
    end else begin
        case(cs)
            PAT:begin
                focus_sum_44 <= 0;
            end
            FOCUS:begin
                if((cnt >= 'd16 && cnt < 'd20) || (cnt >= 'd22 && cnt < 'd26))begin
                    focus_sum_44 <= exp_channel_info_conc_temp[1][12:0];
                end else if(cnt == 'd26)begin
                    focus_sum_44 <= focus_sum_44 >> 4;
                end
            end
        endcase
    end
end
// FOCUS: accumulation of difference in 6x6 matrix
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        focus_sum_66 <= 0;
    end else begin
        case(cs)
            PAT:begin
                focus_sum_66 <= 0;
            end
            FOCUS:begin
                if(cnt >= 'd15 && cnt < 'd27)begin
                    focus_sum_66 <= exp_channel_info_conc_temp[2][13:0];
                end else if(cnt == 'd27)begin
                    focus_sum_66 <= focus_sum_66/'d36;
                end
            end
        endcase
    end
end

// FOCUS: OUTPUT
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        focus_out <= 0;
    end else begin
        focus_out <= ns_focus_out;
    end
end
always @(*) begin
    ns_focus_out = focus_out_data[pic_num];
    case (cs)
        FOCUS:begin
            if(cnt == 'd27)begin
                ns_focus_out = (focus_sum_22 < focus_sum_44) ? 8'd1 : 8'd0;
            end else if(cnt == 'd28)begin
                if(focus_out == 'd1)begin
                    ns_focus_out = (focus_sum_44 < focus_sum_66) ? 8'd2 : 8'd1;
                end else begin
                    ns_focus_out = (focus_sum_22 < focus_sum_66) ? 8'd2 : 8'd0;
                end
            end
        end
    endcase
end

//==================================
//            Main FSM
//==================================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cs <= DRAM;
    end else begin
        cs <= ns;
    end
end
always @(*) begin
    ns = cs;
    case (cs)
        DRAM:begin
            if(cnt_channel == 'd48 && cnt_ae == 'd8)begin
                ns = PAT;
            end
        end
        PAT:begin
            if(mode == 'd2)begin
                ns = MM;
            end else if(expose_zero_flag[pic_num] == 1 || (mode == 0 && focus_dirty[pic_num] == 0) || (mode == 1 && ratio == 2 && expose_dirty[pic_num] == 0))begin
                ns = OUT;
            end else begin
                ns = WAIT;
            end
        end
        WAIT:begin
            case(mode)
                'd0:begin
                    ns = FOCUS;
                end
                'd1:begin
                    ns = EXPOSE;
                end
            endcase
        end
        IDLE:begin
            if(in_valid)begin
                ns = PAT;
            end
        end
        FOCUS:begin
            if(cnt == 'd28)begin
                ns = OUT;
            end
        end
        EXPOSE:begin
            if(cnt == 'd58)begin
                ns = OUT;
            end
        end
        MM:begin
            if(cnt == 'd2)begin
                ns = OUT;
            end
        end
        OUT:begin
            ns = IDLE;
        end
    endcase
end

// Global Counter
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt <= 0;
    end else begin
        cnt <= ns_cnt;
    end
end
always @(*) begin
    ns_cnt = 0;
    case (cs)
        DRAM:begin
            if(r_handshake_delay)begin
                // 63 will become 0
                ns_cnt = cnt + 'd1;
            end
        end
        FOCUS:begin
            // become 0 after leaving the state
            ns_cnt = cnt + 'd1;
        end
        EXPOSE:begin
            // become 0 after leaving the state
            ns_cnt = cnt + 'd1;
        end
        MM:begin
            // become 0 after leaving the state
            ns_cnt = cnt + 'd1;
        end
    endcase
end

// pattern input
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        mode <= 0;
        ratio <= 0;
        pic_num <= 0;
    end else if((cs == DRAM || cs == IDLE) && in_valid) begin
        mode <= in_mode;
        ratio <= in_ratio_mode;
        pic_num <= in_pic_no;
    end
end

//==================================
//           EXPOSE FSM
//==================================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cs_ae <= AE_DRAM_IDLE;
    end else begin
        cs_ae <= ns_ae;
    end
end
always @(*) begin
    ns_ae = cs_ae;
    case (cs_ae)
        AE_DRAM_IDLE:begin
            if(cnt == 'd63)begin
                ns_ae = AE_DRAM_STOP;
            end
        end
        AE_DRAM_STOP:begin
            ns_ae = AE_DRAM_WRITE;
        end
        AE_DRAM_WRITE:begin
            if(cnt_ae == 'd8)begin
                if(cnt_channel == 'd48)begin
                    ns_ae = AE_PAT;
                end else begin
                    ns_ae = AE_DRAM_IDLE;
                end
            end
        end
        AE_PAT:begin
            if(mode == 'd0 || mode == 'd2)begin
                ns_ae = AE_IDLE;
            end else if(mode == 'd1) begin
                // auto-expose zero detection
                if(expose_zero_flag[pic_num] == 1 || (ratio == 2 && expose_dirty[pic_num] == 0) )begin
                    ns_ae = AE_IDLE;
                end else begin
                    ns_ae = AE_READ;
                end
            end
        end
        AE_READ:begin
            if(cnt_ae == 'd8)begin
                ns_ae = AE_RATIO;
            end
        end
        AE_RATIO:begin
            if(cnt_ae == 'd1)begin
                ns_ae = AE_WRITE;
            end
        end
        AE_WRITE:begin
            if(cnt_ae == 'd8)begin
                if(cnt_ae_update == 'd2)begin
                    ns_ae = AE_IDLE;
                end else begin
                    ns_ae = AE_READ;
                end
            end
        end
        AE_IDLE:begin
            if(in_valid)begin
                ns_ae = AE_PAT;
            end
        end
    endcase
end

// Counters for auto-expose
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_ae <= 0;
    end else begin
        cnt_ae <= ns_cnt_ae;
    end
end
always @(*) begin
    ns_cnt_ae = 0;
    case (cs_ae)
        AE_DRAM_WRITE:begin
            if(cnt_ae == 'd8)begin
                ns_cnt_ae = 0;
            end else begin
                ns_cnt_ae = cnt_ae + 'd1;
            end
        end
        AE_READ:begin
            if(cnt_ae == 'd8)begin
                ns_cnt_ae = 0;
            end else begin
                ns_cnt_ae = cnt_ae + 'd1;
            end
        end
        AE_RATIO:begin
            if(cnt_ae == 'd1)begin
                ns_cnt_ae = 0;
            end else begin
                ns_cnt_ae = cnt_ae + 'd1;
            end
        end
        AE_WRITE:begin
            if(cnt_ae == 'd8)begin
                ns_cnt_ae = 0;
            end else begin
                ns_cnt_ae = cnt_ae + 'd1;
            end
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_ae_update <= 0;
    end else begin
        cnt_ae_update <= ns_cnt_ae_update;
    end
end
always @(*) begin
    ns_cnt_ae_update = 0;
    case (cs_ae)
        AE_READ:begin
            ns_cnt_ae_update = cnt_ae_update;
        end
        AE_RATIO:begin
            ns_cnt_ae_update = cnt_ae_update;
        end
        AE_WRITE:begin
            if(cnt_ae == 'd8)begin
                if(cnt_ae_update == 'd2)begin
                    ns_cnt_ae_update = 0;
                end else begin
                    ns_cnt_ae_update = cnt_ae_update + 'd1;
                end
            end else begin
                ns_cnt_ae_update = cnt_ae_update;
            end
        end
    endcase
end

//==================================
//           EXPOSE SRAM
//==================================
SUMA180_432X44X1BM1 AE(.A0(addr_expose[0]),.A1(addr_expose[1]),.A2(addr_expose[2]),.A3(addr_expose[3]),.A4(addr_expose[4]),
                      .A5(addr_expose[5]),.A6(addr_expose[6]),.A7(addr_expose[7]),.A8(addr_expose[8]),
                      .DO0(rdata_expose[0]),.DO1(rdata_expose[1]),.DO2(rdata_expose[2]),.DO3(rdata_expose[3]),.DO4(rdata_expose[4]),
                      .DO5(rdata_expose[5]),.DO6(rdata_expose[6]),.DO7(rdata_expose[7]),.DO8(rdata_expose[8]),.DO9(rdata_expose[9]),.DO10(rdata_expose[10]),
                      .DO11(rdata_expose[11]),.DO12(rdata_expose[12]),.DO13(rdata_expose[13]),.DO14(rdata_expose[14]),.DO15(rdata_expose[15]),
                      .DO16(rdata_expose[16]),.DO17(rdata_expose[17]),.DO18(rdata_expose[18]),.DO19(rdata_expose[19]),.DO20(rdata_expose[20]),.DO21(rdata_expose[21]),
                      .DO22(rdata_expose[22]),.DO23(rdata_expose[23]),.DO24(rdata_expose[24]),.DO25(rdata_expose[25]),.DO26(rdata_expose[26]),
                      .DO27(rdata_expose[27]),.DO28(rdata_expose[28]),.DO29(rdata_expose[29]),.DO30(rdata_expose[30]),.DO31(rdata_expose[31]),.DO32(rdata_expose[32]),
                      .DO33(rdata_expose[33]),.DO34(rdata_expose[34]),.DO35(rdata_expose[35]),.DO36(rdata_expose[36]),.DO37(rdata_expose[37]),
                      .DO38(rdata_expose[38]),.DO39(rdata_expose[39]),.DO40(rdata_expose[40]),.DO41(rdata_expose[41]),.DO42(rdata_expose[42]),.DO43(rdata_expose[43]),
                      .DI0(wdata_expose[0]),.DI1(wdata_expose[1]),.DI2(wdata_expose[2]),.DI3(wdata_expose[3]),.DI4(wdata_expose[4]),
                      .DI5(wdata_expose[5]),.DI6(wdata_expose[6]),.DI7(wdata_expose[7]),.DI8(wdata_expose[8]),.DI9(wdata_expose[9]),.DI10(wdata_expose[10]),
                      .DI11(wdata_expose[11]),.DI12(wdata_expose[12]),.DI13(wdata_expose[13]),.DI14(wdata_expose[14]),.DI15(wdata_expose[15]),
                      .DI16(wdata_expose[16]),.DI17(wdata_expose[17]),.DI18(wdata_expose[18]),.DI19(wdata_expose[19]),.DI20(wdata_expose[20]),.DI21(wdata_expose[21]),
                      .DI22(wdata_expose[22]),.DI23(wdata_expose[23]),.DI24(wdata_expose[24]),.DI25(wdata_expose[25]),.DI26(wdata_expose[26]),
                      .DI27(wdata_expose[27]),.DI28(wdata_expose[28]),.DI29(wdata_expose[29]),.DI30(wdata_expose[30]),.DI31(wdata_expose[31]),.DI32(wdata_expose[32]),
                      .DI33(wdata_expose[33]),.DI34(wdata_expose[34]),.DI35(wdata_expose[35]),.DI36(wdata_expose[36]),.DI37(wdata_expose[37]),
                      .DI38(wdata_expose[38]),.DI39(wdata_expose[39]),.DI40(wdata_expose[40]),.DI41(wdata_expose[41]),.DI42(wdata_expose[42]),.DI43(wdata_expose[43]),
                      .CK(clk),.WEB(web_expose),.OE(1'b1),.CS(cs_expose));

// chip enable and write enable for expose
always @(*) begin
    cs_expose = 0;
    case (cs_ae)
        AE_DRAM_WRITE:begin
            cs_expose = 1;
        end
        AE_READ:begin
            cs_expose = 1;
        end
        AE_WRITE:begin
            cs_expose = 1;
        end
    endcase
end
always @(*) begin
    web_expose = 1;
    case (cs_ae)
        AE_DRAM_WRITE:begin
            web_expose = 0;
        end 
        AE_WRITE:begin
            web_expose = 0;
        end
    endcase
end

// address for expose
always @(*)begin
    addr_expose = 0;
    case(cs_ae)
        AE_DRAM_WRITE:begin
            addr_expose = addr_expose_offset;
        end
        AE_READ:begin
            addr_expose = addr_expose_offset;
        end
        AE_WRITE:begin
            addr_expose = addr_expose_offset;
        end
    endcase
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        addr_expose_offset <= 0;
    end else begin
        addr_expose_offset <= ns_addr_expose_offset;
    end
end
always @(*) begin
    ns_addr_expose_offset = 0;
    case (cs_ae)
        AE_DRAM_IDLE:begin
            ns_addr_expose_offset = addr_expose_offset;
        end
        AE_DRAM_STOP:begin
            ns_addr_expose_offset = addr_expose_offset;
        end
        AE_DRAM_WRITE:begin
            ns_addr_expose_offset = addr_expose_offset + 'd1;
        end
        AE_PAT:begin
            // no matter what mode is, the address of expose sram should be the same value
            ns_addr_expose_offset = (pic_num << 4) + (pic_num << 3) + (pic_num << 1) + pic_num;
        end
        AE_READ:begin
            ns_addr_expose_offset = addr_expose_offset + 'd1;
        end
        AE_RATIO:begin
            if(cnt_ae[0])begin
                ns_addr_expose_offset = addr_expose_offset -'d9;
            end else begin
                ns_addr_expose_offset = addr_expose_offset;
            end
        end
        AE_WRITE:begin
            ns_addr_expose_offset = addr_expose_offset + 'd1;
        end
    endcase
end

// write data for expose
always @(*) begin
    wdata_expose = 0;
    case (cs_ae)
        AE_DRAM_WRITE:begin
            wdata_expose = {exp_channel_info[3], exp_channel_info[2], exp_channel_info[1], exp_channel_info[0]};
        end
        AE_WRITE:begin
            wdata_expose = {exp_channel_info[3], exp_channel_info[2], exp_channel_info[1], exp_channel_info[0]};
        end
    endcase
end

//==================================
//            FOCUS FSM
//==================================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cs_af <= AF_DRAM_IDLE;
    end else begin
        cs_af <= ns_af;
    end
end
always @(*) begin
    ns_af = cs_af;
    case (cs_af)
        AF_DRAM_IDLE:begin
            if(cnt_ae == 'd8 && cnt_channel == 'd48)begin
                ns_af = AF_PAT;
            end else if(cnt == 'd63)begin
                ns_af = AF_DRAM_WRITE;
            end
        end
        AF_DRAM_WRITE:begin
            if(cnt_af == 'd5)begin
                ns_af = AF_DRAM_IDLE;
            end
        end
        AF_PAT:begin
            if(expose_zero_flag[pic_num] == 1 || mode == 'd2)begin
                ns_af = AF_IDLE;
            end else begin
                if(mode == 'd0)begin
                    if(focus_dirty[pic_num] == 0)begin
                        ns_af = AF_IDLE;
                    end else begin
                        ns_af = AF_FOCUS_READ;
                    end
                end else if(mode == 'd1) begin
                    if(ratio == 'd2)begin
                        ns_af = AF_IDLE;
                    end else begin
                        ns_af = AF_EXPOSE_READ;
                    end
                end
            end
        end
        AF_EXPOSE_READ:begin
            if(cnt_af == 'd5)begin
                ns_af = AF_EXPOSE_WRITE;
            end
        end
        AF_EXPOSE_WRITE:begin
            if(cnt_af == 'd5)begin
                if(cnt_af_update == 'd2)begin
                    ns_af = AF_IDLE;
                end else begin
                    ns_af = AF_EXPOSE_READ;
                end
            end
        end
        AF_FOCUS_READ:begin
            if(cnt_af == 'd17)begin
                ns_af = AF_IDLE;
            end
        end
        AF_IDLE:begin
            if(in_valid)begin
                ns_af = AF_PAT;
            end
        end
    endcase
end

// Counters for auto-focus
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_af <= 0;
    end else begin
        cnt_af <= ns_cnt_af;
    end
end
always @(*) begin
    ns_cnt_af = 0;
    case (cs_af)
        AF_DRAM_WRITE:begin
            // if(cnt_af == 'd5)begin
                // ns_cnt_af = 0;
            // end else begin
                ns_cnt_af = cnt_af + 'd1;
            // end
        end
        AF_EXPOSE_READ:begin
            if(cnt_af == 'd5)begin
                ns_cnt_af = 0;
            end else begin
                ns_cnt_af = cnt_af + 'd1;
            end
        end
        AF_EXPOSE_WRITE:begin
            if(cnt_af == 'd5)begin
                ns_cnt_af = 0;
            end else begin
                ns_cnt_af = cnt_af + 'd1;
            end
        end
        AF_FOCUS_READ:begin
            if(cnt_af == 'd17)begin
                ns_cnt_af = 0;
            end else begin
                ns_cnt_af = cnt_af + 'd1;
            end
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_af_update <= 0;
    end else begin
        cnt_af_update <= ns_cnt_af_update;
    end
end
always @(*) begin
    ns_cnt_af_update = 0;
    case (cs_af)
        AF_EXPOSE_READ:begin
            ns_cnt_af_update = cnt_af_update;
        end
        AF_EXPOSE_WRITE:begin
            if(cnt_af == 'd5)begin
                if(cnt_af_update == 'd2)begin
                    ns_cnt_af_update = 0;
                end else begin
                    ns_cnt_af_update = cnt_af_update + 'd1;
                end
            end else begin
                ns_cnt_af_update = cnt_af_update;
            end
        end
    endcase
end

//==================================
//           FOCUS SRAM
//==================================
SUMA180_288X48X1BM1 AF(.A0(addr_focus[0]),.A1(addr_focus[1]),.A2(addr_focus[2]),.A3(addr_focus[3]),.A4(addr_focus[4]),
                       .A5(addr_focus[5]),.A6(addr_focus[6]),.A7(addr_focus[7]),.A8(addr_focus[8]),
                       .DO0(rdata_focus[0]),.DO1(rdata_focus[1]),.DO2(rdata_focus[2]),.DO3(rdata_focus[3]),.DO4(rdata_focus[4]),.DO5(rdata_focus[5]),
                       .DO6(rdata_focus[6]),.DO7(rdata_focus[7]),.DO8(rdata_focus[8]),.DO9(rdata_focus[9]),.DO10(rdata_focus[10]),.DO11(rdata_focus[11]),
                       .DO12(rdata_focus[12]),.DO13(rdata_focus[13]),.DO14(rdata_focus[14]),.DO15(rdata_focus[15]),.DO16(rdata_focus[16]),.DO17(rdata_focus[17]),
                       .DO18(rdata_focus[18]),.DO19(rdata_focus[19]),.DO20(rdata_focus[20]),.DO21(rdata_focus[21]),.DO22(rdata_focus[22]),.DO23(rdata_focus[23]),
                       .DO24(rdata_focus[24]),.DO25(rdata_focus[25]),.DO26(rdata_focus[26]),.DO27(rdata_focus[27]),.DO28(rdata_focus[28]),.DO29(rdata_focus[29]),
                       .DO30(rdata_focus[30]),.DO31(rdata_focus[31]),.DO32(rdata_focus[32]),.DO33(rdata_focus[33]),.DO34(rdata_focus[34]),.DO35(rdata_focus[35]),
                       .DO36(rdata_focus[36]),.DO37(rdata_focus[37]),.DO38(rdata_focus[38]),.DO39(rdata_focus[39]),.DO40(rdata_focus[40]),.DO41(rdata_focus[41]),
                       .DO42(rdata_focus[42]),.DO43(rdata_focus[43]),.DO44(rdata_focus[44]),.DO45(rdata_focus[45]),.DO46(rdata_focus[46]),.DO47(rdata_focus[47]),
                       .DI0(wdata_focus[0]),.DI1(wdata_focus[1]),.DI2(wdata_focus[2]),.DI3(wdata_focus[3]),.DI4(wdata_focus[4]),.DI5(wdata_focus[5]),
                       .DI6(wdata_focus[6]),.DI7(wdata_focus[7]),.DI8(wdata_focus[8]),.DI9(wdata_focus[9]),.DI10(wdata_focus[10]),.DI11(wdata_focus[11]),
                       .DI12(wdata_focus[12]),.DI13(wdata_focus[13]),.DI14(wdata_focus[14]),.DI15(wdata_focus[15]),.DI16(wdata_focus[16]),.DI17(wdata_focus[17]),
                       .DI18(wdata_focus[18]),.DI19(wdata_focus[19]),.DI20(wdata_focus[20]),.DI21(wdata_focus[21]),.DI22(wdata_focus[22]),.DI23(wdata_focus[23]),
                       .DI24(wdata_focus[24]),.DI25(wdata_focus[25]),.DI26(wdata_focus[26]),.DI27(wdata_focus[27]),.DI28(wdata_focus[28]),.DI29(wdata_focus[29]),
                       .DI30(wdata_focus[30]),.DI31(wdata_focus[31]),.DI32(wdata_focus[32]),.DI33(wdata_focus[33]),.DI34(wdata_focus[34]),.DI35(wdata_focus[35]),
                       .DI36(wdata_focus[36]),.DI37(wdata_focus[37]),.DI38(wdata_focus[38]),.DI39(wdata_focus[39]),.DI40(wdata_focus[40]),.DI41(wdata_focus[41]),
                       .DI42(wdata_focus[42]),.DI43(wdata_focus[43]),.DI44(wdata_focus[44]),.DI45(wdata_focus[45]),.DI46(wdata_focus[46]),.DI47(wdata_focus[47]),
                       .CK(clk),.WEB(web_focus),.OE(1'b1),.CS(cs_focus));

// chip enable and write enable for focus
always @(*) begin
    cs_focus = 0;
    case (cs_af)
        AF_DRAM_WRITE:begin
            cs_focus = 1;
        end
        AF_FOCUS_READ:begin
            cs_focus = 1;
        end
        AF_EXPOSE_READ:begin
            cs_focus = 1;
        end
        AF_EXPOSE_WRITE:begin
            cs_focus = 1;
        end
    endcase
end
always @(*) begin
    web_focus = 1;
    case (cs_af)
        AF_DRAM_WRITE:begin
            web_focus = 0;
        end
        AF_EXPOSE_WRITE:begin
            web_focus = 0;
        end
    endcase
end

// address for focus
always @(*) begin
    addr_focus = 0;
    case (cs_af)
        AF_DRAM_WRITE:begin
            addr_focus = addr_focus_offset;
        end
        AF_FOCUS_READ:begin
            addr_focus = addr_focus_offset;
        end
        AF_EXPOSE_READ:begin
            addr_focus = addr_focus_offset;
        end
        AF_EXPOSE_WRITE:begin
            addr_focus = addr_focus_offset;
        end
    endcase
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        addr_focus_offset <= 0;
    end else begin
        addr_focus_offset <= ns_addr_focus_offset;
    end
end
always @(*) begin
    ns_addr_focus_offset = 0;
    case (cs_af)
        AF_DRAM_IDLE:begin
            ns_addr_focus_offset = addr_focus_offset;
        end
        AF_DRAM_WRITE:begin
            ns_addr_focus_offset = addr_focus_offset + 'd1;
        end
        AF_PAT:begin
            // no matter what mode is, the address offset of focus sram should be the same value
            ns_addr_focus_offset = (pic_num << 4) + (pic_num << 1);
        end
        AF_FOCUS_READ:begin
            ns_addr_focus_offset = addr_focus_offset + 'd1;
        end
        AF_EXPOSE_READ:begin
            if(cnt_af == 'd5)begin
                ns_addr_focus_offset = addr_focus_offset - 'd5;
            end else begin
                ns_addr_focus_offset = addr_focus_offset + 'd1;
            end
        end
        AF_EXPOSE_WRITE:begin
            ns_addr_focus_offset = addr_focus_offset + 'd1;
        end
    endcase
end


// write data for focus
always @(*) begin
    wdata_focus = 0;
    case (cs_af)
        AF_DRAM_WRITE:begin
            wdata_focus = {focus_channel_info[5], focus_channel_info[4], focus_channel_info[3], focus_channel_info[2], focus_channel_info[1], focus_channel_info[0]};
        end
        AF_EXPOSE_WRITE:begin
            wdata_focus = {focus_channel_info[12], focus_channel_info[13], focus_channel_info[14], focus_channel_info[15], focus_channel_info[16], focus_channel_info[17]};
        end
    endcase
end

//==================================
//             OUTPUT
//==================================
assign out_valid = (cs == OUT) ? 1 : 0;
always @(*) begin
    out_data = 0;
    case (cs)
        OUT:begin
            case (mode)
                'd0:begin
                    out_data = focus_out;
                end
                'd1:begin
                    out_data = expose_out;
                end
                'd2:begin
                    out_data = mm_out;
                end
            endcase
        end
    endcase
end


endmodule

module classifier(clk, data_in,
                out_0, out_1, out_2, out_3, out_4, out_5,
                out_6, out_7, out_8, out_9, out_10, out_11,
                out_12, out_13, out_14, out_15, out_16, out_17,
                out_18, out_19, out_20, out_21, out_22, out_23,
                out_24, out_25, out_26, out_27, out_28, out_29,
                out_30, out_31, out_32, out_33, out_34, out_35,
                max, min);

input           clk;
input   [127:0] data_in;
output  [10:0]  out_0; 
output  [10:0]  out_1; 
output  [10:0]  out_2; 
output  [10:0]  out_3; 
output  [10:0]  out_4; 
output  [10:0]  out_5;
output  [10:0]  out_6; 
output  [10:0]  out_7; 
output  [10:0]  out_8; 
output  [10:0]  out_9; 
output  [10:0]  out_10; 
output  [10:0]  out_11;
output  [10:0]  out_12; 
output  [10:0]  out_13; 
output  [10:0]  out_14; 
output  [10:0]  out_15; 
output  [10:0]  out_16; 
output  [10:0]  out_17;
output  [10:0]  out_18; 
output  [10:0]  out_19; 
output  [10:0]  out_20; 
output  [10:0]  out_21; 
output  [10:0]  out_22; 
output  [10:0]  out_23;
output  [10:0]  out_24; 
output  [10:0]  out_25; 
output  [10:0]  out_26; 
output  [10:0]  out_27; 
output  [10:0]  out_28; 
output  [10:0]  out_29;
output  [10:0]  out_30; 
output  [10:0]  out_31; 
output  [10:0]  out_32; 
output  [10:0]  out_33; 
output  [10:0]  out_34; 
output  [10:0]  out_35;
output  [7:0]   max;
output  [7:0]   min;

wire    [7:0]   data        [0:15];
wire            data_info_0 [0:36];
wire            data_info_1 [0:36];
wire            data_info_2 [0:36];
wire            data_info_3 [0:36];
wire            data_info_4 [0:36];
wire            data_info_5 [0:36];
wire            data_info_6 [0:36];
wire            data_info_7 [0:36];
wire            data_info_8 [0:36];
wire            data_info_9 [0:36];
wire            data_info_10[0:36];
wire            data_info_11[0:36];
wire            data_info_12[0:36];
wire            data_info_13[0:36];
wire            data_info_14[0:36];
wire            data_info_15[0:36];
wire            data_info_16[0:36];
wire            data_info_17[0:36];
wire            data_info_18[0:36];
wire            data_info_19[0:36];
wire            data_info_20[0:36];
wire            data_info_21[0:36];
wire            data_info_22[0:36];
wire            data_info_23[0:36];
wire            data_info_24[0:36];
wire            data_info_25[0:36];
wire            data_info_26[0:36];
wire            data_info_27[0:36];
wire            data_info_28[0:36];
wire            data_info_29[0:36];
wire            data_info_30[0:36];
wire            data_info_31[0:36];
wire            data_info_32[0:36];
wire            data_info_33[0:36];
wire            data_info_34[0:36];
wire            data_info_35[0:36];

wire    [7:0]   b   [0:7];
wire    [7:0]   s   [0:7];
wire    [7:0]   bb  [0:3];
wire    [7:0]   ss  [0:3];
reg     [7:0]   bb_reg  [0:3];
reg     [7:0]   ss_reg  [0:3];
wire    [7:0]   bbb [0:1];
wire    [7:0]   sss [0:1];
// adder for 1 bit * 16
wire    [4:0]   data_temp       [0:35];
reg     [4:0]   data_temp_reg   [0:35];

assign data[0] = data_in[7:0];
assign data[1] = data_in[15:8];
assign data[2] = data_in[23:16];
assign data[3] = data_in[31:24];
assign data[4] = data_in[39:32];
assign data[5] = data_in[47:40];
assign data[6] = data_in[55:48];
assign data[7] = data_in[63:56];
assign data[8] = data_in[71:64];
assign data[9] = data_in[79:72];
assign data[10] = data_in[87:80];
assign data[11] = data_in[95:88];
assign data[12] = data_in[103:96];
assign data[13] = data_in[111:104];
assign data[14] = data_in[119:112];
assign data[15] = data_in[127:120];

// max and min
assign b[0] = (data[0] > data[1]) ? data[0] : data[1];
assign s[0] = (data[0] > data[1]) ? data[1] : data[0];
assign b[1] = (data[2] > data[3]) ? data[2] : data[3];
assign s[1] = (data[2] > data[3]) ? data[3] : data[2];
assign b[2] = (data[4] > data[5]) ? data[4] : data[5];
assign s[2] = (data[4] > data[5]) ? data[5] : data[4];
assign b[3] = (data[6] > data[7]) ? data[6] : data[7];
assign s[3] = (data[6] > data[7]) ? data[7] : data[6];
assign b[4] = (data[8] > data[9]) ? data[8] : data[9];
assign s[4] = (data[8] > data[9]) ? data[9] : data[8];
assign b[5] = (data[10] > data[11]) ? data[10] : data[11];
assign s[5] = (data[10] > data[11]) ? data[11] : data[10];
assign b[6] = (data[12] > data[13]) ? data[12] : data[13];
assign s[6] = (data[12] > data[13]) ? data[13] : data[12];
assign b[7] = (data[14] > data[15]) ? data[14] : data[15];
assign s[7] = (data[14] > data[15]) ? data[15] : data[14];

assign bb[0] = (b[0] > b[1]) ? b[0] : b[1];
assign ss[0] = (s[0] > s[1]) ? s[1] : s[0];
assign bb[1] = (b[2] > b[3]) ? b[2] : b[3];
assign ss[1] = (s[2] > s[3]) ? s[3] : s[2];
assign bb[2] = (b[4] > b[5]) ? b[4] : b[5];
assign ss[2] = (s[4] > s[5]) ? s[5] : s[4];
assign bb[3] = (b[6] > b[7]) ? b[6] : b[7];
assign ss[3] = (s[6] > s[7]) ? s[7] : s[6];
always @(posedge clk) begin
    bb_reg[0] <= bb[0];
    ss_reg[0] <= ss[0];
    bb_reg[1] <= bb[1];
    ss_reg[1] <= ss[1];
    bb_reg[2] <= bb[2];
    ss_reg[2] <= ss[2];
    bb_reg[3] <= bb[3];
    ss_reg[3] <= ss[3];
end

assign bbb[0] = (bb_reg[0] > bb_reg[1]) ? bb_reg[0] : bb_reg[1];
assign sss[0] = (ss_reg[0] > ss_reg[1]) ? ss_reg[1] : ss_reg[0];
assign bbb[1] = (bb_reg[2] > bb_reg[3]) ? bb_reg[2] : bb_reg[3];
assign sss[1] = (ss_reg[2] > ss_reg[3]) ? ss_reg[3] : ss_reg[2];

assign max = (bbb[0] > bbb[1]) ? bbb[0] : bbb[1];
assign min = (sss[0] > sss[1]) ? sss[1] : sss[0];

// small classifier
classifier_8 U0(.in(data[0]),.out_0(data_info_0[0]) ,  .out_1(data_info_0[1]) ,  .out_2(data_info_0[2]) ,  .out_3(data_info_0[3]) ,  .out_4(data_info_0[4]) ,  .out_5(data_info_0[5]),
                             .out_6(data_info_0[6]) ,  .out_7(data_info_0[7]) ,  .out_8(data_info_0[8]) ,  .out_9(data_info_0[9]),  .out_10(data_info_0[10]), .out_11(data_info_0[11]),
                            .out_12(data_info_0[12]), .out_13(data_info_0[13]), .out_14(data_info_0[14]), .out_15(data_info_0[15]), .out_16(data_info_0[16]), .out_17(data_info_0[17]),
                            .out_18(data_info_0[18]), .out_19(data_info_0[19]), .out_20(data_info_0[20]), .out_21(data_info_0[21]), .out_22(data_info_0[22]), .out_23(data_info_0[23]),
                            .out_24(data_info_0[24]), .out_25(data_info_0[25]), .out_26(data_info_0[26]), .out_27(data_info_0[27]), .out_28(data_info_0[28]), .out_29(data_info_0[29]),
                            .out_30(data_info_0[30]), .out_31(data_info_0[31]), .out_32(data_info_0[32]), .out_33(data_info_0[33]), .out_34(data_info_0[34]), .out_35(data_info_0[35]));

classifier_8 U1(.in(data[1]),.out_0(data_info_1[0]) ,  .out_1(data_info_1[1]) ,  .out_2(data_info_1[2]) ,  .out_3(data_info_1[3]) ,  .out_4(data_info_1[4]) ,  .out_5(data_info_1[5]),
                             .out_6(data_info_1[6]) ,  .out_7(data_info_1[7]) ,  .out_8(data_info_1[8]) ,  .out_9(data_info_1[9]),  .out_10(data_info_1[10]), .out_11(data_info_1[11]),
                            .out_12(data_info_1[12]), .out_13(data_info_1[13]), .out_14(data_info_1[14]), .out_15(data_info_1[15]), .out_16(data_info_1[16]), .out_17(data_info_1[17]),
                            .out_18(data_info_1[18]), .out_19(data_info_1[19]), .out_20(data_info_1[20]), .out_21(data_info_1[21]), .out_22(data_info_1[22]), .out_23(data_info_1[23]),
                            .out_24(data_info_1[24]), .out_25(data_info_1[25]), .out_26(data_info_1[26]), .out_27(data_info_1[27]), .out_28(data_info_1[28]), .out_29(data_info_1[29]),
                            .out_30(data_info_1[30]), .out_31(data_info_1[31]), .out_32(data_info_1[32]), .out_33(data_info_1[33]), .out_34(data_info_1[34]), .out_35(data_info_1[35]));

classifier_8 U2(.in(data[2]),.out_0(data_info_2[0]) ,  .out_1(data_info_2[1]) ,  .out_2(data_info_2[2]) ,  .out_3(data_info_2[3]) ,  .out_4(data_info_2[4]) ,  .out_5(data_info_2[5]),
                             .out_6(data_info_2[6]) ,  .out_7(data_info_2[7]) ,  .out_8(data_info_2[8]) ,  .out_9(data_info_2[9]),  .out_10(data_info_2[10]), .out_11(data_info_2[11]),
                            .out_12(data_info_2[12]), .out_13(data_info_2[13]), .out_14(data_info_2[14]), .out_15(data_info_2[15]), .out_16(data_info_2[16]), .out_17(data_info_2[17]),
                            .out_18(data_info_2[18]), .out_19(data_info_2[19]), .out_20(data_info_2[20]), .out_21(data_info_2[21]), .out_22(data_info_2[22]), .out_23(data_info_2[23]),
                            .out_24(data_info_2[24]), .out_25(data_info_2[25]), .out_26(data_info_2[26]), .out_27(data_info_2[27]), .out_28(data_info_2[28]), .out_29(data_info_2[29]),
                            .out_30(data_info_2[30]), .out_31(data_info_2[31]), .out_32(data_info_2[32]), .out_33(data_info_2[33]), .out_34(data_info_2[34]), .out_35(data_info_2[35]));

classifier_8 U3(.in(data[3]),.out_0(data_info_3[0]) ,  .out_1(data_info_3[1]) ,  .out_2(data_info_3[2]) ,  .out_3(data_info_3[3]) ,  .out_4(data_info_3[4]) ,  .out_5(data_info_3[5]),
                             .out_6(data_info_3[6]) ,  .out_7(data_info_3[7]) ,  .out_8(data_info_3[8]) ,  .out_9(data_info_3[9]),  .out_10(data_info_3[10]), .out_11(data_info_3[11]),
                            .out_12(data_info_3[12]), .out_13(data_info_3[13]), .out_14(data_info_3[14]), .out_15(data_info_3[15]), .out_16(data_info_3[16]), .out_17(data_info_3[17]),
                            .out_18(data_info_3[18]), .out_19(data_info_3[19]), .out_20(data_info_3[20]), .out_21(data_info_3[21]), .out_22(data_info_3[22]), .out_23(data_info_3[23]),
                            .out_24(data_info_3[24]), .out_25(data_info_3[25]), .out_26(data_info_3[26]), .out_27(data_info_3[27]), .out_28(data_info_3[28]), .out_29(data_info_3[29]),
                            .out_30(data_info_3[30]), .out_31(data_info_3[31]), .out_32(data_info_3[32]), .out_33(data_info_3[33]), .out_34(data_info_3[34]), .out_35(data_info_3[35]));

classifier_8 U4(.in(data[4]),.out_0(data_info_4[0]) ,  .out_1(data_info_4[1]) ,  .out_2(data_info_4[2]) ,  .out_3(data_info_4[3]) ,  .out_4(data_info_4[4]) ,  .out_5(data_info_4[5]),
                             .out_6(data_info_4[6]) ,  .out_7(data_info_4[7]) ,  .out_8(data_info_4[8]) ,  .out_9(data_info_4[9]),  .out_10(data_info_4[10]), .out_11(data_info_4[11]),
                            .out_12(data_info_4[12]), .out_13(data_info_4[13]), .out_14(data_info_4[14]), .out_15(data_info_4[15]), .out_16(data_info_4[16]), .out_17(data_info_4[17]),
                            .out_18(data_info_4[18]), .out_19(data_info_4[19]), .out_20(data_info_4[20]), .out_21(data_info_4[21]), .out_22(data_info_4[22]), .out_23(data_info_4[23]),
                            .out_24(data_info_4[24]), .out_25(data_info_4[25]), .out_26(data_info_4[26]), .out_27(data_info_4[27]), .out_28(data_info_4[28]), .out_29(data_info_4[29]),
                            .out_30(data_info_4[30]), .out_31(data_info_4[31]), .out_32(data_info_4[32]), .out_33(data_info_4[33]), .out_34(data_info_4[34]), .out_35(data_info_4[35]));

classifier_8 U5(.in(data[5]),.out_0(data_info_5[0]) ,  .out_1(data_info_5[1]) ,  .out_2(data_info_5[2]) ,  .out_3(data_info_5[3]) ,  .out_4(data_info_5[4]) ,  .out_5(data_info_5[5]),
                             .out_6(data_info_5[6]) ,  .out_7(data_info_5[7]) ,  .out_8(data_info_5[8]) ,  .out_9(data_info_5[9]),  .out_10(data_info_5[10]), .out_11(data_info_5[11]),
                            .out_12(data_info_5[12]), .out_13(data_info_5[13]), .out_14(data_info_5[14]), .out_15(data_info_5[15]), .out_16(data_info_5[16]), .out_17(data_info_5[17]),
                            .out_18(data_info_5[18]), .out_19(data_info_5[19]), .out_20(data_info_5[20]), .out_21(data_info_5[21]), .out_22(data_info_5[22]), .out_23(data_info_5[23]),
                            .out_24(data_info_5[24]), .out_25(data_info_5[25]), .out_26(data_info_5[26]), .out_27(data_info_5[27]), .out_28(data_info_5[28]), .out_29(data_info_5[29]),
                            .out_30(data_info_5[30]), .out_31(data_info_5[31]), .out_32(data_info_5[32]), .out_33(data_info_5[33]), .out_34(data_info_5[34]), .out_35(data_info_5[35]));

classifier_8 U6(.in(data[6]),.out_0(data_info_6[0]) ,  .out_1(data_info_6[1]) ,  .out_2(data_info_6[2]) ,  .out_3(data_info_6[3]) ,  .out_4(data_info_6[4]) ,  .out_5(data_info_6[5]),
                             .out_6(data_info_6[6]) ,  .out_7(data_info_6[7]) ,  .out_8(data_info_6[8]) ,  .out_9(data_info_6[9]),  .out_10(data_info_6[10]), .out_11(data_info_6[11]),
                            .out_12(data_info_6[12]), .out_13(data_info_6[13]), .out_14(data_info_6[14]), .out_15(data_info_6[15]), .out_16(data_info_6[16]), .out_17(data_info_6[17]),
                            .out_18(data_info_6[18]), .out_19(data_info_6[19]), .out_20(data_info_6[20]), .out_21(data_info_6[21]), .out_22(data_info_6[22]), .out_23(data_info_6[23]),
                            .out_24(data_info_6[24]), .out_25(data_info_6[25]), .out_26(data_info_6[26]), .out_27(data_info_6[27]), .out_28(data_info_6[28]), .out_29(data_info_6[29]),
                            .out_30(data_info_6[30]), .out_31(data_info_6[31]), .out_32(data_info_6[32]), .out_33(data_info_6[33]), .out_34(data_info_6[34]), .out_35(data_info_6[35]));

classifier_8 U7(.in(data[7]),.out_0(data_info_7[0]) ,  .out_1(data_info_7[1]) ,  .out_2(data_info_7[2]) ,  .out_3(data_info_7[3]) ,  .out_4(data_info_7[4]) ,  .out_5(data_info_7[5]),
                             .out_6(data_info_7[6]) ,  .out_7(data_info_7[7]) ,  .out_8(data_info_7[8]) ,  .out_9(data_info_7[9]),  .out_10(data_info_7[10]), .out_11(data_info_7[11]),
                            .out_12(data_info_7[12]), .out_13(data_info_7[13]), .out_14(data_info_7[14]), .out_15(data_info_7[15]), .out_16(data_info_7[16]), .out_17(data_info_7[17]),
                            .out_18(data_info_7[18]), .out_19(data_info_7[19]), .out_20(data_info_7[20]), .out_21(data_info_7[21]), .out_22(data_info_7[22]), .out_23(data_info_7[23]),
                            .out_24(data_info_7[24]), .out_25(data_info_7[25]), .out_26(data_info_7[26]), .out_27(data_info_7[27]), .out_28(data_info_7[28]), .out_29(data_info_7[29]),
                            .out_30(data_info_7[30]), .out_31(data_info_7[31]), .out_32(data_info_7[32]), .out_33(data_info_7[33]), .out_34(data_info_7[34]), .out_35(data_info_7[35]));

classifier_8 U8(.in(data[8]),.out_0(data_info_8[0]) ,  .out_1(data_info_8[1]) ,  .out_2(data_info_8[2]) ,  .out_3(data_info_8[3]) ,  .out_4(data_info_8[4]) ,  .out_5(data_info_8[5]),
                             .out_6(data_info_8[6]) ,  .out_7(data_info_8[7]) ,  .out_8(data_info_8[8]) ,  .out_9(data_info_8[9]),  .out_10(data_info_8[10]), .out_11(data_info_8[11]),
                            .out_12(data_info_8[12]), .out_13(data_info_8[13]), .out_14(data_info_8[14]), .out_15(data_info_8[15]), .out_16(data_info_8[16]), .out_17(data_info_8[17]),
                            .out_18(data_info_8[18]), .out_19(data_info_8[19]), .out_20(data_info_8[20]), .out_21(data_info_8[21]), .out_22(data_info_8[22]), .out_23(data_info_8[23]),
                            .out_24(data_info_8[24]), .out_25(data_info_8[25]), .out_26(data_info_8[26]), .out_27(data_info_8[27]), .out_28(data_info_8[28]), .out_29(data_info_8[29]),
                            .out_30(data_info_8[30]), .out_31(data_info_8[31]), .out_32(data_info_8[32]), .out_33(data_info_8[33]), .out_34(data_info_8[34]), .out_35(data_info_8[35]));

classifier_8 U9(.in(data[9]),.out_0(data_info_9[0]) ,  .out_1(data_info_9[1]) ,  .out_2(data_info_9[2]) ,  .out_3(data_info_9[3]) ,  .out_4(data_info_9[4]) ,  .out_5(data_info_9[5]),
                             .out_6(data_info_9[6]) ,  .out_7(data_info_9[7]) ,  .out_8(data_info_9[8]) ,  .out_9(data_info_9[9]),  .out_10(data_info_9[10]), .out_11(data_info_9[11]),
                            .out_12(data_info_9[12]), .out_13(data_info_9[13]), .out_14(data_info_9[14]), .out_15(data_info_9[15]), .out_16(data_info_9[16]), .out_17(data_info_9[17]),
                            .out_18(data_info_9[18]), .out_19(data_info_9[19]), .out_20(data_info_9[20]), .out_21(data_info_9[21]), .out_22(data_info_9[22]), .out_23(data_info_9[23]),
                            .out_24(data_info_9[24]), .out_25(data_info_9[25]), .out_26(data_info_9[26]), .out_27(data_info_9[27]), .out_28(data_info_9[28]), .out_29(data_info_9[29]),
                            .out_30(data_info_9[30]), .out_31(data_info_9[31]), .out_32(data_info_9[32]), .out_33(data_info_9[33]), .out_34(data_info_9[34]), .out_35(data_info_9[35]));

classifier_8 U10(.in(data[10]),.out_0(data_info_10[0]) ,  .out_1(data_info_10[1]) ,  .out_2(data_info_10[2]) ,  .out_3(data_info_10[3]) ,  .out_4(data_info_10[4]) ,  .out_5(data_info_10[5]),
                             .out_6(data_info_10[6]) ,  .out_7(data_info_10[7]) ,  .out_8(data_info_10[8]) ,  .out_9(data_info_10[9]),  .out_10(data_info_10[10]), .out_11(data_info_10[11]),
                            .out_12(data_info_10[12]), .out_13(data_info_10[13]), .out_14(data_info_10[14]), .out_15(data_info_10[15]), .out_16(data_info_10[16]), .out_17(data_info_10[17]),
                            .out_18(data_info_10[18]), .out_19(data_info_10[19]), .out_20(data_info_10[20]), .out_21(data_info_10[21]), .out_22(data_info_10[22]), .out_23(data_info_10[23]),
                            .out_24(data_info_10[24]), .out_25(data_info_10[25]), .out_26(data_info_10[26]), .out_27(data_info_10[27]), .out_28(data_info_10[28]), .out_29(data_info_10[29]),
                            .out_30(data_info_10[30]), .out_31(data_info_10[31]), .out_32(data_info_10[32]), .out_33(data_info_10[33]), .out_34(data_info_10[34]), .out_35(data_info_10[35]));

classifier_8 U11(.in(data[11]),.out_0(data_info_11[0]) ,  .out_1(data_info_11[1]) ,  .out_2(data_info_11[2]) ,  .out_3(data_info_11[3]) ,  .out_4(data_info_11[4]) ,  .out_5(data_info_11[5]),
                             .out_6(data_info_11[6]) ,  .out_7(data_info_11[7]) ,  .out_8(data_info_11[8]) ,  .out_9(data_info_11[9]),  .out_10(data_info_11[10]), .out_11(data_info_11[11]),
                            .out_12(data_info_11[12]), .out_13(data_info_11[13]), .out_14(data_info_11[14]), .out_15(data_info_11[15]), .out_16(data_info_11[16]), .out_17(data_info_11[17]),
                            .out_18(data_info_11[18]), .out_19(data_info_11[19]), .out_20(data_info_11[20]), .out_21(data_info_11[21]), .out_22(data_info_11[22]), .out_23(data_info_11[23]),
                            .out_24(data_info_11[24]), .out_25(data_info_11[25]), .out_26(data_info_11[26]), .out_27(data_info_11[27]), .out_28(data_info_11[28]), .out_29(data_info_11[29]),
                            .out_30(data_info_11[30]), .out_31(data_info_11[31]), .out_32(data_info_11[32]), .out_33(data_info_11[33]), .out_34(data_info_11[34]), .out_35(data_info_11[35]));

classifier_8 U12(.in(data[12]),.out_0(data_info_12[0]) ,  .out_1(data_info_12[1]) ,  .out_2(data_info_12[2]) ,  .out_3(data_info_12[3]) ,  .out_4(data_info_12[4]) ,  .out_5(data_info_12[5]),
                             .out_6(data_info_12[6]) ,  .out_7(data_info_12[7]) ,  .out_8(data_info_12[8]) ,  .out_9(data_info_12[9]),  .out_10(data_info_12[10]), .out_11(data_info_12[11]),
                            .out_12(data_info_12[12]), .out_13(data_info_12[13]), .out_14(data_info_12[14]), .out_15(data_info_12[15]), .out_16(data_info_12[16]), .out_17(data_info_12[17]),
                            .out_18(data_info_12[18]), .out_19(data_info_12[19]), .out_20(data_info_12[20]), .out_21(data_info_12[21]), .out_22(data_info_12[22]), .out_23(data_info_12[23]),
                            .out_24(data_info_12[24]), .out_25(data_info_12[25]), .out_26(data_info_12[26]), .out_27(data_info_12[27]), .out_28(data_info_12[28]), .out_29(data_info_12[29]),
                            .out_30(data_info_12[30]), .out_31(data_info_12[31]), .out_32(data_info_12[32]), .out_33(data_info_12[33]), .out_34(data_info_12[34]), .out_35(data_info_12[35]));

classifier_8 U13(.in(data[13]),.out_0(data_info_13[0]) ,  .out_1(data_info_13[1]) ,  .out_2(data_info_13[2]) ,  .out_3(data_info_13[3]) ,  .out_4(data_info_13[4]) ,  .out_5(data_info_13[5]),
                             .out_6(data_info_13[6]) ,  .out_7(data_info_13[7]) ,  .out_8(data_info_13[8]) ,  .out_9(data_info_13[9]),  .out_10(data_info_13[10]), .out_11(data_info_13[11]),
                            .out_12(data_info_13[12]), .out_13(data_info_13[13]), .out_14(data_info_13[14]), .out_15(data_info_13[15]), .out_16(data_info_13[16]), .out_17(data_info_13[17]),
                            .out_18(data_info_13[18]), .out_19(data_info_13[19]), .out_20(data_info_13[20]), .out_21(data_info_13[21]), .out_22(data_info_13[22]), .out_23(data_info_13[23]),
                            .out_24(data_info_13[24]), .out_25(data_info_13[25]), .out_26(data_info_13[26]), .out_27(data_info_13[27]), .out_28(data_info_13[28]), .out_29(data_info_13[29]),
                            .out_30(data_info_13[30]), .out_31(data_info_13[31]), .out_32(data_info_13[32]), .out_33(data_info_13[33]), .out_34(data_info_13[34]), .out_35(data_info_13[35]));

classifier_8 U14(.in(data[14]),.out_0(data_info_14[0]) ,  .out_1(data_info_14[1]) ,  .out_2(data_info_14[2]) ,  .out_3(data_info_14[3]) ,  .out_4(data_info_14[4]) ,  .out_5(data_info_14[5]),
                             .out_6(data_info_14[6]) ,  .out_7(data_info_14[7]) ,  .out_8(data_info_14[8]) ,  .out_9(data_info_14[9]),  .out_10(data_info_14[10]), .out_11(data_info_14[11]),
                            .out_12(data_info_14[12]), .out_13(data_info_14[13]), .out_14(data_info_14[14]), .out_15(data_info_14[15]), .out_16(data_info_14[16]), .out_17(data_info_14[17]),
                            .out_18(data_info_14[18]), .out_19(data_info_14[19]), .out_20(data_info_14[20]), .out_21(data_info_14[21]), .out_22(data_info_14[22]), .out_23(data_info_14[23]),
                            .out_24(data_info_14[24]), .out_25(data_info_14[25]), .out_26(data_info_14[26]), .out_27(data_info_14[27]), .out_28(data_info_14[28]), .out_29(data_info_14[29]),
                            .out_30(data_info_14[30]), .out_31(data_info_14[31]), .out_32(data_info_14[32]), .out_33(data_info_14[33]), .out_34(data_info_14[34]), .out_35(data_info_14[35]));

classifier_8 U15(.in(data[15]),.out_0(data_info_15[0]) ,  .out_1(data_info_15[1]) ,  .out_2(data_info_15[2]) ,  .out_3(data_info_15[3]) ,  .out_4(data_info_15[4]) ,  .out_5(data_info_15[5]),
                             .out_6(data_info_15[6]) ,  .out_7(data_info_15[7]) ,  .out_8(data_info_15[8]) ,  .out_9(data_info_15[9]),  .out_10(data_info_15[10]), .out_11(data_info_15[11]),
                            .out_12(data_info_15[12]), .out_13(data_info_15[13]), .out_14(data_info_15[14]), .out_15(data_info_15[15]), .out_16(data_info_15[16]), .out_17(data_info_15[17]),
                            .out_18(data_info_15[18]), .out_19(data_info_15[19]), .out_20(data_info_15[20]), .out_21(data_info_15[21]), .out_22(data_info_15[22]), .out_23(data_info_15[23]),
                            .out_24(data_info_15[24]), .out_25(data_info_15[25]), .out_26(data_info_15[26]), .out_27(data_info_15[27]), .out_28(data_info_15[28]), .out_29(data_info_15[29]),
                            .out_30(data_info_15[30]), .out_31(data_info_15[31]), .out_32(data_info_15[32]), .out_33(data_info_15[33]), .out_34(data_info_15[34]), .out_35(data_info_15[35]));

assign data_temp[0]= data_info_0[0] + data_info_1[0] + data_info_2[0] + data_info_3[0] + data_info_4[0] + data_info_5[0] + data_info_6[0] + data_info_7[0] + data_info_8[0] + data_info_9[0] + data_info_10[0] + data_info_11[0] + data_info_12[0] + data_info_13[0] + data_info_14[0] + data_info_15[0];
assign data_temp[1]= data_info_0[1] + data_info_1[1] + data_info_2[1] + data_info_3[1] + data_info_4[1] + data_info_5[1] + data_info_6[1] + data_info_7[1] + data_info_8[1] + data_info_9[1] + data_info_10[1] + data_info_11[1] + data_info_12[1] + data_info_13[1] + data_info_14[1] + data_info_15[1];
assign data_temp[2]= data_info_0[2] + data_info_1[2] + data_info_2[2] + data_info_3[2] + data_info_4[2] + data_info_5[2] + data_info_6[2] + data_info_7[2] + data_info_8[2] + data_info_9[2] + data_info_10[2] + data_info_11[2] + data_info_12[2] + data_info_13[2] + data_info_14[2] + data_info_15[2];
assign data_temp[3]= data_info_0[3] + data_info_1[3] + data_info_2[3] + data_info_3[3] + data_info_4[3] + data_info_5[3] + data_info_6[3] + data_info_7[3] + data_info_8[3] + data_info_9[3] + data_info_10[3] + data_info_11[3] + data_info_12[3] + data_info_13[3] + data_info_14[3] + data_info_15[3];
assign data_temp[4]= data_info_0[4] + data_info_1[4] + data_info_2[4] + data_info_3[4] + data_info_4[4] + data_info_5[4] + data_info_6[4] + data_info_7[4] + data_info_8[4] + data_info_9[4] + data_info_10[4] + data_info_11[4] + data_info_12[4] + data_info_13[4] + data_info_14[4] + data_info_15[4];
assign data_temp[5]= data_info_0[5] + data_info_1[5] + data_info_2[5] + data_info_3[5] + data_info_4[5] + data_info_5[5] + data_info_6[5] + data_info_7[5] + data_info_8[5] + data_info_9[5] + data_info_10[5] + data_info_11[5] + data_info_12[5] + data_info_13[5] + data_info_14[5] + data_info_15[5];
assign data_temp[6]= data_info_0[6] + data_info_1[6] + data_info_2[6] + data_info_3[6] + data_info_4[6] + data_info_5[6] + data_info_6[6] + data_info_7[6] + data_info_8[6] + data_info_9[6] + data_info_10[6] + data_info_11[6] + data_info_12[6] + data_info_13[6] + data_info_14[6] + data_info_15[6];
assign data_temp[7]= data_info_0[7] + data_info_1[7] + data_info_2[7] + data_info_3[7] + data_info_4[7] + data_info_5[7] + data_info_6[7] + data_info_7[7] + data_info_8[7] + data_info_9[7] + data_info_10[7] + data_info_11[7] + data_info_12[7] + data_info_13[7] + data_info_14[7] + data_info_15[7];
assign data_temp[8]= data_info_0[8] + data_info_1[8] + data_info_2[8] + data_info_3[8] + data_info_4[8] + data_info_5[8] + data_info_6[8] + data_info_7[8] + data_info_8[8] + data_info_9[8] + data_info_10[8] + data_info_11[8] + data_info_12[8] + data_info_13[8] + data_info_14[8] + data_info_15[8];
assign data_temp[9]= data_info_0[9] + data_info_1[9] + data_info_2[9] + data_info_3[9] + data_info_4[9] + data_info_5[9] + data_info_6[9] + data_info_7[9] + data_info_8[9] + data_info_9[9] + data_info_10[9] + data_info_11[9] + data_info_12[9] + data_info_13[9] + data_info_14[9] + data_info_15[9];
assign data_temp[10] = data_info_0[10] + data_info_1[10] + data_info_2[10] + data_info_3[10] + data_info_4[10] + data_info_5[10] + data_info_6[10] + data_info_7[10] + data_info_8[10] + data_info_9[10] + data_info_10[10] + data_info_11[10] + data_info_12[10] + data_info_13[10] + data_info_14[10] + data_info_15[10];
assign data_temp[11] = data_info_0[11] + data_info_1[11] + data_info_2[11] + data_info_3[11] + data_info_4[11] + data_info_5[11] + data_info_6[11] + data_info_7[11] + data_info_8[11] + data_info_9[11] + data_info_10[11] + data_info_11[11] + data_info_12[11] + data_info_13[11] + data_info_14[11] + data_info_15[11];
assign data_temp[12] = data_info_0[12] + data_info_1[12] + data_info_2[12] + data_info_3[12] + data_info_4[12] + data_info_5[12] + data_info_6[12] + data_info_7[12] + data_info_8[12] + data_info_9[12] + data_info_10[12] + data_info_11[12] + data_info_12[12] + data_info_13[12] + data_info_14[12] + data_info_15[12];
assign data_temp[13] = data_info_0[13] + data_info_1[13] + data_info_2[13] + data_info_3[13] + data_info_4[13] + data_info_5[13] + data_info_6[13] + data_info_7[13] + data_info_8[13] + data_info_9[13] + data_info_10[13] + data_info_11[13] + data_info_12[13] + data_info_13[13] + data_info_14[13] + data_info_15[13];
assign data_temp[14] = data_info_0[14] + data_info_1[14] + data_info_2[14] + data_info_3[14] + data_info_4[14] + data_info_5[14] + data_info_6[14] + data_info_7[14] + data_info_8[14] + data_info_9[14] + data_info_10[14] + data_info_11[14] + data_info_12[14] + data_info_13[14] + data_info_14[14] + data_info_15[14];
assign data_temp[15] = data_info_0[15] + data_info_1[15] + data_info_2[15] + data_info_3[15] + data_info_4[15] + data_info_5[15] + data_info_6[15] + data_info_7[15] + data_info_8[15] + data_info_9[15] + data_info_10[15] + data_info_11[15] + data_info_12[15] + data_info_13[15] + data_info_14[15] + data_info_15[15];
assign data_temp[16] = data_info_0[16] + data_info_1[16] + data_info_2[16] + data_info_3[16] + data_info_4[16] + data_info_5[16] + data_info_6[16] + data_info_7[16] + data_info_8[16] + data_info_9[16] + data_info_10[16] + data_info_11[16] + data_info_12[16] + data_info_13[16] + data_info_14[16] + data_info_15[16];
assign data_temp[17] = data_info_0[17] + data_info_1[17] + data_info_2[17] + data_info_3[17] + data_info_4[17] + data_info_5[17] + data_info_6[17] + data_info_7[17] + data_info_8[17] + data_info_9[17] + data_info_10[17] + data_info_11[17] + data_info_12[17] + data_info_13[17] + data_info_14[17] + data_info_15[17];
assign data_temp[18] = data_info_0[18] + data_info_1[18] + data_info_2[18] + data_info_3[18] + data_info_4[18] + data_info_5[18] + data_info_6[18] + data_info_7[18] + data_info_8[18] + data_info_9[18] + data_info_10[18] + data_info_11[18] + data_info_12[18] + data_info_13[18] + data_info_14[18] + data_info_15[18];
assign data_temp[19] = data_info_0[19] + data_info_1[19] + data_info_2[19] + data_info_3[19] + data_info_4[19] + data_info_5[19] + data_info_6[19] + data_info_7[19] + data_info_8[19] + data_info_9[19] + data_info_10[19] + data_info_11[19] + data_info_12[19] + data_info_13[19] + data_info_14[19] + data_info_15[19];
assign data_temp[20] = data_info_0[20] + data_info_1[20] + data_info_2[20] + data_info_3[20] + data_info_4[20] + data_info_5[20] + data_info_6[20] + data_info_7[20] + data_info_8[20] + data_info_9[20] + data_info_10[20] + data_info_11[20] + data_info_12[20] + data_info_13[20] + data_info_14[20] + data_info_15[20];
assign data_temp[21] = data_info_0[21] + data_info_1[21] + data_info_2[21] + data_info_3[21] + data_info_4[21] + data_info_5[21] + data_info_6[21] + data_info_7[21] + data_info_8[21] + data_info_9[21] + data_info_10[21] + data_info_11[21] + data_info_12[21] + data_info_13[21] + data_info_14[21] + data_info_15[21];
assign data_temp[22] = data_info_0[22] + data_info_1[22] + data_info_2[22] + data_info_3[22] + data_info_4[22] + data_info_5[22] + data_info_6[22] + data_info_7[22] + data_info_8[22] + data_info_9[22] + data_info_10[22] + data_info_11[22] + data_info_12[22] + data_info_13[22] + data_info_14[22] + data_info_15[22];
assign data_temp[23] = data_info_0[23] + data_info_1[23] + data_info_2[23] + data_info_3[23] + data_info_4[23] + data_info_5[23] + data_info_6[23] + data_info_7[23] + data_info_8[23] + data_info_9[23] + data_info_10[23] + data_info_11[23] + data_info_12[23] + data_info_13[23] + data_info_14[23] + data_info_15[23];
assign data_temp[24] = data_info_0[24] + data_info_1[24] + data_info_2[24] + data_info_3[24] + data_info_4[24] + data_info_5[24] + data_info_6[24] + data_info_7[24] + data_info_8[24] + data_info_9[24] + data_info_10[24] + data_info_11[24] + data_info_12[24] + data_info_13[24] + data_info_14[24] + data_info_15[24];
assign data_temp[25] = data_info_0[25] + data_info_1[25] + data_info_2[25] + data_info_3[25] + data_info_4[25] + data_info_5[25] + data_info_6[25] + data_info_7[25] + data_info_8[25] + data_info_9[25] + data_info_10[25] + data_info_11[25] + data_info_12[25] + data_info_13[25] + data_info_14[25] + data_info_15[25];
assign data_temp[26] = data_info_0[26] + data_info_1[26] + data_info_2[26] + data_info_3[26] + data_info_4[26] + data_info_5[26] + data_info_6[26] + data_info_7[26] + data_info_8[26] + data_info_9[26] + data_info_10[26] + data_info_11[26] + data_info_12[26] + data_info_13[26] + data_info_14[26] + data_info_15[26];
assign data_temp[27] = data_info_0[27] + data_info_1[27] + data_info_2[27] + data_info_3[27] + data_info_4[27] + data_info_5[27] + data_info_6[27] + data_info_7[27] + data_info_8[27] + data_info_9[27] + data_info_10[27] + data_info_11[27] + data_info_12[27] + data_info_13[27] + data_info_14[27] + data_info_15[27];
assign data_temp[28] = data_info_0[28] + data_info_1[28] + data_info_2[28] + data_info_3[28] + data_info_4[28] + data_info_5[28] + data_info_6[28] + data_info_7[28] + data_info_8[28] + data_info_9[28] + data_info_10[28] + data_info_11[28] + data_info_12[28] + data_info_13[28] + data_info_14[28] + data_info_15[28];
assign data_temp[29] = data_info_0[29] + data_info_1[29] + data_info_2[29] + data_info_3[29] + data_info_4[29] + data_info_5[29] + data_info_6[29] + data_info_7[29] + data_info_8[29] + data_info_9[29] + data_info_10[29] + data_info_11[29] + data_info_12[29] + data_info_13[29] + data_info_14[29] + data_info_15[29];
assign data_temp[30] = data_info_0[30] + data_info_1[30] + data_info_2[30] + data_info_3[30] + data_info_4[30] + data_info_5[30] + data_info_6[30] + data_info_7[30] + data_info_8[30] + data_info_9[30] + data_info_10[30] + data_info_11[30] + data_info_12[30] + data_info_13[30] + data_info_14[30] + data_info_15[30];
assign data_temp[31] = data_info_0[31] + data_info_1[31] + data_info_2[31] + data_info_3[31] + data_info_4[31] + data_info_5[31] + data_info_6[31] + data_info_7[31] + data_info_8[31] + data_info_9[31] + data_info_10[31] + data_info_11[31] + data_info_12[31] + data_info_13[31] + data_info_14[31] + data_info_15[31];
assign data_temp[32] = data_info_0[32] + data_info_1[32] + data_info_2[32] + data_info_3[32] + data_info_4[32] + data_info_5[32] + data_info_6[32] + data_info_7[32] + data_info_8[32] + data_info_9[32] + data_info_10[32] + data_info_11[32] + data_info_12[32] + data_info_13[32] + data_info_14[32] + data_info_15[32];
assign data_temp[33] = data_info_0[33] + data_info_1[33] + data_info_2[33] + data_info_3[33] + data_info_4[33] + data_info_5[33] + data_info_6[33] + data_info_7[33] + data_info_8[33] + data_info_9[33] + data_info_10[33] + data_info_11[33] + data_info_12[33] + data_info_13[33] + data_info_14[33] + data_info_15[33];
assign data_temp[34] = data_info_0[34] + data_info_1[34] + data_info_2[34] + data_info_3[34] + data_info_4[34] + data_info_5[34] + data_info_6[34] + data_info_7[34] + data_info_8[34] + data_info_9[34] + data_info_10[34] + data_info_11[34] + data_info_12[34] + data_info_13[34] + data_info_14[34] + data_info_15[34];
assign data_temp[35] = data_info_0[35] + data_info_1[35] + data_info_2[35] + data_info_3[35] + data_info_4[35] + data_info_5[35] + data_info_6[35] + data_info_7[35] + data_info_8[35] + data_info_9[35] + data_info_10[35] + data_info_11[35] + data_info_12[35] + data_info_13[35] + data_info_14[35] + data_info_15[35];

always @(posedge clk) begin
    data_temp_reg[0] <= data_temp[0];
    data_temp_reg[1] <= data_temp[1];
    data_temp_reg[2] <= data_temp[2];
    data_temp_reg[3] <= data_temp[3];
    data_temp_reg[4] <= data_temp[4];
    data_temp_reg[5] <= data_temp[5];
    data_temp_reg[6] <= data_temp[6];
    data_temp_reg[7] <= data_temp[7];
    data_temp_reg[8] <= data_temp[8];
    data_temp_reg[9] <= data_temp[9];
    data_temp_reg[10] <= data_temp[10];
    data_temp_reg[11] <= data_temp[11];
    data_temp_reg[12] <= data_temp[12];
    data_temp_reg[13] <= data_temp[13];
    data_temp_reg[14] <= data_temp[14];
    data_temp_reg[15] <= data_temp[15];
    data_temp_reg[16] <= data_temp[16];
    data_temp_reg[17] <= data_temp[17];
    data_temp_reg[18] <= data_temp[18];
    data_temp_reg[19] <= data_temp[19];
    data_temp_reg[20] <= data_temp[20];
    data_temp_reg[21] <= data_temp[21];
    data_temp_reg[22] <= data_temp[22];
    data_temp_reg[23] <= data_temp[23];
    data_temp_reg[24] <= data_temp[24];
    data_temp_reg[25] <= data_temp[25];
    data_temp_reg[26] <= data_temp[26];
    data_temp_reg[27] <= data_temp[27];
    data_temp_reg[28] <= data_temp[28];
    data_temp_reg[29] <= data_temp[29];
    data_temp_reg[30] <= data_temp[30];
    data_temp_reg[31] <= data_temp[31];
    data_temp_reg[32] <= data_temp[32];
    data_temp_reg[33] <= data_temp[33];
    data_temp_reg[34] <= data_temp[34];
    data_temp_reg[35] <= data_temp[35];
end
assign out_0 = data_temp_reg[0];
assign out_1 = data_temp_reg[1];
assign out_2 = data_temp_reg[2];
assign out_3 = data_temp_reg[3];
assign out_4 = data_temp_reg[4];
assign out_5 = data_temp_reg[5];
assign out_6 = data_temp_reg[6];
assign out_7 = data_temp_reg[7];
assign out_8 = data_temp_reg[8];
assign out_9 = data_temp_reg[9];
assign out_10 = data_temp_reg[10];
assign out_11 = data_temp_reg[11];
assign out_12 = data_temp_reg[12];
assign out_13 = data_temp_reg[13];
assign out_14 = data_temp_reg[14];
assign out_15 = data_temp_reg[15];
assign out_16 = data_temp_reg[16];
assign out_17 = data_temp_reg[17];
assign out_18 = data_temp_reg[18];
assign out_19 = data_temp_reg[19];
assign out_20 = data_temp_reg[20];
assign out_21 = data_temp_reg[21];
assign out_22 = data_temp_reg[22];
assign out_23 = data_temp_reg[23];
assign out_24 = data_temp_reg[24];
assign out_25 = data_temp_reg[25];
assign out_26 = data_temp_reg[26];
assign out_27 = data_temp_reg[27];
assign out_28 = data_temp_reg[28];
assign out_29 = data_temp_reg[29];
assign out_30 = data_temp_reg[30];
assign out_31 = data_temp_reg[31];
assign out_32 = data_temp_reg[32];
assign out_33 = data_temp_reg[33];
assign out_34 = data_temp_reg[34];
assign out_35 = data_temp_reg[35];
endmodule

module classifier_8(in, out_0, out_1, out_2, out_3, out_4, out_5,
                        out_6, out_7, out_8, out_9, out_10, out_11,
                        out_12, out_13, out_14, out_15, out_16, out_17,
                        out_18, out_19, out_20, out_21, out_22, out_23,
                        out_24, out_25, out_26, out_27, out_28, out_29,
                        out_30, out_31, out_32, out_33, out_34, out_35);
input   [7:0]   in;
output          out_0; 
output          out_1; 
output          out_2; 
output          out_3; 
output          out_4; 
output          out_5;
output          out_6; 
output          out_7; 
output          out_8; 
output          out_9; 
output          out_10; 
output          out_11;
output          out_12; 
output          out_13; 
output          out_14; 
output          out_15; 
output          out_16; 
output          out_17;
output          out_18; 
output          out_19; 
output          out_20; 
output          out_21; 
output          out_22; 
output          out_23;
output          out_24; 
output          out_25; 
output          out_26; 
output          out_27; 
output          out_28; 
output          out_29;
output          out_30; 
output          out_31; 
output          out_32; 
output          out_33; 
output          out_34; 
output          out_35;
reg             temp    [0:35]; 

always @(*) begin
    temp[0] = 0;
    if(in == 'd1)begin
        temp[0] = 1'b1;
    end
end
always @(*) begin
    temp[1] = 0;
    temp[2] = 0;
    if(in >= 'd2 && in < 'd4)begin
        temp[1] = (in[0])? 1'b1: 1'b0;
        temp[2] = (in[1])? 1'b1: 1'b0;
    end
end
always @(*) begin
    temp[3] = 0;
    temp[4] = 0;
    temp[5] = 0;
    if(in >= 'd4 && in < 'd8)begin
        temp[3] = (in[0])? 1'b1: 1'b0;
        temp[4] = (in[1])? 1'b1: 1'b0;
        temp[5] = (in[2])? 1'b1: 1'b0;
    end
end
always @(*) begin
    temp[6] = 0;
    temp[7] = 0;
    temp[8] = 0;
    temp[9] = 0;
    if(in >= 'd8 && in < 'd16)begin
        temp[6] = (in[0])? 1'b1: 1'b0;
        temp[7] = (in[1])? 1'b1: 1'b0;
        temp[8] = (in[2])? 1'b1: 1'b0;
        temp[9] = (in[3])? 1'b1: 1'b0;
    end
end
always @(*) begin
    temp[10] = 0;
    temp[11] = 0;
    temp[12] = 0;
    temp[13] = 0;
    temp[14] = 0;
    if(in >= 'd16 && in < 'd32)begin
        temp[10] = (in[0])? 1'b1: 1'b0;
        temp[11] = (in[1])? 1'b1: 1'b0;
        temp[12] = (in[2])? 1'b1: 1'b0;
        temp[13] = (in[3])? 1'b1: 1'b0;
        temp[14] = (in[4])? 1'b1: 1'b0;
    end
end
always @(*) begin
    temp[15] = 0;
    temp[16] = 0;
    temp[17] = 0;
    temp[18] = 0;
    temp[19] = 0;
    temp[20] = 0;
    if(in >= 'd32 && in < 'd64)begin
        temp[15] = (in[0])? 1'b1: 1'b0;
        temp[16] = (in[1])? 1'b1: 1'b0;
        temp[17] = (in[2])? 1'b1: 1'b0;
        temp[18] = (in[3])? 1'b1: 1'b0;
        temp[19] = (in[4])? 1'b1: 1'b0;
        temp[20] = (in[5])? 1'b1: 1'b0;
    end
end
always @(*) begin
    temp[21] = 0;
    temp[22] = 0;
    temp[23] = 0;
    temp[24] = 0;
    temp[25] = 0;
    temp[26] = 0;
    temp[27] = 0;
    if(in >= 'd64 && in < 'd128)begin
        temp[21] = (in[0])? 1'b1: 1'b0;
        temp[22] = (in[1])? 1'b1: 1'b0;
        temp[23] = (in[2])? 1'b1: 1'b0;
        temp[24] = (in[3])? 1'b1: 1'b0;
        temp[25] = (in[4])? 1'b1: 1'b0;
        temp[26] = (in[5])? 1'b1: 1'b0;
        temp[27] = (in[6])? 1'b1: 1'b0;
    end
end
always @(*) begin
    temp[28] = 0;
    temp[29] = 0;
    temp[30] = 0;
    temp[31] = 0;
    temp[32] = 0;
    temp[33] = 0;
    temp[34] = 0;
    temp[35] = 0;
    if(in >= 'd128 && in < 'd256)begin
        temp[28] = (in[0])? 1'b1: 1'b0;
        temp[29] = (in[1])? 1'b1: 1'b0;
        temp[30] = (in[2])? 1'b1: 1'b0;
        temp[31] = (in[3])? 1'b1: 1'b0;
        temp[32] = (in[4])? 1'b1: 1'b0;
        temp[33] = (in[5])? 1'b1: 1'b0;
        temp[34] = (in[6])? 1'b1: 1'b0;
        temp[35] = (in[7])? 1'b1: 1'b0;
    end
end
assign out_0  = temp[0];
assign out_1  = temp[1];
assign out_2  = temp[2];
assign out_3  = temp[3];
assign out_4  = temp[4];
assign out_5  = temp[5];
assign out_6  = temp[6];
assign out_7  = temp[7];
assign out_8  = temp[8];
assign out_9  = temp[9];
assign out_10 = temp[10];
assign out_11 = temp[11];
assign out_12 = temp[12];
assign out_13 = temp[13];
assign out_14 = temp[14];
assign out_15 = temp[15];
assign out_16 = temp[16];
assign out_17 = temp[17];
assign out_18 = temp[18];
assign out_19 = temp[19];
assign out_20 = temp[20];
assign out_21 = temp[21];
assign out_22 = temp[22];
assign out_23 = temp[23];
assign out_24 = temp[24];
assign out_25 = temp[25];
assign out_26 = temp[26];
assign out_27 = temp[27];
assign out_28 = temp[28];
assign out_29 = temp[29];
assign out_30 = temp[30];
assign out_31 = temp[31];
assign out_32 = temp[32];
assign out_33 = temp[33];
assign out_34 = temp[34];
assign out_35 = temp[35];
endmodule

module focus_diff(clk, in0, in1, in2, in3, in4, in5, out_22, out_44, out_66);
input           clk;
input   [7:0]   in0;
input   [7:0]   in1;
input   [7:0]   in2;
input   [7:0]   in3;
input   [7:0]   in4;
input   [7:0]   in5;
output  [7:0]   out_22;
output  [9:0]   out_44;
output  [10:0]   out_66;

// 2* 8 bit comparator
wire    [7:0]   sub_in_b    [0:4];
wire    [7:0]   sub_in_s    [0:4];
wire    [7:0]   ns_diff     [0:4];
reg     [7:0]   diff        [0:4];
wire    [7:0]   ns_out_22_temp;
wire    [9:0]   ns_out_44_temp;
wire    [10:0]  ns_out_66_temp;
reg     [7:0]   out_22_temp;
reg     [9:0]   out_44_temp;
reg     [10:0]  out_66_temp;

assign sub_in_b[0] = (in0 > in1)? in0: in1;
assign sub_in_s[0] = (in0 > in1)? in1: in0;
assign sub_in_b[1] = (in1 > in2)? in1: in2;
assign sub_in_s[1] = (in1 > in2)? in2: in1;
assign sub_in_b[2] = (in2 > in3)? in2: in3;
assign sub_in_s[2] = (in2 > in3)? in3: in2;
assign sub_in_b[3] = (in3 > in4)? in3: in4;
assign sub_in_s[3] = (in3 > in4)? in4: in3;
assign sub_in_b[4] = (in4 > in5)? in4: in5;
assign sub_in_s[4] = (in4 > in5)? in5: in4;
assign ns_diff[0] = sub_in_b[0] - sub_in_s[0];
assign ns_diff[1] = sub_in_b[1] - sub_in_s[1];
assign ns_diff[2] = sub_in_b[2] - sub_in_s[2];
assign ns_diff[3] = sub_in_b[3] - sub_in_s[3];
assign ns_diff[4] = sub_in_b[4] - sub_in_s[4];

always @(posedge clk) begin
    diff[0] <= ns_diff[0];
    diff[1] <= ns_diff[1];
    diff[2] <= ns_diff[2];
    diff[3] <= ns_diff[3];
    diff[4] <= ns_diff[4];
end
assign out_22 = diff[2];
assign out_44 = diff[1] + diff[2] + diff[3];
assign out_66 = diff[0] + out_44 + diff[4];
endmodule
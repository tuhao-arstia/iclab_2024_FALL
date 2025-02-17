module CLK_1_MODULE (
    clk,
    rst_n,
    in_valid,
	in_row,
    in_kernel,
    out_idle,
    handshake_sready,
    handshake_din,

    flag_handshake_to_clk1,
    flag_clk1_to_handshake,

	fifo_empty,
    fifo_rdata,
    fifo_rinc,
    out_valid,
    out_data,

    flag_clk1_to_fifo,
    flag_fifo_to_clk1
);
input clk;
input rst_n;
input in_valid;
input [17:0] in_row;
input [11:0] in_kernel;
input out_idle;
output reg handshake_sready;
output reg [29:0] handshake_din;
// You can use the the custom flag ports for your design
input  flag_handshake_to_clk1;
output flag_clk1_to_handshake;

// clk1 domain : fifo read
input fifo_empty;
input [7:0] fifo_rdata;
output fifo_rinc;
output reg out_valid;
output reg [7:0] out_data;
// You can use the the custom flag ports for your design
output flag_clk1_to_fifo;
input flag_fifo_to_clk1;

// DESIGN
integer i;
// handshake
localparam    IDLE = 2'b00;
localparam   INPUT = 2'b01;
localparam HS_WAIT = 2'b10;
localparam HS_IDLE = 2'b11;

reg [1:0]   cs, ns;
reg [3:0]   data_cnt, ns_data_cnt;
reg [29:0]  handshake_data  [0:5];

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cs <= IDLE;
    end else begin
        cs <= ns;
    end
end
always @(*) begin
    ns = cs;
    case (cs)
        IDLE:begin
            if(in_valid)begin
                ns = INPUT;
            end else begin
                ns = cs;
            end
        end
        INPUT:begin
            if(!in_valid)begin
                ns = HS_WAIT;
            end else begin
                ns = cs;
            end
        end
        HS_WAIT:begin
            if(out_idle)begin
                ns = HS_IDLE;
            end else begin
                ns = cs;
            end
        end
        HS_IDLE:begin
            if(out_idle)begin
                ns = cs;
            end else begin
                if(data_cnt == 'd5)begin
                    ns = IDLE;
                end else begin
                    ns = HS_WAIT;
                end
            end
        end
    endcase
end

always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        data_cnt <= 0;
    end else begin
        data_cnt <= ns_data_cnt;
    end
end
always @(*) begin
    case (cs)
        HS_WAIT:begin
            ns_data_cnt = data_cnt;
        end
        HS_IDLE:begin
            if(!out_idle)begin
                ns_data_cnt = data_cnt + 'd1;
            end else begin
                ns_data_cnt = data_cnt;
            end
        end
        default:begin
            ns_data_cnt = 0;
        end 
    endcase
end

// INPUT stage
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 6; i = i + 1)begin
            handshake_data[i] <= 0;
        end
    end else if(in_valid) begin
        handshake_data[0] <= handshake_data[1];
        handshake_data[1] <= handshake_data[2];
        handshake_data[2] <= handshake_data[3];
        handshake_data[3] <= handshake_data[4];
        handshake_data[4] <= handshake_data[5];
        handshake_data[5] <= {in_row, in_kernel};
    end
end
// handshake_sready: trigger sready
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        handshake_sready <= 0;
    end else if(cs == HS_IDLE)begin
        handshake_sready <= 1;
    end else begin
        handshake_sready <= 0;
    end
end
// handshake_din
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        handshake_din <= 0;
    end else if(cs == HS_WAIT && out_idle && data_cnt < 'd6)begin
        handshake_din <= handshake_data[data_cnt];
    end
end

// read from fifo
// output setting : fifo_rinc, out_valid, out_data
reg         out_valid_delay1, out_valid_delay2;

assign fifo_rinc = ~fifo_empty;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        out_valid_delay1 <= 0;
    end else if(~fifo_empty) begin
        out_valid_delay1 <= 1;
    end else begin
        out_valid_delay1 <= 0;
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        out_valid_delay2 <= 0;
    end else begin
        out_valid_delay2 <= out_valid_delay1;
    end
end
always @(*) begin
    if(out_valid_delay2)begin
        out_valid = 1;
        out_data = fifo_rdata;
    end else begin
        out_valid = 0;
        out_data = 0;
    end
end

endmodule






module CLK_2_MODULE (
    clk,
    rst_n,
    in_valid,
    fifo_full,
    in_data,
    out_valid,
    out_data,
    busy,

    flag_handshake_to_clk2,
    flag_clk2_to_handshake,

    flag_fifo_to_clk2,
    flag_clk2_to_fifo
);

input clk;
input rst_n;
input in_valid;
input fifo_full;
input [29:0] in_data;
output reg out_valid;
output reg [7:0] out_data;
output reg busy;

// You can use the the custom flag ports for your design
input  flag_handshake_to_clk2;
output flag_clk2_to_handshake;

input  flag_fifo_to_clk2;
output flag_clk2_to_fifo;


// DESIGN
integer i;
localparam IDLE = 2'b00;
localparam STALL= 2'b01;
localparam CAL  = 2'b10;
localparam WRITE= 2'b11;
// in_valid here equals to dvalid from clk1 module
// out_valid means winc for sram
reg         full;
reg [1:0]   cs_conv, ns_conv;

reg [2:0]   cnt_fifo_received;
reg [4:0]   cnt_fifo_sent;
reg [2:0]   cnt_map_sent;

reg [2:0]   img     [0:35];
reg [11:0]  kernel  [0:5];

// convolution: sum is the write data
wire        switch_kernel;
wire[5:0]   ns_mult_out0, ns_mult_out1, ns_mult_out2, ns_mult_out3;
reg [3:0]   mult_img0, mult_kernel0; 
reg [3:0]   mult_img1, mult_kernel1; 
reg [3:0]   mult_img2, mult_kernel2; 
reg [3:0]   mult_img3, mult_kernel3; 

reg [7:0]   sum;
wire[7:0]   ns_sum;

always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        cs_conv <= IDLE;
    end else begin
        cs_conv <= ns_conv;
    end
end
always @(*) begin
    case (cs_conv)
        IDLE:begin
            if(in_valid)begin
                ns_conv = STALL;
            end else begin
                ns_conv = cs_conv;
            end
        end 
        STALL:begin
            if(cnt_fifo_received == 'd1)begin
                ns_conv = cs_conv;
            end else if(busy || cnt_fifo_received == 'd6)begin
                ns_conv = CAL;
            end else begin
                ns_conv = cs_conv;
            end
        end
        CAL:begin
            if(!fifo_full)begin
                ns_conv = WRITE;
            end else begin
                ns_conv = cs_conv;
            end
        end
        WRITE:begin
            if(cnt_fifo_received == 'd6)begin
                if(!fifo_full && cnt_map_sent == 'd5 && cnt_fifo_sent == 'd25)begin
                    ns_conv = IDLE;
                end else if(fifo_full || cnt_fifo_sent == 'd25)begin
                    ns_conv = STALL;
                end else begin
                    ns_conv = cs_conv;
                end
            end else if(cnt_fifo_sent % 5 == 'd0)begin
                ns_conv = STALL;
            end else begin
                ns_conv = cs_conv;
            end
        end
        default:begin
            ns_conv = cs_conv;
        end
    endcase
end

// busy
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        busy <= 0;
    end else if(in_valid)begin
        busy <= 1;
    end else begin
        busy <= 0;
    end
end

// counter for reveived data(0-5)
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_fifo_received <= 0;
    end else if(in_valid)begin
        cnt_fifo_received <= cnt_fifo_received + 'd1;
    end else if(cs_conv == IDLE)begin
        cnt_fifo_received <= 0;
    end
end

// counter for sent map
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_map_sent <= 0;
    end else if(cnt_map_sent == 'd6)begin
        cnt_map_sent <= 0;
    end else begin
        if(!fifo_full && cnt_fifo_sent == 'd25)begin
            cnt_map_sent <= cnt_map_sent + 'd1;
        end else begin
            cnt_map_sent <= cnt_map_sent;
        end
    end
end
// counter for sent data (0-25, for 6 times)
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_fifo_sent <= 0;
    end else begin
        case (cs_conv)
            IDLE:begin
                cnt_fifo_sent <= 0;
            end 
            CAL:begin
                if(fifo_full)begin
                    cnt_fifo_sent <= cnt_fifo_sent;
                end else begin
                    if(cnt_fifo_sent == 'd25)begin
                        cnt_fifo_sent <= 0;
                    end else begin
                        cnt_fifo_sent <= cnt_fifo_sent + 'd1;
                    end
                end
            end
            WRITE:begin
                if(fifo_full)begin
                    cnt_fifo_sent <= cnt_fifo_sent - 'd1;
                end else begin
                    if(cnt_fifo_received == 'd6)begin
                        if(cnt_fifo_sent == 'd25)begin
                            cnt_fifo_sent <= 0;
                        end else begin
                            cnt_fifo_sent <= cnt_fifo_sent + 'd1;
                        end
                    end else begin
                        if(cnt_fifo_sent % 5 == 'd0)begin
                            cnt_fifo_sent <= cnt_fifo_sent;
                        end else begin
                            cnt_fifo_sent <= cnt_fifo_sent + 'd1;
                        end
                    end
                end
            end
            default:begin
                cnt_fifo_sent <= cnt_fifo_sent;
            end 
        endcase
    end
end

// data from handshake
assign switch_kernel = (!fifo_full && cnt_fifo_sent == 'd25)? 1 : 0;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 36; i = i + 1)begin
            img[i] <= 3'd0;
        end
    end else if(in_valid) begin
        img[cnt_fifo_received*6] <= in_data[14:12];
        img[cnt_fifo_received*6 + 'd1] <= in_data[17:15];
        img[cnt_fifo_received*6 + 'd2] <= in_data[20:18];
        img[cnt_fifo_received*6 + 'd3] <= in_data[23:21];
        img[cnt_fifo_received*6 + 'd4] <= in_data[26:24];
        img[cnt_fifo_received*6 + 'd5] <= in_data[29:27];
    end
end
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        for(i = 0; i < 6; i = i + 1)begin
            kernel[i] <= 12'd0;
        end
    end else if(in_valid)begin
        kernel[cnt_fifo_received] <= in_data[11:0];
    end else if(switch_kernel)begin
        kernel[0] <= kernel[1];
        kernel[1] <= kernel[2];
        kernel[2] <= kernel[3];
        kernel[3] <= kernel[4];
        kernel[4] <= kernel[5];
        kernel[5] <= kernel[0];
    end
end

// convolution
reg [4:0] x, ns_x;
assign ns_mult_out0 = mult_img0 * mult_kernel0;
assign ns_mult_out1 = mult_img1 * mult_kernel1;
assign ns_mult_out2 = mult_img2 * mult_kernel2;
assign ns_mult_out3 = mult_img3 * mult_kernel3;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        x <= 0;
    end else begin
        x <= ns_x;
    end
end
always @(*) begin
    ns_x = 0;
    if(!fifo_full)begin
        if(cs_conv == WRITE || cs_conv == CAL)begin
            if(cnt_map_sent == 'd0)begin
                if(x == 'd29)begin
                    ns_x = 'd0;
                end else begin
                    ns_x = x + 'd1;
                end
            end else begin
                case (x)
                    'd4:begin
                        ns_x = 'd6;
                    end
                    'd10:begin
                        ns_x = 'd12;
                    end
                    'd16:begin
                        ns_x = 'd18;
                    end
                    'd22:begin
                        ns_x = 'd24;
                    end
                    'd29:begin
                        ns_x = 'd0;
                    end
                    default:begin
                        ns_x = x + 'd1;
                    end
                endcase
            end
        end else begin
            ns_x = x;
        end
    end else begin
        if(cs_conv == WRITE)begin
            case (x)
                'd6:begin
                    ns_x = 'd4;
                end
                'd12:begin
                    ns_x = 'd10;
                end
                'd18:begin
                    ns_x = 'd16;
                end
                'd24:begin
                    ns_x = 'd22;
                end
                'd0:begin
                    ns_x = 'd29;
                end
                default:begin
                    ns_x = x - 'd1;
                end
            endcase
        end else begin
            ns_x = x;
        end
    end
end
always @(*) begin
    mult_img0 = img[x];
    mult_img1 = img[x+'d1];
    mult_img2 = img[x+'d6];
    mult_img3 = img[x+'d7];
end
always @(*) begin
    mult_kernel0 = kernel[0][2:0];
    mult_kernel1 = kernel[0][5:3];
    mult_kernel2 = kernel[0][8:6];
    mult_kernel3 = kernel[0][11:9];
end
assign ns_sum = ns_mult_out0 + ns_mult_out1 + ns_mult_out2 + ns_mult_out3;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        sum <= 0;
    end else begin
        sum <= ns_sum;
    end
end

// output setting: out_valid, out_data, busy
always @(*) begin
    if(cs_conv == WRITE && !fifo_full)begin
        out_valid = 1;
    end else begin
        out_valid = 0;
    end
end
always @(*) begin
    if(cs_conv == WRITE && !fifo_full)begin
        out_data = sum;
    end else begin
        out_data = 0;
    end
end


endmodule
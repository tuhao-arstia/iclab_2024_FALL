module TMIP(
    // input signals
    clk,
    rst_n,
    in_valid, 
    in_valid2,
    
    image,
    template,
    image_size,
	action,
	
    // output signals
    out_valid,
    out_value
    );

input            clk, rst_n;
input            in_valid, in_valid2;

input      [7:0] image;
input      [7:0] template;
input      [1:0] image_size;
input      [2:0] action;

output reg       out_valid;
output reg       out_value;

//==================================================================
// parameter & integer
//==================================================================
parameter IDLE = 3'd0;
parameter RGB  = 3'd1;
parameter ACT  = 3'd2;
parameter MAX  = 3'd3;
parameter MIN  = 3'd4;
parameter IF   = 3'd5;
parameter OUT  = 3'd6;
parameter RST  = 3'd7;
parameter BIAS_512_1 = 9'd128;
parameter BIAS_512_2 = 9'd256;
parameter BIAS_512_3 = 9'd384;

integer i, j;
//==================================================================
// reg & wire
//==================================================================
// fsm
reg [2:0] cs, ns;
reg [2:0] fsm_pointer, ns_fsm_pointer;
reg mp_invalid_flag, ns_mp_invalid_flag;
// sram
reg [8:0]  addr_512;
reg [6:0]  addr_128;
reg [15:0] di_512, di_128, do_512, do_128;
reg        web_512, cs_512;
reg        web_128, cs_128;
reg        rw_direction, ns_rw_direction;
// 0: 512 write and 128 read
// 1: 128 write and 512 read
reg [8:0]  bias_512;
reg [8:0]  x_512, ns_x_512;
reg [6:0]  x_128, ns_x_128;
reg [8:0]  x_read, x_write;

// input size and template
reg [7:0]  kernel [0:8];
reg [7:0]  ns_kernel [0:8];
reg [3:0]  cnt_kernel, ns_cnt_kernel;
reg [1:0]  pat_size, size, ns_size;
// input RGB
reg [2:0]  cnt_rgb, ns_cnt_rgb;
reg [7:0]  r, g, b, ns_r, ns_g, ns_b;
reg [7:0]  gs_m0, gs_a0, gs_w0, ns_gs_m0, ns_gs_a0, ns_gs_w0;
reg [7:0]  gs_a1, gs_w1;
reg [7:0]  gs_m_rg, ns_gs_m_rg;

// action 
reg [2:0] cnt_act, ns_cnt_act;
reg [2:0] first_act;
reg [2:0] act [0:6];
reg [2:0] ns_act;
// first action size = size
reg [2:0] act_pointer, ns_act_pointer;
reg neg_odd, ns_neg_odd;
reg flip_odd, ns_flip_odd;
// direct act to output
reg [1:0] cnt_act_delay, ns_cnt_act_delay;

// pooling
reg [2:0]  cnt_pool, ns_cnt_pool;
reg [15:0]  mp_in [0:1];
reg [7:0]   mp_out;
wire[7:0]   ns_mp_out;

// image filter
reg [3:0]  cnt_if, ns_cnt_if;
// will share with conv
reg [15:0] if_conv_in [0:2][0:7];
reg [15:0] ns_if_out;
reg  [7:0] l0, l1, l2;
reg [15:0] m0, m1, m2;
reg  [7:0] r0, r1, r2;

// cross correlation
reg [3:0]  cnt_out, ns_cnt_out;
reg [4:0]  cnt_20, ns_cnt_20;
reg [8:0]  cnt_acc, ns_cnt_acc;
reg        cnt_20_odd_flag , ns_cnt_20_odd_flag;  
reg [19:0] out_temp [0:1];
reg [19:0] out_temp_choice;
reg [7:0]  data;
reg [7:0]  kernel_temp;
reg [19:0] ns_out_temp;

// reset stage
reg [1:0] cnt_rst, ns_cnt_rst;
reg next_is_out, ns_next_is_out;
//==================================================================
// design
//==================================================================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_act_delay <= 0;
    end else begin
        cnt_act_delay <= ns_cnt_act_delay;
    end
end
always @(*) begin
    case (cs)
        ACT:begin
            if(!in_valid2)begin
                ns_cnt_act_delay = 1;
            end else begin
                ns_cnt_act_delay = 0;
            end
        end 
        default:begin
            ns_cnt_act_delay = 0;
        end
    endcase
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        next_is_out <= 0;
    end else begin
        next_is_out <= ns_next_is_out;
    end
end
always @(*) begin
    if(act[fsm_pointer] == OUT && cs == ACT)begin
        ns_next_is_out = 1;
    end else if(act[fsm_pointer+1] == OUT && cs == RST)begin
        ns_next_is_out = 1;
    end else begin
        ns_next_is_out = 0;
    end
end
// fsm and fsm pointer
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cs <= IDLE;
    end else begin
        cs <= ns;
    end
end
always @(*) begin
    case (cs)
        IDLE:begin
            if(in_valid2)begin
                ns = ACT;
            end else if(in_valid && cnt_rgb == 'd2) begin
                ns = RGB;
            end else begin
                ns = cs;
            end
        end 
        RGB:begin
            if(in_valid2)begin
                ns = ACT;
            end else begin
                ns = cs;
            end
        end
        ACT:begin
            if(cnt_act_delay == 1)begin
                ns = act[0];
            end else begin
                ns = cs;
            end
        end
        MAX, MIN:begin
            // u can try case(size)
            if(size == 0)begin
                ns = RST;
            end else if(size == 1 && cnt_pool == 'd2 && x_write == 'd8)begin
                // (x_128 == 'd8 || x_512 == 'd8)
                ns = RST;
            end else if(size == 2 && cnt_pool == 'd2 && x_write == 'd32)begin
                // (x_128 == 'd32 || x_512 == 'd32)
                ns = RST;
            end else begin
                ns = cs;
            end
        end
        IF:begin
            // u can try case(size)
            if(size == 0 && x_write == 'd7)begin
                // (x_128 == 'd7 || x_512 == 'd7)
                ns = RST;
            end else if(size == 1 && x_write == 'd31)begin
                // (x_128 == 'd31 || x_512 == 'd31)
                ns = RST;
            end else if(size == 2 && x_write == 'd127)begin
                // (x_128 == 'd127 || x_512 == 'd127)
                ns = RST;
            end else begin
                ns = cs;
            end
        end
        OUT:begin
            case (size)
                'd0:begin
                    if(cnt_acc == 'd16)begin
                        ns = IDLE;
                    end else begin
                        ns = cs;
                    end
                end 
                'd1:begin
                    if(cnt_acc == 'd64)begin
                        ns = IDLE;
                    end else begin
                        ns = cs;
                    end
                end
                'd2:begin
                    if(cnt_acc == 'd256)begin
                        ns = IDLE;
                    end else begin
                        ns = cs;
                    end
                end
                default:begin
                    ns = cs;
                end 
            endcase
        end
        RST:begin
            // reset for two cycle
            if(cnt_rst == 'd1)begin
                ns = act[fsm_pointer+1];
            end else begin
                ns = cs;
            end
        end
        default:begin
            ns = cs;
        end 
    endcase
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_rst <= 0;
    end else begin
        cnt_rst <= ns_cnt_rst;
    end
end
always @(*) begin
    case (cs)
        RST:begin
            ns_cnt_rst = cnt_rst + 'd1;
        end
        default:begin
            ns_cnt_rst = 0;
        end 
    endcase    
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        fsm_pointer <= 3'd0;
    end else begin
        fsm_pointer <= ns_fsm_pointer;
    end
end
always @(*) begin
    case (cs)
        IDLE:begin
            ns_fsm_pointer = 0;
        end
        RST:begin
            //switching action
            if(cnt_rst == 'd1)begin
                ns_fsm_pointer = fsm_pointer + 'd1;
            end else begin
                ns_fsm_pointer = fsm_pointer;
            end
        end
        default:begin
            ns_fsm_pointer = fsm_pointer;
        end
    endcase
end
reg [2:0] wk_pointer,ns_wk_pointer;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        wk_pointer <= 0;
    end else begin
        wk_pointer <= ns_wk_pointer;
    end
end
always @(*) begin
    case (cs)
        IDLE:begin
            ns_wk_pointer = 0;
        end
        RST:begin
            //switching action
            if(!mp_invalid_flag)begin
                if(cnt_rst == 'd1)begin
                    ns_wk_pointer = wk_pointer + 'd1;
                end else begin
                    ns_wk_pointer = wk_pointer;
                end
            end else begin
                ns_wk_pointer = wk_pointer;
            end
            
        end
        default:begin
            ns_wk_pointer = wk_pointer;
        end
    endcase
end
// input template and image size
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_kernel <= 0;
    end else begin
        cnt_kernel <= ns_cnt_kernel;
    end
end
always @(*) begin
    if((cs == IDLE && !in_valid) || cs == OUT)begin
        ns_cnt_kernel = 0;
    end else if(cnt_kernel == 'd9) begin
        ns_cnt_kernel = cnt_kernel;
    end else begin
        ns_cnt_kernel = cnt_kernel + 'd1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for( i = 0; i < 9; i = i + 1 )begin
            kernel[i] <= 0;
        end
    end else begin
        for( i = 0; i < 9; i = i + 1 )begin
            kernel[i] <= ns_kernel[i];
        end
    end
end
always @(*) begin
    for( i = 0; i < 9; i = i + 1 )begin
        if(in_valid && cnt_kernel == i)begin
            ns_kernel[i] = template;
        end else begin
            ns_kernel[i] = kernel[i];
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        pat_size <= 0;
    end else if(in_valid && cs == IDLE && cnt_rgb == 'd0)begin
        pat_size <= image_size;
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        size <= 0;
    end else begin
        size <= ns_size;
    end
end
always @(*) begin
    case (cs)
        ACT:begin
            ns_size = pat_size;
        end
        MAX, MIN:begin
            // u can try case(size)
            if(size == 0)begin
                ns_size = size;
            end else if(size == 1 && cnt_pool == 'd2 && x_write == 'd8)begin
                //(x_128 == 'd8 || x_512 == 'd8)
                ns_size = size - 'd1;
            end else if(size == 2 && cnt_pool == 'd2 && x_write == 'd32)begin
                // (x_128 == 'd32 || x_512 == 'd32)
                ns_size = size - 'd1;
            end else begin
                ns_size = size;
            end
        end 
        default:begin
            ns_size = size;
        end 
    endcase
end

// counter for rgb state
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_rgb <= 0;
    end else begin
        cnt_rgb <= ns_cnt_rgb;
    end
end
always @(*) begin
    case (cs)
        IDLE:begin
            if(in_valid)begin
                ns_cnt_rgb = cnt_rgb + 'd1;
            end else begin
                ns_cnt_rgb = 0;
            end
        end 
        RGB:begin
            if(cnt_rgb == 'd5)begin
                ns_cnt_rgb = 0;
            end else begin
                ns_cnt_rgb = cnt_rgb + 'd1;
            end
        end
        OUT:begin
            ns_cnt_rgb = 0;
        end
        default:begin
            ns_cnt_rgb = cnt_rgb + 'd1;
        end 
    endcase
end

// input RGB
always @(posedge clk) begin
    r <= ns_r;
    g <= ns_g;
    b <= ns_b;
end
always @(*) begin
    case (cnt_rgb)
        'd0, 'd3:begin
            ns_r = image;
            ns_g = g;
            ns_b = b;
        end
        'd1, 'd4:begin
            ns_r = r;
            ns_g = image;
            ns_b = b;
        end
        'd2, 'd5:begin
            ns_r = r;
            ns_b = image;
            ns_g = g;
        end
        default:begin
            ns_r = r;
            ns_g = g;
            ns_b = b;
        end 
    endcase
end

// wire direct to sram
always @(posedge clk) begin
    gs_m_rg <= ns_gs_m_rg;
    if(cnt_rgb == 'd3)begin
        gs_m0 <= ns_gs_m0;
        gs_a0 <= ns_gs_a0;
        gs_w0 <= ns_gs_w0;
    end
    if(cnt_rgb == 'd0)begin
        gs_a1 <= ns_gs_a0;
        gs_w1 <= ns_gs_w0;
    end
end
always @(*) begin
    ns_gs_m_rg = (r > g) ? r : g;
    ns_gs_m0 = (gs_m_rg > b) ? gs_m_rg : b;

    ns_gs_a0 = (r + g + b)/3;

    ns_gs_w0 = (r >> 2) + (g >> 1) + (b >> 2);
end

// action
// counter for act state
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_act <= 0;
    end else begin
        cnt_act <= ns_cnt_act;
    end
end
always @(*) begin
    case (cs)
        IDLE, RGB:begin
            ns_cnt_act = 0;
        end 
        ACT:begin
            ns_cnt_act = cnt_act + 'd1;
        end
        default:begin
            ns_cnt_act = cnt_act;
        end 
    endcase
end

// get action and rearrange 
// action 3=maxpooling, 4=negative  , 5=horizontal flip, 6=image filter, 7=conv
// act    3=maxpooling, 4=minpooling, 5=image filter, 6=conv
always @(posedge clk) begin
    // first action : 0/1/2
    if((in_valid2 && cs == RGB) || (in_valid2 && cs == IDLE))begin
        first_act <= action;
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for( i = 0; i < 8; i = i + 1)begin
            act[i] <= 0;
        end
    end else if(cs == IDLE)begin
        for( i = 0; i < 8; i = i + 1)begin
            act[i] <= 0;
        end
    end else if(in_valid2)begin
        act[act_pointer] <= ns_act;
    end
end
always @(*) begin
    case (cs)
        ACT:begin
            case (action)
                3'd3:begin
                    if(neg_odd)begin
                        ns_act = MIN;
                    end else begin
                        ns_act = MAX;
                    end
                end
                3'd6:begin
                    ns_act = IF;
                end
                3'd7:begin
                    ns_act = OUT;
                end
                default:begin
                    ns_act = 0;
                end
            endcase
        end 
        default:begin
            ns_act = 0;
        end 
    endcase
end

// action pointer
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        act_pointer <= 0;
    end else begin
        act_pointer <= ns_act_pointer;
    end
end
always @(*) begin
    case (cs)
        IDLE:begin
            ns_act_pointer = 0;
        end
        ACT:begin
            if(action == 'd3 || action == 'd6)begin
                ns_act_pointer = act_pointer + 'd1;
            end else begin
                ns_act_pointer = act_pointer;
            end
        end 
        default:begin
            ns_act_pointer = act_pointer;
        end
    endcase
end

// negative flag and horizontal flip flag
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        neg_odd <= 0;
        flip_odd <= 0;
    end else begin
        neg_odd <= ns_neg_odd;
        flip_odd <= ns_flip_odd;
    end
end
always @(*) begin
    case (cs)
        IDLE:begin
            ns_neg_odd = 0;
        end
        ACT:begin
            if(action == 'd4 && in_valid2)begin
                ns_neg_odd = ~neg_odd;
            end else begin
                ns_neg_odd = neg_odd;
            end
        end 
        default:begin
            ns_neg_odd = neg_odd;
        end 
    endcase
end
always @(*) begin
    case (cs)
        IDLE:begin
            ns_flip_odd = 0;
        end
        ACT:begin
            if(action == 'd5 && in_valid2)begin
                ns_flip_odd = ~flip_odd;
            end else begin
                ns_flip_odd = flip_odd;
            end
        end
        default:begin
            ns_flip_odd = flip_odd;
        end 
    endcase
end

// pooling
// pooling counter
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_pool <= 0;
    end else begin
        cnt_pool <= ns_cnt_pool;
    end
end
always @(*) begin
    case (cs)
        // 4, 5, (2, 3, 0, 1)(repeat)
        MAX, MIN:begin
            if(cnt_pool == 'd3)begin
                ns_cnt_pool = 0;
            end else if(cnt_pool == 'd5)begin
                ns_cnt_pool = 'd2;
            end else begin
                ns_cnt_pool = cnt_pool + 'd1;
            end
        end 
        default:begin
            //RST between consecutive MAX/MIN
            ns_cnt_pool = 'd4;
        end
    endcase
end

// saving pooling input
always @(posedge clk) begin
    case (cnt_pool)
        'd5, 'd3, 'd1:begin
            if(rw_direction == 0)begin
                // read from 512
                mp_in[0] <= do_512;
            end else begin
                mp_in[0] <= do_128;
            end
            
        end
        'd2, 'd0:begin
            if(rw_direction == 0)begin
                mp_in[1] <= do_512;
            end else begin
                mp_in[1] <= do_128;
            end
        end
    endcase
end

pooling POOL(.current_state(cs), .pool_in1(mp_in[0]), .pool_in2(mp_in[1]), .pool_out(ns_mp_out));

// saving pooling output
always @(posedge clk) begin
    if(cnt_pool == 'd3)begin
        mp_out <= ns_mp_out;
    end
end

// image filter
// IF counter
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_if <= 0;
    end else begin
        cnt_if <= ns_cnt_if;
    end
end
always @(*) begin
    case (cs)
        IF:begin
            if(cnt_if == 'd0)begin
                ns_cnt_if = 'd0;
            end else begin
                ns_cnt_if = cnt_if + 'd1;
            end
        end
        default:begin
            // including RST
            case (size)
                'd0:begin
                    ns_cnt_if = 'd11;
                end 
                'd1:begin
                    ns_cnt_if = 'd9;
                end
                default:begin
                    // 'd0
                    ns_cnt_if = 'd5;
                end
            endcase
        end 
    endcase
end

median MEDIAN( .mid_in_l0(l0), .mid_in_l1(l1), .mid_in_l2(l2), .mid_in_m0(m0), .mid_in_m1(m1), .mid_in_m2(m2), .mid_in_r0(r0), .mid_in_r1(r1), .mid_in_r2(r2), .median_out(ns_if_out));

always @(*) begin
    case (size)
        'd0: begin
            case (x_read)
                'd5:begin
                    l0 = if_conv_in[1][0][15:8];
                    l1 = if_conv_in[1][0][15:8];
                    l2 = if_conv_in[2][0][15:8];
                    m0 = if_conv_in[1][0];
                    m1 = if_conv_in[1][0];
                    m2 = if_conv_in[2][0];
                    r0 = if_conv_in[1][1][15:8];
                    r1 = if_conv_in[1][1][15:8];
                    r2 = if_conv_in[2][1][15:8];
                end
                'd6:begin
                    l0 = if_conv_in[1][2][7:0];
                    l1 = if_conv_in[1][2][7:0];
                    l2 = if_conv_in[2][2][7:0];
                    m0 = if_conv_in[1][3];
                    m1 = if_conv_in[1][3];
                    m2 = if_conv_in[2][3];
                    r0 = if_conv_in[1][3][7:0];
                    r1 = if_conv_in[1][3][7:0];
                    r2 = if_conv_in[2][3][7:0];
                end
                'd7, 'd9:begin
                    l0 = if_conv_in[0][0][15:8];
                    l1 = if_conv_in[1][0][15:8];
                    l2 = if_conv_in[2][0][15:8];
                    m0 = if_conv_in[0][0];
                    m1 = if_conv_in[1][0];
                    m2 = if_conv_in[2][0];
                    r0 = if_conv_in[0][1][15:8];
                    r1 = if_conv_in[1][1][15:8];
                    r2 = if_conv_in[2][1][15:8];
                end
                'd8, 'd10:begin
                    l0 = if_conv_in[0][2][7:0];
                    l1 = if_conv_in[1][2][7:0];
                    l2 = if_conv_in[2][2][7:0];
                    m0 = if_conv_in[0][3];
                    m1 = if_conv_in[1][3];
                    m2 = if_conv_in[2][3];
                    r0 = if_conv_in[0][3][7:0];
                    r1 = if_conv_in[1][3][7:0];
                    r2 = if_conv_in[2][3][7:0];
                end
                'd11:begin
                    l0 = if_conv_in[0][0][15:8];
                    l1 = if_conv_in[1][0][15:8];
                    l2 = if_conv_in[1][0][15:8];
                    m0 = if_conv_in[0][0];
                    m1 = if_conv_in[1][0];
                    m2 = if_conv_in[1][0];
                    r0 = if_conv_in[0][1][15:8];
                    r1 = if_conv_in[1][1][15:8];
                    r2 = if_conv_in[1][1][15:8];
                end
                'd12:begin
                    l0 = if_conv_in[0][2][7:0];
                    l1 = if_conv_in[1][2][7:0];
                    l2 = if_conv_in[1][2][7:0];
                    m0 = if_conv_in[0][3];
                    m1 = if_conv_in[1][3];
                    m2 = if_conv_in[1][3];
                    r0 = if_conv_in[0][3][7:0];
                    r1 = if_conv_in[1][3][7:0];
                    r2 = if_conv_in[1][3][7:0];
                end
                default:begin
                    l0 = 0; m0 = 0; r0 = 0;
                    l1 = 0; m1 = 0; r1 = 0;
                    l2 = 0; m2 = 0; r2 = 0;
                end
            endcase
        end
        'd1:begin
            case (x_read)
                'd7:begin
                    l0 = if_conv_in[1][0][15:8];
                    l1 = if_conv_in[1][0][15:8];
                    l2 = if_conv_in[2][0][15:8];
                    m0 = if_conv_in[1][0];
                    m1 = if_conv_in[1][0];
                    m2 = if_conv_in[2][0];
                    r0 = if_conv_in[1][1][15:8];
                    r1 = if_conv_in[1][1][15:8];
                    r2 = if_conv_in[2][1][15:8];
                end
                'd8:begin
                    l0 = if_conv_in[1][0][7:0];
                    l1 = if_conv_in[1][0][7:0];
                    l2 = if_conv_in[2][0][7:0];
                    m0 = if_conv_in[1][1];
                    m1 = if_conv_in[1][1];
                    m2 = if_conv_in[2][1];
                    r0 = if_conv_in[1][2][15:8];
                    r1 = if_conv_in[1][2][15:8];
                    r2 = if_conv_in[2][2][15:8];
                end
                'd9:begin
                    l0 = if_conv_in[1][1][7:0];
                    l1 = if_conv_in[1][1][7:0];
                    l2 = if_conv_in[2][1][7:0];
                    m0 = if_conv_in[1][2];
                    m1 = if_conv_in[1][2];
                    m2 = if_conv_in[2][2];
                    r0 = if_conv_in[1][3][15:8];
                    r1 = if_conv_in[1][3][15:8];
                    r2 = if_conv_in[2][3][15:8];
                end
                'd10:begin
                    l0 = if_conv_in[1][2][7:0];
                    l1 = if_conv_in[1][2][7:0];
                    l2 = if_conv_in[2][2][7:0];
                    m0 = if_conv_in[1][3];
                    m1 = if_conv_in[1][3];
                    m2 = if_conv_in[2][3];
                    r0 = if_conv_in[1][3][7:0];
                    r1 = if_conv_in[1][3][7:0];
                    r2 = if_conv_in[2][3][7:0];
                end
                'd11, 'd15, 'd19, 'd23, 'd27, 'd31:begin
                    l0 = if_conv_in[0][0][15:8];
                    l1 = if_conv_in[1][0][15:8];
                    l2 = if_conv_in[2][0][15:8];
                    m0 = if_conv_in[0][0];
                    m1 = if_conv_in[1][0];
                    m2 = if_conv_in[2][0];
                    r0 = if_conv_in[0][1][15:8];
                    r1 = if_conv_in[1][1][15:8];
                    r2 = if_conv_in[2][1][15:8];
                end
                'd12, 'd16, 'd20, 'd24, 'd28, 'd32:begin
                    l0 = if_conv_in[0][0][7:0];
                    l1 = if_conv_in[1][0][7:0];
                    l2 = if_conv_in[2][0][7:0];
                    m0 = if_conv_in[0][1];
                    m1 = if_conv_in[1][1];
                    m2 = if_conv_in[2][1];
                    r0 = if_conv_in[0][2][15:8];
                    r1 = if_conv_in[1][2][15:8];
                    r2 = if_conv_in[2][2][15:8];
                end
                'd13, 'd17, 'd21, 'd25, 'd29, 'd33:begin
                    l0 = if_conv_in[0][1][7:0];
                    l1 = if_conv_in[1][1][7:0];
                    l2 = if_conv_in[2][1][7:0];
                    m0 = if_conv_in[0][2];
                    m1 = if_conv_in[1][2];
                    m2 = if_conv_in[2][2];
                    r0 = if_conv_in[0][3][15:8];
                    r1 = if_conv_in[1][3][15:8];
                    r2 = if_conv_in[2][3][15:8];
                end
                'd14, 'd18, 'd22, 'd26, 'd30, 'd34:begin
                    l0 = if_conv_in[0][2][7:0];
                    l1 = if_conv_in[1][2][7:0];
                    l2 = if_conv_in[2][2][7:0];
                    m0 = if_conv_in[0][3];
                    m1 = if_conv_in[1][3];
                    m2 = if_conv_in[2][3];
                    r0 = if_conv_in[0][3][7:0];
                    r1 = if_conv_in[1][3][7:0];
                    r2 = if_conv_in[2][3][7:0];
                end
                'd35:begin
                    l0 = if_conv_in[0][0][15:8];
                    l1 = if_conv_in[1][0][15:8];
                    l2 = if_conv_in[1][0][15:8];
                    m0 = if_conv_in[0][0];
                    m1 = if_conv_in[1][0];
                    m2 = if_conv_in[1][0];
                    r0 = if_conv_in[0][1][15:8];
                    r1 = if_conv_in[1][1][15:8];
                    r2 = if_conv_in[1][1][15:8];
                end
                'd36:begin
                    l0 = if_conv_in[0][0][7:0];
                    l1 = if_conv_in[1][0][7:0];
                    l2 = if_conv_in[1][0][7:0];
                    m0 = if_conv_in[0][1];
                    m1 = if_conv_in[1][1];
                    m2 = if_conv_in[1][1];
                    r0 = if_conv_in[0][2][15:8];
                    r1 = if_conv_in[1][2][15:8];
                    r2 = if_conv_in[1][2][15:8];
                end
                'd37:begin
                    l0 = if_conv_in[0][1][7:0];
                    l1 = if_conv_in[1][1][7:0];
                    l2 = if_conv_in[1][1][7:0];
                    m0 = if_conv_in[0][2];
                    m1 = if_conv_in[1][2];
                    m2 = if_conv_in[1][2];
                    r0 = if_conv_in[0][3][15:8];
                    r1 = if_conv_in[1][3][15:8];
                    r2 = if_conv_in[1][3][15:8];
                end
                'd38:begin
                    l0 = if_conv_in[0][2][7:0];
                    l1 = if_conv_in[1][2][7:0];
                    l2 = if_conv_in[1][2][7:0];
                    m0 = if_conv_in[0][3];
                    m1 = if_conv_in[1][3];
                    m2 = if_conv_in[1][3];
                    r0 = if_conv_in[0][3][7:0];
                    r1 = if_conv_in[1][3][7:0];
                    r2 = if_conv_in[1][3][7:0];
                end
                default:begin
                    l0 = 0; m0 = 0; r0 = 0;
                    l1 = 0; m1 = 0; r1 = 0;
                    l2 = 0; m2 = 0; r2 = 0;
                end
            endcase
        end
        'd2:begin
            case (cnt_acc)
                'd11:begin
                    l0 = if_conv_in[1][0][15:8];
                    l1 = if_conv_in[1][0][15:8];
                    l2 = if_conv_in[2][0][15:8];
                    m0 = if_conv_in[1][0];
                    m1 = if_conv_in[1][0];
                    m2 = if_conv_in[2][0];
                    r0 = if_conv_in[1][1][15:8];
                    r1 = if_conv_in[1][1][15:8];
                    r2 = if_conv_in[2][1][15:8];
                end
                'd12:begin
                    l0 = if_conv_in[1][0][7:0];
                    l1 = if_conv_in[1][0][7:0];
                    l2 = if_conv_in[2][0][7:0];
                    m0 = if_conv_in[1][1];
                    m1 = if_conv_in[1][1];
                    m2 = if_conv_in[2][1];
                    r0 = if_conv_in[1][2][15:8];
                    r1 = if_conv_in[1][2][15:8];
                    r2 = if_conv_in[2][2][15:8];
                end
                'd13:begin
                    l0 = if_conv_in[1][1][7:0];
                    l1 = if_conv_in[1][1][7:0];
                    l2 = if_conv_in[2][1][7:0];
                    m0 = if_conv_in[1][2];
                    m1 = if_conv_in[1][2];
                    m2 = if_conv_in[2][2];
                    r0 = if_conv_in[1][3][15:8];
                    r1 = if_conv_in[1][3][15:8];
                    r2 = if_conv_in[2][3][15:8];
                end
                'd14:begin
                    l0 = if_conv_in[1][2][7:0];
                    l1 = if_conv_in[1][2][7:0];
                    l2 = if_conv_in[2][2][7:0];
                    m0 = if_conv_in[1][3];
                    m1 = if_conv_in[1][3];
                    m2 = if_conv_in[2][3];
                    r0 = if_conv_in[1][4][15:8];
                    r1 = if_conv_in[1][4][15:8];
                    r2 = if_conv_in[2][4][15:8];
                end
                'd15:begin
                    l0 = if_conv_in[1][3][7:0];
                    l1 = if_conv_in[1][3][7:0];
                    l2 = if_conv_in[2][3][7:0];
                    m0 = if_conv_in[1][4];
                    m1 = if_conv_in[1][4];
                    m2 = if_conv_in[2][4];
                    r0 = if_conv_in[1][5][15:8];
                    r1 = if_conv_in[1][5][15:8];
                    r2 = if_conv_in[2][5][15:8];
                end
                'd16:begin
                    l0 = if_conv_in[1][4][7:0];
                    l1 = if_conv_in[1][4][7:0];
                    l2 = if_conv_in[2][4][7:0];
                    m0 = if_conv_in[1][5];
                    m1 = if_conv_in[1][5];
                    m2 = if_conv_in[2][5];
                    r0 = if_conv_in[1][6][15:8];
                    r1 = if_conv_in[1][6][15:8];
                    r2 = if_conv_in[2][6][15:8];
                end
                'd17:begin
                    l0 = if_conv_in[1][5][7:0];
                    l1 = if_conv_in[1][5][7:0];
                    l2 = if_conv_in[2][5][7:0];
                    m0 = if_conv_in[1][6];
                    m1 = if_conv_in[1][6];
                    m2 = if_conv_in[2][6];
                    r0 = if_conv_in[1][7][15:8];
                    r1 = if_conv_in[1][7][15:8];
                    r2 = if_conv_in[2][7][15:8];
                end
                'd18:begin
                    l0 = if_conv_in[1][6][7:0];
                    l1 = if_conv_in[1][6][7:0];
                    l2 = if_conv_in[2][6][7:0];
                    m0 = if_conv_in[1][7];
                    m1 = if_conv_in[1][7];
                    m2 = if_conv_in[2][7];
                    r0 = if_conv_in[1][7][7:0];
                    r1 = if_conv_in[1][7][7:0];
                    r2 = if_conv_in[2][7][7:0];
                end
                'd131:begin
                    l0 = if_conv_in[0][0][15:8];
                    l1 = if_conv_in[1][0][15:8];
                    l2 = if_conv_in[1][0][15:8];
                    m0 = if_conv_in[0][0];
                    m1 = if_conv_in[1][0];
                    m2 = if_conv_in[1][0];
                    r0 = if_conv_in[0][1][15:8];
                    r1 = if_conv_in[1][1][15:8];
                    r2 = if_conv_in[1][1][15:8];
                end
                'd132:begin
                    l0 = if_conv_in[0][0][7:0];
                    l1 = if_conv_in[1][0][7:0];
                    l2 = if_conv_in[1][0][7:0];
                    m0 = if_conv_in[0][1];
                    m1 = if_conv_in[1][1];
                    m2 = if_conv_in[1][1];
                    r0 = if_conv_in[0][2][15:8];
                    r1 = if_conv_in[1][2][15:8];
                    r2 = if_conv_in[1][2][15:8];
                end
                'd133:begin
                    l0 = if_conv_in[0][1][7:0];
                    l1 = if_conv_in[1][1][7:0];
                    l2 = if_conv_in[1][1][7:0];
                    m0 = if_conv_in[0][2];
                    m1 = if_conv_in[1][2];
                    m2 = if_conv_in[1][2];
                    r0 = if_conv_in[0][3][15:8];
                    r1 = if_conv_in[1][3][15:8];
                    r2 = if_conv_in[1][3][15:8];
                end
                'd134:begin
                    l0 = if_conv_in[0][2][7:0];
                    l1 = if_conv_in[1][2][7:0];
                    l2 = if_conv_in[1][2][7:0];
                    m0 = if_conv_in[0][3];
                    m1 = if_conv_in[1][3];
                    m2 = if_conv_in[1][3];
                    r0 = if_conv_in[0][4][15:8];
                    r1 = if_conv_in[1][4][15:8];
                    r2 = if_conv_in[1][4][15:8];
                end
                'd135:begin
                    l0 = if_conv_in[0][3][7:0];
                    l1 = if_conv_in[1][3][7:0];
                    l2 = if_conv_in[1][3][7:0];
                    m0 = if_conv_in[0][4];
                    m1 = if_conv_in[1][4];
                    m2 = if_conv_in[1][4];
                    r0 = if_conv_in[0][5][15:8];
                    r1 = if_conv_in[1][5][15:8];
                    r2 = if_conv_in[1][5][15:8];
                end
                'd136:begin
                    l0 = if_conv_in[0][4][7:0];
                    l1 = if_conv_in[1][4][7:0];
                    l2 = if_conv_in[1][4][7:0];
                    m0 = if_conv_in[0][5];
                    m1 = if_conv_in[1][5];
                    m2 = if_conv_in[1][5];
                    r0 = if_conv_in[0][6][15:8];
                    r1 = if_conv_in[1][6][15:8];
                    r2 = if_conv_in[1][6][15:8];
                end
                'd137:begin
                    l0 = if_conv_in[0][5][7:0];
                    l1 = if_conv_in[1][5][7:0];
                    l2 = if_conv_in[1][5][7:0];
                    m0 = if_conv_in[0][6];
                    m1 = if_conv_in[1][6];
                    m2 = if_conv_in[1][6];
                    r0 = if_conv_in[0][7][15:8];
                    r1 = if_conv_in[1][7][15:8];
                    r2 = if_conv_in[1][7][15:8];
                end
                'd138:begin
                    l0 = if_conv_in[0][6][7:0];
                    l1 = if_conv_in[1][6][7:0];
                    l2 = if_conv_in[1][6][7:0];
                    m0 = if_conv_in[0][7];
                    m1 = if_conv_in[1][7];
                    m2 = if_conv_in[1][7];
                    r0 = if_conv_in[0][7][7:0];
                    r1 = if_conv_in[1][7][7:0];
                    r2 = if_conv_in[1][7][7:0];
                end
                default:begin
                    case (cnt_acc%8)
                        'd3:begin
                            l0 = if_conv_in[0][0][15:8];
                            l1 = if_conv_in[1][0][15:8];
                            l2 = if_conv_in[2][0][15:8];
                            m0 = if_conv_in[0][0];
                            m1 = if_conv_in[1][0];
                            m2 = if_conv_in[2][0];
                            r0 = if_conv_in[0][1][15:8];
                            r1 = if_conv_in[1][1][15:8];
                            r2 = if_conv_in[2][1][15:8];
                        end
                        'd4:begin
                            l0 = if_conv_in[0][0][7:0];
                            l1 = if_conv_in[1][0][7:0];
                            l2 = if_conv_in[2][0][7:0];
                            m0 = if_conv_in[0][1];
                            m1 = if_conv_in[1][1];
                            m2 = if_conv_in[2][1];
                            r0 = if_conv_in[0][2][15:8];
                            r1 = if_conv_in[1][2][15:8];
                            r2 = if_conv_in[2][2][15:8];
                        end
                        'd5:begin
                            l0 = if_conv_in[0][1][7:0];
                            l1 = if_conv_in[1][1][7:0];
                            l2 = if_conv_in[2][1][7:0];
                            m0 = if_conv_in[0][2];
                            m1 = if_conv_in[1][2];
                            m2 = if_conv_in[2][2];
                            r0 = if_conv_in[0][3][15:8];
                            r1 = if_conv_in[1][3][15:8];
                            r2 = if_conv_in[2][3][15:8];
                        end
                        'd6:begin
                            l0 = if_conv_in[0][2][7:0];
                            l1 = if_conv_in[1][2][7:0];
                            l2 = if_conv_in[2][2][7:0];
                            m0 = if_conv_in[0][3];
                            m1 = if_conv_in[1][3];
                            m2 = if_conv_in[2][3];
                            r0 = if_conv_in[0][4][15:8];
                            r1 = if_conv_in[1][4][15:8];
                            r2 = if_conv_in[2][4][15:8];
                        end
                        'd7:begin
                            l0 = if_conv_in[0][3][7:0];
                            l1 = if_conv_in[1][3][7:0];
                            l2 = if_conv_in[2][3][7:0];
                            m0 = if_conv_in[0][4];
                            m1 = if_conv_in[1][4];
                            m2 = if_conv_in[2][4];
                            r0 = if_conv_in[0][5][15:8];
                            r1 = if_conv_in[1][5][15:8];
                            r2 = if_conv_in[2][5][15:8];
                        end
                        'd0:begin
                            l0 = if_conv_in[0][4][7:0];
                            l1 = if_conv_in[1][4][7:0];
                            l2 = if_conv_in[2][4][7:0];
                            m0 = if_conv_in[0][5];
                            m1 = if_conv_in[1][5];
                            m2 = if_conv_in[2][5];
                            r0 = if_conv_in[0][6][15:8];
                            r1 = if_conv_in[1][6][15:8];
                            r2 = if_conv_in[2][6][15:8];
                        end
                        'd1:begin
                            l0 = if_conv_in[0][5][7:0];
                            l1 = if_conv_in[1][5][7:0];
                            l2 = if_conv_in[2][5][7:0];
                            m0 = if_conv_in[0][6];
                            m1 = if_conv_in[1][6];
                            m2 = if_conv_in[2][6];
                            r0 = if_conv_in[0][7][15:8];
                            r1 = if_conv_in[1][7][15:8];
                            r2 = if_conv_in[2][7][15:8];
                        end
                        'd2:begin
                            l0 = if_conv_in[0][6][7:0];
                            l1 = if_conv_in[1][6][7:0];
                            l2 = if_conv_in[2][6][7:0];
                            m0 = if_conv_in[0][7];
                            m1 = if_conv_in[1][7];
                            m2 = if_conv_in[2][7];
                            r0 = if_conv_in[0][7][7:0];
                            r1 = if_conv_in[1][7][7:0];
                            r2 = if_conv_in[2][7][7:0];
                        end
                        default:begin
                            l0 = 0; m0 = 0; r0 = 0;
                            l1 = 0; m1 = 0; r1 = 0;
                            l2 = 0; m2 = 0; r2 = 0;
                        end
                    endcase
                end
            endcase
        end 
        default:begin
            l0 = 0; m0 = 0; r0 = 0;
            l1 = 0; m1 = 0; r1 = 0;
            l2 = 0; m2 = 0; r2 = 0;
        end
    endcase
end

// cross correlation
// out counter
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        // output logic needs these cnt
        cnt_out <= 0;
        cnt_acc <= 0;
        cnt_20 <= 0;
    end else begin
        cnt_out <= ns_cnt_out;
        cnt_acc <= ns_cnt_acc;
        cnt_20 <= ns_cnt_20;
    end
end
always @(*) begin
    // support reading into if_conv_in
    // 4*4 cnt out range 0~2(1~2 read)
    // 8*8 cnt out range 0~4(1~4 read)
    // 16*16 cnt out range 0~8(1~8 read)
    case (cs)
        OUT:begin
            case (size)
                'd0:begin
                    if(cnt_acc == 'd0 && cnt_20 == 'd0)begin
                        case (x_read)
                            'd0, 'd2, 'd4:begin
                                if(!flip_odd)begin
                                    ns_cnt_out = 'd1;
                                end else begin
                                    ns_cnt_out = 'd2;
                                end
                                
                            end 
                            'd1, 'd3, 'd5:begin
                                if(!flip_odd)begin
                                    ns_cnt_out = 'd2;
                                end else begin
                                    ns_cnt_out = 'd1;
                                end
                            end
                            default:begin
                                ns_cnt_out = 0;
                            end
                        endcase
                    end else begin
                        //exact cycle
                        if(cnt_acc == 'd6)begin
                            if(cnt_20 >= 'd16 && cnt_20 <= 'd17)begin
                                ns_cnt_out = cnt_out + 'd1;
                            end else begin
                                ns_cnt_out = 0;
                            end
                        end else begin
                            // if(cnt_20 == 'd1 && !flip_odd)begin
                                // ns_cnt_out = cnt_out + 'd1;
                            // end else begin
                                ns_cnt_out = 0;
                            // end
                        end
                    end
                end
                'd1:begin
                    if(cnt_acc == 'd0 && cnt_20 == 'd0)begin
                        if(cnt_out == 'd4)begin
                            if(x_read < 'd8)begin
                                // read 2 rows
                                ns_cnt_out = 'd1;
                            end else begin
                                ns_cnt_out = 0;
                            end
                        end else begin
                            ns_cnt_out = cnt_out + 'd1;
                        end
                    end else begin
                        if(cnt_acc%8 == 'd7)begin
                            if(cnt_20 >= 'd14 && cnt_20 <= 'd17)begin
                                ns_cnt_out = cnt_out + 'd1;
                            end else begin
                                ns_cnt_out = 0;
                            end
                        end else begin
                            ns_cnt_out = 0;
                        end
                    end
                end
                'd2:begin
                    if(cnt_acc == 'd0 && cnt_20 == 'd0)begin
                        if(cnt_out == 'd8)begin
                            if(x_read < 'd16)begin
                                ns_cnt_out = 'd1;
                            end else begin
                                ns_cnt_out = 0;
                            end
                        end else begin
                            ns_cnt_out = cnt_out + 'd1;
                        end
                    end else begin
                        if(cnt_acc%16 == 'd15)begin
                            if(cnt_20 >= 'd10 && cnt_20 <= 'd17)begin
                                ns_cnt_out = cnt_out + 'd1;
                            end else begin
                                ns_cnt_out = 0;
                            end
                        end else begin
                            if(x_read < 'd16)begin
                                ns_cnt_out = cnt_out + 'd1;
                            end else begin
                                ns_cnt_out = 0;
                            end
                        end
                    end
                end
                default:begin
                    ns_cnt_out = 0;
                end
            endcase
        end 
        default:begin
            ns_cnt_out = 0;
        end 
    endcase
end
always @(*) begin
    // refresh each 20 cycles
    if(out_valid)begin
        if(cnt_20 == 'd19)begin
            ns_cnt_20 = 0;
        end else begin
            ns_cnt_20 = cnt_20 + 'd1;
        end
    end else begin
        ns_cnt_20 = 0;
    end
end
always @(*) begin
    //counter how many outputs are finished
    if(cs == IF)begin
        ns_cnt_acc = cnt_acc + 'd1;
    end else if(cs == OUT)begin
        if(cnt_20 == 'd19)begin
            ns_cnt_acc = cnt_acc + 'd1;
        end else begin
            ns_cnt_acc = cnt_acc;
        end
    end else begin
        ns_cnt_acc = 0;
    end
end

// cnt_20_odd_flag: help to choose which out_temp to save output rn and using other to calculate
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        cnt_20_odd_flag <= 0;
    end else begin
        cnt_20_odd_flag <= ns_cnt_20_odd_flag;
    end
end
always @(*) begin
    case (cs)
        OUT:begin
            case (size)
                'd0:begin
                    if((x_read == 'd5 && !flip_odd) || (x_read == 'd4 && flip_odd) && cnt_acc == 'd0)begin
                        ns_cnt_20_odd_flag = 1;
                    end else if(cnt_20 == 'd19) begin
                        ns_cnt_20_odd_flag = ~cnt_20_odd_flag;
                    end else begin
                        ns_cnt_20_odd_flag = cnt_20_odd_flag;
                    end
                end 
                'd1:begin
                    //x_read == 'd7 is 1 cycle before the first output of 8*8
                    if((x_read == 'd7 && !flip_odd)|| (x_read == 'd4 && flip_odd) && cnt_acc == 'd0)begin
                        //run only once
                        ns_cnt_20_odd_flag = 1;
                    end else if(cnt_20 == 'd19)begin
                        ns_cnt_20_odd_flag = ~cnt_20_odd_flag;
                    end else begin
                        ns_cnt_20_odd_flag = cnt_20_odd_flag;
                    end
                end
                'd2:begin
                    //x_read == 'd11 is 1 cycle before the first output of 16*16
                    if((x_read == 'd11 && !flip_odd) || (x_read == 'd12 && flip_odd) && cnt_acc == 'd0)begin
                        //run only once
                        ns_cnt_20_odd_flag = 1;
                    end else if(cnt_20 == 'd19)begin
                        ns_cnt_20_odd_flag = ~cnt_20_odd_flag;
                    end else begin
                        ns_cnt_20_odd_flag = cnt_20_odd_flag;
                    end
                end
                default:begin
                    ns_cnt_20_odd_flag = cnt_20_odd_flag;
                end 
            endcase
        end 
        default:begin
            ns_cnt_20_odd_flag = 0;
        end
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        out_temp[0] <= 0;
        out_temp[1] <= 0;
    end else if(cs == IDLE)begin
        out_temp[0] <= 0;
        out_temp[1] <= 0;
    end else begin
        if(cnt_20_odd_flag)begin
            //output: out_temp[0], calculate:out_temp[1]
            if(cnt_20 == 'd19)begin
                out_temp[0] <= 0;
            end else begin
                out_temp[0] <= out_temp[0];
            end
            out_temp[1] <= ns_out_temp;
        end else begin
            //output: out_temp[1], calculate:out_temp[0]
            if(cnt_20 == 'd19)begin
                out_temp[1] <= 0;
            end else begin
                out_temp[1] <= out_temp[1];
            end
            out_temp[0] <= ns_out_temp;
        end
        
    end
end
// if and conv sharing register
always @(posedge clk) begin
    case(cs)
        IDLE, RST:begin
            for(i = 0; i < 3; i = i + 1)begin
                for(j = 0; j < 8; j = j + 1)begin
                    if_conv_in[i][j] <= 0;
                end
            end
        end
        IF:begin
            case (size)
                'd0:begin
                    // check 4*4 IF
                    case (x_read%2)
                        'd1:begin
                            if_conv_in[0][0] <= if_conv_in[1][0];
                            if_conv_in[1][0] <= if_conv_in[2][0];
                            if(rw_direction == 0)begin
                                if_conv_in[2][0] <= do_512;
                            end else begin
                                if_conv_in[2][0] <= do_128;
                            end
                            //replicate to finish the sorting
                            if_conv_in[0][2] <= if_conv_in[0][0];
                            if_conv_in[0][3] <= if_conv_in[0][1];
                            if_conv_in[1][2] <= if_conv_in[1][0];
                            if_conv_in[1][3] <= if_conv_in[1][1];
                            if_conv_in[2][2] <= if_conv_in[2][0];
                            if_conv_in[2][3] <= if_conv_in[2][1];
                        end
                        'd0:begin
                            if_conv_in[0][1] <= if_conv_in[1][1];
                            if_conv_in[1][1] <= if_conv_in[2][1];
                            if(rw_direction == 0)begin
                                if_conv_in[2][1] <= do_512;
                            end else begin
                                if_conv_in[2][1] <= do_128;
                            end
                        end 
                    endcase
                end 
                'd1:begin
                    case (x_read%4)
                        'd2:begin
                            if_conv_in[0][1] <= if_conv_in[1][1];
                            if_conv_in[1][1] <= if_conv_in[2][1];
                            if(rw_direction == 0)begin
                                if_conv_in[2][1] <= do_512;
                            end else begin
                                if_conv_in[2][1] <= do_128;
                            end
                        end
                        'd3:begin
                            if_conv_in[0][2] <= if_conv_in[1][2];
                            if_conv_in[1][2] <= if_conv_in[2][2];
                            if(rw_direction == 0)begin
                                if_conv_in[2][2] <= do_512;
                            end else begin
                                if_conv_in[2][2] <= do_128;
                            end
                        end
                        'd0:begin
                            if_conv_in[0][3] <= if_conv_in[1][3];
                            if_conv_in[1][3] <= if_conv_in[2][3];
                            if(rw_direction == 0)begin
                                if_conv_in[2][3] <= do_512;
                            end else begin
                                if_conv_in[2][3] <= do_128;
                            end
                        end
                        'd1:begin
                            if_conv_in[0][0] <= if_conv_in[1][0];
                            if_conv_in[1][0] <= if_conv_in[2][0];
                            if(rw_direction == 0)begin
                                if_conv_in[2][0] <= do_512;
                            end else begin
                                if_conv_in[2][0] <= do_128;
                            end
                        end
                    endcase
                end
                'd2:begin
                    case (x_read%8)
                        'd2:begin
                            if_conv_in[0][1] <= if_conv_in[1][1];
                            if_conv_in[1][1] <= if_conv_in[2][1];
                            if(rw_direction == 0)begin
                                if_conv_in[2][1] <= do_512;
                            end else begin
                                if_conv_in[2][1] <= do_128;
                            end
                        end
                        'd3:begin
                            if_conv_in[0][2] <= if_conv_in[1][2];
                            if_conv_in[1][2] <= if_conv_in[2][2];
                            if(rw_direction == 0)begin
                                if_conv_in[2][2] <= do_512;
                            end else begin
                                if_conv_in[2][2] <= do_128;
                            end
                        end
                        'd4:begin
                            if_conv_in[0][3] <= if_conv_in[1][3];
                            if_conv_in[1][3] <= if_conv_in[2][3];
                            if(rw_direction == 0)begin
                                if_conv_in[2][3] <= do_512;
                            end else begin
                                if_conv_in[2][3] <= do_128;
                            end
                        end
                        'd5:begin
                            if_conv_in[0][4] <= if_conv_in[1][4];
                            if_conv_in[1][4] <= if_conv_in[2][4];
                            if(rw_direction == 0)begin
                                if_conv_in[2][4] <= do_512;
                            end else begin
                                if_conv_in[2][4] <= do_128;
                            end
                        end
                        'd6:begin
                            if_conv_in[0][5] <= if_conv_in[1][5];
                            if_conv_in[1][5] <= if_conv_in[2][5];
                            if(rw_direction == 0)begin
                                if_conv_in[2][5] <= do_512;
                            end else begin
                                if_conv_in[2][5] <= do_128;
                            end
                        end
                        'd7:begin
                            if_conv_in[0][6] <= if_conv_in[1][6];
                            if_conv_in[1][6] <= if_conv_in[2][6];
                            if(rw_direction == 0)begin
                                if_conv_in[2][6] <= do_512;
                            end else begin
                                if_conv_in[2][6] <= do_128;
                            end
                        end
                        'd0:begin
                            if_conv_in[0][7] <= if_conv_in[1][7];
                            if_conv_in[1][7] <= if_conv_in[2][7];
                            if(rw_direction == 0)begin
                                if_conv_in[2][7] <= do_512;
                            end else begin
                                if_conv_in[2][7] <= do_128;
                            end
                        end
                        'd1:begin
                            if_conv_in[0][0] <= if_conv_in[1][0];
                            if_conv_in[1][0] <= if_conv_in[2][0];
                            if(rw_direction == 0)begin
                                if_conv_in[2][0] <= do_512;
                            end else begin
                                if_conv_in[2][0] <= do_128;
                            end
                        end
                    endcase
                end
            endcase
        end
        OUT:begin
            case (size)
                'd0:begin
                    if(!flip_odd)begin
                        case (cnt_out)
                            'd1:begin
                                if_conv_in[0][0] <= if_conv_in[1][0];
                                if_conv_in[1][0] <= if_conv_in[2][0];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][0] <= do_512;
                                end else begin
                                    if_conv_in[2][0] <= do_128;
                                end
                            end 
                            'd2:begin
                                if_conv_in[0][1] <= if_conv_in[1][1];
                                if_conv_in[1][1] <= if_conv_in[2][1];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][1] <= do_512;
                                end else begin
                                    if_conv_in[2][1] <= do_128;
                                end
                            end
                        endcase
                    end else begin
                        case (cnt_out)
                            'd2:begin
                                if_conv_in[0][0] <= if_conv_in[1][0];
                                if_conv_in[1][0] <= if_conv_in[2][0];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][0] <= do_512;
                                end else begin
                                    if_conv_in[2][0] <= do_128;
                                end
                            end 
                            'd1:begin
                                if_conv_in[0][1] <= if_conv_in[1][1];
                                if_conv_in[1][1] <= if_conv_in[2][1];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][1] <= do_512;
                                end else begin
                                    if_conv_in[2][1] <= do_128;
                                end
                            end
                        endcase
                    end
                end 
                'd1:begin
                    if(!flip_odd)begin
                        case (cnt_out)
                            'd1:begin
                                if_conv_in[0][0] <= if_conv_in[1][0];
                                if_conv_in[1][0] <= if_conv_in[2][0];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][0] <= do_512;
                                end else begin
                                    if_conv_in[2][0] <= do_128;
                                end
                            end
                            'd2:begin
                                if_conv_in[0][1] <= if_conv_in[1][1];
                                if_conv_in[1][1] <= if_conv_in[2][1];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][1] <= do_512;
                                end else begin
                                    if_conv_in[2][1] <= do_128;
                                end
                            end
                            'd3:begin
                                if_conv_in[0][2] <= if_conv_in[1][2];
                                if_conv_in[1][2] <= if_conv_in[2][2];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][2] <= do_512;
                                end else begin
                                    if_conv_in[2][2] <= do_128;
                                end
                            end
                            'd4:begin
                                if_conv_in[0][3] <= if_conv_in[1][3];
                                if_conv_in[1][3] <= if_conv_in[2][3];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][3] <= do_512;
                                end else begin
                                    if_conv_in[2][3] <= do_128;
                                end
                            end
                        endcase
                    end else begin
                        // flip
                        case (cnt_out)
                            'd1:begin
                                if_conv_in[0][3] <= if_conv_in[1][3];
                                if_conv_in[1][3] <= if_conv_in[2][3];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][3] <= do_512;
                                end else begin
                                    if_conv_in[2][3] <= do_128;
                                end
                            end
                            'd2:begin
                                if_conv_in[0][2] <= if_conv_in[1][2];
                                if_conv_in[1][2] <= if_conv_in[2][2];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][2] <= do_512;
                                end else begin
                                    if_conv_in[2][2] <= do_128;
                                end
                            end
                            'd3:begin
                                if_conv_in[0][1] <= if_conv_in[1][1];
                                if_conv_in[1][1] <= if_conv_in[2][1];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][1] <= do_512;
                                end else begin
                                    if_conv_in[2][1] <= do_128;
                                end
                            end
                            'd4:begin
                                if_conv_in[0][0] <= if_conv_in[1][0];
                                if_conv_in[1][0] <= if_conv_in[2][0];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][0] <= do_512;
                                end else begin
                                    if_conv_in[2][0] <= do_128;
                                end
                            end
                        endcase
                    end
                end
                'd2:begin
                    // stop and continue condition?
                    if(!flip_odd)begin
                        case (cnt_out)
                            'd1:begin
                                if_conv_in[0][0] <= if_conv_in[1][0];
                                if_conv_in[1][0] <= if_conv_in[2][0];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][0] <= do_512;
                                end else begin
                                    if_conv_in[2][0] <= do_128;
                                end
                            end
                            'd2:begin
                                if_conv_in[0][1] <= if_conv_in[1][1];
                                if_conv_in[1][1] <= if_conv_in[2][1];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][1] <= do_512;
                                end else begin
                                    if_conv_in[2][1] <= do_128;
                                end
                            end
                            'd3:begin
                                if_conv_in[0][2] <= if_conv_in[1][2];
                                if_conv_in[1][2] <= if_conv_in[2][2];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][2] <= do_512;
                                end else begin
                                    if_conv_in[2][2] <= do_128;
                                end
                            end
                            'd4:begin
                                if_conv_in[0][3] <= if_conv_in[1][3];
                                if_conv_in[1][3] <= if_conv_in[2][3];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][3] <= do_512;
                                end else begin
                                    if_conv_in[2][3] <= do_128;
                                end
                            end
                            'd5:begin
                                if_conv_in[0][4] <= if_conv_in[1][4];
                                if_conv_in[1][4] <= if_conv_in[2][4];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][4] <= do_512;
                                end else begin
                                    if_conv_in[2][4] <= do_128;
                                end
                            end
                            'd6:begin
                                if_conv_in[0][5] <= if_conv_in[1][5];
                                if_conv_in[1][5] <= if_conv_in[2][5];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][5] <= do_512;
                                end else begin
                                    if_conv_in[2][5] <= do_128;
                                end
                            end
                            'd7:begin
                                if_conv_in[0][6] <= if_conv_in[1][6];
                                if_conv_in[1][6] <= if_conv_in[2][6];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][6] <= do_512;
                                end else begin
                                    if_conv_in[2][6] <= do_128;
                                end
                            end
                            'd8:begin
                                if_conv_in[0][7] <= if_conv_in[1][7];
                                if_conv_in[1][7] <= if_conv_in[2][7];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][7] <= do_512;
                                end else begin
                                    if_conv_in[2][7] <= do_128;
                                end
                            end
                        endcase
                    end else begin
                        // flip
                        case (cnt_out)
                            'd1:begin
                                if_conv_in[0][7] <= if_conv_in[1][7];
                                if_conv_in[1][7] <= if_conv_in[2][7];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][7] <= do_512;
                                end else begin
                                    if_conv_in[2][7] <= do_128;
                                end
                            end
                            'd2:begin
                                if_conv_in[0][6] <= if_conv_in[1][6];
                                if_conv_in[1][6] <= if_conv_in[2][6];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][6] <= do_512;
                                end else begin
                                    if_conv_in[2][6] <= do_128;
                                end
                            end
                            'd3:begin
                                if_conv_in[0][5] <= if_conv_in[1][5];
                                if_conv_in[1][5] <= if_conv_in[2][5];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][5] <= do_512;
                                end else begin
                                    if_conv_in[2][5] <= do_128;
                                end
                            end
                            'd4:begin
                                if_conv_in[0][4] <= if_conv_in[1][4];
                                if_conv_in[1][4] <= if_conv_in[2][4];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][4] <= do_512;
                                end else begin
                                    if_conv_in[2][4] <= do_128;
                                end
                            end
                            'd5:begin
                                if_conv_in[0][3] <= if_conv_in[1][3];
                                if_conv_in[1][3] <= if_conv_in[2][3];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][3] <= do_512;
                                end else begin
                                    if_conv_in[2][3] <= do_128;
                                end
                            end
                            'd6:begin
                                if_conv_in[0][2] <= if_conv_in[1][2];
                                if_conv_in[1][2] <= if_conv_in[2][2];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][2] <= do_512;
                                end else begin
                                    if_conv_in[2][2] <= do_128;
                                end
                            end
                            'd7:begin
                                if_conv_in[0][1] <= if_conv_in[1][1];
                                if_conv_in[1][1] <= if_conv_in[2][1];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][1] <= do_512;
                                end else begin
                                    if_conv_in[2][1] <= do_128;
                                end
                            end
                            'd8:begin
                                if_conv_in[0][0] <= if_conv_in[1][0];
                                if_conv_in[1][0] <= if_conv_in[2][0];
                                if(rw_direction == 0)begin
                                    if_conv_in[2][0] <= do_512;
                                end else begin
                                    if_conv_in[2][0] <= do_128;
                                end
                            end
                        endcase
                    end
                end
            endcase
        end
        default:begin
            for(i = 0; i < 3; i = i + 1) begin
                for(j = 0; j < 8; j = j + 1)begin
                    if_conv_in[i][j] <= 0;
                end
            end
        end
    endcase
end

mac MAC(.in1(data), .in2(kernel_temp), .in3(out_temp_choice), .neg_flag(neg_odd), .out(ns_out_temp));
// out_temp_choice
always @(*) begin
    if(cnt_20_odd_flag)begin
        out_temp_choice = out_temp[1];
    end else begin
        out_temp_choice = out_temp[0];
    end
end
always @(*) begin
    data = 0;
    kernel_temp = 0;
    case (size)
        'd0:begin
            if(!flip_odd)begin
                case (cnt_acc)
                    'd0:begin
                        if(cs == OUT)begin
                            case (cnt_20)
                                'd0:begin
                                    case (x_read)
                                        // 0th output
                                        'd2:begin
                                            data = if_conv_in[2][0][15:8];
                                            kernel_temp = kernel[4];
                                        end
                                        'd3:begin
                                            data = if_conv_in[2][0][7:0];
                                            kernel_temp = kernel[5];
                                        end
                                        'd4:begin
                                            data = if_conv_in[2][0][15:8];
                                            kernel_temp = kernel[7];
                                        end
                                        'd5:begin
                                            data = if_conv_in[2][0][7:0];
                                            kernel_temp = kernel[8];
                                        end
                                    endcase
                                end
                                // 1st output :6 elements (save 6 data in a row, notice index is different from 8*8 and 16*16)
                                'd14:begin
                                    data = if_conv_in[0][0][15:8];
                                    kernel_temp = kernel[3];
                                end
                                'd15:begin
                                    data = if_conv_in[0][0][7:0];
                                    kernel_temp = kernel[4];
                                end
                                'd16:begin
                                    data = if_conv_in[1][0][15:8];
                                    kernel_temp = kernel[6];
                                end
                                'd17:begin
                                    data = if_conv_in[1][0][7:0];
                                    kernel_temp = kernel[7];
                                end
                                'd18:begin
                                    data = if_conv_in[0][1][15:8];
                                    kernel_temp = kernel[5];
                                end
                                'd19:begin
                                    data = if_conv_in[1][1][15:8];
                                    kernel_temp = kernel[8];
                                end
                            endcase
                        end
                    end
                    'd1:begin
                        // 6 elements
                        case(cnt_20)
                            'd14:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[6];
                            end
                            'd16:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd18:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[8];
                        end
                        endcase
                    end
                    'd2:begin
                        // top right
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[6];
                            end
                            'd19:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[7];
                            end
                        endcase
                    end
                    'd3, 'd7:begin
                        // 6 elements
                        case(cnt_20)
                            'd14:begin
                                data = if_conv_in[0][0][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd15:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd16:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd18:begin
                                data = if_conv_in[2][0][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[8];
                            end
                        endcase
                    end
                    // 4,5,8,9 :9 elements
                    'd4, 'd8:begin
                        case(cnt_20)
                            'd11:begin
                                data = if_conv_in[0][0][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd12:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd13:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd14:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd17:begin
                                data = if_conv_in[2][0][15:8];
                                kernel_temp = kernel[6];
                            end
                            'd18:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[8];
                            end
                        endcase
                    end
                    'd5, 'd9:begin
                        case(cnt_20)
                            'd11:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd12:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd13:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd14:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd17:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[6];
                            end
                            'd18:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[8];
                            end
                        endcase
                    end
                    'd6:begin
                        // 6 elements
                        case(cnt_20)
                            'd14:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[6];
                            end
                            'd19:begin
                                // pushed 
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[7];
                            end
                        endcase
                    end
                    'd10:begin
                        // 6 elements
                        case(cnt_20)
                            'd14:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[6];
                            end
                            'd19:begin
                                // pushed 
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[7];
                            end
                        endcase
                    end
                    'd11:begin
                        // bottem left
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd18:begin
                                data = if_conv_in[2][0][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[5];
                            end
                        endcase
                    end
                    'd12:begin
                        case(cnt_20)
                            'd14:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd17:begin
                                data = if_conv_in[2][0][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd18:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[5];
                            end
                        endcase
                    end
                    'd13:begin
                        case(cnt_20)
                            'd14:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd17:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd18:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[5];
                            end
                        endcase
                    end
                    'd14:begin
                        // bottem right
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd17:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd18:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[4];
                            end
                        endcase
                    end
                endcase
            end else begin
                // horizontal flip
                case (cnt_acc)
                    'd0:begin
                        if(cs == OUT)begin
                            case (cnt_20)
                                'd0:begin
                                    case (x_read)
                                        // 0th output
                                        'd3:begin
                                            data = if_conv_in[2][1][15:8];
                                            kernel_temp = kernel[5];
                                        end
                                        'd2:begin
                                            data = if_conv_in[2][1][7:0];
                                            kernel_temp = kernel[4];
                                        end
                                        'd5:begin
                                            data = if_conv_in[2][1][15:8];
                                            kernel_temp = kernel[8];
                                        end
                                        'd4:begin
                                            data = if_conv_in[2][1][7:0];
                                            kernel_temp = kernel[7];
                                        end
                                    endcase
                                end
                                // 1st output :6 elements (save 6 data in a row, notice index is different from 8*8 and 16*16)
                                'd14:begin
                                    data = if_conv_in[0][0][7:0];
                                    kernel_temp = kernel[5];
                                end
                                'd15:begin
                                    data = if_conv_in[0][1][15:8];
                                    kernel_temp = kernel[4];
                                end
                                'd16:begin
                                    data = if_conv_in[0][1][7:0];
                                    kernel_temp = kernel[3];
                                end
                                'd17:begin
                                    data = if_conv_in[1][0][7:0];
                                    kernel_temp = kernel[8];
                                end
                                'd18:begin
                                    data = if_conv_in[1][1][15:8];
                                    kernel_temp = kernel[7];
                                end
                                'd19:begin
                                    data = if_conv_in[1][1][7:0];
                                    kernel_temp = kernel[6];
                                end
                            endcase
                        end
                    end
                    'd1:begin
                        // 6 elements
                        case(cnt_20)
                            'd14:begin
                                data = if_conv_in[0][0][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[8];
                            end
                            'd18:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[6];
                        end
                        endcase
                    end
                    'd2:begin
                        // top left
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[0][0][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd18:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd3, 'd7:begin
                        // 6 elements
                        case(cnt_20)
                            'd14:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd17:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[8];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[7];
                            end
                        endcase
                    end
                    // 4,5,8,9 :9 elements
                    'd4, 'd8:begin
                        case(cnt_20)
                            'd11:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd12:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd13:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd14:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[8];
                            end
                            'd18:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd5, 'd9:begin
                        case(cnt_20)
                            'd11:begin
                                data = if_conv_in[0][0][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd12:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd13:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd14:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[2][0][15:8];
                                kernel_temp = kernel[8];
                            end
                            'd18:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    //probably wrong here!!!
                    'd6:begin
                        // 6 elements
                        case(cnt_20)
                            'd14:begin
                                data = if_conv_in[0][0][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd15:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd16:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd18:begin
                                data = if_conv_in[2][0][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                // pushed !!!
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd10:begin
                        // 6 elements
                        case(cnt_20)
                            'd14:begin
                                data = if_conv_in[0][0][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd15:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd16:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd18:begin
                                data = if_conv_in[2][0][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                // pushed 
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd11:begin
                        // bottem right
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd17:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd18:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[4];
                            end
                        endcase
                    end
                    'd12:begin
                        case(cnt_20)
                            'd14:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd17:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd18:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    'd13:begin
                        case(cnt_20)
                            'd14:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd17:begin
                                data = if_conv_in[2][0][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd18:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    'd14:begin
                        // bottem left
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd18:begin
                                data = if_conv_in[2][0][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                endcase
            end
        end 
        'd1:begin
            if(!flip_odd)begin
                case (cnt_acc)
                    'd0:begin
                        if(cs == OUT)begin
                            case (cnt_20)
                                'd0:begin
                                    case (x_read)
                                        // top left
                                        // 0th output
                                        'd4:begin
                                            data = if_conv_in[2][0][15:8];
                                            kernel_temp = kernel[4];
                                        end
                                        'd5:begin
                                            data = if_conv_in[2][0][7:0];
                                            kernel_temp = kernel[5];
                                        end
                                        'd6:begin
                                            data = if_conv_in[2][0][15:8];
                                            kernel_temp = kernel[7];
                                        end
                                        'd7:begin
                                            data = if_conv_in[2][0][7:0];
                                            kernel_temp = kernel[8];
                                        end
                                        default:begin
                                            data = 0;
                                            kernel_temp = 0;
                                        end
                                    endcase
                                end
                                // 1st output
                                'd14:begin
                                    data = if_conv_in[1][0][15:8];
                                    kernel_temp = kernel[3];
                                end
                                'd15:begin
                                    data = if_conv_in[1][0][7:0];
                                    kernel_temp = kernel[4];
                                end
                                'd16:begin
                                    data = if_conv_in[2][0][15:8];
                                    kernel_temp = kernel[6];
                                end
                                'd17:begin
                                    data = if_conv_in[2][0][7:0];
                                    kernel_temp = kernel[7];
                                end
                                'd18:begin
                                    data = if_conv_in[1][1][15:8];
                                    kernel_temp = kernel[5];
                                end
                                'd19:begin
                                    data = if_conv_in[2][1][15:8];
                                    kernel_temp = kernel[8];
                                end
                                default:begin
                                    data = 0;
                                    kernel_temp = 0;
                                end
                            endcase
                        end else begin
                            data = 0;
                            kernel_temp = 0;
                        end
                    end
                    'd6:begin
                        // top right 4 elements
                        // care reading
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[2][3][15:8];
                                kernel_temp = kernel[6];
                            end
                            'd19:begin
                                data = if_conv_in[2][3][7:0];
                                kernel_temp = kernel[7];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end 
                        endcase
                    end
                    'd55:begin
                        //bottom left
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[0][0][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd18:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[5];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end 
                        endcase
                    end
                    'd62:begin
                        //bottom right
                        //care pushing blank
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[0][3][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd17:begin
                                data = if_conv_in[0][3][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd18:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd19:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[4];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end 
                        endcase
                    end
                    // 1 ~ 5 :6 elements
                    'd1:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[6];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd18:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[8];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd2:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[6];
                            end
                            'd17:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd19:begin
                                data = if_conv_in[2][2][15:8];
                                kernel_temp = kernel[8];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd3:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[6];
                            end
                            'd16:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd18:begin
                                data = if_conv_in[2][2][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][2][7:0];
                                kernel_temp = kernel[8];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd4:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][2][15:8];
                                kernel_temp = kernel[6];
                            end
                            'd17:begin
                                data = if_conv_in[2][2][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd19:begin
                                data = if_conv_in[2][3][15:8];
                                kernel_temp = kernel[8];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd5:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[2][2][7:0];
                                kernel_temp = kernel[6];
                            end
                            'd16:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd18:begin
                                data = if_conv_in[2][3][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][3][7:0];
                                kernel_temp = kernel[8];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    // 56 ~ 61 :6 elements
                    'd56:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][0][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd19:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[5];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd57:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd16:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd18:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[5];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd58:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][2][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd19:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[5];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd59:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd16:begin
                                data = if_conv_in[0][2][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][2][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd18:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[5];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd60:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][2][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[0][2][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][3][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd19:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[5];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd61:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][2][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd16:begin
                                data = if_conv_in[0][3][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][3][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd18:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[5];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    default:begin
                        case (cnt_acc%8)
                            'd7:begin
                                // 6 elements
                                case (cnt_20)
                                    'd14:begin
                                        // not pushed
                                        data = if_conv_in[1][0][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd15:begin
                                        // not pushed
                                        data = if_conv_in[1][0][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd16:begin
                                        // pushed
                                        data = if_conv_in[1][0][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd17:begin
                                        // pushed
                                        data = if_conv_in[1][0][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][0][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][0][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end 
                            'd6:begin
                                // 6 elements
                                case (cnt_20)
                                    'd14:begin
                                        data = if_conv_in[0][3][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd15:begin
                                        data = if_conv_in[0][3][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][3][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[1][3][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][3][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][3][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end
                            // 0 ~ 5: 9 elements
                            'd0:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][0][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][0][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][1][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][0][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][0][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][1][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][0][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][0][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][1][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end
                            'd1:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][0][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][1][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][1][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][0][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][1][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][1][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][0][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][1][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][1][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end
                            'd2:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][1][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][1][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][2][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][1][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][1][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][2][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][1][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][1][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][2][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end
                            'd3:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][1][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][2][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][2][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][1][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][2][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][2][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][1][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][2][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][2][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end
                            'd4:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][2][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][2][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][3][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][2][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][2][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][3][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][2][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][2][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][3][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end
                            'd5:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][2][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][3][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][3][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][2][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][3][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][3][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][2][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][3][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][3][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                endcase
            end else begin
                // horizontal flip
                case (cnt_acc)
                    'd0:begin
                        if(cs == OUT)begin
                            case(cnt_20)
                                'd0:begin
                                    case (x_read)
                                        // top right
                                        'd7:begin
                                            data = if_conv_in[2][3][15:8];
                                            kernel_temp = kernel[5];
                                        end
                                        'd6:begin
                                            data = if_conv_in[2][3][7:0];
                                            kernel_temp = kernel[4];
                                        end
                                        'd5:begin
                                            data = if_conv_in[2][3][15:8];
                                            kernel_temp = kernel[8];
                                        end
                                        'd4:begin
                                            data = if_conv_in[2][3][7:0];
                                            kernel_temp = kernel[7];
                                        end
                                        default:begin
                                            data = 0;
                                            kernel_temp = 0;
                                        end
                                    endcase
                                end
                                'd14:begin
                                    data = if_conv_in[1][2][7:0];
                                    kernel_temp = kernel[5];
                                end
                                'd15:begin
                                    data = if_conv_in[2][2][7:0];
                                    kernel_temp = kernel[8];
                                end
                                'd16:begin
                                    data = if_conv_in[1][3][15:8];
                                    kernel_temp = kernel[4];
                                end
                                'd17:begin
                                    data = if_conv_in[1][3][7:0];
                                    kernel_temp = kernel[3];
                                end
                                'd18:begin
                                    data = if_conv_in[2][3][15:8];
                                    kernel_temp = kernel[7];
                                end
                                'd19:begin
                                    data = if_conv_in[2][3][7:0];
                                    kernel_temp = kernel[6];
                                end
                                default:begin
                                    data = 0;
                                    kernel_temp = 0;
                                end
                                endcase
                        end else begin
                            data = 0;
                            kernel_temp = 0;
                        end
                    end
                    'd6:begin
                        // top left 
                        // 4 elements
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd18:begin
                                data = if_conv_in[2][0][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[6];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end 
                        endcase
                    end
                    'd55:begin
                        //bottom right
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[0][3][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd17:begin
                                data = if_conv_in[0][3][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd18:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd19:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[4];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end 
                        endcase
                    end
                    'd62:begin
                        //bottom left
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[0][0][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd18:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[3];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end 
                        endcase
                    end
                    // 1 ~ 5 :6 elements
                    'd1:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][2][15:8];
                                kernel_temp = kernel[8];
                            end
                            'd17:begin
                                data = if_conv_in[2][2][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd19:begin
                                data = if_conv_in[2][3][15:8];
                                kernel_temp = kernel[6];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd2:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[8];
                            end
                            'd16:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd18:begin
                                data = if_conv_in[2][2][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][2][7:0];
                                kernel_temp = kernel[6];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd3:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[8];
                            end
                            'd17:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd19:begin
                                data = if_conv_in[2][2][15:8];
                                kernel_temp = kernel[6];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd4:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[8];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd18:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[6];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd5:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][0][15:8];
                                kernel_temp = kernel[8];
                            end
                            'd17:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[6];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    // 56 ~ 61 :6 elements
                    'd56:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][2][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd16:begin
                                data = if_conv_in[0][3][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][3][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd18:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[3];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd57:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][2][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[0][2][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd17:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][3][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd19:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[3];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd58:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd16:begin
                                data = if_conv_in[0][2][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][2][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd18:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[3];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd59:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd17:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][2][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd19:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[3];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd60:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd16:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd18:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[3];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd61:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][0][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd17:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd19:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[3];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    default:begin
                        case (cnt_acc%8)
                            'd7:begin
                                // 6 elements
                                case (cnt_20)
                                    'd14:begin
                                        // not pushed
                                        data = if_conv_in[1][3][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd15:begin
                                        // not pushed
                                        data = if_conv_in[1][3][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][3][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[1][3][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][3][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][3][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end 
                            'd6:begin
                                // 6 elements
                                case (cnt_20)
                                    'd14:begin
                                        data = if_conv_in[0][0][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd15:begin
                                        data = if_conv_in[0][0][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][0][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd17:begin
                                        data = if_conv_in[1][0][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][0][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][0][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end
                            // 1 ~ 6: 9 elements
                            'd0:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][2][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][3][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][3][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][2][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][3][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][3][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][2][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][3][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][3][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end
                            'd1:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][2][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][2][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][3][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][2][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][2][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][3][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][2][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][2][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][3][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end
                            'd2:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][1][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][2][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][2][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][1][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][2][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][2][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][1][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][2][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][2][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end
                            'd3:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][1][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][1][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][2][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][1][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][1][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][2][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][1][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][1][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][2][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end
                            'd4:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][0][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][1][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][1][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][0][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][1][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][1][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][0][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][1][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][1][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end
                            'd5:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][0][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][0][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][1][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][0][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][0][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][1][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][0][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][0][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][1][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                endcase
            end
        end
        'd2:begin
            if(!flip_odd)begin
                case (cnt_acc)
                    // corner
                    'd0:begin
                        if(cs == OUT)begin
                            case(cnt_20)
                                'd0:begin
                                    case (x_read)
                                        // top left
                                        'd8:begin
                                            data = if_conv_in[2][0][15:8];
                                            kernel_temp = kernel[4];
                                        end
                                        'd9:begin
                                            data = if_conv_in[2][0][7:0];
                                            kernel_temp = kernel[5];
                                        end
                                        'd10:begin
                                            data = if_conv_in[2][0][15:8];
                                            kernel_temp = kernel[7];
                                        end
                                        'd11:begin
                                            data = if_conv_in[2][0][7:0];
                                            kernel_temp = kernel[8];
                                        end
                                    endcase
                                end
                                // 1st output
                                'd14:begin
                                    data = if_conv_in[1][0][15:8];
                                    kernel_temp = kernel[3];
                                end
                                'd15:begin
                                    data = if_conv_in[1][0][7:0];
                                    kernel_temp = kernel[4];
                                end
                                'd16:begin
                                    data = if_conv_in[2][0][15:8];
                                    kernel_temp = kernel[6];
                                end
                                'd17:begin
                                    data = if_conv_in[2][0][7:0];
                                    kernel_temp = kernel[7];
                                end
                                'd18:begin
                                    data = if_conv_in[1][1][15:8];
                                    kernel_temp = kernel[5];
                                end
                                'd19:begin
                                    data = if_conv_in[2][1][15:8];
                                    kernel_temp = kernel[8];
                                end
                            endcase
                        end
                    end
                    'd14:begin
                        // top right 4 elements
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[1][7][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[1][7][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[2][7][15:8];
                                kernel_temp = kernel[6];
                            end
                            'd19:begin
                                data = if_conv_in[2][7][7:0];
                                kernel_temp = kernel[7];
                            end
                        endcase
                    end
                    'd239:begin
                        //bottom left
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[0][0][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd18:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[5];
                            end
                        endcase
                    end
                    'd254:begin
                        //bottom right
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[0][7][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd17:begin
                                data = if_conv_in[0][7][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd18:begin
                                data = if_conv_in[1][7][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd19:begin
                                data = if_conv_in[1][7][7:0];
                                kernel_temp = kernel[4];
                            end
                        endcase
                    end
                    // top side
                    'd1:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[6];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd18:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[8];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd2:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[6];
                            end
                            'd17:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd19:begin
                                data = if_conv_in[2][2][15:8];
                                kernel_temp = kernel[8];
                            end
                        endcase
                    end
                    'd3:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[6];
                            end
                            'd16:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd18:begin
                                data = if_conv_in[2][2][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][2][7:0];
                                kernel_temp = kernel[8];
                            end
                        endcase
                    end
                    'd4:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][2][15:8];
                                kernel_temp = kernel[6];
                            end
                            'd17:begin
                                data = if_conv_in[2][2][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd19:begin
                                data = if_conv_in[2][3][15:8];
                                kernel_temp = kernel[8];
                            end
                        endcase
                    end
                    'd5:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[2][2][7:0];
                                kernel_temp = kernel[6];
                            end
                            'd16:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd18:begin
                                data = if_conv_in[2][3][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][3][7:0];
                                kernel_temp = kernel[8];
                            end
                        endcase
                    end
                    'd6:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][3][15:8];
                                kernel_temp = kernel[6];
                            end
                            'd17:begin
                                data = if_conv_in[2][3][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][4][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd19:begin
                                data = if_conv_in[2][4][15:8];
                                kernel_temp = kernel[8];
                            end
                        endcase
                    end
                    'd7:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[2][3][7:0];
                                kernel_temp = kernel[6];
                            end
                            'd16:begin
                                data = if_conv_in[1][4][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][4][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd18:begin
                                data = if_conv_in[2][4][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][4][7:0];
                                kernel_temp = kernel[8];
                            end
                        endcase
                    end
                    'd8:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][4][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[1][4][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][4][15:8];
                                kernel_temp = kernel[6];
                            end
                            'd17:begin
                                data = if_conv_in[2][4][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][5][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd19:begin
                                data = if_conv_in[2][5][15:8];
                                kernel_temp = kernel[8];
                            end
                        endcase
                    end
                    'd9:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][4][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[2][4][7:0];
                                kernel_temp = kernel[6];
                            end
                            'd16:begin
                                data = if_conv_in[1][5][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][5][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd18:begin
                                data = if_conv_in[2][5][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][5][7:0];
                                kernel_temp = kernel[8];
                            end
                        endcase
                    end
                    'd10:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][5][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[1][5][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][5][15:8];
                                kernel_temp = kernel[6];
                            end
                            'd17:begin
                                data = if_conv_in[2][5][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][6][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd19:begin
                                data = if_conv_in[2][6][15:8];
                                kernel_temp = kernel[8];
                            end
                        endcase
                    end
                    'd11:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][5][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[2][5][7:0];
                                kernel_temp = kernel[6];
                            end
                            'd16:begin
                                data = if_conv_in[1][6][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][6][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd18:begin
                                data = if_conv_in[2][6][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][6][7:0];
                                kernel_temp = kernel[8];
                            end
                        endcase
                    end
                    'd12:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][6][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[1][6][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][6][15:8];
                                kernel_temp = kernel[6];
                            end
                            'd17:begin
                                data = if_conv_in[2][6][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][7][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd19:begin
                                data = if_conv_in[2][7][15:8];
                                kernel_temp = kernel[8];
                            end
                        endcase
                    end
                    'd13:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][6][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd15:begin
                                data = if_conv_in[2][6][7:0];
                                kernel_temp = kernel[6];
                            end
                            'd16:begin
                                data = if_conv_in[1][7][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][7][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd18:begin
                                data = if_conv_in[2][7][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][7][7:0];
                                kernel_temp = kernel[8];
                            end
                        endcase
                    end
                    // bottom side
                    'd240:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][0][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd19:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[5];
                            end
                        endcase
                    end
                    'd241:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd16:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd18:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[5];
                            end
                        endcase
                    end
                    'd242:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][2][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd19:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[5];
                            end
                        endcase
                    end
                    'd243:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd16:begin
                                data = if_conv_in[0][2][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][2][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd18:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[5];
                            end
                        endcase
                    end
                    'd244:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][2][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[0][2][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][3][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd19:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[5];
                            end
                        endcase
                    end
                    'd245:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][2][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd16:begin
                                data = if_conv_in[0][3][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][3][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd18:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[5];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd246:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][3][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[0][3][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][4][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd19:begin
                                data = if_conv_in[1][4][15:8];
                                kernel_temp = kernel[5];
                            end
                        endcase
                    end
                    'd247:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][3][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd16:begin
                                data = if_conv_in[0][4][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][4][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd18:begin
                                data = if_conv_in[1][4][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][4][7:0];
                                kernel_temp = kernel[5];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd248:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][4][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[0][4][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][4][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[1][4][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][5][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd19:begin
                                data = if_conv_in[1][5][15:8];
                                kernel_temp = kernel[5];
                            end
                        endcase
                    end
                    'd249:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][4][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[1][4][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd16:begin
                                data = if_conv_in[0][5][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][5][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd18:begin
                                data = if_conv_in[1][5][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][5][7:0];
                                kernel_temp = kernel[5];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd250:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][5][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[0][5][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][5][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[1][5][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][6][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd19:begin
                                data = if_conv_in[1][6][15:8];
                                kernel_temp = kernel[5];
                            end
                        endcase
                    end
                    'd251:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][5][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[1][5][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd16:begin
                                data = if_conv_in[0][6][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][6][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd18:begin
                                data = if_conv_in[1][6][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][6][7:0];
                                kernel_temp = kernel[5];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    'd252:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][6][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[0][6][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][6][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd17:begin
                                data = if_conv_in[1][6][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][7][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd19:begin
                                data = if_conv_in[1][7][15:8];
                                kernel_temp = kernel[5];
                            end
                        endcase
                    end
                    'd253:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][6][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd15:begin
                                data = if_conv_in[1][6][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd16:begin
                                data = if_conv_in[0][7][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][7][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd18:begin
                                data = if_conv_in[1][7][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][7][7:0];
                                kernel_temp = kernel[5];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end
                        endcase
                    end
                    default:begin
                        case (cnt_acc%16)
                            'd15:begin
                                // 6 elements
                                case (cnt_20)
                                    'd14:begin
                                        data = if_conv_in[0][0][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd15:begin
                                        data = if_conv_in[0][0][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][0][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd17:begin
                                        data = if_conv_in[1][0][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][0][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][0][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                endcase
                            end
                            'd14:begin
                                // 6 elements
                                case (cnt_20)
                                    'd14:begin
                                        data = if_conv_in[0][7][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd15:begin
                                        data = if_conv_in[0][7][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][7][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[1][7][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][7][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][7][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    default:begin
                                        data = 0;
                                        kernel_temp = 0;
                                    end
                                endcase
                            end
                            //9 elements
                            'd0:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][0][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][0][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][1][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][0][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][0][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][1][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][0][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][0][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][1][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                endcase
                            end
                            'd1:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][0][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][1][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][1][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][0][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][1][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][1][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][0][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][1][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][1][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                endcase
                            end
                            'd2:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][1][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][1][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][2][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][1][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][1][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][2][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][1][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][1][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][2][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                endcase
                            end
                            'd3:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][1][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][2][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][2][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][1][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][2][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][2][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][1][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][2][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][2][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                endcase
                            end
                            'd4:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][2][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][2][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][3][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][2][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][2][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][3][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][2][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][2][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][3][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                endcase
                            end
                            'd5:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][2][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][3][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][3][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][2][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][3][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][3][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][2][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][3][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][3][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                endcase
                            end
                            'd6:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][3][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][3][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][4][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][3][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][3][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][4][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][3][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][3][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][4][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                endcase
                            end
                            'd7:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][3][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][4][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][4][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][3][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][4][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][4][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][3][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][4][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][4][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                endcase
                            end
                            'd8:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][4][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][4][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][5][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][4][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][4][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][5][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][4][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][4][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][5][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                endcase
                            end
                            'd9:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][4][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][5][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][5][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][4][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][5][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][5][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][4][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][5][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][5][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                endcase
                            end
                            'd10:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][5][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][5][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][6][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][5][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][5][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][6][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][5][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][5][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][6][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                endcase
                            end
                            'd11:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][5][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][6][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][6][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][5][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][6][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][6][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][5][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][6][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][6][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                endcase
                            end
                            'd12:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][6][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][6][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][7][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][6][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][6][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][7][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][6][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][6][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][7][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                endcase
                            end
                            'd13:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][6][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][7][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][7][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][6][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][7][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][7][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][6][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][7][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][7][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                endcase
                            end
                        endcase
                    end
                endcase
            end else begin
                // horizontal flip
                case (cnt_acc)
                    // corners
                    'd0:begin
                        if(cs == OUT)begin
                            case(cnt_20)
                                'd0:begin
                                    case (x_read)
                                        // top right
                                        'd15:begin
                                            data = if_conv_in[2][7][15:8];
                                            kernel_temp = kernel[5];
                                        end
                                        'd14:begin
                                            data = if_conv_in[2][7][7:0];
                                            kernel_temp = kernel[4];
                                        end
                                        'd13:begin
                                            data = if_conv_in[2][7][15:8];
                                            kernel_temp = kernel[8];
                                        end
                                        'd12:begin
                                            data = if_conv_in[2][7][7:0];
                                            kernel_temp = kernel[7];
                                        end
                                    endcase
                                end
                                // 1st output
                                'd14:begin
                                    data = if_conv_in[1][6][7:0];
                                    kernel_temp = kernel[5];
                                end
                                'd15:begin
                                    data = if_conv_in[2][6][7:0];
                                    kernel_temp = kernel[8];
                                end
                                'd16:begin
                                    data = if_conv_in[1][7][15:8];
                                    kernel_temp = kernel[4];
                                end
                                'd17:begin
                                    data = if_conv_in[1][7][7:0];
                                    kernel_temp = kernel[3];
                                end
                                'd18:begin
                                    data = if_conv_in[2][7][15:8];
                                    kernel_temp = kernel[7];
                                end
                                'd19:begin
                                    data = if_conv_in[2][7][7:0];
                                    kernel_temp = kernel[6];
                                end
                            endcase
                        end
                    end
                    'd14:begin
                        // top left 
                        // 4 elements
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd18:begin
                                data = if_conv_in[2][0][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd254:begin
                        //bottom left
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[0][0][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd18:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[3];
                            end
                            default:begin
                                data = 0;
                                kernel_temp = 0;
                            end 
                        endcase
                    end
                    'd239:begin
                        //bottom right
                        case (cnt_20)
                            'd16:begin
                                data = if_conv_in[0][7][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd17:begin
                                data = if_conv_in[0][7][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd18:begin
                                data = if_conv_in[1][7][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd19:begin
                                data = if_conv_in[1][7][7:0];
                                kernel_temp = kernel[4];
                            end
                        endcase
                    end
                    //top side
                    'd1:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][6][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[1][6][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][6][15:8];
                                kernel_temp = kernel[8];
                            end
                            'd17:begin
                                data = if_conv_in[2][6][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][7][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd19:begin
                                data = if_conv_in[2][7][15:8];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd2:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][5][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[2][5][7:0];
                                kernel_temp = kernel[8];
                            end
                            'd16:begin
                                data = if_conv_in[1][6][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][6][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd18:begin
                                data = if_conv_in[2][6][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][6][7:0];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd3:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][5][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[1][5][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][5][15:8];
                                kernel_temp = kernel[8];
                            end
                            'd17:begin
                                data = if_conv_in[2][5][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][6][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd19:begin
                                data = if_conv_in[2][6][15:8];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd4:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][4][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[2][4][7:0];
                                kernel_temp = kernel[8];
                            end
                            'd16:begin
                                data = if_conv_in[1][5][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][5][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd18:begin
                                data = if_conv_in[2][5][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][5][7:0];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd5:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][4][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[1][4][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][4][15:8];
                                kernel_temp = kernel[8];
                            end
                            'd17:begin
                                data = if_conv_in[2][4][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][5][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd19:begin
                                data = if_conv_in[2][5][15:8];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd6:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[2][3][7:0];
                                kernel_temp = kernel[8];
                            end
                            'd16:begin
                                data = if_conv_in[1][4][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][4][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd18:begin
                                data = if_conv_in[2][4][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][4][7:0];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd7:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][3][15:8];
                                kernel_temp = kernel[8];
                            end
                            'd17:begin
                                data = if_conv_in[2][3][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][4][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd19:begin
                                data = if_conv_in[2][4][15:8];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd8:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[2][2][7:0];
                                kernel_temp = kernel[8];
                            end
                            'd16:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd18:begin
                                data = if_conv_in[2][3][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][3][7:0];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd9:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][2][15:8];
                                kernel_temp = kernel[8];
                            end
                            'd17:begin
                                data = if_conv_in[2][2][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd19:begin
                                data = if_conv_in[2][3][15:8];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd10:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[8];
                            end
                            'd16:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd18:begin
                                data = if_conv_in[2][2][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][2][7:0];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd11:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[8];
                            end
                            'd17:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd19:begin
                                data = if_conv_in[2][2][15:8];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd12:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[8];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd17:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[3];
                            end
                            'd18:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[7];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][7:0];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd13:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd15:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd16:begin
                                data = if_conv_in[2][0][15:8];
                                kernel_temp = kernel[8];
                            end
                            'd17:begin
                                data = if_conv_in[2][0][7:0];
                                kernel_temp = kernel[7];
                            end
                            'd18:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[3];
                            end
                            'd19:begin
                                data = if_conv_in[2][1][15:8];
                                kernel_temp = kernel[6];
                            end
                        endcase
                    end
                    'd240:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][6][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[1][6][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd16:begin
                                data = if_conv_in[0][7][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][7][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd18:begin
                                data = if_conv_in[1][7][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][7][7:0];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    'd241:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][6][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[0][6][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][6][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd17:begin
                                data = if_conv_in[1][6][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][7][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd19:begin
                                data = if_conv_in[1][7][15:8];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    'd242:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][5][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[1][5][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd16:begin
                                data = if_conv_in[0][6][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][6][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd18:begin
                                data = if_conv_in[1][6][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][6][7:0];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    'd243:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][5][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[0][5][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][5][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd17:begin
                                data = if_conv_in[1][5][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][6][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd19:begin
                                data = if_conv_in[1][6][15:8];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    'd244:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][4][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[1][4][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd16:begin
                                data = if_conv_in[0][5][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][5][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd18:begin
                                data = if_conv_in[1][5][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][5][7:0];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    'd245:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][4][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[0][4][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][4][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd17:begin
                                data = if_conv_in[1][4][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][5][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd19:begin
                                data = if_conv_in[1][5][15:8];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    'd246:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][3][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd16:begin
                                data = if_conv_in[0][4][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][4][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd18:begin
                                data = if_conv_in[1][4][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][4][7:0];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    'd247:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][3][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[0][3][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd17:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][4][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd19:begin
                                data = if_conv_in[1][4][15:8];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    'd248:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][2][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd16:begin
                                data = if_conv_in[0][3][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][3][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd18:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][3][7:0];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    'd249:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][2][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[0][2][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd17:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][3][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd19:begin
                                data = if_conv_in[1][3][15:8];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    'd250:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd16:begin
                                data = if_conv_in[0][2][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][2][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd18:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][2][7:0];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    'd251:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd17:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][2][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd19:begin
                                data = if_conv_in[1][2][15:8];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    'd252:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[5];
                            end
                            'd16:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[1];
                            end
                            'd17:begin
                                data = if_conv_in[0][1][7:0];
                                kernel_temp = kernel[0];
                            end
                            'd18:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[4];
                            end
                            'd19:begin
                                data = if_conv_in[1][1][7:0];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    'd253:begin
                        case (cnt_20)
                            'd14:begin
                                data = if_conv_in[0][0][15:8];
                                kernel_temp = kernel[2];
                            end
                            'd15:begin
                                data = if_conv_in[0][0][7:0];
                                kernel_temp = kernel[1];
                            end
                            'd16:begin
                                data = if_conv_in[1][0][15:8];
                                kernel_temp = kernel[5];
                            end
                            'd17:begin
                                data = if_conv_in[1][0][7:0];
                                kernel_temp = kernel[4];
                            end
                            'd18:begin
                                data = if_conv_in[0][1][15:8];
                                kernel_temp = kernel[0];
                            end
                            'd19:begin
                                data = if_conv_in[1][1][15:8];
                                kernel_temp = kernel[3];
                            end
                        endcase
                    end
                    default:begin
                        case (cnt_acc%16)
                            // right side
                            'd15:begin
                                case (cnt_20)
                                    'd14:begin
                                        data = if_conv_in[0][7][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd15:begin
                                        // not pushed
                                        data = if_conv_in[0][7][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][7][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd17:begin
                                        data = if_conv_in[1][7][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][7][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][7][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                endcase
                            end
                            // left side
                            'd14:begin
                                case (cnt_20)
                                    'd14:begin
                                        data = if_conv_in[0][0][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd15:begin
                                        data = if_conv_in[0][0][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][0][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd17:begin
                                        data = if_conv_in[1][0][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][0][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][0][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                endcase
                            end
                            // 9 elements
                            'd0:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][6][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][7][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][7][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][6][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][7][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][7][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][6][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][7][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][7][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                endcase
                            end
                            'd1:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][6][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][6][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][7][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][6][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][6][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][7][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][6][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][6][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][7][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                endcase
                            end
                            'd2:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][5][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][6][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][6][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][5][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][6][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][6][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][5][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][6][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][6][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                endcase
                            end
                            'd3:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][5][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][5][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][6][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][5][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][5][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][6][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][5][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][5][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][6][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                endcase
                            end
                            'd4:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][4][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][5][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][5][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][4][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][5][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][5][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][4][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][5][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][5][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                endcase
                            end
                            'd5:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][4][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][4][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][5][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][4][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][4][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][5][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][4][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][4][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][5][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                endcase
                            end
                            'd6:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][3][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][4][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][4][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][3][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][4][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][4][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][3][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][4][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][4][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                endcase
                            end
                            'd7:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][3][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][3][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][4][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][3][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][3][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][4][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][3][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][3][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][4][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                endcase
                            end
                            'd8:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][2][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][3][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][3][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][2][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][3][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][3][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][2][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][3][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][3][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                endcase
                            end
                            'd9:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][2][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][2][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][3][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][2][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][2][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][3][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][2][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][2][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][3][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                endcase
                            end
                            'd10:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][1][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][2][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][2][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][1][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][2][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][2][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][1][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][2][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][2][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                endcase
                            end
                            'd11:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][1][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][1][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][2][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][1][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][1][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][2][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][1][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][1][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][2][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                endcase
                            end
                            'd12:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][0][7:0];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][1][15:8];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][1][7:0];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][0][7:0];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][1][15:8];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][1][7:0];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][0][7:0];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][1][15:8];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][1][7:0];
                                        kernel_temp = kernel[6];
                                    end
                                endcase
                            end
                            'd13:begin
                                case (cnt_20)
                                    'd11:begin
                                        data = if_conv_in[0][0][15:8];
                                        kernel_temp = kernel[2];
                                    end
                                    'd12:begin
                                        data = if_conv_in[0][0][7:0];
                                        kernel_temp = kernel[1];
                                    end
                                    'd13:begin
                                        data = if_conv_in[0][1][15:8];
                                        kernel_temp = kernel[0];
                                    end
                                    'd14:begin
                                        data = if_conv_in[1][0][15:8];
                                        kernel_temp = kernel[5];
                                    end
                                    'd15:begin
                                        data = if_conv_in[1][0][7:0];
                                        kernel_temp = kernel[4];
                                    end
                                    'd16:begin
                                        data = if_conv_in[1][1][15:8];
                                        kernel_temp = kernel[3];
                                    end
                                    'd17:begin
                                        data = if_conv_in[2][0][15:8];
                                        kernel_temp = kernel[8];
                                    end
                                    'd18:begin
                                        data = if_conv_in[2][0][7:0];
                                        kernel_temp = kernel[7];
                                    end
                                    'd19:begin
                                        data = if_conv_in[2][1][15:8];
                                        kernel_temp = kernel[6];
                                    end
                                endcase
                            end
                        endcase
                    end
                endcase
            end
        end
        default:begin
            data = 0;
            kernel_temp = 0;
        end
    endcase
end





// output
always @(*) begin
    if(cs == OUT) begin
        case (size)
            'd0:begin
                if(cnt_acc == 'd16)begin
                    out_valid = 0;
                end else if(x_read > 'd5)begin
                    out_valid = 1;
                end else begin
                    out_valid = 0;
                end
            end
            'd1:begin
                if(cnt_acc == 'd64)begin
                    out_valid = 0;
                end else if(x_read > 'd7)begin
                    out_valid = 1;
                end else begin
                    out_valid = 0;
                end
            end
            'd2:begin
                if(cnt_acc == 'd256)begin
                    out_valid = 0;
                end else if((x_read > 'd11 && !flip_odd) || ((x_read >= 'd8 && x_read <= 'd11) && flip_odd) || (x_read > 'd15 && flip_odd))begin
                    out_valid = 1;
                end else begin
                    out_valid = 0;
                end
            end
            default:begin
                out_valid = 0;
            end 
        endcase
    end else begin
        out_valid = 0;
    end
end
always @(*) begin
    if(cs == OUT)begin
        case (size)
            'd0:begin
                if(cnt_acc == 'd16)begin
                    out_value = 0;
                end else if(x_read > 'd5)begin
                    if(cnt_20_odd_flag)begin
                        out_value = out_temp[0][19-cnt_20];
                    end else begin
                        out_value = out_temp[1][19-cnt_20];
                    end
                end else begin
                    out_value = 0;
                end
            end 
            'd1:begin
                if(cnt_acc == 'd64)begin
                    out_value = 0;
                end else if(x_read > 'd7)begin
                    if(cnt_20_odd_flag)begin
                        out_value = out_temp[0][19-cnt_20];
                    end else begin
                        out_value = out_temp[1][19-cnt_20];
                    end
                end else begin
                    out_value = 0;
                end
            end
            'd2:begin
                if(cnt_acc == 'd256)begin
                    out_value = 0;
                end else if((x_read > 'd11 && !flip_odd) || ((x_read >= 'd8 && x_read <= 'd11) && flip_odd) || (x_read > 'd15 && flip_odd))begin
                    if(cnt_20_odd_flag)begin
                        out_value = out_temp[0][19-cnt_20];
                    end else begin
                        out_value = out_temp[1][19-cnt_20];
                    end
                end else begin
                    out_value = 0;
                end
            end
            default:begin
                out_value = 0;
            end 
        endcase
    end else begin
        out_value = 0;
    end
end



// MEM control
always @(*) begin
    if(rw_direction == 0)begin
        x_read = x_512;
        x_write = x_128;
    end else begin
        x_read = x_128;
        x_write = x_512;
    end
end
// flag for invalid pooling

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        mp_invalid_flag <= 0;
    end else begin
        mp_invalid_flag <= ns_mp_invalid_flag;
    end
end
always @(*) begin
    if((cs == MAX || cs == MIN) && size == 0)begin
        ns_mp_invalid_flag = 1;
    end else if(cs == RST)begin
        ns_mp_invalid_flag = mp_invalid_flag;
    end else begin
        ns_mp_invalid_flag = 0;
    end
end
// direction setting
// 0: 512 read and 128 write
// 1: 128 read and 512 write
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        rw_direction <= 0;
    end else begin
        rw_direction <= ns_rw_direction;
    end
end
always @(*) begin
    case (cs)
        IDLE:begin
            // reset after output
            ns_rw_direction = 'd0;
        end
        RST:begin
            if(mp_invalid_flag)begin
                // invalid pooling occurs
                ns_rw_direction = rw_direction;
            end else begin
                if(cnt_rst == 'd1)begin
                    ns_rw_direction = ~rw_direction;
                end else begin
                    ns_rw_direction = rw_direction;
                end
                
            end
        end
        default:begin
            ns_rw_direction = rw_direction;
        end 
    endcase
end
// A:addr 9 bits; DI/DO: data inout 16 bits; CLK,WEB,OE,CS
MEM_512_16 ML(.A0(addr_512[0]),.A1(addr_512[1]),.A2(addr_512[2]),.A3(addr_512[3]),.A4(addr_512[4]),.A5(addr_512[5]),.A6(addr_512[6]),.A7(addr_512[7]),.A8(addr_512[8]),
.DO0(do_512[0]),.DO1(do_512[1]),.DO2(do_512[2]),.DO3(do_512[3]),.DO4(do_512[4]),
 .DO5(do_512[5]),.DO6(do_512[6]),.DO7(do_512[7]),.DO8(do_512[8]),.DO9(do_512[9]),.DO10(do_512[10]),.DO11(do_512[11]),.DO12(do_512[12]),.DO13(do_512[13]),.DO14(do_512[14]),
 .DO15(do_512[15]),.DI0(di_512[0]),.DI1(di_512[1]),.DI2(di_512[2]),.DI3(di_512[3]),.DI4(di_512[4]),.DI5(di_512[5]),.DI6(di_512[6]),.DI7(di_512[7]),.DI8(di_512[8]),
 .DI9(di_512[9]),.DI10(di_512[10]),.DI11(di_512[11]),.DI12(di_512[12]),.DI13(di_512[13]),.DI14(di_512[14]),.DI15(di_512[15]),.CK(clk),.WEB(web_512),.OE(1'b1), .CS(1'b1));

always @(*) begin
    case (cs)
        RGB:begin
            //only 512 write
            if(cnt_rgb == 'd0 || cnt_rgb == 'd1 || cnt_rgb == 'd2)begin
                web_512 = 0;
                // cs_512 = 1;
            end else begin
                web_512 = 1;
                // cs_512 = 0;
            end
        end
        MAX, MIN:begin
            if(rw_direction == 0)begin
                // 512 read
                web_512 = 1;
                // if((size == 'd1 && x_512 < 'd32) || (size == 'd2 && x_512 < 'd128))begin
                    // cs_512 = 1;
                // end else begin
                    // size = 0: pooling invalid
                    // cs_512 = 0;
                // end
            end else begin
                // 512 write when cnt_pool = 1
                web_512 = 0;
                // if(cnt_pool == 'd1)begin
                    // cs_512 = 1;
                // end else begin
                    // cs_512 = 0;
                // end
            end
        end
        IF:begin
            if(rw_direction == 0)begin
                // 512 read
                web_512 = 1;
                // if((size == 'd0 && x_512 < 'd8) || (size == 'd1 && x_512 < 'd32) || (size == 'd2 && x_512 < 'd128))begin
                    // cs_512 = 1;
                // end else begin
                    // cs_512 = 0;
                // end
            end else begin
                // 512 write consecutively when cnt_if == 0
                web_512 = 0;
                // if(cnt_if == 'd0)begin
                    // cs_512 = 1;
                // end else begin
                    // cs_512 = 0;
                // end
            end
        end
        OUT:begin
            web_512 = 1;
            // if(rw_direction == 0)begin
                // read from 512
                // cs_512 = 1;
            // end else begin
                //no write when output
                // cs_512 = 0;
            // end
        end
        default:begin
            // IDL, RST, ACT
            web_512 = 1;
            // cs_512 = 0;
        end
    endcase
end

always @(*) begin
    case (cs)
        RGB:begin
            //must write into 512
            case (cnt_rgb)
                'd0:begin
                    // max gs
                    addr_512 = x_512;
                end
                'd1:begin
                    // avg gs
                    addr_512 = x_512 + BIAS_512_1;
                end 
                'd2:begin
                    // wgt gs
                    addr_512 = x_512 + BIAS_512_2;
                end
                default:begin
                    addr_512 = 0;
                end
            endcase
        end 
        MAX, MIN, IF, OUT:begin
            addr_512 = x_512 + bias_512;
        end
        default:begin
            addr_512 = 0;
        end
    endcase
end
// bias for larger sram

always @(*) begin
    if(wk_pointer == 0)begin
        case (first_act)
            // first_act 512 must read
            'd1:begin
                // average grayscale
                bias_512 = BIAS_512_1; 
            end
            'd2:begin
                // weighted grayscale
                bias_512 = BIAS_512_2; 
            end
            default:begin
                // maximum grayscale
                bias_512 = 0;
            end 
        endcase
    end else begin
        bias_512 = BIAS_512_3;
    end
end

always @(*) begin
    case (cs)
        RGB:begin
            // must write
            case (cnt_rgb)
                'd0:begin
                    di_512 = {gs_m0, ns_gs_m0};
                end
                'd1:begin
                    di_512 = {gs_a0, gs_a1};
                end 
                'd2:begin
                    di_512 = {gs_w0, gs_w1};
                end
                default:begin
                    di_512 = 0;
                end
            endcase
        end 
        MAX, MIN:begin
            if(rw_direction == 1)begin
                // cs_512 is controlled ,try to delete the if-else after finishi all
                di_512 = {mp_out, ns_mp_out};
            end else begin
                di_512 = 0;
            end
        end
        IF:begin
            if(rw_direction == 1)begin
                di_512 = ns_if_out;
            end else begin
                di_512 = 0;
            end
        end
        default:begin
            di_512 = 0;
        end 
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        x_512 <= 0;
    end else begin
        x_512 <= ns_x_512;
    end
end
always @(*) begin
    case (cs)
        IDLE:begin
            ns_x_512 = 0;
        end
        RGB:begin
            if(cnt_rgb == 'd2)begin
                ns_x_512 = x_512 + 'd1;
            end else begin
                ns_x_512 = x_512;
            end
        end 
        MAX, MIN:begin
            if(rw_direction == 0)begin
                // x_512 for read
                case (size)
                    'd1:begin
                        case (x_512 % 8)
                            'd4, 'd5, 'd6: begin
                                ns_x_512 = x_512 - 'd3;
                            end
                            'd7:begin
                                ns_x_512 = x_512 + 'd1;
                            end
                            default:begin
                                // even
                                ns_x_512 = x_512 + 'd4;
                            end
                        endcase
                    end 
                    'd2:begin
                        case (x_512 % 16)
                            'd8, 'd9, 'd10, 'd11, 'd12, 'd13, 'd14:begin
                                ns_x_512 = x_512 - 'd7;
                            end 
                            'd15:begin
                                ns_x_512 = x_512 + 'd1;
                            end
                            default:begin
                                // even
                                ns_x_512 = x_512 + 'd8;
                            end
                        endcase
                    end
                    default:begin
                        ns_x_512 = x_512;
                    end 
                endcase
            end else begin
                // x_512 for write
                if(cnt_pool == 'd1)begin
                    ns_x_512 = x_512 + 'd1;
                end else begin
                    ns_x_512 = x_512;
                end
            end
        end
        IF:begin
            if(rw_direction == 0)begin
                // x_512 for read
                ns_x_512 = x_512 + 'd1;
            end else begin
                if(cnt_if == 'd0)begin
                    ns_x_512 = x_512 + 'd1;
                end else begin
                    ns_x_512 = x_512;
                end
            end
        end
        OUT:begin
            if(rw_direction == 0)begin
                if(flip_odd)begin
                    case (size)
                        'd0:begin
                            // exact cycle
                            if(cnt_acc == 'd6 && cnt_20 >= 'd16 && cnt_20 <= 'd17)begin
                                if(x_512 == 'd6)begin
                                    ns_x_512 = x_512;
                                end else begin
                                    if(x_512%2 == 0)begin
                                        ns_x_512 = x_512 + 'd3;
                                    end else begin
                                        ns_x_512 = x_512 - 'd1;
                                    end
                                end
                            end else if(x_512 > 'd5)begin
                                ns_x_512 = x_512;
                            end else begin
                                if(x_512%2 == 0)begin
                                    ns_x_512 = x_512 + 'd3;
                                end else begin
                                    ns_x_512 = x_512 - 'd1;
                                end
                            end
                        end 
                        'd1:begin
                            if(cnt_acc%8 == 'd7 && cnt_20 >= 'd14 && cnt_20 <= 'd17)begin
                                if(x_512 == 'd28)begin
                                    ns_x_512 = x_512;
                                end else begin
                                    if(x_512%4 == 0)begin
                                        ns_x_512 = x_512 + 'd7;
                                    end else begin
                                        ns_x_512 = x_512 - 'd1;
                                    end
                                end
                            end else if(x_512 > 'd7)begin
                                ns_x_512 = x_512;
                            end else begin
                                if(x_512%4 == 0)begin
                                    ns_x_512 = x_512 + 'd7;
                                end else begin
                                    ns_x_512 = x_512 - 'd1;
                                end
                            end
                        end
                        'd2:begin
                            if(cnt_acc%16 == 'd15 && cnt_20 >= 'd10 && cnt_20 <= 'd17)begin
                                if(x_512 == 'd120)begin
                                    ns_x_512 = x_512;
                                end else begin
                                    if(x_512%8 == 0)begin
                                        ns_x_512 = x_512 + 'd15;
                                    end else begin
                                        ns_x_512 = x_512 - 'd1;
                                    end
                                end
                            end else if(x_512 > 'd15) begin
                                ns_x_512 = x_512;
                            end else begin
                                if(x_512%8 == 0)begin
                                    ns_x_512 = x_512 + 'd15;
                                end else begin
                                    ns_x_512 = x_512 - 'd1;
                                end
                            end
                        end
                        default:begin
                            ns_x_512 = 0;
                        end
                    endcase
                end else begin
                    // not flip
                    case (size)
                        'd0:begin
                            if(cnt_acc == 'd6 && cnt_20 >= 'd16 && cnt_20 <= 'd17)begin
                                if(x_512 == 'd7)begin
                                    ns_x_512 = x_512;
                                end else begin
                                    ns_x_512 = x_512 + 'd1;
                                end
                            end else if(x_512 > 'd5)begin
                                ns_x_512 = x_512;
                            end else begin
                                ns_x_512 = x_512 + 'd1;
                            end
                        end 
                        'd1:begin
                            if(cnt_acc%8 == 'd7 && cnt_20 >= 'd14 && cnt_20 <= 'd17)begin
                                if(x_512 == 'd31)begin
                                    ns_x_512 = x_512;
                                end else begin
                                    ns_x_512 = x_512 + 'd1;
                                end
                            end else if(x_512 > 'd7)begin
                                ns_x_512 = x_512;
                            end else begin
                                ns_x_512 = x_512 + 'd1;
                            end
                        end
                        'd2:begin
                            if(cnt_acc%16 == 'd15 && cnt_20 >= 'd10 && cnt_20 <= 'd17)begin
                                if(x_512 == 'd127)begin
                                    ns_x_512 = x_512;
                                end else begin
                                    ns_x_512 = x_512 + 'd1;
                                end
                            end else if(x_512 > 'd15) begin
                                ns_x_512 = x_512;
                            end else begin
                                ns_x_512 = x_512 + 'd1;
                            end
                        end
                        default:begin
                            ns_x_512 = 0;
                        end
                    endcase
                end
            end else begin
                ns_x_512 = 0;
            end
        end
        RST:begin
            if(next_is_out && flip_odd && !in_valid)begin
                case (size)
                    'd0:begin
                        ns_x_512 = 'd1;
                    end 
                    'd1:begin
                        ns_x_512 = 'd3;
                    end
                    'd2:begin
                        ns_x_512 = 'd7;
                    end
                    default:begin
                        ns_x_512 = 0;
                    end
                endcase
            end else begin
                ns_x_512 = 0;
            end
        end
        ACT:begin
            // if ACT direction to OUT
            if(next_is_out && flip_odd && !in_valid)begin
                case (size)
                    'd0:begin
                        ns_x_512 = 'd1;
                    end 
                    'd1:begin
                        ns_x_512 = 'd3;
                    end
                    'd2:begin
                        ns_x_512 = 'd7;
                    end
                    default:begin
                        ns_x_512 = 0;
                    end
                endcase
            end else begin
                ns_x_512 = 0;
            end
        end
        default:begin
            ns_x_512 = 0;
        end
    endcase
end

// A:addr 7 bits; DI/DO: data inout 16 bits
MEM_128_16 MS(.A0(addr_128[0]),.A1(addr_128[1]),.A2(addr_128[2]),.A3(addr_128[3]),.A4(addr_128[4]),.A5(addr_128[5]),.A6(addr_128[6]),
 .DO0(do_128[0]),.DO1(do_128[1]),.DO2(do_128[2]),.DO3(do_128[3]),.DO4(do_128[4]),.DO5(do_128[5]),.DO6(do_128[6]),
 .DO7(do_128[7]),.DO8(do_128[8]),.DO9(do_128[9]),.DO10(do_128[10]),.DO11(do_128[11]),.DO12(do_128[12]),.DO13(do_128[13]),.DO14(do_128[14]),.DO15(do_128[15]),
 .DI0(di_128[0]),.DI1(di_128[1]),.DI2(di_128[2]),.DI3(di_128[3]),.DI4(di_128[4]),.DI5(di_128[5]),.DI6(di_128[6]),.DI7(di_128[7]),.DI8(di_128[8]),.DI9(di_128[9]),
 .DI10(di_128[10]),.DI11(di_128[11]),.DI12(di_128[12]),.DI13(di_128[13]),.DI14(di_128[14]),.DI15(di_128[15]),.CK(clk),.WEB(web_128),.OE(1'b1), .CS(1'b1));
always @(*) begin
    case (cs)
        MAX, MIN:begin
            if(rw_direction == 1)begin
                web_128 = 1;
                // 128 read until finish
                // if((size == 'd1 && x_128 < 'd32) || (size == 'd2 && x_128 < 'd128))begin
                    // cs_128 = 1;
                // end else begin
                    // size = 0: pooling invalid
                    // cs_128 = 0;
                // end                
            end else begin
                // 128 write when cnt_pool = 1
                web_128 = 0;
                // if(cnt_pool == 'd1)begin
                    // cs_128 = 1;
                // end else begin
                    // cs_128 = 0;
                // end
            end
        end
        IF:begin
            if(rw_direction == 1)begin
                // 128 read
                web_128 = 1;
                // if((size == 'd0 && x_128 < 'd8) || (size == 'd1 && x_128 < 'd32) || (size == 'd2 && x_128 < 'd128))begin
                    // cs_128 = 1;
                // end else begin
                    // cs_128 = 0;
                // end
            end else begin
                // 128 write consecutively when cnt_if == 0
                web_128 = 0;
                // if(cnt_if == 'd0)begin
                    // cs_128 = 1;
                // end else begin
                    // cs_128 = 0;
                // end
            end
        end
        OUT:begin
            web_128 = 1;
            // if(rw_direction == 1)begin
                // read from 128
                // cs_128 = 1;
            // end else begin
                // cs_128 = 0;
            // end
        end
        default:begin
            web_128 = 1;
            // cs_128 = 0;
        end
    endcase
end

always @(*) begin
    case (cs)
        MAX, MIN:begin
            // read/write same addr, cs_128 is controlled
            addr_128 = x_128;
        end
        IF:begin
            addr_128 = x_128;
        end
        OUT:begin
            addr_128 = x_128;
        end
        default:begin
            addr_128 = 0;
        end
    endcase
end

always @(*) begin
    case (cs)
        MAX, MIN:begin
            //try to delete if - else
            if(rw_direction == 0)begin
                di_128 = {mp_out, ns_mp_out};
            end else begin
                di_128 = 0;
            end
        end 
        IF:begin
            if(rw_direction == 0) begin
                di_128 = ns_if_out;
            end else begin
                di_128 = 0;
            end
        end
        default:begin
            di_128 = 0;
        end 
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        x_128 <= 0;
    end else begin
        x_128 <= ns_x_128;
    end
end
always @(*) begin
    case (cs)
        IDLE:begin
            ns_x_128 = 0;
        end
        MAX, MIN:begin
            if(rw_direction == 1)begin
                // x_128 for read
                case (size)
                    'd1:begin
                        case (x_128 % 8)
                            'd4, 'd5, 'd6: begin
                                ns_x_128 = x_128 - 'd3;
                            end
                            'd7:begin
                                ns_x_128 = x_128 + 'd1;
                            end
                            default:begin
                                // even
                                ns_x_128 = x_128 + 'd4;
                            end
                        endcase
                    end 
                    'd2:begin
                        case (x_128 % 16)
                            'd8, 'd9, 'd10, 'd11, 'd12, 'd13, 'd14:begin
                                ns_x_128 = x_128 - 'd7;
                            end 
                            'd15:begin
                                ns_x_128 = x_128 + 'd1;
                            end
                            default:begin
                                // even
                                ns_x_128 = x_128 + 'd8;
                            end
                        endcase
                    end
                    default:begin
                        ns_x_128 = x_128;
                    end 
                endcase
            end else begin
                // x_128 for write
                if(cnt_pool == 'd1)begin
                    ns_x_128 = x_128 + 'd1;
                end else begin
                    ns_x_128 = x_128;
                end
            end
        end
        IF:begin
            if(rw_direction == 1)begin
                // x_128 for read
                ns_x_128 = x_128 + 'd1;
            end else begin
                if(cnt_if == 'd0)begin
                    ns_x_128 = x_128 + 'd1;
                end else begin
                    ns_x_128 = x_128;
                end
            end
        end
        OUT:begin
            if(rw_direction == 1)begin
                if(flip_odd)begin
                    case (size)
                        'd0:begin
                            if(cnt_acc == 'd6 && cnt_20 >= 'd16 && cnt_20 <= 'd17)begin
                                if(x_128 == 'd6)begin
                                    ns_x_128 = x_128;
                                end else begin
                                    if(x_128%2 == 0)begin
                                        ns_x_128 = x_128 + 'd3;
                                    end else begin
                                        ns_x_128 = x_128 - 'd1;
                                    end
                                end
                            end else if(x_128 > 'd5)begin
                                ns_x_128 = x_128;
                            end else begin
                                if(x_128%2 == 0)begin
                                    ns_x_128 = x_128 + 'd3;
                                end else begin
                                    ns_x_128 = x_128 - 'd1;
                                end
                            end
                        end 
                        'd1:begin
                            if(cnt_acc%8 == 'd7 && cnt_20 >= 'd14 && cnt_20 <= 'd17)begin
                                if(x_128 == 'd28)begin
                                    ns_x_128 = x_128;
                                end else begin
                                    if(x_128%4 == 0)begin
                                        ns_x_128 = x_128 + 'd7;
                                    end else begin
                                        ns_x_128 = x_128 - 'd1;
                                    end
                                end
                            end else if(x_128 > 'd7)begin
                                ns_x_128 = x_128;
                            end else begin
                                if(x_128%4 == 0)begin
                                    ns_x_128 = x_128 + 'd7;
                                end else begin
                                    ns_x_128 = x_128 - 'd1;
                                end
                            end
                        end
                        'd2:begin
                            if(cnt_acc%16 == 'd15 && cnt_20 >= 'd10 && cnt_20 <= 'd17)begin
                                if(x_128 == 'd120)begin
                                    ns_x_128 = x_128;
                                end else begin
                                    if(x_128%8 == 0)begin
                                        ns_x_128 = x_128 + 'd15;
                                    end else begin
                                        ns_x_128 = x_128 - 'd1;
                                    end
                                end
                            end else if(x_128 > 'd15) begin
                                ns_x_128 = x_128;
                            end else begin
                                if(x_128%8 == 0)begin
                                    ns_x_128 = x_128 + 'd15;
                                end else begin
                                    ns_x_128 = x_128 - 'd1;
                                end
                            end
                        end
                        default:begin
                            ns_x_128 = 0;
                        end
                    endcase
                end else begin
                    // no flip
                    case (size)
                        'd0:begin
                            if(cnt_acc == 'd6 && cnt_20 >= 'd16 && cnt_20 <= 'd17)begin
                                if(x_128 == 'd7)begin
                                    ns_x_128 = x_128;
                                end else begin
                                    ns_x_128 = x_128 + 'd1;
                                end
                            end else if(x_128 > 'd5)begin
                                ns_x_128 = x_128;
                            end else begin
                                ns_x_128 = x_128 + 'd1;
                            end
                        end 
                        'd1:begin
                            if(cnt_acc%8 == 'd7 && cnt_20 >= 'd14 && cnt_20 <= 'd17)begin
                                if(x_128 == 'd31)begin
                                    ns_x_128 = x_128;
                                end else begin
                                    ns_x_128 = x_128 + 'd1;
                                end
                            end else if(x_128 > 'd7)begin
                                ns_x_128 = x_128;
                            end else begin
                                ns_x_128 = x_128 + 'd1;
                            end
                        end
                        'd2:begin
                            if(cnt_acc%16 == 'd15 && cnt_20 >= 'd10 && cnt_20 <= 'd17)begin
                                if(x_128 == 'd127)begin
                                    ns_x_128 = x_128;
                                end else begin
                                    ns_x_128 = x_128 + 'd1;
                                end
                            end else if(x_128 > 'd15) begin
                                ns_x_128 = x_128;
                            end else begin
                                ns_x_128 = x_128 + 'd1;
                            end
                        end
                        default:begin
                            ns_x_128 = 0;
                        end
                    endcase
                end
            end else begin
                ns_x_128 = 0;
            end
        end
        RST:begin
            if(next_is_out && flip_odd && !in_valid)begin
                case (size)
                    'd0:begin
                        ns_x_128 = 'd1;
                    end 
                    'd1:begin
                        ns_x_128 = 'd3;
                    end
                    'd2:begin
                        ns_x_128 = 'd7;
                    end
                    default:begin
                        ns_x_128 = 0;
                    end
                endcase
            end else begin
                ns_x_128 = 0;
            end
        end
        ACT:begin
            // if ACT direction to OUT
            if(next_is_out && flip_odd && !in_valid)begin
                case (size)
                    'd0:begin
                        ns_x_128 = 'd1;
                    end 
                    'd1:begin
                        ns_x_128 = 'd3;
                    end
                    'd2:begin
                        ns_x_128 = 'd7;
                    end
                    default:begin
                        ns_x_128 = 0;
                    end
                endcase
            end else begin
                ns_x_128 = 0;
            end
        end
        default:begin
            ns_x_128 = 0;
        end
    endcase
end

endmodule

module pooling( current_state, pool_in1, pool_in2, pool_out );
input  [2:0] current_state;
input [15:0] pool_in1;
input [15:0] pool_in2;
output [7:0] pool_out;
wire   [7:0] m1, m2, m3, m4;
wire   [7:0] s1, s2;
localparam MAX = 3'd3;

assign m1 = pool_in1[15:8];
assign m2 = pool_in1[7:0];
assign m3 = pool_in2[15:8];
assign m4 = pool_in2[7:0];

assign s1 = (current_state == MAX) ? (m1 > m2) ? m1 : m2 : (m1 < m2) ? m1 : m2;
assign s2 = (current_state == MAX) ? (m3 > m4) ? m3 : m4 : (m3 < m4) ? m3 : m4;

assign pool_out = (current_state == MAX) ? (s1 > s2) ? s1 : s2 : (s1 < s2) ? s1 : s2;
endmodule



module median( mid_in_l0, mid_in_l1, mid_in_l2, mid_in_m0, mid_in_m1, mid_in_m2, mid_in_r0, mid_in_r1, mid_in_r2, median_out);
input  [7:0] mid_in_l0, mid_in_l1, mid_in_l2, mid_in_r0, mid_in_r1, mid_in_r2;
input [15:0] mid_in_m0, mid_in_m1, mid_in_m2;
output[15:0] median_out;
wire   [7:0] m0_l, m0_r, m1_l, m1_r, m2_l, m2_r;
wire   [7:0] a0, a1, a2, a3, a4, a5;
wire   [7:0] b0, b1, b2, b3, b4, b5;
wire   [7:0] c0, c1, c2, c3, c4, c5;
wire   [7:0] d0, d1, d2, d3, d4, d5;
wire   [7:0] e0, e1, e2, e3;
wire   [7:0] ec0, ed0, ec1, ed1, ec3, ed3;
wire   [7:0] ac, ad;
wire   [7:0] mc0, md0, mc1, md1, mc2, md2;
wire   [7:0] median_l, median_r;

assign m0_l = mid_in_m0[15:8];
assign m1_l = mid_in_m1[15:8];
assign m2_l = mid_in_m2[15:8];
assign m0_r = mid_in_m0[7:0];
assign m1_r = mid_in_m1[7:0];
assign m2_r = mid_in_m2[7:0];
// reusing elements in the middle
assign a0 = (m0_l > m1_l) ? m0_l : m1_l;
assign a1 = (m0_l > m1_l) ? m1_l : m0_l;
assign a2 = (a1 > m2_l)  ?   a1 : m2_l;
assign a3 = (a1 > m2_l)  ? m2_l :   a1;
assign a4 = (a0 > a2)  ? a0 : a2;
assign a5 = (a0 > a2)  ? a2 : a0;

assign b0 = (m0_r > m1_r) ? m0_r : m1_r;
assign b1 = (m0_r > m1_r) ? m1_r : m0_r;
assign b2 = (b1 > m2_r) ?   b1 : m2_r;
assign b3 = (b1 > m2_r) ? m2_r :   b1;
assign b4 = (b0 > b2) ? b0 : b2;
assign b5 = (b0 > b2) ? b2 : b0;

assign c0 = (mid_in_l0 > mid_in_l1) ? mid_in_l0 : mid_in_l1;
assign c1 = (mid_in_l0 > mid_in_l1) ? mid_in_l1 : mid_in_l0;
assign c2 = (c1 > mid_in_l2) ?   c1 : mid_in_l2;
assign c3 = (c1 > mid_in_l2) ? mid_in_l2 :   c1;
assign c4 = (c0 > c2) ? c0 : c2;
assign c5 = (c0 > c2) ? c2 : c0;

assign d0 = (mid_in_r0 > mid_in_r1) ? mid_in_r0 : mid_in_r1;
assign d1 = (mid_in_r0 > mid_in_r1) ? mid_in_r1 : mid_in_r0;
assign d2 = (d1 > mid_in_r2) ?   d1 : mid_in_r2;
assign d3 = (d1 > mid_in_r2) ? mid_in_r2 :   d1;
assign d4 = (d0 > d2) ? d0 : d2;
assign d5 = (d0 > d2) ? d2 : d0;

assign e0 = (a4 > b4) ? b4 : a4;
assign ec0 = (e0 > c4) ? c4 : e0;
assign ed0 = (e0 > d4) ? d4 : e0;

assign e1 = (a5 > b5) ? a5 : b5;
assign e2 = (a5 > b5) ? b5 : a5;
assign ec1 = (e2 > c5) ? e2 : c5;
assign ed1 = (e2 > d5) ? e2 : d5;
assign ac = (ec1 > e1) ? e1 : ec1;
assign ad = (ed1 > e1) ? e1 : ed1;

assign e3 = (a3 > b3) ? a3 : b3;
assign ec3 = (e3 > c3) ? e3 : c3;
assign ed3 = (e3 > d3) ? e3 : d3;

assign mc0 = (ec3 > ac) ? ec3 : ac;
assign md0 = (ed3 > ad) ? ed3 : ad;
assign mc1 = (ec3 > ac) ? ac : ec3;
assign md1 = (ed3 > ad) ? ad : ed3;
assign mc2 = (mc1 > ec0) ? mc1 : ec0;
assign md2 = (md1 > ed0) ? md1 : ed0;
assign median_l = (mc0 > mc2) ? mc2 : mc0;
assign median_r = (md0 > md2) ? md2 : md0;

assign median_out = {median_l, median_r};
endmodule

module mac(in1, in2, in3, neg_flag, out);
input  [7:0]  in1;
input  [7:0]  in2;
input  [19:0] in3;
input         neg_flag;
output [19:0] out;
wire [15:0] mult_out;
wire [7:0]  new_in1;

assign new_in1 = (neg_flag) ? ~in1 : in1;
assign mult_out = new_in1 * in2;

assign out = mult_out + in3;
endmodule
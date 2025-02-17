//############################################################################
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//   (C) Copyright Laboratory System Integration and Silicon Implementation
//   All Right Reserved
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   ICLAB 2023 Fall
//   Lab04 Exercise		: Convolution Neural Network 
//   Author     		: Pei-Hong Chen (ph1223.ii12@nycu.edu.tw)
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//
//   File Name   : CNN.v
//   Module Name : CNN
//   Release version : V1.0 (Release Date: 2024-10)
//
//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
//############################################################################

`define CYCLE_TIME      20.4
`define SEED_NUMBER     28825252
`define PATTERN_NUMBER  1000

module PATTERN(
    //Output Port
    clk,
    rst_n,
    in_valid,
    Img,
    Kernel_ch1,
    Kernel_ch2,
	Weight,
    Opt,
    //Input Port
    out_valid,
    out
    );

//---------------------------------------------------------------------
//   PORT DECLARATION          
//---------------------------------------------------------------------
output  logic        clk, rst_n, in_valid;
output  logic[31:0]  Img;
output  logic[31:0]  Kernel_ch1;
output  logic[31:0]  Kernel_ch2;
output  logic[31:0]  Weight;
output  logic        Opt;
input           out_valid;
input   [31:0]  out;

//---------------------------------------------------------------------
//   PARAMETER & INTEGER DECLARATION
//---------------------------------------------------------------------
real CYCLE = `CYCLE_TIME;
parameter inst_sig_width = 23;
parameter inst_exp_width = 8;
parameter inst_ieee_compliance = 0;
parameter inst_arch_type = 0;
parameter inst_arch = 0;

parameter IMAG_NUM = 3;
parameter IMAG_SIZE = 5;
parameter KERNEL_INPUT = 2;
parameter KERNEL_NUM = 3;
parameter KERNEL_SIZE = 2;
parameter WEIGHT_INPUT = 3;
parameter WEIGHT_SIZE = 8;

integer i_pat;
integer total_latency, latency;
integer t;
integer out_num;
integer SEED = `SEED_NUMBER;
//---------------------------------------------------------------------
//   Reg & Wires
//---------------------------------------------------------------------

//input
reg [inst_sig_width + inst_exp_width : 0] _imag[1:IMAG_NUM][0:IMAG_SIZE - 1][0:IMAG_SIZE - 1 ];
reg [inst_sig_width + inst_exp_width : 0] _kernel[1:KERNEL_INPUT ][1:KERNEL_NUM][0:KERNEL_SIZE - 1 ][0:KERNEL_SIZE - 1];
reg [inst_sig_width + inst_exp_width : 0] _weight[1:WEIGHT_INPUT][0:WEIGHT_SIZE - 1];
reg _opt;

// feature map
reg [inst_sig_width + inst_exp_width : 0] _pad[1:IMAG_NUM][0:IMAG_SIZE + 1][0:IMAG_SIZE + 1];
reg [inst_sig_width + inst_exp_width : 0] _conv[1:KERNEL_INPUT][1:IMAG_NUM][0:IMAG_SIZE][0:IMAG_SIZE];
reg [inst_sig_width + inst_exp_width : 0] _conv_sum[1:KERNEL_INPUT][0:IMAG_SIZE][0:IMAG_SIZE];
reg [inst_sig_width + inst_exp_width : 0] _pool[1:KERNEL_INPUT][0:1][0:1];
reg [inst_sig_width + inst_exp_width : 0] _encode[1:KERNEL_INPUT][0:1][0:1];
reg [inst_sig_width + inst_exp_width : 0] _full[0:2];
reg [inst_sig_width + inst_exp_width : 0] _soft[0:2];

wire [inst_sig_width + inst_exp_width : 0] _conv_w[1:KERNEL_INPUT][1:IMAG_NUM][0:IMAG_SIZE][0:IMAG_SIZE];
wire [inst_sig_width + inst_exp_width : 0] _conv_sum_w[1:KERNEL_INPUT][0:IMAG_SIZE][0:IMAG_SIZE];
wire [inst_sig_width + inst_exp_width : 0] _pool_w[1:KERNEL_INPUT][0:1][0:1];
wire [inst_sig_width + inst_exp_width : 0] _encode_w[1:KERNEL_INPUT][0:1][0:1];
wire [inst_sig_width + inst_exp_width : 0] _full_w[0:2];
wire [inst_sig_width + inst_exp_width : 0] _soft_w[0:2];

reg [inst_sig_width + inst_exp_width : 0] _out[0:2];
// ERROR CHECK 0.005
wire [inst_sig_width+inst_exp_width:0] _errAllow = 32'h38D1B717;
reg  [inst_sig_width+inst_exp_width:0] _errDiff;
wire [inst_sig_width+inst_exp_width:0] _errDiff_w;
reg  [inst_sig_width+inst_exp_width:0] _errBound;
wire [inst_sig_width+inst_exp_width:0] _errBound_w;

wire _isErr[2:0];

reg[10*8:1] txt_blue_prefix   = "\033[1;34m";
reg[10*8:1] txt_green_prefix  = "\033[1;32m";
reg[9*8:1]  reset_color       = "\033[1;0m";
//================================================================
// clock
//================================================================

always #(CYCLE/2.0) clk = ~clk;
initial	clk = 0;

//---------------------------------------------------------------------
//   Pattern_Design
//---------------------------------------------------------------------

always @(negedge clk) begin
	if(out_valid === 0 && out !== 'd0) begin
		$display("*************************************************************************");
		$display("*                              FAIL!                                    *");
		$display("*       The out_data should be reset when your out_valid is low.        *");
		$display("*************************************************************************");
		repeat(2) #(CYCLE);
		$finish;
	end
end

initial begin
    reset_task;

    total_latency = 0;

    for(i_pat = 0; i_pat < `PATTERN_NUMBER; i_pat = i_pat + 1) begin
        input_task;
        cal_task;
        wait_task;
        total_latency = total_latency + latency;
        check_task;
        $display("%0sPASS PATTERN NO.%4d, %0sCycles: %3d%0s",txt_blue_prefix, i_pat, txt_green_prefix, latency, reset_color);
    end

    // All patterns passed
    YOU_PASS_task;
end

task reset_task; begin
	rst_n = 1'b1;
	in_valid = 1'b0;

	Img = 'dx;
	Kernel_ch1 = 'dx;
    Kernel_ch2 = 'dx;
    Weight = 'dx;
    Opt = 'dx;

	force clk = 0;

	// Apply reset
    #CYCLE; rst_n = 1'b0; 
    #CYCLE; rst_n = 1'b1;
	#(9 * CYCLE);

	// Check initial conditions
    if (out_valid !== 0 || out !== 0) begin
        $display("************************************************************");  
        $display("                           FAIL                             ");    
        $display("*  Output signals should be 0 after initial RESET at %8t *", $time);
        $display("************************************************************");
        repeat (2) #CYCLE;
        $finish;
    end

	#CYCLE; release clk;
end endtask

task input_task;
    integer i,j,k,m,count;
begin 
    random_input;
    _padding;
    
    t = $urandom_range(1,4);
    repeat(t) @(negedge clk);

    count = 0;
    for(i = 0; i < IMAG_NUM * IMAG_SIZE * IMAG_SIZE; i = i + 1)begin
        in_valid = 'b1;
        Img = _imag[(i/IMAG_SIZE/IMAG_SIZE) % IMAG_NUM + 1][(i/IMAG_SIZE) % IMAG_SIZE][i % IMAG_SIZE];
        if(count < KERNEL_NUM * KERNEL_SIZE * KERNEL_SIZE) begin
            Kernel_ch1 = _kernel[1][i/(KERNEL_SIZE * KERNEL_SIZE) + 1][(i/KERNEL_SIZE) % KERNEL_SIZE][i % KERNEL_SIZE];
            Kernel_ch2 = _kernel[2][i/(KERNEL_SIZE * KERNEL_SIZE) + 1][(i/KERNEL_SIZE) % KERNEL_SIZE][i % KERNEL_SIZE];
        end
        else begin
            Kernel_ch1 = 'dx;
            Kernel_ch2 = 'dx;
        end

        if(count < WEIGHT_INPUT * WEIGHT_SIZE)
            Weight = _weight[i/WEIGHT_SIZE + 1][i % WEIGHT_SIZE];
        else
            Weight = 'dx;

        if(count < 1)
            Opt = _opt;
        else
            Opt = 'dx;
        
        @(negedge clk);
        count = count + 1;
    end

    in_valid = 'b0;
    Img = 'dx;
    Kernel_ch1 = 'dx;
    Kernel_ch2 = 'dx;
    Weight = 'dx;
    Opt = 'dx;
end endtask

// random input
task random_input;
    integer i,j,k,m;
begin
    for(i = 1; i <= IMAG_NUM; i = i + 1) begin
        for(j = 0; j < IMAG_SIZE; j = j + 1) begin
            for(k = 0; k < IMAG_SIZE; k = k + 1) begin
                _imag[i][j][k] = _randinput(i_pat);
            end
        end
    end
    for(m = 1; m <= KERNEL_INPUT; m = m + 1) begin
        for(i = 1; i <= KERNEL_NUM; i = i + 1) begin
            for(j = 0; j < KERNEL_SIZE; j = j + 1) begin
                for(k = 0; k < KERNEL_SIZE; k = k + 1) begin
                    _kernel[m][i][j][k] = _randinput(i_pat);
                end
            end
        end
    end
     for(i = 1; i <= WEIGHT_INPUT; i = i + 1) begin
        for(j = 0; j < WEIGHT_SIZE; j = j + 1) begin
            _weight[i][j] = _randinput(i_pat);
            
        end
    end
    _opt = {$random(SEED)} % 2;
end endtask

// padding
task _padding; 
    integer i,j,k,m;
begin 
    for(i = 1; i <= IMAG_NUM; i = i + 1) begin
        for(j = 0; j < IMAG_SIZE; j = j + 1) begin
            for(k = 0; k < IMAG_SIZE; k = k + 1) begin
                _pad[i][j + 1][k + 1] = _imag[i][j][k];
            end
        end
    end

    for(i = 1; i <= IMAG_NUM; i = i + 1) begin
        for(j = 0; j < IMAG_SIZE + 2; j = j + 1) begin
            for(k = 0; k < IMAG_SIZE + 2; k = k + 1) begin
                if(_opt === 1) begin
                    if(j===0 && k===0)
                        _pad[i][j][k] = _pad[i][j + 1][k + 1];
                    else if(j===0 && k===IMAG_SIZE + 1)
                        _pad[i][j][k] = _pad[i][j + 1][k - 1];
                    else if(j===IMAG_SIZE + 1 && k===0)
                        _pad[i][j][k] = _pad[i][j - 1][k + 1];
                    else if(j===IMAG_SIZE + 1 && k===IMAG_SIZE + 1)
                        _pad[i][j][k] = _pad[i][j - 1][k - 1];
                    else begin
                        if(j===0) 
                            _pad[i][j][k] = _pad[i][j + 1][k];
                        else if(j===IMAG_SIZE + 1)
                            _pad[i][j][k] = _pad[i][j - 1][k];
                        else if(k===0)
                            _pad[i][j][k] = _pad[i][j][k + 1];
                        else if(k===IMAG_SIZE + 1)
                            _pad[i][j][k] = _pad[i][j][k - 1];
                    end
                end
                else begin
                    if(j===0 || j===IMAG_SIZE + 1)
                        _pad[i][j][k] = 0;
                    if(k===0 || k===IMAG_SIZE + 1)
                        _pad[i][j][k] = 0;
                end
            end
        end
    end
end endtask


task cal_task; 
    integer i,j,k,m;
begin
    for(i = 1; i <= KERNEL_INPUT; i = i + 1) begin
        for(j = 1; j <= IMAG_NUM; j = j + 1) begin
            for(k = 0; k <= IMAG_SIZE ; k = k + 1) begin
                for(m = 0; m <= IMAG_SIZE ; m = m + 1) begin
                    _conv[i][j][k][m] = _conv_w[i][j][k][m];
                end
            end
        end
    end
    for(i = 1; i <= KERNEL_INPUT; i = i + 1) begin
        for(k = 0; k <= IMAG_SIZE ; k = k + 1) begin
            for(m = 0; m <= IMAG_SIZE ; m = m + 1) begin
                _conv_sum[i][k][m] = _conv_sum_w[i][k][m];
            end
        end
    end
    for(i = 1 ; i <= KERNEL_INPUT ; i = i + 1) begin
        for(j = 0 ; j < 2 ; j = j + 1) begin
            for(k = 0 ; k < 2 ; k = k + 1) begin
                _pool[i][j][k] = _pool_w[i][j][k];
            end
        end
    end
    for(i = 1 ; i <= KERNEL_INPUT ; i = i + 1) begin
        for(j = 0 ; j < 2 ; j = j + 1) begin
            for(k = 0 ; k < 2 ; k = k + 1) begin
                _encode[i][j][k] = _encode_w[i][j][k];
            end
        end
    end
    for(i = 0 ; i <= 2 ; i = i + 1) begin
        _full[i] = _full_w[i];
    end
    for(i = 0 ; i <= 2 ; i = i + 1) begin
        _soft[i] = _soft_w[i];
    end
end endtask

task wait_task; begin
    latency = 0;
    while (out_valid !== 1) begin
        if(latency == 200) begin
            $display("*************************************************************************");
		    $display("*                              FAIL!                                    *");
		    $display("*         The execution latency is limited in 200 cycles.               *");
		    $display("*************************************************************************");
		    repeat(2) @(negedge clk);
		    $finish;
        end
        latency = latency + 1;
        @(negedge clk);
    end
end endtask

task check_task; begin
    out_num = 0;
    while (out_valid === 1) begin
        _out[out_num] = out;
        if(_isErr[out_num] !== 0) begin
            $display("************************************************************");  
            $display("                          FAIL!                           ");
            $display(" Expected: ans = %8h", _soft[out_num]);
            $display(" Received: ans = %8h", out);
            $display("************************************************************");
            $finish;
        end
        else begin
            @(negedge clk);
            out_num = out_num + 1;
        end
    end

    if(out_num !== 3) begin
            $display("************************************************************");  
            $display("                          FAIL!                              ");
            $display(" Expected three valid output, but found %d", out_num);
            $display("************************************************************");
            repeat(2) @(negedge clk);
            $finish;
    end

end endtask

task YOU_PASS_task; begin
        $display("----------------------------------------------------------------------------------------------------------------------");
        $display("                                                  Congratulations!                                                    ");
        $display("                                           You have passed all patterns!                                               ");
        $display("                                           Your execution cycles = %5d cycles                                          ", total_latency);
        $display("                                           Your clock period = %.1f ns                                                 ", CYCLE);
        $display("                                           Total Latency = %.1f ns                                                    ", total_latency * CYCLE);
        $display("----------------------------------------------------------------------------------------------------------------------");
        repeat (2) @(negedge clk);
        $finish;
    end endtask

//=================
// Convolution
//=================
genvar i_input, i_imag, i_row, i_col, i_innner;
generate
    for(i_input = 1 ; i_input <= KERNEL_INPUT ; i_input = i_input + 1) begin : gen_conv
        for(i_imag = 1 ; i_imag <= KERNEL_NUM ; i_imag = i_imag + 1) begin
            for(i_row = 0 ; i_row <= IMAG_SIZE; i_row = i_row + 1) begin
                for(i_col = 0 ; i_col <= IMAG_SIZE ; i_col = i_col + 1) begin
                    wire [inst_sig_width+inst_exp_width:0] out1;
                    convSubMult #(inst_sig_width, inst_exp_width, inst_ieee_compliance)
                    CSM(
                        // Image
                        _pad[i_imag][i_row][i_col],   _pad[i_imag][i_row][i_col+1],   
                        _pad[i_imag][i_row+1][i_col], _pad[i_imag][i_row+1][i_col+1],
                        // Kernel
                        _kernel[i_input][i_imag][0][0], _kernel[i_input][i_imag][0][1],
                        _kernel[i_input][i_imag][1][0], _kernel[i_input][i_imag][1][1],

                        // Output
                        out1
                    );
                    assign _conv_w[i_input][i_imag][i_row][i_col] = out1;
                end
            end
        end
    end
endgenerate

//=================
// Convolution Sum
//=================
generate
    for(i_input = 1 ; i_input <= KERNEL_INPUT ; i_input = i_input + 1) begin : gen_conv_sum
        for(i_row = 0 ; i_row <= IMAG_SIZE ; i_row = i_row + 1) begin
            for(i_col = 0 ; i_col <= IMAG_SIZE ; i_col = i_col + 1) begin
                wire [inst_sig_width+inst_exp_width:0] add0;
                wire [inst_sig_width+inst_exp_width:0] add1;
                DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
                    A0 (.a(_conv_w[i_input][1][i_row][i_col]), .b(_conv_w[i_input][2][i_row][i_col]), .op(1'd0), .rnd(3'd0), .z(add0));
                
                DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
                    A1 (.a(add0), .b(_conv_w[i_input][3][i_row][i_col]), .op(1'd0), .rnd(3'd0), .z(add1));
                
                assign _conv_sum_w[i_input][i_row][i_col] = add1;
            end
        end
    end
endgenerate

//=================
// Maxpooling
//=================
generate
    for(i_input = 1 ; i_input <= KERNEL_INPUT ; i_input = i_input + 1) begin : gen_maxpool
        for(i_row = 0 ; i_row < 2 ; i_row = i_row + 1) begin
            for(i_col = 0 ; i_col < 2 ; i_col = i_col + 1) begin
                wire [inst_sig_width+inst_exp_width:0] min;
                wire [inst_sig_width+inst_exp_width:0] max;
                findMinAndMax#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
                    FMAM(
                        _conv_sum_w[i_input][i_row*3][i_col*3],
                        _conv_sum_w[i_input][i_row*3][i_col*3 + 1],
                        _conv_sum_w[i_input][i_row*3][i_col*3 + 2],
                        _conv_sum_w[i_input][i_row*3+1][i_col*3],
                        _conv_sum_w[i_input][i_row*3+1][i_col*3 + 1],
                        _conv_sum_w[i_input][i_row*3+1][i_col*3 + 2],
                        _conv_sum_w[i_input][i_row*3+2][i_col*3],
                        _conv_sum_w[i_input][i_row*3+2][i_col*3 + 1],
                        _conv_sum_w[i_input][i_row*3+2][i_col*3 + 2],
                        min, max
                    ); 
                assign _pool_w[i_input][i_row][i_col] = max;
            end
        end
    end
endgenerate

//=================
// Encode
//=================
generate
    for(i_input = 1 ; i_input <= KERNEL_INPUT ; i_input = i_input + 1) begin : gen_encode
        for(i_row = 0 ; i_row < 2 ; i_row = i_row + 1) begin
            for(i_col = 0 ; i_col < 2 ; i_col = i_col + 1) begin
                wire [inst_sig_width+inst_exp_width:0] sigmoid_out;
                wire [inst_sig_width+inst_exp_width:0] tanh_out;
                sigmoid#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
                    s(_pool_w[i_input][i_row][i_col], sigmoid_out);
                tanh#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
                    t(_pool_w[i_input][i_row][i_col], tanh_out);
                assign _encode_w[i_input][i_row][i_col] = _opt==1 ? tanh_out : sigmoid_out;
            end
        end
    end
endgenerate

//=================
// Fully Connected
//=================
// TODO : improve generate for
generate
    for(i_input = 1 ; i_input <= 3 ; i_input = i_input + 1) begin : gen_full

        wire [inst_sig_width+inst_exp_width:0] out0;
        wire [inst_sig_width+inst_exp_width:0] out1;
        wire [inst_sig_width+inst_exp_width:0] out2, out3, out4, out5, out6, out7;
        wire [inst_sig_width+inst_exp_width:0] add0, add1, add2, add3, add4, add5, add6, add7;

        DW_fp_mult#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
            M0 (.a(_encode_w[1][0][0]), .b(_weight[i_input][0]), .rnd(3'd0), .z(out0));
        DW_fp_mult#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
            M1 (.a(_encode_w[1][0][1]), .b(_weight[i_input][1]), .rnd(3'd0), .z(out1));
        DW_fp_mult#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
            M2 (.a(_encode_w[1][1][0]), .b(_weight[i_input][2]), .rnd(3'd0), .z(out2));
        DW_fp_mult#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
            M3 (.a(_encode_w[1][1][1]), .b(_weight[i_input][3]), .rnd(3'd0), .z(out3));
        DW_fp_mult#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
            M4 (.a(_encode_w[2][0][0]), .b(_weight[i_input][4]), .rnd(3'd0), .z(out4));
        DW_fp_mult#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
            M5 (.a(_encode_w[2][0][1]), .b(_weight[i_input][5]), .rnd(3'd0), .z(out5));
        DW_fp_mult#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
            M6 (.a(_encode_w[2][1][0]), .b(_weight[i_input][6]), .rnd(3'd0), .z(out6));
        DW_fp_mult#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
            M7 (.a(_encode_w[2][1][1]), .b(_weight[i_input][7]), .rnd(3'd0), .z(out7));

        DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
            A0 (.a(out0), .b(out1), .op(1'd0), .rnd(3'd0), .z(add0));
        DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
            A1 (.a(add0), .b(out2), .op(1'd0), .rnd(3'd0), .z(add1));
        DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
            A2 (.a(add1), .b(out3), .op(1'd0), .rnd(3'd0), .z(add2));
        DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
            A3 (.a(add2), .b(out4), .op(1'd0), .rnd(3'd0), .z(add3));
        DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
            A4 (.a(add3), .b(out5), .op(1'd0), .rnd(3'd0), .z(add4));
        DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
            A5 (.a(add4), .b(out6), .op(1'd0), .rnd(3'd0), .z(add5));
        DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
            A6 (.a(add5), .b(out7), .op(1'd0), .rnd(3'd0), .z(add6));
        
        assign _full_w[i_input - 1] = add6;
    end
endgenerate

//=================
// Soft Max
//=================
// TODO : improve generate for
generate
    for(i_input = 0 ; i_input <= 2; i_input = i_input + 1) begin
        wire [inst_sig_width+inst_exp_width:0] out0;
        wire [inst_sig_width+inst_exp_width:0] add0, add1;
        wire [inst_sig_width+inst_exp_width:0] exp0, exp1, exp2, exp3;

        DW_fp_exp // exp(x)
        #(inst_sig_width,inst_exp_width,inst_ieee_compliance, inst_arch)
            E0 (.a(_full_w[0]), .z(exp0));
        DW_fp_exp // exp(x)
        #(inst_sig_width,inst_exp_width,inst_ieee_compliance, inst_arch)
            E1 (.a(_full_w[1]), .z(exp1));
        DW_fp_exp // exp(x)
        #(inst_sig_width,inst_exp_width,inst_ieee_compliance, inst_arch)
            E2 (.a(_full_w[2]), .z(exp2));
        DW_fp_exp // exp(x)
        #(inst_sig_width,inst_exp_width,inst_ieee_compliance, inst_arch)
            E3 (.a(_full_w[i_input]), .z(exp3));

        DW_fp_div // [exp(x)-exp(-x)] / [exp(x)+exp(-x)]
        #(inst_sig_width,inst_exp_width,inst_ieee_compliance, 0)
            D0 (.a(exp3), .b(add1), .rnd(3'd0), .z(out0));

        DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
            A0 (.a(exp0), .b(exp1), .op(1'd0), .rnd(3'd0), .z(add0));
        DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
            A1 (.a(add0), .b(exp2), .op(1'd0), .rnd(3'd0), .z(add1));
        
        assign _soft_w[i_input] = out0;
    end
endgenerate

//======================================
//      Error Calculation
//======================================
generate
    for(i_input = 0 ; i_input < 3 ; i_input = i_input + 1) begin : gen_err
        wire [inst_sig_width+inst_exp_width:0] bound;
        wire [inst_sig_width+inst_exp_width:0] error_diff;
        wire [inst_sig_width+inst_exp_width:0] error_diff_pos;
        DW_fp_sub
        #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
            Err_S0 (.a(_soft_w[i_input]), .b(out), .z(error_diff), .rnd(3'd0));

        // gold * _errAllow
        //DW_fp_mult
        //#(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
        //    Err_M0 (.a(_errAllow), .b(_soft_w[i_input]), .z(bound), .rnd(3'd0));

        // check |gold - ans| > _errAllow * gold
        DW_fp_cmp
        #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
            Err_C0 (.a(error_diff_pos), .b(_errAllow), .agtb(_isErr[i_input]), .zctr(1'd0));

        assign error_diff_pos = error_diff[inst_sig_width+inst_exp_width] ? {1'b0, error_diff[inst_sig_width+inst_exp_width-1:0]} : error_diff;
        assign _errDiff_w = error_diff_pos;
        assign _errBound_w = bound;
    end
endgenerate


function [31:0] _randinput;
    input integer _i_pat;
    reg [6:0] rand_fract;
    integer idx;
    begin
        _randinput = 0;
        if(_i_pat < 100) begin
            _randinput = 0;
            _randinput[31] = {$random(SEED)} % 2;
            _randinput[30:23] = {$random(SEED)} % 4 + 123;
        end
        else begin
            _randinput = 0;
            _randinput[31] = {$random(SEED)} % 2;
            _randinput[30:23] = {$random(SEED)} % 9 + 118;
            rand_fract = {$random(SEED)} % 128;
            for(idx = 0; idx < 7; idx = idx + 1) begin
                _randinput[22 - idx] = rand_fract[6-idx];
            end
        end
    end
endfunction


endmodule

module convSubMult
#(  parameter inst_sig_width       = 23,
    parameter inst_exp_width       = 8,
    parameter inst_ieee_compliance = 0
)
(
    input  [inst_sig_width+inst_exp_width:0] a0, a1, a2, a3,
    input  [inst_sig_width+inst_exp_width:0] b0, b1, b2, b3,
    output [inst_sig_width+inst_exp_width:0] out
);

    wire [inst_sig_width+inst_exp_width:0] pixel0, pixel1, pixel2, pixel3;

    // Multiplication
    DW_fp_mult#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
        M0 (.a(a0), .b(b0), .rnd(3'd0), .z(pixel0));
    
    DW_fp_mult#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
        M1 (.a(a1), .b(b1), .rnd(3'd0), .z(pixel1));
    
    DW_fp_mult#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
        M2 (.a(a2), .b(b2), .rnd(3'd0), .z(pixel2));
    
    DW_fp_mult#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
        M3 (.a(a3), .b(b3), .rnd(3'd0), .z(pixel3));
    

    wire [inst_sig_width+inst_exp_width:0] add0, add1;

    // Addition
    DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        A0 (.a(pixel0), .b(pixel1), .op(1'd0), .rnd(3'd0), .z(add0));

    DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        A1 (.a(add0), .b(pixel2), .op(1'd0), .rnd(3'd0), .z(add1));

    DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        A2 (.a(add1), .b(pixel3), .op(1'd0), .rnd(3'd0), .z(out));

endmodule

module findMinAndMax
#(  parameter inst_sig_width       = 23,
    parameter inst_exp_width       = 8,
    parameter inst_ieee_compliance = 0
)
(
    input  [inst_sig_width+inst_exp_width:0] a0, a1, a2, a3, a4, a5, a6, a7, a8,
    output [inst_sig_width+inst_exp_width:0] minOut, maxOut
);
    wire [inst_sig_width+inst_exp_width:0] max0, max1, max2, max3, max4, max5, max6;
    wire [inst_sig_width+inst_exp_width:0] min0, min1, min2, min3, min4, min5, min6;
    wire flag0;
    wire flag1;
    wire flag2;
    wire flag3;
    wire flag4, flag5, flag6, flag7, flag8, flag9, flag10, flag11;
    DW_fp_cmp #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
        C0_1 (.a(a0), .b(a1), .agtb(flag0), .zctr(1'd0));
    DW_fp_cmp #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
        C0_2 (.a(a2), .b(a3), .agtb(flag1), .zctr(1'd0));
    DW_fp_cmp #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
        C0_3 (.a(a4), .b(a5), .agtb(flag2), .zctr(1'd0));
    DW_fp_cmp #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
        C0_4 (.a(a6), .b(a7), .agtb(flag3), .zctr(1'd0));
    
    DW_fp_cmp #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
        Cmax0 (.a(max0), .b(max1), .agtb(flag4), .zctr(1'd0));
    DW_fp_cmp #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
        Cmax1 (.a(max2), .b(max3), .agtb(flag5), .zctr(1'd0));
    DW_fp_cmp #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
        Cmax2 (.a(max4), .b(max5), .agtb(flag8), .zctr(1'd0));
    DW_fp_cmp #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
        Cmin0 (.a(min0), .b(min1), .agtb(flag6), .zctr(1'd0));
    DW_fp_cmp #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
        Cmin1 (.a(min2), .b(min3), .agtb(flag7), .zctr(1'd0));
    DW_fp_cmp #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
        Cmin2 (.a(min4), .b(min5), .agtb(flag9), .zctr(1'd0));

    DW_fp_cmp #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
        Cmax3 (.a(max6), .b(a8), .agtb(flag10), .zctr(1'd0));
    DW_fp_cmp #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
        Cmin3 (.a(min6), .b(a8), .agtb(flag11), .zctr(1'd0));

    assign max0 = flag0==1 ? a0 : a1;
    assign max1 = flag1==1 ? a2 : a3;
    assign max2 = flag2==1 ? a4 : a5;
    assign max3 = flag3==1 ? a6 : a7;

    assign min0 = flag0==1 ? a1 : a0;
    assign min1 = flag1==1 ? a3 : a2;
    assign min2 = flag2==1 ? a5 : a4;
    assign min3 = flag3==1 ? a7 : a6;

    assign max4 = flag4 ? max0 : max1;
    assign max5 = flag5 ? max2 : max3;
    
    assign min4 = flag6 ? min1 : min0;
    assign min5 = flag7 ? min3 : min2;

    assign max6 = flag8 ? max4 : max5;
    assign min6 = flag9 ? min5 : min4;

    assign maxOut = flag10==1 ? max6 : a8;
    assign minOut = flag11==1 ? a8 : min6;
endmodule

module sigmoid
#(  parameter inst_sig_width       = 23,
    parameter inst_exp_width       = 8,
    parameter inst_ieee_compliance = 0,
    parameter inst_arch            = 0
)
(
    input  [inst_sig_width+inst_exp_width:0] in,
    output [inst_sig_width+inst_exp_width:0] out
);
    wire [inst_sig_width+inst_exp_width:0] float_gain1 = 32'h3F800000; // Activation 1.0
    wire [inst_sig_width+inst_exp_width:0] float_gain2 = 32'hBF800000; // Activation -1.0
    wire [inst_sig_width+inst_exp_width:0] x_neg;
    wire [inst_sig_width+inst_exp_width:0] exp;
    wire [inst_sig_width+inst_exp_width:0] deno;

    DW_fp_mult // -x
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        M0 (.a(in), .b(float_gain2), .rnd(3'd0), .z(x_neg));
    
    DW_fp_exp // exp(-x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, inst_arch)
        E0 (.a(x_neg), .z(exp));
    
    DW_fp_addsub // 1+exp(-x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        A0 (.a(float_gain1), .b(exp), .op(1'd0), .rnd(3'd0), .z(deno));
    
    DW_fp_div // 1 / [1+exp(-x)]
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, 0)
        D0 (.a(float_gain1), .b(deno), .rnd(3'd0), .z(out));
endmodule

module tanh
#(  parameter inst_sig_width       = 23,
    parameter inst_exp_width       = 8,
    parameter inst_ieee_compliance = 0,
    parameter inst_arch            = 0
)
(
    input  [inst_sig_width+inst_exp_width:0] in,
    output [inst_sig_width+inst_exp_width:0] out
);
    wire [inst_sig_width+inst_exp_width:0] float_gain1 = 32'h3F800000; // Activation 1.0
    wire [inst_sig_width+inst_exp_width:0] float_gain2 = 32'hBF800000; // Activation -1.0
    wire [inst_sig_width+inst_exp_width:0] x_neg;
    wire [inst_sig_width+inst_exp_width:0] exp_pos;
    wire [inst_sig_width+inst_exp_width:0] exp_neg;
    wire [inst_sig_width+inst_exp_width:0] nume;
    wire [inst_sig_width+inst_exp_width:0] deno;

    DW_fp_mult // -x
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        M0 (.a(in), .b(float_gain2), .rnd(3'd0), .z(x_neg));
    
    DW_fp_exp // exp(-x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, inst_arch)
        E0 (.a(x_neg), .z(exp_neg));

    DW_fp_exp // exp(x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, inst_arch)
        E1 (.a(in), .z(exp_pos));

    //

    DW_fp_addsub // exp(x)-exp(-x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        A0 (.a(exp_pos), .b(exp_neg), .op(1'd1), .rnd(3'd0), .z(nume));

    DW_fp_addsub // exp(x)+exp(-x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        A1 (.a(exp_pos), .b(exp_neg), .op(1'd0), .rnd(3'd0), .z(deno));

    DW_fp_div // [exp(x)-exp(-x)] / [exp(x)+exp(-x)]
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, 0)
        D0 (.a(nume), .b(deno), .rnd(3'd0), .z(out));
endmodule
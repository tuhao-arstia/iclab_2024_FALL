/**************************************************************************/
// Copyright (c) 2024, OASIS Lab
// MODULE: SA
// FILE NAME: PATTERN_CG.v
// VERSRION: 1.0
// DATE: Nov 06, 2024
// AUTHOR: Yen-Ning Tung, NYCU AIG
// CODE TYPE: RTL or Behavioral Level (Verilog)
// DESCRIPTION: 2024 Fall IC Lab / Exersise Lab08 / PATTERN_CG
// MODIFICATION HISTORY:
// Date                 Description
// 
/**************************************************************************/

module PATTERN(
    // Output signals
    clk,
    rst_n,
    cg_en,
    in_valid,
    T,
    in_data,
    w_Q,
    w_K,
    w_V,

    // Input signals
    out_valid,
    out_data
);

output reg clk;
output reg rst_n;
output reg cg_en;
output reg in_valid;
output reg [3:0] T;
output reg signed [7:0] in_data;
output reg signed [7:0] w_Q;
output reg signed [7:0] w_K;
output reg signed [7:0] w_V;

input out_valid;
input signed [63:0] out_data;

//================================================================
// Clock
//================================================================
real CYCLE = 50;
always #(CYCLE/2.0) clk = ~clk;

//================================================================
// parameters & integer
//================================================================
integer i,j, i_pat;
integer total_latency, latency;
integer total_pattern = 1000;
integer SEED = 1234;
integer out_num;


//================================================================
// Wire & Reg Declaration
//================================================================
reg [3:0] T_in;
reg signed [7:0] in_data_in[0:7][0:7];
reg signed [7:0] w_Q_in[0:7][0:7];
reg signed [7:0] w_K_in[0:7][0:7];
reg signed [7:0] w_V_in[0:7][0:7];

reg signed [63:0] w_Q_linear[0:7][0:7];
reg signed [63:0] w_K_linear[0:7][0:7];
reg signed [63:0] w_V_linear[0:7][0:7];

reg signed [63:0] matmul_1_out[0:7][0:7];
reg signed [63:0] scale_out[0:7][0:7];
reg signed [63:0] ReLu_out[0:7][0:7];
reg signed [63:0] matmul_2_out[0:7][0:7];


//================================================================
// Task & Function Declaration
//================================================================
always @(negedge clk) begin
	if(out_valid === 0 && out_data !== 'd0) begin
		$display("*************************************************************************");
		$display("*                              \033[1;31mFAIL!\033[1;0m                                    *");
		$display("*       The out_data should be reset when your out_valid is low.        *");
		$display("*************************************************************************");
		repeat(1) #(CYCLE);
		$finish;
	end
end

initial begin
	//reset signal
	reset_task; 
    repeat (4) @(negedge clk);
	i_pat = 0;
	total_latency = 0;

    cg_en = 1'b1;
	for (i_pat = 0; i_pat < total_pattern; i_pat = i_pat + 1) begin
        input_task;
        wait_out_valid_task;
        check_ans_task;
		total_latency = total_latency + latency;
        $display("\033[1;34mPASS PATTERN \033[1;32mNO.%4d  Cycles = %4d\033[m", i_pat,latency);
    end

	YOU_PASS_task;

end

task reset_task; begin
	rst_n = 1'b1;
	in_valid = 1'b0;
    cg_en = 1'b0;
	T = 'bx;
	in_data = 'bx;
	w_Q = 'bx;
	w_K = 'bx;
	w_V = 'bx;

	force clk = 0;

	// Apply reset
    #CYCLE; rst_n = 1'b0; 
    repeat(2) #(CYCLE); rst_n = 1'b1;

	// Check initial conditions
    if (out_valid !== 'd0 || out_data !== 'd0) begin
        $display("************************************************************");  
        $display("                           \033[1;31mFAIL!\033[1;0m                             ");    
        $display("*  Output signals should be 0 after initial RESET at %8t *", $time);
        $display("************************************************************");
        repeat (1) #CYCLE;
        $finish;
    end

	#CYCLE; release clk;
end endtask

task input_task; 
	integer m;
begin
    random_input;

    in_valid = 1;

    for(i = 0; i < 192; i = i + 1)begin
        if(i == 0)begin
			T = T_in;
		end
		else begin
			T = 'bx;
		end
		
		if((i/8) < T_in) begin
			in_data = in_data_in[i/8][i%8];
		end
		else begin
			in_data = 'bx;
		end

		if(i < 64) begin
			w_Q = w_Q_in[i/8][i%8];
			w_K = 'bx;
			w_V = 'bx;
		end
		else if(i < 128) begin
			w_Q = 'bx;
			w_K = w_K_in[(i/8) % 8][i%8];
			w_V = 'bx;
		end
		else begin
			w_Q = 'bx;
			w_K = 'bx;
			w_V = w_V_in[(i/8) % 8][i%8];
		end

		if(out_valid !== 0 || out_data !== 'd0) begin
			$display("*************************************************************************");
			$display("*                              \033[1;31mFAIL!\033[1;0m                                    *");
			$display("*       Output signal out_valid and out_data should be zero when in_valid is high.        *");
			$display("*************************************************************************");
			repeat(1) #(CYCLE);
			$finish;
		end

		@(negedge clk);
    end

	in_valid = 1'b0;
	T = 'bx;
	in_data = 'bx;
	w_Q = 'bx;
	w_K = 'bx;
	w_V = 'bx;

    cal_ans;
end
endtask

task wait_out_valid_task; begin
	latency = 0;
	while (out_valid !== 1'b1) begin
		latency = latency + 1;
		if(latency == 2000)begin
            $display("*************************************************************************");
		    $display("*                              \033[1;31mFAIL!\033[1;0m                                    *");
		    $display("*         The execution latency is limited in 2000 cycles.              *");
		    $display("*************************************************************************");
		    repeat(1) @(negedge clk);
		    $finish;
        end

		@(negedge clk);
	end
	
end
endtask

task check_ans_task; begin 
    out_num = 0;
    while(out_valid === 1) begin
	    if (out_data !== matmul_2_out[out_num/8][out_num%8]) begin
                $display("************************************************************");  
                $display("                          \033[1;31mFAIL!\033[1;0m                              ");
                $display(" Expected: data = %d", matmul_2_out[out_num/8][out_num%8]);
                $display(" Received: data = %d", out_data);
                $display("************************************************************");
                repeat (1) @(negedge clk);
                $finish;

        end
        else begin
            @(negedge clk);
            out_num = out_num + 1;
        end
    end

    if(out_num !== (T_in * 8)) begin
            $display("************************************************************");  
            $display("                            \033[1;31mFAIL!\033[1;0m                            ");
            $display(" Expected %d out_valid, but found %d",(T_in * 8), out_num);
            $display("************************************************************");
            repeat(2) @(negedge clk);
            $finish;
    end

    repeat({$random(SEED)} % 4 + 2)@(negedge clk);
end endtask 

task random_input; 
    integer idx,idy, x, y;
    
begin
	x = {$random(SEED)} % 3;

	if(x == 0)
		T_in = 'd1;
	else if(x == 1)
		T_in = 'd8;
	else 
		T_in = 'd4;
	
	if(i_pat < 10) begin // simple case
		for(idy = 0; idy < 8; idy = idy + 1) begin
        	for(idx = 0; idx < 8; idx = idx + 1)begin
        	    in_data_in[idy][idx] = ({$random(SEED)} % 19) - 9;
				w_Q_in[idy][idx] = ({$random(SEED)} % 19) - 9;
				w_K_in[idy][idx] = ({$random(SEED)} % 19) - 9;
				w_V_in[idy][idx] = ({$random(SEED)} % 19) - 9;
        	end
    	end
	end
	else if(i_pat == 10)begin // max case
		T_in = 'd8;
		for(idy = 0; idy < 8; idy = idy + 1) begin
        	for(idx = 0; idx < 8; idx = idx + 1)begin
        	    in_data_in[idy][idx] = 127;
				w_Q_in[idy][idx] = 127;
				w_K_in[idy][idx] = 127;
				w_V_in[idy][idx] = 127;
        	end
    	end
	end
	else if(i_pat == 11)begin // min case
		T_in = 'd8;
		for(idy = 0; idy < 8; idy = idy + 1) begin
        	for(idx = 0; idx < 8; idx = idx + 1)begin
        	    in_data_in[idy][idx] = 0 - 128;
				w_Q_in[idy][idx] = 0 - 128;
				w_K_in[idy][idx] = 0 - 128;
				w_V_in[idy][idx] = 0 - 128;
        	end
    	end
	end
	else begin
		for(idy = 0; idy < 8; idy = idy + 1) begin
        	for(idx = 0; idx < 8; idx = idx + 1)begin
        	    in_data_in[idy][idx] = ({$random(SEED)} % 256) - 128;
				w_Q_in[idy][idx] = ({$random(SEED)} % 256) - 128;
				w_K_in[idy][idx] = ({$random(SEED)} % 256) - 128;
				w_V_in[idy][idx] = ({$random(SEED)} % 256) - 128;
        	end
    	end
	end

    
end
endtask



task cal_ans; 
begin 
	linear_transformation;
	matmul_1;
	scale;
	ReLu;
	matmul_2;
end
endtask

task linear_transformation; 
	integer i,j,k;
	reg signed [63:0] sum;
	reg signed [63:0] temp[0:7][0:7];
begin
	for(i = 0; i < 8; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			temp[i][j] = 0;
		end
	end
	for(i = 0; i < T_in; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			sum = 0;
			for(k = 0; k < 8; k = k + 1) begin
				sum = sum + in_data_in[i][k] * w_Q_in[k][j];
			end
			temp[i][j] = sum;
		end
	end

	for(i = 0; i < 8; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			w_Q_linear[i][j] = temp[i][j];
		end
	end

	for(i = 0; i < 8; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			temp[i][j] = 0;
		end
	end

	for(i = 0; i < T_in; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			sum = 0;
			for(k = 0; k < 8; k = k + 1) begin
				sum = sum + in_data_in[i][k] * w_K_in[k][j];
			end
			temp[i][j] = sum;
		end
	end

	for(i = 0; i < 8; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			w_K_linear[i][j] = temp[i][j];
		end
	end

	for(i = 0; i < 8; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			temp[i][j] = 0;
		end
	end

	for(i = 0; i < T_in; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			sum = 0;
			for(k = 0; k < 8; k = k + 1) begin
				sum = sum + in_data_in[i][k] * w_V_in[k][j];
			end
			temp[i][j] = sum;
		end
	end

	for(i = 0; i < 8; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			w_V_linear[i][j] = temp[i][j];
		end
	end
end
endtask

task matmul_1; 
	integer i,j,k;
	reg signed [63:0] sum;
	reg signed [63:0] temp[0:7][0:7];
begin
	for(i = 0; i < 8; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			temp[i][j] = 0;
		end
	end
	// Q * K transpose
	for(i = 0; i < T_in; i = i + 1) begin
		for(j = 0; j < T_in; j = j + 1) begin
			sum = 0;
			for(k = 0; k < 8; k = k + 1) begin
				sum = sum + w_Q_linear[i][k] * w_K_linear[j][k];
			end
			temp[i][j] = sum;
		end
	end

	for(i = 0; i < 8; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			matmul_1_out[i][j] = temp[i][j];
		end
	end
end
endtask

task scale; 
	integer i,j;
	reg signed [63:0] temp[0:7][0:7];
begin
	for(i = 0; i < 8; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			temp[i][j] = 0;
		end
	end

	for(i = 0; i < 8; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			temp[i][j] = matmul_1_out[i][j] / 3;
		end
	end

	for(i = 0; i < 8; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			scale_out[i][j] = temp[i][j];
		end
	end
end
endtask

task ReLu; 
	integer i,j;
begin
	for(i = 0; i < 8; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			ReLu_out[i][j] = 0;
		end
	end

	for(i = 0; i < 8; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			if(scale_out[i][j] < 0)
				ReLu_out[i][j] = 0;
			else
				ReLu_out[i][j] = scale_out[i][j];
		end
	end
end
endtask

task matmul_2; 
	integer i,j,k;
	reg signed [63:0] sum;
	reg signed [63:0] temp[0:7][0:7];
begin
	for(i = 0; i < 8; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			temp[i][j] = 0;
		end
	end
	// ReLu_out * V
	for(i = 0; i < T_in; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			sum = 0;
			for(k = 0; k < T_in; k = k + 1) begin
				sum = sum + ReLu_out[i][k] * w_V_linear[k][j];
			end
			temp[i][j] = sum;
		end
	end

	for(i = 0; i < 8; i = i + 1) begin
		for(j = 0; j < 8; j = j + 1) begin
			matmul_2_out[i][j] = temp[i][j];
		end
	end
end
endtask

task YOU_PASS_task; begin
    $display("----------------------------------------------------------------------------------------------------------------------");
    $display("                                                  \033[0;32mCongratulations!\033[m                                                     ");
    $display("                                           You have passed all patterns!                                               ");
    $display("                                           Your execution cycles = %7d cycles                                          ", total_latency);
    $display("                                           Your clock period = %.1f ns                                                 ", CYCLE);
    $display("                                           Total Latency = %.1f ns                                                    ", total_latency * CYCLE);
    $display("----------------------------------------------------------------------------------------------------------------------");
    repeat (2) @(negedge clk);
    $finish;
end endtask

endmodule
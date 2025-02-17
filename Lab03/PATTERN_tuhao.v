/**************************************************************************/
// Copyright (c) 2024, OASIS Lab
// MODULE: PATTERN
// FILE NAME: PATTERN.v
// VERSRION: 1.0
// DATE: August 15, 2024
// AUTHOR: Yu-Hsuan Hsu, NYCU IEE
// DESCRIPTION: ICLAB2024FALL / LAB3 / PATTERN
// MODIFICATION HISTORY:
// Date                 Description
// 
/**************************************************************************/

`ifdef RTL
    `define CYCLE_TIME 7.4
`endif
`ifdef GATE
    `define CYCLE_TIME 7.4
`endif

module PATTERN(
	//OUTPUT
	rst_n,
	clk,
	in_valid,
	tetrominoes,
	position,
	//INPUT
	tetris_valid,
	score_valid,
	fail,
	score,
	tetris
);

//---------------------------------------------------------------------
//   PORT DECLARATION          
//---------------------------------------------------------------------
output reg			rst_n, clk, in_valid;
output reg	[2:0]	tetrominoes;
output reg  [2:0]	position;
input 				tetris_valid, score_valid, fail;
input 		[3:0]	score;
input		[71:0]	tetris;

//---------------------------------------------------------------------
//   PARAMETER & INTEGER DECLARATION
//---------------------------------------------------------------------
integer total_latency;
real CYCLE = `CYCLE_TIME;
integer pat_read;
integer PAT_NUM;
integer i_pat;
integer pat_num_now;
integer i, j, idx, a;
integer latency, out_latency;

//---------------------------------------------------------------------
//   REG & WIRE DECLARATION
//---------------------------------------------------------------------
reg [2:0]  pat_tetris, nt;
reg [2:0]  pat_pos, np;
reg [5:0]  tetris_temp[0:15];
reg [3:0]  score_temp;
reg        failed;
reg [3:0]  height[0:5];
reg [71:0] golden_tetris;
reg [3:0]  golden_score;
reg        golden_fail;   
//---------------------------------------------------------------------
//  CLOCK
//---------------------------------------------------------------------
always #(CYCLE/2.0) clk = ~clk;

//---------------------------------------------------------------------
//  SIMULATION
//---------------------------------------------------------------------
initial begin
    pat_read = $fopen("../00_TESTBED/input.txt", "r");
    reset_signal_task;

    i_pat = 0;
    idx = 0;
    total_latency = 0;
    a = $fscanf(pat_read, "%d", PAT_NUM);
    for (i_pat = 1; i_pat <= PAT_NUM; i_pat = i_pat + 1) begin
        a = $fscanf(pat_read, "%d", pat_num_now);
        clear_map_and_score_task;
        for (idx = 1; idx <= 16; idx = idx + 1)begin
            if(!failed)begin
                input_task;
                filled_map_task;
                elimination_task;
                check_fail_task;
                wait_score_valid_task;
                check_ans_task;
                repeat($urandom_range(0,3)) @(negedge clk);
            end else begin
                clear_rest_input_task;
            end
        end
        $display("PASS PATTERN NO.%4d", i_pat);
    end
    $fclose(pat_read);

    YOU_PASS_task;
end

//---------------------------------------------------------------------
//  TASK
//---------------------------------------------------------------------

task reset_signal_task; begin
    rst_n = 'b1;
    in_valid = 'b0;
    tetrominoes = 'bx;
    position = 'bx;

    force clk = 0;
    #CYCLE; rst_n = 0;
    #CYCLE; rst_n = 1;
    #(100);
    if( tetris_valid !== 0 || score_valid !== 0 || tetris !== 0 || score !== 0 || fail !== 0)begin
        $display("                    SPEC-4 FAIL                   ");
        repeat(2) #CYCLE;
        $finish;
    end
    #CYCLE; release clk;
end endtask

task clear_map_and_score_task; begin
    for(i = 0; i < 16; i = i + 1)begin
        tetris_temp[i] = 'd0;
    end
    for(i = 0; i < 72; i = i + 1)begin
        golden_tetris[i] = 'd0;
    end

    score_temp = 'd0;
    golden_score = 'd0;

    for(i = 0; i < 6; i = i + 1)begin
        height[i] = 'd0;
    end

    failed = 'd0;
    golden_fail = 'd0;
end endtask

task input_task; begin
    a = $fscanf(pat_read, "%d %d", pat_tetris, pat_pos);
    @(negedge clk);

    in_valid = 1'b1;
    tetrominoes = pat_tetris;
    position = pat_pos;
    @(negedge clk);

    in_valid = 1'b0;
    tetrominoes = 'bx;
    position = 'bx;
end endtask

task filled_map_task; begin
    case (pat_tetris)
        3'd0:begin
            if(height[pat_pos+1] > height[pat_pos])begin
                tetris_temp[height[pat_pos+1]]  [pat_pos+1] = 1;
                tetris_temp[height[pat_pos+1]]  [pat_pos]   = 1;
                tetris_temp[height[pat_pos+1]+1][pat_pos+1] = 1;
                tetris_temp[height[pat_pos+1]+1][pat_pos]   = 1;
            end else begin
                tetris_temp[height[pat_pos]]  [pat_pos+1] = 1;
                tetris_temp[height[pat_pos]]  [pat_pos]   = 1;
                tetris_temp[height[pat_pos]+1][pat_pos+1] = 1;
                tetris_temp[height[pat_pos]+1][pat_pos]   = 1;
            end
        end
        3'd1:begin
            tetris_temp[height[pat_pos]]  [pat_pos] = 1;
            tetris_temp[height[pat_pos]+1][pat_pos] = 1;
            tetris_temp[height[pat_pos]+2][pat_pos] = 1;
            tetris_temp[height[pat_pos]+3][pat_pos] = 1;
        end
        3'd2:begin
            if((height[pat_pos] >= height[pat_pos+1]) && (height[pat_pos] >= height[pat_pos+2]) && (height[pat_pos] >= height[pat_pos+3]))begin
                tetris_temp[height[pat_pos]][pat_pos]   = 1;
                tetris_temp[height[pat_pos]][pat_pos+1] = 1;
                tetris_temp[height[pat_pos]][pat_pos+2] = 1;
                tetris_temp[height[pat_pos]][pat_pos+3] = 1;
            end
            if((height[pat_pos+1] >= height[pat_pos]) && (height[pat_pos+1] >= height[pat_pos+2]) && (height[pat_pos+1] >= height[pat_pos+3]))begin
                tetris_temp[height[pat_pos+1]][pat_pos]   = 1;
                tetris_temp[height[pat_pos+1]][pat_pos+1] = 1;
                tetris_temp[height[pat_pos+1]][pat_pos+2] = 1;
                tetris_temp[height[pat_pos+1]][pat_pos+3] = 1;
            end
            if((height[pat_pos+2] >= height[pat_pos]) && (height[pat_pos+2] >= height[pat_pos+1]) && (height[pat_pos+2] >= height[pat_pos+3]))begin
                tetris_temp[height[pat_pos+2]][pat_pos]   = 1;
                tetris_temp[height[pat_pos+2]][pat_pos+1] = 1;
                tetris_temp[height[pat_pos+2]][pat_pos+2] = 1;
                tetris_temp[height[pat_pos+2]][pat_pos+3] = 1;
            end
            if((height[pat_pos+3] >= height[pat_pos]) && (height[pat_pos+3] >= height[pat_pos+1]) && (height[pat_pos+3] >= height[pat_pos+2]))begin
                tetris_temp[height[pat_pos+3]][pat_pos]   = 1;
                tetris_temp[height[pat_pos+3]][pat_pos+1] = 1;
                tetris_temp[height[pat_pos+3]][pat_pos+2] = 1;
                tetris_temp[height[pat_pos+3]][pat_pos+3] = 1;
            end
        end
        3'd3:begin
            if(height[pat_pos] >= (height[pat_pos+1]+2))begin
                tetris_temp[height[pat_pos]]  [pat_pos]   = 1;
                tetris_temp[height[pat_pos]]  [pat_pos+1] = 1;
                tetris_temp[height[pat_pos]-1][pat_pos+1] = 1;
                tetris_temp[height[pat_pos]-2][pat_pos+1] = 1;
            end else begin
                tetris_temp[height[pat_pos+1]]  [pat_pos+1] = 1;
                tetris_temp[height[pat_pos+1]+1][pat_pos+1] = 1;
                tetris_temp[height[pat_pos+1]+2][pat_pos+1] = 1;
                tetris_temp[height[pat_pos+1]+2][pat_pos] = 1;
            end
        end
        3'd4:begin
            if((height[pat_pos] + 1) >= height[pat_pos+1] && (height[pat_pos] + 1) >= height[pat_pos+2])begin
                tetris_temp[height[pat_pos]]  [pat_pos] = 1;
                tetris_temp[height[pat_pos]+1][pat_pos] = 1;
                tetris_temp[height[pat_pos]+1][pat_pos+1] = 1;
                tetris_temp[height[pat_pos]+1][pat_pos+2] = 1;
            end else begin
                if(height[pat_pos+1] > height[pat_pos+2])begin
                    tetris_temp[height[pat_pos+1]][pat_pos+1] = 1;
                    tetris_temp[height[pat_pos+1]][pat_pos]   = 1;
                    tetris_temp[height[pat_pos+1]][pat_pos+2] = 1;
                    tetris_temp[height[pat_pos+1]-1][pat_pos] = 1;
                end else begin
                    tetris_temp[height[pat_pos+2]][pat_pos+2] = 1;
                    tetris_temp[height[pat_pos+2]][pat_pos]   = 1;
                    tetris_temp[height[pat_pos+2]][pat_pos+1] = 1;
                    tetris_temp[height[pat_pos+2]-1][pat_pos] = 1;
                end
            end
        end
        3'd5:begin
            if(height[pat_pos] > height[pat_pos+1])begin
                tetris_temp[height[pat_pos]]  [pat_pos] = 1;
                tetris_temp[height[pat_pos]+1][pat_pos] = 1;
                tetris_temp[height[pat_pos]+2][pat_pos] = 1;
                tetris_temp[height[pat_pos]][pat_pos+1] = 1;
            end else begin
                tetris_temp[height[pat_pos+1]]  [pat_pos+1] = 1;
                tetris_temp[height[pat_pos+1]]  [pat_pos]   = 1;
                tetris_temp[height[pat_pos+1]+1][pat_pos]   = 1;
                tetris_temp[height[pat_pos+1]+2][pat_pos]   = 1;
            end
        end
        3'd6:begin
            if(height[pat_pos] > height[pat_pos+1])begin
                tetris_temp[height[pat_pos]]  [pat_pos] = 1;
                tetris_temp[height[pat_pos]+1][pat_pos] = 1;
                tetris_temp[height[pat_pos]]  [pat_pos+1] = 1;
                tetris_temp[height[pat_pos]-1][pat_pos+1] = 1;
            end else begin
                tetris_temp[height[pat_pos+1]]  [pat_pos+1] = 1;
                tetris_temp[height[pat_pos+1]+1][pat_pos+1] = 1;
                tetris_temp[height[pat_pos+1]+1][pat_pos] = 1;
                tetris_temp[height[pat_pos+1]+2][pat_pos] = 1;
            end
        end
        3'd7:begin
            if(height[pat_pos+2] > height[pat_pos] && height[pat_pos+2] > height[pat_pos+1])begin
                tetris_temp[height[pat_pos+2]]  [pat_pos+2] = 1;
                tetris_temp[height[pat_pos+2]]  [pat_pos+1] = 1;
                tetris_temp[height[pat_pos+2]-1][pat_pos+1] = 1;
                tetris_temp[height[pat_pos+2]-1][pat_pos]   = 1;
            end else begin
                if(height[pat_pos] > height[pat_pos+1])begin
                    tetris_temp[height[pat_pos]][pat_pos] = 1;
                    tetris_temp[height[pat_pos]][pat_pos+1] = 1;
                    tetris_temp[height[pat_pos]+1][pat_pos+1] = 1;
                    tetris_temp[height[pat_pos]+1][pat_pos+2] = 1;
                end else begin
                    tetris_temp[height[pat_pos+1]]  [pat_pos+1] = 1;
                    tetris_temp[height[pat_pos+1]+1][pat_pos+1] = 1;
                    tetris_temp[height[pat_pos+1]+1][pat_pos+2] = 1;
                    tetris_temp[height[pat_pos+1]]  [pat_pos] = 1;
                end
            end
        end
        default:begin
            $display("filled_map_task exception");
        end
    endcase
end endtask

task elimination_task; begin
    for( i = 11 ; i >= 0; i = i - 1)begin
        if(tetris_temp[i] == 'd63)begin
            for( j = i ; j < 15; j = j + 1)begin
                tetris_temp[j] = tetris_temp[j+1];
            end
            tetris_temp[15] = 'd0;
            score_temp = score_temp + 1;
        end
    end
    for( i = 0; i < 6; i = i + 1)begin
        height[i] = (tetris_temp[11][i]) ? 12 : (tetris_temp[10][i]) ? 11 : (tetris_temp[9][i]) ? 10 : (tetris_temp[8][i]) ? 9 : (tetris_temp[7][i]) ? 8 : 
                    (tetris_temp[6][i])  ?  7 : (tetris_temp[5][i])  ? 6  : (tetris_temp[4][i]) ?  5 : (tetris_temp[3][i]) ? 4 : (tetris_temp[2][i]) ? 3 :
                    (tetris_temp[1][i])  ?  2 : (tetris_temp[0][i])  ? 1  : 0;
    end
    golden_score = score_temp;
    for( i = 0; i < 12; i = i + 1)begin
        for( j = 0; j < 6; j = j + 1)begin
            golden_tetris[6*i + j] = tetris_temp[i][j];
        end
    end
end endtask

task check_fail_task;begin
    if(|(tetris_temp[15] || tetris_temp[14] || tetris_temp[13] || tetris_temp[12]))begin
        failed = 1;
    end
    golden_fail = failed;
end endtask

task wait_score_valid_task; begin
    latency = 1;
    while(score_valid !== 'b1)begin
        latency = latency + 1;
        if(latency > 1000)begin
            $display("                    SPEC-6 FAIL                   ");
            repeat(2) #CYCLE;
            $finish;
        end
        @(negedge clk);
    end
    total_latency = total_latency + latency;
end endtask

task check_ans_task; begin
    if(score_valid)begin
        if(score !== golden_score)begin
            $display("                     SCORE: %d", score);
            $display("                 GOLDEN_SCORE: %d", golden_score);
            $display("                    SPEC-7 FAIL                   ");
            repeat(2) #CYCLE;
            $finish;
        end
        if(fail !== golden_fail)begin
            $display("            fail:%d and golden_fail:%d", fail, golden_fail);
            $display("                    SPEC-7 FAIL                   ");
            repeat(2) #CYCLE;
            $finish;
        end
    end
    if(tetris_valid)begin
        if(tetris !== golden_tetris)begin
            $display("tetris:%d and golden_tetris:%d", tetris, golden_tetris);
            $display("                    SPEC-7 FAIL                   ");
            repeat(2) #CYCLE;
            $finish;
        end
    end
    #CYCLE;
    if(score_valid || tetris_valid)begin
        $display("                    SPEC-8 FAIL                   ");
        repeat(2) #CYCLE;
        $finish;
    end
end endtask

task clear_rest_input_task; begin
    a = $fscanf(pat_read, "%d %d", nt, np);
end endtask

// SPEC 5 FAIL
always @(negedge clk) begin
    if((score_valid === 'b0 && score !== 'b0) || (score_valid === 'b0 && fail !== 'b0) || (score_valid === 'b0 && tetris_valid !== 'b0) || tetris_valid === 'b0 && tetris !== 'b0)begin
        $display("                    SPEC-5 FAIL                   ");
        $finish;
    end
end


task YOU_PASS_task; begin
    $display("                  Congratulations!               ");
    $display("              execution cycles = %7d", total_latency);
    $display("              clock period = %4fns", CYCLE);
    $finish;
end endtask


endmodule
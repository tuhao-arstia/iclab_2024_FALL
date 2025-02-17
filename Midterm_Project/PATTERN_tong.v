
`ifdef RTL
    `define CYCLE_TIME 3.7
`endif
`ifdef GATE
    `define CYCLE_TIME 3.7
`endif

`define DRAM_PATH "../00_TESTBED/DRAM/dram0.dat"
`define PATNUM 1000
`define SEED 120

`include "../00_TESTBED/pseudo_DRAM.v"

module PATTERN(
    // Input Signals
    clk,
    rst_n,
    in_valid,
    in_pic_no,
    in_mode,
    in_ratio_mode,
    out_valid,
    out_data
);

/* Input for design */
output reg        clk, rst_n;
output reg        in_valid;

output reg [3:0] in_pic_no;
output reg       in_mode;
output reg [1:0] in_ratio_mode;

input out_valid;
input [7:0] out_data;
//////////////////////////////////////////////////////////////////////
parameter DRAM_p_r = `DRAM_PATH;
parameter CYCLE = `CYCLE_TIME;

reg [7:0] DRAM_r[0:196607];
reg [7:0] image [0:2][0:31][0:31];
integer patcount;
integer latency, total_latency;
integer file;
integer PATNUM = `PATNUM;
integer seed = `SEED;

reg [1:0] golden_in_ratio_mode;
reg [3:0] golden_in_pic_no;
reg  golden_in_mode;
reg [7:0] golden_out_data;

reg [7:0] two_by_two [0:1][0:1];
reg [7:0] four_by_four [0:3][0:3];
reg [7:0] six_by_six [0:5][0:5];

reg [31:0] out_data_temp;
reg [31:0] D_constrate [0:2];
reg [31:0] D_constrate_add [0:2];


// testing focus and exposure
integer focus_num;
integer exposure_num;
reg focus_flag [0:15];
reg exposure_flag [0:15];
reg [3:0] dram_all_zero_flag [0:15];
integer read_dram_times;

//////////////////////////////////////////////////////////////////////
// Write your own task here
//////////////////////////////////////////////////////////////////////
initial clk=0;
always #(CYCLE/2.0) clk = ~clk;

// Do it yourself, I believe you can!!!

/* Check for invalid overlap */
always @(*) begin
    if (in_valid && out_valid) begin
        display_fail;
        $display("************************************************************");  
        $display("                          FAIL!                           ");    
        $display("*  The out_valid signal cannot overlap with in_valid.   *");
        $display("************************************************************");
        $finish;            
    end    
end







initial begin
    reset_task;
    $readmemh(DRAM_p_r,DRAM_r);
    file = $fopen("../00_TESTBED/debug.txt", "w");
    focus_num = 0;
    exposure_num = 0;
    read_dram_times = 0;
    for(integer i = 0; i < 16; i = i + 1)begin
        focus_flag[i] = 0;
        exposure_flag[i] = 0;
        dram_all_zero_flag[i] = 0;
    end

    for( patcount = 0; patcount < PATNUM; patcount++) begin 
        repeat(2) @(negedge clk); 
        input_task;
        write_dram_file;
        calculate_ans;
        write_to_file;
        wait_out_valid_task;
        check_ans;
        $display("\033[0;34mPASS PATTERN NO.%4d,\033[m \033[0;32mExecution Cycle: %3d \033[0m", patcount + 1, latency);
  
    end
    display_pass;
    repeat (3) @(negedge clk);
    $finish;
end

task reset_task; begin 
    rst_n = 1'b1;
    in_valid = 1'b0;
    in_ratio_mode = 2'bx;
    in_pic_no = 4'bx;
    in_mode = 1'bx;
    total_latency = 0;

    force clk = 0;

    // Apply reset
    #CYCLE; rst_n = 1'b0; 
    #CYCLE; rst_n = 1'b1;
    
    // Check initial conditions
    if (out_valid !== 1'b0 || out_data !== 'b0) begin
        display_fail;
        $display("************************************************************");  
        $display("                          FAIL!                           ");    
        $display("*  Output signals should be 0 after initial RESET at %8t *", $time);
        $display("************************************************************");
        repeat (2) #CYCLE;
        $finish;
    end
    #CYCLE; release clk;
end endtask


task input_task; begin
    integer i,j;
    in_valid = 1'b1;
    
    
    // in_pic_no = 15;
    // in_mode = 1;
    in_pic_no = $random(seed) % 'd16;
    in_mode = $random(seed) % 'd2;
    // in_mode = 1'b1;
    in_ratio_mode = (in_mode) ? $random(seed) % 'd4 : 2'bx;
    golden_in_ratio_mode = in_ratio_mode;
    golden_in_pic_no = in_pic_no;
    golden_in_mode = in_mode;

    // count focus and exposure

    if(in_mode == 1'b0)begin
        focus_num = focus_num + 1;
    //     if(focus_flag[in_pic_no] == 1'b0)begin
    //         focus_flag[in_pic_no] = 1'b1;
    //         if(dram_all_zero_flag[in_pic_no] != 4'd8)begin
    //             read_dram_times = read_dram_times + 1;
    //         end
    //     end
    end
    else begin
        exposure_num = exposure_num + 1;
    end    
        

    //     if(focus_flag[in_pic_no] == 1'b0)begin
    //         focus_flag[in_pic_no] = 1'b1;
    //     end
    //     if(exposure_flag[in_pic_no] != 1'b1 || (in_ratio_mode != 2 && in_ratio_mode != 0 && in_ratio_mode != 1))begin
    //         exposure_flag[in_pic_no] = 1'b1;
    //         if(dram_all_zero_flag[in_pic_no] != 4'd8)begin
    //             read_dram_times = read_dram_times + 1;
    //         end
    //     end

    //     if(dram_all_zero_flag[in_pic_no] != 4'd8)begin
    //         if(in_ratio_mode == 0)begin
    //             dram_all_zero_flag[in_pic_no] = (dram_all_zero_flag[in_pic_no] >= 6) ? 8 : dram_all_zero_flag[in_pic_no] + 2;
    //         end
    //         else if(in_ratio_mode == 1)begin
    //             dram_all_zero_flag[in_pic_no] = dram_all_zero_flag[in_pic_no] + 1;
    //         end
    //         else if(in_ratio_mode == 3)begin
    //             dram_all_zero_flag[in_pic_no] = (dram_all_zero_flag[in_pic_no] == 0) ? 0 : dram_all_zero_flag[in_pic_no] - 1;
    //         end
    //     end

        
    // end

    

    

    for(integer i = 0; i < 3; i = i + 1)begin
        for(integer j = 0; j < 32; j = j + 1)begin
            for(integer k = 0; k < 32; k = k + 1)begin
                image[i][j][k] = DRAM_r[65536 + i * 32 * 32 + j * 32 + k + golden_in_pic_no * 32 * 32 * 3];
            end
        end
    end   
    

    @(negedge clk);

    in_valid = 1'b0;
    in_ratio_mode = 2'bx;
    in_pic_no = 4'bx;
    in_mode = 1'bx;
    
end endtask


task calculate_ans;begin
   

    if(golden_in_mode == 1'b0)begin
        for(integer i = 0; i < 3; i = i + 1)begin
            D_constrate_add[i] = 0;
        end
        
        for(integer j = 0; j < 2; j = j + 1)begin
            for(integer k = 0; k < 2; k = k + 1)begin
                two_by_two[j][k] = (image[0][15 + j][15 + k] ) / 4 + (image[1][15 + j][15 + k]) / 2 + 
                                        (image[2][15 + j][15 + k] ) / 4 ;
            end
        end

        for(integer j = 0; j < 4; j = j + 1)begin
            for(integer k = 0; k < 4; k = k + 1)begin
                four_by_four[j][k] = (image[0][14 + j][14 + k] ) / 4 + (image[1][14 + j][14 + k]) / 2 + 
                                        (image[2][14 + j][14 + k] ) / 4 ;
            end
        end

        for(integer j = 0; j < 6; j = j + 1)begin
            for(integer k = 0; k < 6; k = k + 1)begin
                six_by_six[j][k] = (image[0][13 + j][13 + k] ) / 4 + (image[1][13 + j][13 + k]) / 2 + 
                                        (image[2][13 + j][13 + k] ) / 4 ;
            end
        end



        for(integer i = 0; i < 2; i = i + 1)begin
            for(integer j = 0; j < 1; j = j + 1)begin
                D_constrate_add[0] = D_constrate_add[0] + diff_abs(two_by_two[i][j + 1], two_by_two[i][j]) + diff_abs(two_by_two[j + 1][i], two_by_two[j][i]);
            end
        end

        for(integer i = 0; i < 4; i = i + 1)begin
            for(integer j = 0; j < 3; j = j + 1)begin
                D_constrate_add[1] = D_constrate_add[1] + diff_abs(four_by_four[i][j + 1], four_by_four[i][j]) + diff_abs(four_by_four[j + 1][i], four_by_four[j][i]);
            end
        end

        for(integer i = 0; i < 6; i = i + 1)begin
            for(integer j = 0; j < 5; j = j + 1)begin
                D_constrate_add[2] = D_constrate_add[2] + diff_abs(six_by_six[i][j + 1], six_by_six[i][j]) + diff_abs(six_by_six[j + 1][i], six_by_six[j][i]);
            end
        end

        D_constrate[0] = D_constrate_add[0] / (2 * 2);
        D_constrate[1] = D_constrate_add[1] / (4 * 4);
        D_constrate[2] = D_constrate_add[2] / (6 * 6);

        if(D_constrate[0] >= D_constrate[1] && D_constrate[0] >= D_constrate[2])begin
            golden_out_data = 8'b00000000;
        end
        else if(D_constrate[1] >= D_constrate[2])begin
            golden_out_data = 8'b00000001;
        end
        else begin
            golden_out_data = 8'b00000010;
        end

    end
    else begin
        for(integer i = 0; i < 3; i = i + 1)begin
            for(integer j = 0; j < 32; j = j + 1)begin
                for(integer k = 0; k < 32; k = k + 1)begin
                    if(golden_in_ratio_mode == 0)begin
                        image[i][j][k] = image[i][j][k] / 4;
                    end
                    else if(golden_in_ratio_mode == 1)begin
                        image[i][j][k] = image[i][j][k] / 2;
                    end
                    else if(golden_in_ratio_mode == 2)begin
                        image[i][j][k] = image[i][j][k];
                    end
                    else begin
                        image[i][j][k] = (image[i][j][k] < 128)  ? image[i][j][k] * 2 : 255;
                        // MSB is 1, image = 255, else shift left 1;
                    end
                    
                end
            end
        end

        for(integer i = 0; i < 3; i = i + 1)begin
            for(integer j = 0; j < 32; j = j + 1)begin
                for(integer k = 0; k < 32; k = k + 1)begin
                    DRAM_r[65536 + i * 32 * 32 + j * 32 + k + golden_in_pic_no * 32 * 32 * 3] = image[i][j][k];
                end
            end
        end
        
        out_data_temp = 0;
        for(integer i = 0; i < 32; i = i + 1)begin
            for(integer j = 0; j < 32; j = j + 1)begin
                out_data_temp = out_data_temp + image[0][i][j] / 4 + image[1][i][j] / 2 + image[2][i][j] / 4;
            end
        end
        golden_out_data = out_data_temp / 1024;

    end



end endtask

task wait_out_valid_task; begin
    latency = 0;
    while (out_valid !== 1'b1) begin
        latency = latency + 1;
        if (latency == 20000) begin
            display_fail;
            $display("********************************************************");     
            $display("                          FAIL!                           ");
            $display("*  The execution latency exceeded 20000 cycles at %8t   *", $time);
            $display("********************************************************");
            repeat (2) @(negedge clk);
            $finish;
        end
        @(negedge clk);
    end
    total_latency = total_latency + latency;
end endtask



task check_ans; begin
    if(golden_in_mode == 0)begin
        if(out_data !== golden_out_data)begin
            display_fail;
            $display("********************************************************");     
            $display("                          FAIL!                           ");
            $display("*               The golden_in_mode is %d               *", golden_in_mode);
            $display("*  The golden_out_data is %d, but your out_data is %d  *", golden_out_data, out_data);
            $display("********************************************************");
            repeat (2) @(negedge clk);
            $finish;
        end
    end
    else begin
        if(golden_out_data == 0)begin
            if(out_data !== 1 && out_data !== 0)begin
                display_fail;
                $display("********************************************************");     
                $display("                FAIL error is large than 1 !                ");
                $display("*               The golden_in_mode is %d               *", golden_in_mode);
                $display("*  The golden_out_data is %d, but your out_data is %d  *", golden_out_data, out_data);
                $display("********************************************************");
                repeat (2) @(negedge clk);
                $finish;
            end
        end
        else if(golden_out_data == 255)begin
            if(out_data !== 255 && out_data !== 254)begin
                display_fail;
                $display("********************************************************");     
                $display("                FAIL error is large than 1 !                ");
                $display("*               The golden_in_mode is %d               *", golden_in_mode);
                $display("*  The golden_out_data is %d, but your out_data is %d  *", golden_out_data, out_data);
                $display("********************************************************");
                repeat (2) @(negedge clk);
                $finish;
            end
        end
        else begin
            if(out_data > golden_out_data + 1 || out_data < golden_out_data - 1)begin
                display_fail;
                $display("********************************************************");     
                $display("                FAIL error is large than 1 !                ");
                $display("*               The golden_in_mode is %d               *", golden_in_mode);
                $display("*  The golden_out_data is %d, but your out_data is %d  *", golden_out_data, out_data);
                $display("********************************************************");
                repeat (2) @(negedge clk);
                $finish;
            end
        end
        
    end

end endtask

task write_dram_file; begin
    $fwrite(file, "===========  PATTERN NO.%4d  ==============\n", patcount);
    $fwrite(file, "==========  GOLDEN_PIC_NO.%2d  ==============\n", golden_in_pic_no);
    $fwrite(file, "===========    RED IMAGE     ==============\n");
    for(integer i = 0; i < 32; i = i + 1) begin
        for(integer j = 0; j < 32; j = j + 1) begin
            $fwrite(file, "%5d ", image[0][i][j]);
        end
        $fwrite(file, "\n");
    end
    $fwrite(file, "===========    GREEN IMAGE     ============\n");
    for(integer i = 0; i < 32; i = i + 1) begin
        for(integer j = 0; j < 32; j = j + 1) begin
            $fwrite(file, "%5d ", image[1][i][j]);
        end
        $fwrite(file, "\n");
    end
    $fwrite(file, "===========    BLUE IMAGE     ============\n");
    for(integer i = 0; i < 32; i = i + 1) begin
        for(integer j = 0; j < 32; j = j + 1) begin
            $fwrite(file, "%5d ", image[2][i][j]);
        end
        $fwrite(file, "\n");
    end
    $fwrite(file, "\n");
end endtask












task write_to_file; begin
    
    $fwrite(file, "==========  GOLDEN_IN_MODE is %b  ==============\n", golden_in_mode);   
    if(golden_in_mode == 1'b0)begin
        $fwrite(file, "===========    TWO_BY_TWO     ============\n");
        for(integer i = 0; i < 2; i = i + 1) begin
            for(integer j = 0; j < 2; j = j + 1) begin
                $fwrite(file, "%5d ", two_by_two[i][j]);
            end
            $fwrite(file, "\n");
        end

        $fwrite(file, "===========    FOUR_BY_FOUR     ============\n");
        for(integer i = 0; i < 4; i = i + 1) begin
            for(integer j = 0; j < 4; j = j + 1) begin
                $fwrite(file, "%5d ", four_by_four[i][j]);
            end
            $fwrite(file, "\n");
        end

        $fwrite(file, "===========    SIX_BY_SIX     ============\n");
        for(integer i = 0; i < 6; i = i + 1) begin
            for(integer j = 0; j < 6; j = j + 1) begin
                $fwrite(file, "%5d ", six_by_six[i][j]);
            end
            $fwrite(file, "\n");
        end
        $fwrite(file, "===========   D_CONSTRATE(ADD)  ============\n");
        for(integer i = 0; i < 3; i = i + 1) begin
            $fwrite(file, "%10d", D_constrate_add[i]);
        end
        $fwrite(file, "\n");
        $fwrite(file, "===========    D_CONSTRATE     ============\n");
        for(integer i = 0; i < 3; i = i + 1) begin
            $fwrite(file, "%10d", D_constrate[i]);
        end
        $fwrite(file, "\n");
    end
    else begin
        $fwrite(file, "=========  IMAGE_AFTER_AUTO_EXPOSURE  ============\n");
        $fwrite(file, "=========  GOLDEN_RATIO is %d  ============\n",golden_in_ratio_mode);
        $fwrite(file, "===========    RED IMAGE     ==============\n");
        for(integer i = 0; i < 32; i = i + 1) begin
            for(integer j = 0; j < 32; j = j + 1) begin
                $fwrite(file, "%5d ", image[0][i][j]);
            end
            $fwrite(file, "\n");
        end
        $fwrite(file, "===========    GREEN IMAGE     ============\n");
        for(integer i = 0; i < 32; i = i + 1) begin
            for(integer j = 0; j < 32; j = j + 1) begin
                $fwrite(file, "%5d ", image[1][i][j]);
            end
            $fwrite(file, "\n");
        end
        $fwrite(file, "===========    BLUE IMAGE     ============\n");
        for(integer i = 0; i < 32; i = i + 1) begin
            for(integer j = 0; j < 32; j = j + 1) begin
                $fwrite(file, "%5d ", image[2][i][j]);
            end
            $fwrite(file, "\n");
        end
        $fwrite(file, "\n");

        $fwrite(file, "===========  DATA_SUM (not divide 1024)  ============\n");
        $fwrite(file, "%10d\n", out_data_temp);
    end
    $fwrite(file, "===========  GOLDEN_OUT_DATA  ============\n");
    $fwrite(file, "%10d\n", golden_out_data);

    $fwrite(file, "\n\n\n");
end endtask






function [7:0]diff_abs; 
    input [7:0]a;
    input [7:0]b;
    begin
        if(a > b)begin
            diff_abs = a - b;
        end
        else begin
            diff_abs = b - a;
        end
    end
endfunction





















task display_fail; begin

    /*$display("        ----------------------------               ");
    $display("        --                        --       |\__||  ");
    $display("        --  OOPS!!                --      / X,X  | ");
    $display("        --                        --    /_____   | ");
    $display("        --  \033[0;31mSimulation FAIL!!\033[m   --   /^ ^ ^ \\  |");
    $display("        --                        --  |^ ^ ^ ^ |w| ");
    $display("        ----------------------------   \\m___m__|_|");
    $display("\n");*/
end endtask

/*task display_pass; begin
        $display("\n");
        $display("\n");
        $display("        ----------------------------               ");
        $display("        --                        --       |\__||  ");
        $display("        --  Congratulations !!    --      / O.O  | ");
        $display("        --                        --    /_____   | ");
        $display("        --  \033[0;32mSimulation PASS!!\033[m     --   /^ ^ ^ \\  |");
        $display("        --                        --  |^ ^ ^ ^ |w| ");
        $display("        ----------------------------   \\m___m__|_|");
        $display("\n");
end endtask*/

task display_pass; begin
    $display("-----------------------------------------------------------------");
    $display("                       Congratulations!                          ");
    $display("                You have passed all patterns!                     ");
    $display("                Your execution cycles = %5d cycles                ", total_latency);
    $display("                Your clock period = %.1f ns                       ", CYCLE);
    $display("                Total Latency = %.1f ns                          ", total_latency * CYCLE);
    $display("                Focus number = %4d, Exposure number = %4d           ", focus_num, exposure_num);
    // $display("                Total Read DRAM times = %4d                             ", read_dram_times);
    // $display("                DRAM all zero number %d = %d                            ", 0, dram_all_zero_flag[0]);
    // $display("                DRAM all zero number %d = %d                            ", 1, dram_all_zero_flag[1]);
    // $display("                DRAM all zero number %d = %d                            ", 2, dram_all_zero_flag[2]);
    // $display("                DRAM all zero number %d = %d                            ", 3, dram_all_zero_flag[3]);
    // $display("                DRAM all zero number %d = %d                            ", 4, dram_all_zero_flag[4]);
    // $display("                DRAM all zero number %d = %d                            ", 5, dram_all_zero_flag[5]);
    // $display("                DRAM all zero number %d = %d                            ", 6, dram_all_zero_flag[6]);
    // $display("                DRAM all zero number %d = %d                            ", 7, dram_all_zero_flag[7]);
    // $display("                DRAM all zero number %d = %d                            ", 8, dram_all_zero_flag[8]);
    // $display("                DRAM all zero number %d = %d                            ", 9, dram_all_zero_flag[9]);
    // $display("                DRAM all zero number %d = %d                            ", 10, dram_all_zero_flag[10]);
    // $display("                DRAM all zero number %d = %d                            ", 11, dram_all_zero_flag[11]);
    // $display("                DRAM all zero number %d = %d                            ", 12, dram_all_zero_flag[12]);
    // $display("                DRAM all zero number %d = %d                            ", 13, dram_all_zero_flag[13]);
    // $display("                DRAM all zero number %d = %d                            ", 14, dram_all_zero_flag[14]);
    // $display("                DRAM all zero number %d = %d                            ", 15, dram_all_zero_flag[15]);
    $display("-----------------------------------------------------------------");
    repeat (2) @(negedge clk);
    $finish;
end endtask


endmodule

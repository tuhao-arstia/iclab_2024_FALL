
// `include "../00_TESTBED/pseudo_DRAM.sv"
`include "Usertype.sv"

program automatic PATTERN(input clk, INF.PATTERN inf);
import usertype::*;
//================================================================
// parameters & integer
//================================================================
integer SEED = 10;
parameter PATNUM = 5400;
parameter DRAM_p_r = "../00_TESTBED/DRAM/dram.dat";
parameter MAX_CYCLE=1000;

integer latency;
integer total_latency;
integer pat_cnt;
integer index_check_cnt;
integer out_valid_cnt;
integer i;


//================================================================
// wire & registers 
//================================================================
logic [7:0] golden_DRAM [((65536+8*256)-1):(65536+0)];
// golden(current)
Action          golden_action;
Formula_Type    golden_formula;
Mode            golden_mode;
Data_No         golden_data_no; 
Date            golden_date;
Data_Dir        golden_dram_data;

// IC
Index           golden_late_index_A;
Index           golden_late_index_B;
Index           golden_late_index_C;
Index           golden_late_index_D;
Index           diff_index_A;
Index           diff_index_B;
Index           diff_index_C;
Index           diff_index_D;
Index [3:0]     sort_diff_index;
Index [3:0]     sort_early_index;
Index           b0, s0, b1, s1, bb, bs, sb, ss;
logic           d0, d1, d2, d3;
logic           e0, e1, e2, e3;
// golden result for IC
logic [13:0]    golden_result_a;
logic [13:0]    golden_result_b;
logic [13:0]    golden_result_c;
logic [13:0]    golden_result_d;
logic [13:0]    golden_result_e;
logic [13:0]    golden_result_f;
logic [13:0]    golden_result_g;
logic [13:0]    golden_result_h;

// Update
Variation       golden_variation_A;
Variation       golden_variation_B;
Variation       golden_variation_C;
Variation       golden_variation_D;
logic signed [13:0]    update_index_A;
logic signed [13:0]    update_index_B;
logic signed [13:0]    update_index_C;
logic signed [13:0]    update_index_D;
Index           wb_index_A;
Index           wb_index_B;
Index           wb_index_C;
Index           wb_index_D;

// golden output
logic           golden_complete;
Warn_Msg        golden_warn_msg;


//================================================================
// Randomize
//================================================================
// Delay
class delay_random;
    rand int delay;
    function new (int seed);
        this.srandom(seed);
    endfunction
    constraint limit { 
        delay inside {[0:3]}; 
    }
endclass 
delay_random r_delay = new(SEED);

// Action
class action_random;
    rand Action action;
    function new (int seed);
        this.srandom(seed);
    endfunction
    constraint limit { 
        action inside {Index_Check, Update, Check_Valid_Date};
    }
endclass
action_random r_action = new(SEED);

// Formula
class formula_random;
    rand Formula_Type formula;
    function new (int seed);
        this.srandom(seed);
    endfunction
    constraint limit {
        formula inside {Formula_A, Formula_B, Formula_C, Formula_D, Formula_E, Formula_F, Formula_G, Formula_H}; 
    }
endclass
formula_random r_formula = new(SEED);

// Mode
class mode_random;
    rand Mode mode;
    function new (int seed);
        this.srandom(seed);
    endfunction
    constraint limit { 
        mode inside {Insensitive, Normal, Sensitive}; 
    }
endclass
mode_random r_mode = new(SEED);

// Data_No
class data_no_random;
    rand Data_No data_no;
    function new (int seed);
        this.srandom(seed);
    endfunction
    constraint limit { 
        data_no inside {[0:255]}; 
    }
endclass
data_no_random r_data_no = new(SEED);

// late trading index
class late_index_random;
    rand Index late_index;
    function new (int seed);
        this.srandom(seed);
    endfunction
    constraint limit { 
        late_index inside {[0:4095]}; 
    }
endclass
late_index_random r_late_index = new(SEED);

// variation
class variation_random;
    rand Variation variation;
    function new (int seed);
        this.srandom(seed);
    endfunction
    constraint limit { 
        variation inside {[-2048:2047]}; 
    }
endclass
variation_random r_variation = new(SEED);

// date
class date_random;
    rand logic [3:0] month;
    rand logic [4:0] day;
    function new (int seed);
        this.srandom(seed);
    endfunction
    constraint limit {
        month inside {[1:12]};
        if(month == 1 || month == 3 || month == 5 || month == 7 || month == 8 || month == 10 || month == 12)
            day inside {[1:31]};
        else if(month == 4 || month == 6 || month == 9 || month == 11)
            day inside {[1:30]};
        else if(month == 2)
            day inside {[1:28]};
    }
endclass
date_random r_date = new(SEED);




//================================================================
// Initital Block
//================================================================
initial begin
    $readmemh(DRAM_p_r, golden_DRAM);
    inf.rst_n = 1'b1;
    #(5.0);
    inf.rst_n = 1'b0;

    inf.sel_action_valid = 1'b0;
    inf.formula_valid = 1'b0;
    inf.mode_valid = 1'b0;
    inf.date_valid = 1'b0;
    inf.data_no_valid = 1'b0;
    inf.index_valid = 1'b0;
    inf.D = 'bx;
    
    total_latency = 0;
    index_check_cnt = 0;

    #(15.0);
    if(inf.out_valid !== 0 || inf.warn_msg !== 0 || inf.complete !== 0)begin
        $display ("*********             output should be 0 after reset             *********");
        $finish;
    end
    #(1.0);
    inf.rst_n = 1'b1;
    @(negedge clk);

    for( pat_cnt = 0; pat_cnt < PATNUM; pat_cnt+=1)begin
        action_gerenation_task;
        case(golden_action)
            Index_Check: begin
                index_check_task;
            end
            Update: begin
                update_task;
                update_dram_task;
            end
            Check_Valid_Date: begin
                check_valid_date_task;
            end
        endcase
        wait_out_valid_task;
        check_ans_task;
        $display("PASS PATTERN NO.%4d", pat_cnt);
        random_delay_task;
    end

    YOU_PASS_task;
end

//================================================================
// TASK BLOCK
//================================================================
task action_gerenation_task;
    if(pat_cnt < 2700)begin
        case(pat_cnt%9)
            0: begin
                golden_action = Index_Check;
            end
            1: begin
                golden_action = Index_Check;
            end
            2: begin
                golden_action = Update;
            end
            3: begin
                golden_action = Update;
            end
            4: begin
                golden_action = Check_Valid_Date;
            end
            5: begin
                golden_action = Check_Valid_Date;
            end
            6: begin
                golden_action = Index_Check;
            end
            7: begin
                golden_action = Check_Valid_Date;
            end
            8: begin
                golden_action = Update;
            end
        endcase
    end else begin
        golden_action = Index_Check;
    end
endtask

task index_check_task;
    // generate golden formula and golden mode
    case(index_check_cnt%8)
        0: begin
            golden_formula = Formula_A;
        end
        1: begin
            golden_formula = Formula_B;
        end
        2: begin
            golden_formula = Formula_C;
        end
        3: begin
            golden_formula = Formula_D;
        end
        4: begin
            golden_formula = Formula_E;
        end
        5: begin
            golden_formula = Formula_F;
        end
        6: begin
            golden_formula = Formula_G;
        end
        7: begin
            golden_formula = Formula_H;
        end
    endcase
    case (index_check_cnt%3)
        0: begin
            golden_mode = Insensitive;
        end
        1: begin
            golden_mode = Normal;
        end
        2: begin
            golden_mode = Sensitive;
        end
    endcase
    
    index_check_cnt = index_check_cnt + 1;
    // randomize first 
    r_date.randomize();
    r_data_no.randomize();
    golden_date.M = r_date.month;
    golden_date.D = r_date.day;
    golden_data_no = r_data_no.data_no;
    r_late_index.randomize();
    golden_late_index_A = r_late_index.late_index;
    r_late_index.randomize();
    golden_late_index_B = r_late_index.late_index;
    r_late_index.randomize();
    golden_late_index_C = r_late_index.late_index;
    r_late_index.randomize();
    golden_late_index_D = r_late_index.late_index;

    // get golden dram data
    get_dram_info_task;

    // determine difference
    diff_index_A = (golden_late_index_A>golden_dram_data.Index_A)? golden_late_index_A - golden_dram_data.Index_A : golden_dram_data.Index_A - golden_late_index_A;
    diff_index_B = (golden_late_index_B>golden_dram_data.Index_B)? golden_late_index_B - golden_dram_data.Index_B : golden_dram_data.Index_B - golden_late_index_B;
    diff_index_C = (golden_late_index_C>golden_dram_data.Index_C)? golden_late_index_C - golden_dram_data.Index_C : golden_dram_data.Index_C - golden_late_index_C;
    diff_index_D = (golden_late_index_D>golden_dram_data.Index_D)? golden_late_index_D - golden_dram_data.Index_D : golden_dram_data.Index_D - golden_late_index_D;
    // sort early index
    b0 = (golden_dram_data.Index_A > golden_dram_data.Index_B)? golden_dram_data.Index_A : golden_dram_data.Index_B;
    s0 = (golden_dram_data.Index_A > golden_dram_data.Index_B)? golden_dram_data.Index_B : golden_dram_data.Index_A;
    b1 = (golden_dram_data.Index_C > golden_dram_data.Index_D)? golden_dram_data.Index_C : golden_dram_data.Index_D;
    s1 = (golden_dram_data.Index_C > golden_dram_data.Index_D)? golden_dram_data.Index_D : golden_dram_data.Index_C;
    bb = (b0 > b1)? b0 : b1;
    bs = (b0 > b1)? b1 : b0;
    ss = (s0 > s1)? s1 : s0;
    sb = (s0 > s1)? s0 : s1;
    sort_early_index[0] = bb;
    sort_early_index[1] = (bs > sb)? bs : sb;
    sort_early_index[2] = (bs > sb)? sb : bs;
    sort_early_index[3] = ss;
    // sort difference index
    b0 = (diff_index_A > diff_index_B)? diff_index_A : diff_index_B;
    s0 = (diff_index_A > diff_index_B)? diff_index_B : diff_index_A;
    b1 = (diff_index_C > diff_index_D)? diff_index_C : diff_index_D;
    s1 = (diff_index_C > diff_index_D)? diff_index_D : diff_index_C;
    bb = (b0 > b1)? b0 : b1;
    bs = (b0 > b1)? b1 : b0;
    ss = (s0 > s1)? s1 : s0;
    sb = (s0 > s1)? s0 : s1;
    sort_diff_index[0] = bb;
    sort_diff_index[1] = (bs > sb)? bs : sb;
    sort_diff_index[2] = (bs > sb)? sb : bs;
    sort_diff_index[3] = ss;
    // d and e
    d0 = (golden_dram_data.Index_A >= 2047)? 1'b1 : 1'b0;
    d1 = (golden_dram_data.Index_B >= 2047)? 1'b1 : 1'b0;
    d2 = (golden_dram_data.Index_C >= 2047)? 1'b1 : 1'b0;
    d3 = (golden_dram_data.Index_D >= 2047)? 1'b1 : 1'b0;
    e0 = (golden_dram_data.Index_A >= golden_late_index_A)? 1'b1 : 1'b0;
    e1 = (golden_dram_data.Index_B >= golden_late_index_B)? 1'b1 : 1'b0;
    e2 = (golden_dram_data.Index_C >= golden_late_index_C)? 1'b1 : 1'b0;
    e3 = (golden_dram_data.Index_D >= golden_late_index_D)? 1'b1 : 1'b0;

    golden_result_a = (golden_dram_data.Index_A + golden_dram_data.Index_B + golden_dram_data.Index_C + golden_dram_data.Index_D) >> 2;
    golden_result_b = sort_early_index[0] - sort_early_index[3];
    golden_result_c = sort_early_index[3];
    golden_result_d = d0 + d1 + d2 + d3;
    golden_result_e = e0 + e1 + e2 + e3;
    golden_result_f = (sort_diff_index[1] + sort_diff_index[2] + sort_diff_index[3])/3;
    golden_result_g = (sort_diff_index[3] >> 1) + (sort_diff_index[2] >> 2) + (sort_diff_index[1] >> 2);
    golden_result_h = (sort_diff_index[0] + sort_diff_index[1] + sort_diff_index[2] + sort_diff_index[3]) >> 2;
    // determine formula under no date_warn
    golden_complete = 1'b1;
    golden_warn_msg = No_Warn;
    if(golden_dram_data.M < golden_date.M || (golden_dram_data.M === golden_date.M && golden_dram_data.D <= golden_date.D))begin
        case (golden_formula)
            Formula_A: begin
                case (golden_mode)
                    Insensitive:begin
                        if(golden_result_a >= 2047)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Normal:begin
                        if(golden_result_a >= 1023)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Sensitive:begin
                        if(golden_result_a >= 511)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                endcase
            end
            Formula_B: begin
                case (golden_mode)
                    Insensitive:begin
                        if(golden_result_b >= 800)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Normal:begin
                        if(golden_result_b >= 400)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Sensitive:begin
                        if(golden_result_b >= 200)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                endcase
            end
            Formula_C: begin
                case (golden_mode)
                    Insensitive:begin
                        if(golden_result_c >= 2047)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Normal:begin
                        if(golden_result_c >= 1023)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Sensitive:begin
                        if(golden_result_c >= 511)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                endcase
            end
            Formula_D: begin
                case (golden_mode)
                    Insensitive:begin
                        if(golden_result_d >= 3)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Normal:begin
                        if(golden_result_d >= 2)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Sensitive:begin
                        if(golden_result_d >= 1)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                endcase
            end
            Formula_E: begin
                case (golden_mode)
                    Insensitive:begin
                        if(golden_result_e >= 3)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Normal:begin
                        if(golden_result_e >= 2)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Sensitive:begin
                        if(golden_result_e >= 1)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                endcase
            end
            Formula_F: begin
                case (golden_mode)
                    Insensitive:begin
                        if(golden_result_f >= 800)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Normal:begin
                        if(golden_result_f >= 400)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Sensitive:begin
                        if(golden_result_f >= 200)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                endcase
            end
            Formula_G: begin
                case (golden_mode)
                    Insensitive:begin
                        if(golden_result_g >= 800)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Normal:begin
                        if(golden_result_g >= 400)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Sensitive:begin
                        if(golden_result_g >= 200)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                endcase
            end
            Formula_H: begin
                case (golden_mode)
                    Insensitive:begin
                        if(golden_result_h >= 800)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Normal:begin
                        if(golden_result_h >= 400)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                    Sensitive:begin
                        if(golden_result_h >= 200)begin
                            golden_complete = 1'b0;
                            golden_warn_msg = Risk_Warn;
                        end else begin
                            golden_complete = 1'b1;
                            golden_warn_msg = No_Warn;
                        end
                    end
                endcase
            end
        endcase
    end else begin
        golden_complete = 1'b0;
        golden_warn_msg = Date_Warn;
    end
    // action input
    inf.sel_action_valid = 1'b1;
    inf.D = golden_action;
    @(negedge clk);
    inf.sel_action_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    // formula input
    inf.formula_valid = 1'b1;
    inf.D = golden_formula;
    @(negedge clk);
    inf.formula_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    // mode input
    inf.mode_valid = 1'b1;
    inf.D = golden_mode;
    @(negedge clk);
    inf.mode_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    // date input
    inf.date_valid = 1'b1;
    inf.D = {golden_date.M, golden_date.D};
    @(negedge clk);
    inf.date_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    // data_no input
    inf.data_no_valid = 1'b1;
    inf.D = golden_data_no;
    @(negedge clk);
    inf.data_no_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    // late index input * 4
    inf.index_valid = 1'b1;
    inf.D = golden_late_index_A;
    @(negedge clk);
    inf.index_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    inf.index_valid = 1'b1;
    inf.D = golden_late_index_B;
    @(negedge clk);
    inf.index_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    inf.index_valid = 1'b1;
    inf.D = golden_late_index_C;
    @(negedge clk);
    inf.index_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    inf.index_valid = 1'b1;
    inf.D = golden_late_index_D;
    latency = 0;
    @(negedge clk);
    inf.index_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
endtask

task update_task;
    // randomize first 
    r_date.randomize();
    golden_date.M = r_date.month;
    golden_date.D = r_date.day;
    r_data_no.randomize();
    golden_data_no = r_data_no.data_no;
    r_variation.randomize();
    golden_variation_A = r_variation.variation;
    r_variation.randomize();
    golden_variation_B = r_variation.variation;
    r_variation.randomize();
    golden_variation_C = r_variation.variation;
    r_variation.randomize();
    golden_variation_D = r_variation.variation;

    // get golden dram data
    get_dram_info_task;

    // initial golden_complete and golden_warn_msg
    golden_complete = 1'b1;
    golden_warn_msg = No_Warn;

    // determine update index
    update_index_A = {2'b0, golden_dram_data.Index_A} + {{2{golden_variation_A[11]}}, golden_variation_A};
    update_index_B = {2'b0, golden_dram_data.Index_B} + {{2{golden_variation_B[11]}}, golden_variation_B};
    update_index_C = {2'b0, golden_dram_data.Index_C} + {{2{golden_variation_C[11]}}, golden_variation_C};
    update_index_D = {2'b0, golden_dram_data.Index_D} + {{2{golden_variation_D[11]}}, golden_variation_D};
    wb_index_A = (update_index_A[13])? 12'd0: (update_index_A[12])? 12'd4095: update_index_A[11:0];
    wb_index_B = (update_index_B[13])? 12'd0: (update_index_B[12])? 12'd4095: update_index_B[11:0];
    wb_index_C = (update_index_C[13])? 12'd0: (update_index_C[12])? 12'd4095: update_index_C[11:0];
    wb_index_D = (update_index_D[13])? 12'd0: (update_index_D[12])? 12'd4095: update_index_D[11:0];

    if(update_index_A[13] || update_index_A[12] || update_index_B[13] || update_index_B[12] || update_index_C[13] || update_index_C[12] || update_index_D[13] || update_index_D[12])begin
        golden_complete = 1'b0;
        golden_warn_msg = Data_Warn;
    end else begin
        golden_complete = 1'b1;
        golden_warn_msg = No_Warn;
    end

    // action input
    inf.sel_action_valid = 1'b1;
    inf.D = golden_action;
    @(negedge clk);
    inf.sel_action_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    // date input
    inf.date_valid = 1'b1;
    inf.D = {golden_date.M, golden_date.D};
    @(negedge clk);
    inf.date_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    // data_no input
    inf.data_no_valid = 1'b1;
    inf.D = golden_data_no;
    @(negedge clk);
    inf.data_no_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    // variation input * 4
    inf.index_valid = 1'b1;
    inf.D = golden_variation_A;
    @(negedge clk);
    inf.index_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    inf.index_valid = 1'b1;
    inf.D = golden_variation_B;  
    @(negedge clk);
    inf.index_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    inf.index_valid = 1'b1;
    inf.D = golden_variation_C;  
    @(negedge clk);
    inf.index_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    inf.index_valid = 1'b1;
    inf.D = golden_variation_D;
    latency = 0;
    @(negedge clk);
    inf.index_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);

    // update date
    golden_dram_data.M = golden_date.M;
    golden_dram_data.D = golden_date.D;
endtask

task update_dram_task;
    golden_DRAM[65536+golden_data_no*8+7] = wb_index_A[11:4];
    golden_DRAM[65536+golden_data_no*8+6][7:4] = wb_index_A[3:0];
    golden_DRAM[65536+golden_data_no*8+6][3:0] = wb_index_B[11:8];
    golden_DRAM[65536+golden_data_no*8+5] = wb_index_B[7:0];
    golden_DRAM[65536+golden_data_no*8+4] = golden_dram_data.M;
    golden_DRAM[65536+golden_data_no*8+3] = wb_index_C[11:4];
    golden_DRAM[65536+golden_data_no*8+2][7:4] = wb_index_C[3:0];
    golden_DRAM[65536+golden_data_no*8+2][3:0] = wb_index_D[11:8];
    golden_DRAM[65536+golden_data_no*8+1] = wb_index_D[7:0];
    golden_DRAM[65536+golden_data_no*8+0] = golden_dram_data.D;
endtask

task check_valid_date_task;
    r_date.randomize();
    golden_date.M = r_date.month;
    golden_date.D = r_date.day;
    r_data_no.randomize();
    golden_data_no = r_data_no.data_no;

    // get golden dram data
    get_dram_info_task;

    // initial golden_complete and golden_warn_msg
    golden_complete = 1'b1;
    golden_warn_msg = No_Warn;
    if(golden_dram_data.M < golden_date.M || (golden_dram_data.M === golden_date.M && golden_dram_data.D <= golden_date.D))begin
        golden_complete = 1'b1;
        golden_warn_msg = No_Warn;
    end else begin
        golden_complete = 1'b0;
        golden_warn_msg = Date_Warn;
    end

    // action input
    inf.sel_action_valid = 1'b1;
    inf.D = golden_action;
    @(negedge clk);
    inf.sel_action_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    // date input
    inf.date_valid = 1'b1;
    inf.D = {golden_date.M, golden_date.D};
    @(negedge clk);
    inf.date_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

    // data_no input
    inf.data_no_valid = 1'b1;
    inf.D = golden_data_no;
    latency = 0;
    @(negedge clk);
    inf.data_no_valid = 1'b0;
    inf.D = 'bx;
    @(negedge clk);
    random_delay_task;

endtask



task wait_out_valid_task;
    latency = 0;
    while(inf.out_valid !== 1)begin
        latency = latency + 1;
        if(latency == MAX_CYCLE)begin
            $display("*********             over 1000 cycles             *********");
            $finish;
        end
        @(negedge clk);
    end
    total_latency = total_latency + latency;
endtask

task check_ans_task;
    out_valid_cnt = 0;
    while(inf.out_valid === 1)begin
        if(out_valid_cnt >= 1)begin
            $display("*********             out_valid should be one cycle             *********");
            $finish;
        end else if(golden_action == Index_Check)begin
            if(inf.complete !== golden_complete || inf.warn_msg !== golden_warn_msg)begin
                $display("*********             Index_Check fail             *********");
                $display("Golden complete : %d  Your complete : %d   ", golden_complete, inf.complete);
                $display("Golden warn_msg : %d  Your warn_msg : %d   ", golden_warn_msg, inf.warn_msg);
                fail_task;
                $finish;
            end
        end else if(golden_action == Update)begin
            if(inf.complete !== golden_complete || inf.warn_msg !== golden_warn_msg)begin
                $display("*********             Update fail             *********");
                $display("Golden complete : %d  Your complete : %d   ", golden_complete, inf.complete);
                $display("Golden warn_msg : %d  Your warn_msg : %d   ", golden_warn_msg, inf.warn_msg);
                fail_task;
                $finish;
            end
        end else if(golden_action == Check_Valid_Date)begin
            if(inf.complete !== golden_complete || inf.warn_msg !== golden_warn_msg)begin
                $display("*********             Check_Valid_Date fail             *********");
                $display("Golden complete : %d  Your complete : %d   ", golden_complete, inf.complete);
                $display("Golden warn_msg : %d  Your warn_msg : %d   ", golden_warn_msg, inf.warn_msg);
                fail_task;
                $finish;
            end
        end
        @(negedge clk);
        out_valid_cnt = out_valid_cnt + 1;
    end
endtask

task YOU_PASS_task;begin
$display ("----------------------------------------------------------------------------------------------------------------------");
$display ("                                                  Congratulations                                                     ");
$display ("                                           You have passed all patterns!                                              ");
$display ("                                                                                                                      ");
$display ("                                        Your execution cycles   = %5d cycles                                          ", total_latency);
$display ("----------------------------------------------------------------------------------------------------------------------");
$finish;
end endtask

task random_delay_task;
    r_delay.randomize();
    for( i = 0; i < r_delay.delay; i+=1)begin
        @(negedge clk);
    end
endtask 

// sub task
task get_dram_info_task;
    golden_dram_data.Index_A = {golden_DRAM[65536+golden_data_no*8+7], golden_DRAM[65536+golden_data_no*8+6][7:4]};
    golden_dram_data.Index_B = {golden_DRAM[65536+golden_data_no*8+6][3:0], golden_DRAM[65536+golden_data_no*8+5]};
    golden_dram_data.M       = golden_DRAM[65536+golden_data_no*8+4];
    golden_dram_data.Index_C = {golden_DRAM[65536+golden_data_no*8+3], golden_DRAM[65536+golden_data_no*8+2][7:4]};
    golden_dram_data.Index_D = {golden_DRAM[65536+golden_data_no*8+2][3:0], golden_DRAM[65536+golden_data_no*8+1]};
    golden_dram_data.D       = golden_DRAM[65536+golden_data_no*8+0];
endtask

task fail_task;
    $display("Wrong Answer");
endtask

endprogram

/*
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
NYCU Institute of Electronic
2023 Autumn IC Design Laboratory 
Lab10: SystemVerilog Coverage & Assertion
File Name   : CHECKER.sv
Module Name : CHECKER
Release version : v1.0 (Release Date: Nov-2023)
Author : Jui-Huang Tsai (erictsai.10@nycu.edu.tw)
//   (C) Copyright Laboratory System Integration and Silicon Implementation
//   All Right Reserved
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
*/

`include "Usertype.sv"
module Checker(input clk, INF.CHECKER inf);
import usertype::*;

// integer fp_w;

// initial begin
// fp_w = $fopen("out_valid.txt", "w");
// end

/**
 * This section contains the definition of the class and the instantiation of the object.
 *  * 
 * The always_ff blocks update the object based on the values of valid signals.
 * When valid signal is true, the corresponding property is updated with the value of inf.D
 */

class Formula_and_mode;
    Formula_Type f_type;
    Mode f_mode;
endclass

Formula_and_mode fm_info = new();
Action current_action;

always_ff @(posedge clk) begin
    if(inf.formula_valid) begin
        fm_info.f_type = inf.D.d_formula[0];
    end
    if(inf.mode_valid) begin
        fm_info.f_mode = inf.D.d_mode[0];
    end
    if(inf.sel_action_valid) begin
        current_action = inf.D.d_act[0];
    end
end

covergroup spec1 @(posedge clk iff(inf.formula_valid));
    option.per_instance = 1;
    option.at_least = 150;
    bin_formula: coverpoint fm_info.f_type {
        bins Formula_A = {3'h0};
        bins Formula_B = {3'h1};
        bins Formula_C = {3'h2};
        bins Formula_D = {3'h3};
        bins Formula_E = {3'h4};
        bins Formula_F = {3'h5};
        bins Formula_G = {3'h6};
        bins Formula_H = {3'h7};
    }
endgroup

covergroup spec2 @(posedge clk iff(inf.mode_valid));
    option.per_instance = 1;

    bin_mode: coverpoint fm_info.f_mode {
        option.at_least = 150;
        bins Insensitive = {2'b00};
        bins Normal = {2'b01};
        bins Sensitive = {2'b11};
    }
endgroup

covergroup spec3 @(posedge clk iff(inf.date_valid && current_action == Index_Check));
    option.at_least = 150;
    option.per_instance = 1;
    cross fm_info.f_type, fm_info.f_mode;
endgroup

covergroup spec4 @(posedge clk iff(inf.out_valid));
    option.per_instance = 1;
    option.at_least = 50;
    bin_warn_msg: coverpoint inf.warn_msg {
        bins No_Warn = {2'b00};
        bins Date_Warn = {2'b01};
        bins Risk_Warn = {2'b10};
        bins Data_Warn = {2'b11};
    }
endgroup

covergroup spec5 @(posedge clk iff(inf.sel_action_valid));
    option.per_instance = 1;
    option.at_least = 300;
    bin_action: coverpoint inf.D.d_act[0] {
        bins action_transition[] = (Index_Check, Update, Check_Valid_Date => Index_Check, Update, Check_Valid_Date);
    }
endgroup

covergroup spec6 @(posedge clk iff(inf.index_valid && current_action == Update));
    option.per_instance = 1;
    coverpoint inf.D.d_index[0]{
        option.at_least = 1;
        option.auto_bin_max = 32;
    }
endgroup

spec1 cg_1 = new();
spec2 cg_2 = new();
spec3 cg_3 = new();
spec4 cg_4 = new();
spec5 cg_5 = new();
spec6 cg_6 = new();


// ASSERTIONS
// assertion 1:
always @(negedge inf.rst_n) begin
    #(2.0);
    assert_1: assert((inf.out_valid === 0)&&(inf.warn_msg === No_Warn)&&(inf.complete === 0)&&
                    (inf.AR_VALID === 0)&&(inf.AR_ADDR === 0)&&(inf.R_READY === 0)&&(inf.AW_VALID === 0)&&
                    (inf.AW_ADDR === 0)&&(inf.W_VALID === 0)&&(inf.W_DATA === 0)&&(inf.B_READY === 0))
    else begin
        $display("===================================================");
		$display("              Assertion 1 is violated              ");
		$display("===================================================");
		$fatal;
    end 
end

// assertion 2:
assert_2_ic_and_up: assert property (latency_ic_and_up)
else begin
    $display("===================================================");
    $display("              Assertion 2 is violated              ");
    $display("===================================================");
    $fatal;
end

assert_2_cvd: assert property (latency_cvd)
else begin
    $display("===================================================");
    $display("              Assertion 2 is violated              ");
    $display("===================================================");
    $fatal;
end

// assertion 3:
assert_3: assert property (complete_no_warn)
else begin
    $display("===================================================");
    $display("              Assertion 3 is violated              ");
    $display("===================================================");
    $fatal;
end

// assertion 4:
logic [2:0] cnt;
always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        cnt <= 0;
    end
    else begin
        if(inf.index_valid) begin
            cnt <= cnt + 1;
        end else if(cnt == 'd4) begin
            cnt <= 0;
        end
    end
end
assert_4_1: assert property (ic_act_formula)
else begin
    $display("===================================================");
    $display("              Assertion 4 is violated              ");
    $display("===================================================");
    $fatal;
end
assert_4_2: assert property (ic_formula_mode)
else begin
    $display("===================================================");
    $display("              Assertion 4 is violated              ");
    $display("===================================================");
    $fatal;
end
assert_4_3: assert property (ic_mode_date)
else begin
    $display("===================================================");
    $display("              Assertion 4 is violated              ");
    $display("===================================================");
    $fatal;
end
assert_4_4: assert property (act_date)
else begin
    $display("===================================================");
    $display("              Assertion 4 is violated              ");
    $display("===================================================");
    $fatal;
end
assert_4_5: assert property (date_data_no)
else begin
    $display("===================================================");
    $display("              Assertion 4 is violated              ");
    $display("===================================================");
    $fatal;
end
assert_4_6: assert property (data_no_index)
else begin
    $display("===================================================");
    $display("              Assertion 4 is violated              ");
    $display("===================================================");
    $fatal;
end
assert_4_7: assert property (index_index)
else begin
    $display("===================================================");
    $display("              Assertion 4 is violated              ");
    $display("===================================================");
    $fatal;
end

// assertion 5:
assert_5: assert property (valid_overlap)
else begin
    $display("===================================================");
    $display("              Assertion 5 is violated              ");
    $display("===================================================");
    $fatal;
end

// assertion 6:
assert_6: assert property (one_out_valid)
else begin
    $display("===================================================");
    $display("              Assertion 6 is violated              ");
    $display("===================================================");
    $fatal;
end

// assertion 7:
assert_7: assert property (next_pat)
else begin
    $display("===================================================");
    $display("              Assertion 7 is violated              ");
    $display("===================================================");
    $fatal;
end

// assertion 8:
assert_8_1: assert property (month_check)
else begin
    $display("===================================================");
    $display("              Assertion 8 is violated              ");
    $display("===================================================");
    $fatal;
end

assert_8_2: assert property (day_31_check)
else begin
    $display("===================================================");
    $display("              Assertion 8 is violated              ");
    $display("===================================================");
    $fatal;
end

assert_8_3: assert property (day_30_check)
else begin
    $display("===================================================");
    $display("              Assertion 8 is violated              ");
    $display("===================================================");
    $fatal;
end

assert_8_4: assert property (day_28_check)
else begin
    $display("===================================================");
    $display("              Assertion 8 is violated              ");
    $display("===================================================");
    $fatal;
end

// assertion 9:
assert_9: assert property (dram_valid_overlap)
else begin
    $display("===================================================");
    $display("              Assertion 9 is violated              ");
    $display("===================================================");
    $fatal;
end


// property for assertion 2
property latency_ic_and_up;
    @(posedge clk) ((current_action === Index_Check || current_action === Update)&& inf.index_valid) |-> (##[1:1000] inf.out_valid);
endproperty

property latency_cvd;
    @(posedge clk) (current_action === Check_Valid_Date && inf.data_no_valid) |-> (##[1:1000] inf.out_valid);
endproperty

// property for assertion 3
property complete_no_warn;
    @(negedge clk) (inf.complete |-> (inf.warn_msg == No_Warn));
endproperty

// property for assertion 4
property ic_act_formula;
    @(negedge clk) (current_action === Index_Check && inf.sel_action_valid) |-> (##[1:4] inf.formula_valid);
endproperty

property ic_formula_mode;
    @(negedge clk) (current_action === Index_Check && inf.formula_valid) |-> (##[1:4] inf.mode_valid);
endproperty

property ic_mode_date;
    @(negedge clk) (current_action === Index_Check && inf.mode_valid) |-> (##[1:4] inf.date_valid);
endproperty

property act_date;
    @(negedge clk) ((current_action === Update || current_action === Check_Valid_Date) && inf.sel_action_valid) |-> (##[1:4] inf.date_valid);
endproperty

property date_data_no;
    @(negedge clk) (inf.date_valid) |-> (##[1:4] inf.data_no_valid);
endproperty

property data_no_index;
    @(negedge clk) ((current_action === Index_Check || current_action === Update) && inf.data_no_valid) |-> (##[1:4] inf.index_valid);
endproperty

property index_index;
    @(negedge clk) (inf.index_valid && cnt !== 4) |-> (##[1:4] inf.index_valid );
endproperty

// property for assertion 5
logic no_valid;
assign no_valid = !(inf.sel_action_valid || inf.formula_valid || inf.mode_valid || inf.date_valid || inf.data_no_valid || inf.index_valid);
property valid_overlap;
    @(posedge clk) $onehot({inf.sel_action_valid, inf.formula_valid, inf.mode_valid, inf.date_valid, inf.data_no_valid, inf.index_valid, no_valid});
endproperty

// property for assertion 6
property one_out_valid;
    @(posedge clk) (inf.out_valid) |=> (!inf.out_valid);
endproperty

// property for assertion 7
property next_pat;
    @(posedge clk) (inf.out_valid) |-> (##[1:4] inf.sel_action_valid);
endproperty

// property for assertion 8
property month_check;
    @(posedge clk) (inf.date_valid) |-> (inf.D.d_date[0].M >= 1 && inf.D.d_date[0].M <= 12);
endproperty

property day_31_check;
    @(posedge clk) (inf.date_valid && (inf.D.d_date[0].M === 1 || inf.D.d_date[0].M === 3 || inf.D.d_date[0].M === 5 || inf.D.d_date[0].M === 7 || inf.D.d_date[0].M === 8 || inf.D.d_date[0].M ===10 || inf.D.d_date[0].M === 12) |-> (inf.D.d_date[0].D >= 1 && inf.D.d_date[0].D <= 31) );
endproperty

property day_30_check;
    @(posedge clk) (inf.date_valid && (inf.D.d_date[0].M === 4 || inf.D.d_date[0].M === 6 || inf.D.d_date[0].M === 9 || inf.D.d_date[0].M === 11) |-> (inf.D.d_date[0].D >= 1 && inf.D.d_date[0].D <= 30) );
endproperty

property day_28_check;
    @(posedge clk) (inf.date_valid && inf.D.d_date[0].M === 2 |-> (inf.D.d_date[0].D >= 1 && inf.D.d_date[0].D <= 28) );
endproperty

// property for assertion 9
property dram_valid_overlap;
    @(posedge clk) inf.AR_VALID |-> !inf.AW_VALID;
endproperty

endmodule
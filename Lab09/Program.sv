module Program(input clk, INF.Program_inf inf);
import usertype::*;

typedef enum logic [3:0] {
    IDLE = 4'b0000,
    IN_FORMULA = 4'b0001,
    IN_MODE = 4'b0010,
    IN_DATE = 4'b0011,
    IN_DATA_NO = 4'b0100,
    IN_INDEX = 4'b0101,
    IC = 4'b0110,
    UP = 4'b0111,
    CVD = 4'b1000,
    WAIT_DRAM = 4'b1001,
    OUT = 4'b1010
}   main_state;

typedef enum logic [2:0] {
    DRAM_IDLE = 3'b000,
    DRAM_R_ADDR = 3'b001,
    DRAM_R_DATA = 3'b010,
    DRAM_W_ADDR = 3'b011,
    DRAM_W_DATA = 3'b100,
    DRAM_W_RESP = 3'b101
}   dram_state;

main_state cs_main, ns_main;
dram_state cs_dram, ns_dram;

logic   [3:0]   cnt_idx, ns_cnt_idx;
logic           read_finish;

Action current_action;
Order_Info current_order;
Date current_date;
Data_No current_data_no;

Data_Dir current_dram_info;

// Index_Check
// input late index 
Index           [3:0]   current_late_index;
// cmp input
Index           [3:0]   cmp_in;
// difference
Index           [3:0]   diff_index, ns_diff_index;
// Index           [3:0]   sorted_diff_index;
// formula result
// A
logic           [12:0]  result_a_1, result_a_2;
logic           [13:0]  ns_result_a;
logic           [11:0]  result_a;
// B and C
Index                   b0, b1, s0, s1, bb, ss, bs, sb;
Index           [3:0]   sorted_index, ns_sorted_index;
Index                   result_b, result_c;
// D and E
logic                   ns_result_d0, ns_result_d1, ns_result_d2, ns_result_d3;
logic           [2:0]   result_d;
logic                   ns_result_e0, ns_result_e1, ns_result_e2, ns_result_e3;
logic           [2:0]   result_e;
// F, G and H
logic           [13:0]  add_f, ns_add_f;
logic           [11:0]  ns_result_g;
logic           [12:0]  result_h_1, result_h_2;
logic           [13:0]  ns_result_h;
logic           [12:0]  result_f;
logic           [11:0]  result_g, result_h;

// Result for threshold check
logic           [12:0]  result;

// Update
// 0 for A, 1 for B, 2 for C, 3 for D
// signed adder input (13 bit and 12 bit)
Extend_Index    [3:0] old_index;
Variation       [3:0] current_var;
// signed adder output : Update_Index is signed 14 bits
Update_Index    [3:0] update_index, ns_update_index;
Index           [3:0] wb_index;

// Output Temp
logic                 complete_temp;
Warn_Msg              warn_temp;


//#################################
//            DESIGN
//#################################
//#################################
//           DRAM FSM
//#################################
always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        cs_dram <= DRAM_IDLE;
    end else begin
        cs_dram <= ns_dram;
    end
end

always_comb begin
    ns_dram = cs_dram;
    case (cs_dram)
        DRAM_IDLE: begin
            if(inf.data_no_valid) begin
                ns_dram = DRAM_R_ADDR;
            end 
            else if(cs_main ==  UP && cnt_idx == 'd5) begin
                ns_dram = DRAM_W_ADDR;
            end
        end
        DRAM_R_ADDR: begin
            if(inf.AR_VALID && inf.AR_READY) begin
                ns_dram = DRAM_R_DATA;
            end
        end
        DRAM_R_DATA: begin
            if(inf.R_VALID && inf.R_READY) begin
                ns_dram = DRAM_IDLE;
            end
        end
        DRAM_W_ADDR: begin
            if(inf.AW_VALID && inf.AW_READY) begin
                ns_dram = DRAM_W_DATA;
            end
        end
        DRAM_W_DATA: begin
            if(inf.W_VALID && inf.W_READY) begin
                ns_dram = DRAM_W_RESP;
            end
        end
        DRAM_W_RESP: begin
            if(inf.B_VALID && inf.B_READY) begin
                ns_dram = DRAM_IDLE;
            end
        end
    endcase
end

//#################################
//           MAIN FSM
//#################################
always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        cs_main <= IDLE;
    end else begin
        cs_main <= ns_main;
    end
end

always_comb begin
    ns_main = cs_main;
    case (cs_main)
        IDLE: begin
            if(inf.sel_action_valid) begin
                if(inf.D.d_act[0] == 'd0)begin
                    ns_main = IN_FORMULA;
                end else if(inf.D.d_act[0] == 'd1 || inf.D.d_act[0] == 'd2) begin
                    ns_main = IN_DATE;
                end
            end
        end
        IN_FORMULA: begin
            if(inf.mode_valid) begin
                ns_main = IN_MODE;
            end
        end
        IN_MODE: begin
            if(inf.date_valid) begin
                ns_main = IN_DATE;
            end
        end
        IN_DATE: begin
            if(inf.data_no_valid) begin
                ns_main = IN_DATA_NO;
            end
        end
        IN_DATA_NO: begin
            if(current_action == Index_Check || current_action == Update) begin
                ns_main = IN_INDEX;
            end else if(current_action == Check_Valid_Date && read_finish) begin
                ns_main = CVD;
            end
        end
        IN_INDEX: begin
            if(cnt_idx == 'd4 && read_finish) begin
                case (current_action)
                    Index_Check: begin
                        ns_main = IC;
                    end
                    Update: begin
                        ns_main = UP;
                    end
                endcase
            end
        end
        IC: begin
            if(current_date.M < current_dram_info.M) begin
                ns_main = OUT;
            end else if(current_date.M == current_dram_info.M) begin
                if(current_date.D < current_dram_info.D || cnt_idx == 'd9)begin
                    ns_main = OUT;
                end
            end else if(cnt_idx == 'd9) begin
                ns_main = OUT;
            end
        end
        UP: begin
            if(cnt_idx == 'd5)begin
                ns_main = WAIT_DRAM;
            end
        end
        WAIT_DRAM: begin
            if(inf.B_VALID && inf.B_READY) begin
                ns_main = OUT;
            end
        end
        CVD:begin
            ns_main = OUT;
        end
        OUT:begin
            ns_main = IDLE;
        end
    endcase
end

// dram read finish flag
always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        read_finish <= 0;
    end else if(cs_main == IDLE) begin
        read_finish <= 0;
    end else if(inf.R_VALID && inf.R_READY) begin
        read_finish <= 1;
    end
end

// input
always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        current_action <= Index_Check;
    end else if(inf.sel_action_valid) begin
        current_action <= inf.D.d_act[0];
    end
end

always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        current_order.Formula_Type_O <= Formula_A;
    end else if(inf.formula_valid) begin
        current_order.Formula_Type_O <= inf.D.d_formula;
    end
end

always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        current_order.Mode_O <= Insensitive;
    end else if(inf.mode_valid) begin
        current_order.Mode_O <= inf.D.d_mode;
    end
end

always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        current_date.M <= 0;
        current_date.D <= 0;
    end else if(inf.date_valid) begin
        current_date.M <= inf.D.d_date[0][8:5];
        current_date.D <= inf.D.d_date[0][4:0];
    end
end

always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        current_data_no <= 0;
    end else if(inf.data_no_valid) begin
        current_data_no <= inf.D.d_data_no[0];
    end
end

// index input for index check
always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        current_late_index[0] <= 12'd0;
        current_late_index[1] <= 12'd0;
        current_late_index[2] <= 12'd0;
        current_late_index[3] <= 12'd0;
    end else if(current_action == Index_Check && inf.index_valid) begin
        current_late_index[cnt_idx] <= inf.D.d_index[0];
    end
end

// index input for update
always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        current_var[0] <= 0;
        current_var[1] <= 0;
        current_var[2] <= 0;
        current_var[3] <= 0;
    end else if(current_action == Update && inf.index_valid) begin
        current_var[cnt_idx] <= inf.D.d_index[0];
    end
end

always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        current_dram_info.Index_A <= 12'd0;
        current_dram_info.Index_B <= 12'd0;
        current_dram_info.Index_C <= 12'd0;
        current_dram_info.Index_D <= 12'd0;
        current_dram_info.M <= 4'd0;
        current_dram_info.D <= 5'd0;
    end else if(inf.R_VALID && inf.R_READY) begin
        current_dram_info.Index_A <= inf.R_DATA[63:52];
        current_dram_info.Index_B <= inf.R_DATA[51:40];
        current_dram_info.Index_C <= inf.R_DATA[31:20];
        current_dram_info.Index_D <= inf.R_DATA[19:8];
        current_dram_info.M <= inf.R_DATA[35:32];
        current_dram_info.D <= inf.R_DATA[4:0];
    end
end

// counter for index
always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        cnt_idx <= 0;
    end else begin
        cnt_idx <= ns_cnt_idx;
    end
end
always_comb begin
    ns_cnt_idx = 0;
    if(inf.index_valid) begin
        ns_cnt_idx = cnt_idx + 1;
    end else begin
        case (cs_main)
            IN_INDEX:begin
                ns_cnt_idx = cnt_idx;
            end
            UP:begin
                ns_cnt_idx = cnt_idx + 1;
            end
            IC:begin
                ns_cnt_idx = cnt_idx + 1;
            end
        endcase
    end
    // case (cs_main)
        // IN_INDEX:begin
            // if(inf.index_valid) begin
                // ns_cnt_idx = cnt_idx + 1;
            // end else begin
                // ns_cnt_idx = cnt_idx;
            // end
        // end
        // UP:begin
            // ns_cnt_idx = cnt_idx + 1;
        // end
        // IC:begin
            // ns_cnt_idx = cnt_idx + 1;
        // end
    // endcase
end

// Index_Check
// formula A
assign result_a_1 = current_dram_info.Index_A + current_dram_info.Index_B;
assign result_a_2 = current_dram_info.Index_C + current_dram_info.Index_D;
assign ns_result_a = result_a_1 + result_a_2;

// formula B and C
always_comb begin
    cmp_in[0] = 12'd0;
    cmp_in[1] = 12'd0;
    cmp_in[2] = 12'd0;
    cmp_in[3] = 12'd0;
    case (cs_main)
        IC:begin
            if(cnt_idx == 'd4)begin
                cmp_in[0] = current_dram_info.Index_A;
                cmp_in[1] = current_dram_info.Index_B;
                cmp_in[2] = current_dram_info.Index_C;
                cmp_in[3] = current_dram_info.Index_D;
            end else begin
                cmp_in[0] = diff_index[0];
                cmp_in[1] = diff_index[1];
                cmp_in[2] = diff_index[2];
                cmp_in[3] = diff_index[3];
            end
        end
    endcase
end
assign b0 = (cmp_in[0] > cmp_in[1])? cmp_in[0] : cmp_in[1];
assign b1 = (cmp_in[2] > cmp_in[3])? cmp_in[2] : cmp_in[3];
assign s0 = (cmp_in[0] < cmp_in[1])? cmp_in[0] : cmp_in[1];
assign s1 = (cmp_in[2] < cmp_in[3])? cmp_in[2] : cmp_in[3];
assign bb = (b0 > b1)? b0 : b1;
assign bs = (b0 > b1)? b1 : b0;
assign sb = (s0 > s1)? s0 : s1;
assign ss = (s0 > s1)? s1 : s0;
assign ns_sorted_index[0] = bb;
assign ns_sorted_index[1] = (bs > sb)? bs : sb;
assign ns_sorted_index[2] = (bs > sb)? sb : bs;
assign ns_sorted_index[3] = ss;

always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        sorted_index[0] <= 12'd0;
        sorted_index[1] <= 12'd0;
        sorted_index[2] <= 12'd0;
        sorted_index[3] <= 12'd0;
    end else begin
        case (cs_main)
            IC:begin
                sorted_index[0] <= ns_sorted_index[0];
                sorted_index[1] <= ns_sorted_index[1];
                sorted_index[2] <= ns_sorted_index[2];
                sorted_index[3] <= ns_sorted_index[3];
            end
        endcase
    end
end

// formula D
assign ns_result_d0 = (current_dram_info.Index_A[11] || current_dram_info.Index_A == 12'd2047 )? 1 : 0;
assign ns_result_d1 = (current_dram_info.Index_B[11] || current_dram_info.Index_B == 12'd2047 )? 1 : 0;
assign ns_result_d2 = (current_dram_info.Index_C[11] || current_dram_info.Index_C == 12'd2047 )? 1 : 0;
assign ns_result_d3 = (current_dram_info.Index_D[11] || current_dram_info.Index_D == 12'd2047 )? 1 : 0;

// formula E
assign ns_result_e0 = (current_dram_info.Index_A < current_late_index[0])? 0 : 1;
assign ns_result_e1 = (current_dram_info.Index_B < current_late_index[1])? 0 : 1;
assign ns_result_e2 = (current_dram_info.Index_C < current_late_index[2])? 0 : 1;
assign ns_result_e3 = (current_dram_info.Index_D < current_late_index[3])? 0 : 1;
// end

// |difference|
Index [3:0] big, smal, ns_big, ns_smal;
assign ns_big[0] = (current_dram_info.Index_A > current_late_index[0])? current_dram_info.Index_A: current_late_index[0];
assign ns_big[1] = (current_dram_info.Index_B > current_late_index[1])? current_dram_info.Index_B: current_late_index[1];
assign ns_big[2] = (current_dram_info.Index_C > current_late_index[2])? current_dram_info.Index_C: current_late_index[2];
assign ns_big[3] = (current_dram_info.Index_D > current_late_index[3])? current_dram_info.Index_D: current_late_index[3];
assign ns_smal[0] = (current_dram_info.Index_A < current_late_index[0])? current_dram_info.Index_A: current_late_index[0];
assign ns_smal[1] = (current_dram_info.Index_B < current_late_index[1])? current_dram_info.Index_B: current_late_index[1];
assign ns_smal[2] = (current_dram_info.Index_C < current_late_index[2])? current_dram_info.Index_C: current_late_index[2];
assign ns_smal[3] = (current_dram_info.Index_D < current_late_index[3])? current_dram_info.Index_D: current_late_index[3];
always_ff @( posedge clk or negedge inf.rst_n) begin
    if(inf.rst_n)begin
        big[0] <= 12'd0;
        big[1] <= 12'd0;
        big[2] <= 12'd0;
        big[3] <= 12'd0;
        smal[0] <= 12'd0;
        smal[1] <= 12'd0;
        smal[2] <= 12'd0;
        smal[3] <= 12'd0;
    end else begin
        big[0] <= ns_big[0];
        big[1] <= ns_big[1];
        big[2] <= ns_big[2];    
        big[3] <= ns_big[3];
        smal[0] <= ns_smal[0];
        smal[1] <= ns_smal[1];
        smal[2] <= ns_smal[2];
        smal[3] <= ns_smal[3];
    end
end
assign ns_diff_index[0] = big[0] - smal[0];
assign ns_diff_index[1] = big[1] - smal[1];
assign ns_diff_index[2] = big[2] - smal[2];
assign ns_diff_index[3] = big[3] - smal[3];

always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        diff_index[0] <= 12'd0;
        diff_index[1] <= 12'd0;
        diff_index[2] <= 12'd0;
        diff_index[3] <= 12'd0;
    end else begin
        case (cs_main)
            IC:begin
                diff_index[0] <= ns_diff_index[0];
                diff_index[1] <= ns_diff_index[1];
                diff_index[2] <= ns_diff_index[2];
                diff_index[3] <= ns_diff_index[3];
            end
        endcase
    end
end

// formula F
assign ns_add_f = sorted_index[1] + sorted_index[2] + sorted_index[3];
always_ff @( posedge clk or negedge inf.rst_n) begin
    if(!inf.rst_n)begin
        add_f <= 14'd0;
    end else begin
        add_f <= ns_add_f;
    end
end

// formula G
assign ns_result_g = (sorted_index[3] >> 1) + (sorted_index[2] >> 2) + (sorted_index[1] >> 2);

// formula H
assign result_h_1 = sorted_index[0] + sorted_index[1];
assign result_h_2 = sorted_index[2] + sorted_index[3];
assign ns_result_h = result_h_1 + result_h_2;

// Threshold Check
always_ff @( posedge clk or negedge inf.rst_n )begin
    if(!inf.rst_n)begin
        result <= 12'd0;
    end else begin
        case (cs_main)
            IC:begin
                case (current_order.Formula_Type_O)
                    Formula_A:begin
                        result <= ns_result_a >> 2;
                    end
                    Formula_B:begin
                        if(cnt_idx == 'd5)begin
                            result <= sorted_index[0] - sorted_index[3];
                        end
                    end
                    Formula_C:begin
                        if(cnt_idx == 'd4)begin
                            result <= ss;
                        end
                    end
                    Formula_D:begin
                        result <= ns_result_d0 + ns_result_d1 + ns_result_d2 + ns_result_d3;
                    end
                    Formula_E:begin
                        result <= ns_result_e0 + ns_result_e1 + ns_result_e2 + ns_result_e3;
                    end
                    Formula_F:begin
                        result <= add_f/'d3;
                    end
                    Formula_G:begin
                        result <= ns_result_g;
                    end
                    Formula_H:begin
                        result <= ns_result_h >> 2;
                    end
                endcase
            end
        endcase
    end
end

// Update
assign old_index[0] = {1'b0 ,current_dram_info.Index_A};
assign old_index[1] = {1'b0 ,current_dram_info.Index_B};
assign old_index[2] = {1'b0 ,current_dram_info.Index_C};
assign old_index[3] = {1'b0 ,current_dram_info.Index_D};
assign ns_update_index[0] = $signed(old_index[0]) + $signed(current_var[0]);
assign ns_update_index[1] = $signed(old_index[1]) + $signed(current_var[1]);
assign ns_update_index[2] = $signed(old_index[2]) + $signed(current_var[2]);
assign ns_update_index[3] = $signed(old_index[3]) + $signed(current_var[3]);

always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        update_index[0] <= 14'd0;
        update_index[1] <= 14'd0;
        update_index[2] <= 14'd0;
        update_index[3] <= 14'd0;
    end else begin
        case (cs_main)
            UP:begin
                update_index[0] <= ns_update_index[0];
                update_index[1] <= ns_update_index[1];
                update_index[2] <= ns_update_index[2];
                update_index[3] <= ns_update_index[3];
            end
        endcase
    end
end

// write back index
assign wb_index[0] = (update_index[0][13])? 12'd0 : (update_index[0][12])? 12'd4095 : update_index[0][11:0];
assign wb_index[1] = (update_index[1][13])? 12'd0 : (update_index[1][12])? 12'd4095 : update_index[1][11:0];
assign wb_index[2] = (update_index[2][13])? 12'd0 : (update_index[2][12])? 12'd4095 : update_index[2][11:0];
assign wb_index[3] = (update_index[3][13])? 12'd0 : (update_index[3][12])? 12'd4095 : update_index[3][11:0];

// main output setting
always_ff @( posedge clk or negedge inf.rst_n ) begin
    if(!inf.rst_n)begin
        complete_temp <= 0;
        warn_temp <= No_Warn;
    end else begin
        case (cs_main)
            IC:begin
                if(current_date.M < current_dram_info.M) begin
                    warn_temp <= Date_Warn;
                    complete_temp <= 0;
                end else begin
                    if(current_date.M == current_dram_info.M && current_date.D < current_dram_info.D)begin
                        warn_temp <= Date_Warn;
                        complete_temp <= 0;
                    end else begin
                        case (current_order.Formula_Type_O)
                            Formula_A, Formula_C:begin
                                case (current_order.Mode_O)
                                    Insensitive:begin
                                        if(result < 'd2047) begin
                                            warn_temp <= No_Warn;
                                            complete_temp <= 1;
                                        end else begin
                                            warn_temp <= Risk_Warn;
                                            complete_temp <= 0;
                                        end
                                    end 
                                    Normal:begin
                                        if(result < 'd1023) begin
                                            warn_temp <= No_Warn;
                                            complete_temp <= 1;
                                        end else begin
                                            warn_temp <= Risk_Warn;
                                            complete_temp <= 0;
                                        end
                                    end
                                    Sensitive:begin
                                        if(result < 'd511) begin
                                            warn_temp <= No_Warn;
                                            complete_temp <= 1;
                                        end else begin
                                            warn_temp <= Risk_Warn;
                                            complete_temp <= 0;
                                        end
                                    end
                                endcase
                            end
                            Formula_B, Formula_F, Formula_G, Formula_H:begin
                                case (current_order.Mode_O)
                                    Insensitive:begin
                                        if(result < 'd800) begin
                                            warn_temp <= No_Warn;
                                            complete_temp <= 1;
                                        end else begin
                                            warn_temp <= Risk_Warn;
                                            complete_temp <= 0;
                                        end
                                    end 
                                    Normal:begin
                                        if(result < 'd400) begin
                                            warn_temp <= No_Warn;
                                            complete_temp <= 1;
                                        end else begin
                                            warn_temp <= Risk_Warn;
                                            complete_temp <= 0;
                                        end
                                    end
                                    Sensitive:begin
                                        if(result < 'd200) begin
                                            warn_temp <= No_Warn;
                                            complete_temp <= 1;
                                        end else begin
                                            warn_temp <= Risk_Warn;
                                            complete_temp <= 0;
                                        end
                                    end
                                endcase
                            end
                            Formula_D, Formula_E:begin
                                case (current_order.Mode_O)
                                    Insensitive:begin
                                        if(result < 'd3) begin
                                            warn_temp <= No_Warn;
                                            complete_temp <= 1;
                                        end else begin
                                            warn_temp <= Risk_Warn;
                                            complete_temp <= 0;
                                        end
                                    end 
                                    Normal:begin
                                        if(result < 'd2) begin
                                            warn_temp <= No_Warn;
                                            complete_temp <= 1;
                                        end else begin
                                            warn_temp <= Risk_Warn;
                                            complete_temp <= 0;
                                        end
                                    end
                                    Sensitive:begin
                                        if(result < 'd1) begin
                                            warn_temp <= No_Warn;
                                            complete_temp <= 1;
                                        end else begin
                                            warn_temp <= Risk_Warn;
                                            complete_temp <= 0;
                                        end
                                    end
                                endcase
                            end
                        endcase
                    end
                end
            end
            UP:begin
                if(update_index[0][13] || update_index[1][13] || update_index[2][13] || update_index[3][13] || update_index[0][12] || update_index[1][12] || update_index[2][12] || update_index[3][12]) begin
                    warn_temp <= Data_Warn;
                    complete_temp <= 0;
                end else begin
                    warn_temp <= No_Warn;
                    complete_temp <= 1;
                end
            end
            CVD:begin
                if(current_date.M < current_dram_info.M) begin
                    warn_temp <= Date_Warn;
                    complete_temp <= 0;
                end else begin
                    if(current_date.M == current_dram_info.M && current_date.D < current_dram_info.D)begin
                        warn_temp <= Date_Warn;
                        complete_temp <= 0;
                    end else begin
                        warn_temp <= No_Warn;
                        complete_temp <= 1;
                    end
                end
            end
            //IC
        endcase
    end
end

always_comb begin
    inf.out_valid = 0;
    inf.warn_msg = No_Warn;
    inf.complete = 0;
    if(cs_main == OUT) begin
        inf.out_valid = 1;
        inf.complete = complete_temp;
        inf.warn_msg = warn_temp;
    end
end

// dram output setting
// read
always_comb begin
    inf.AR_VALID = 0;
    inf.AR_ADDR = 17'd0;
    case (cs_dram)
        DRAM_R_ADDR:begin
            inf.AR_VALID = 1;
            inf.AR_ADDR = {6'b100000, current_data_no, 3'd0};
        end
    endcase
end
always_comb begin
    inf.R_READY = 0;
    case (cs_dram)
        DRAM_R_DATA:begin
            inf.R_READY = 1;
        end
    endcase
end

// write
always_comb begin
    inf.AW_VALID = 0;
    inf.AW_ADDR = 17'd0;
    case (cs_dram)
        DRAM_W_ADDR:begin
            inf.AW_VALID = 1;
            inf.AW_ADDR = {6'b100000, current_data_no, 3'd0};
        end
    endcase
end
always_comb begin
    inf.W_VALID = 0;
    inf.W_DATA = 64'd0;
    case (cs_dram)
        DRAM_W_DATA:begin
            inf.W_VALID = 1;
            inf.W_DATA = {wb_index[0], wb_index[1], 4'd0, current_date.M, wb_index[2], wb_index[3], 3'd0, current_date.D};
        end
    endcase
end
always_comb begin
    inf.B_READY = 0;
    case (cs_dram)
        DRAM_W_RESP:begin
            inf.B_READY = 1;
        end
    endcase
end

endmodule

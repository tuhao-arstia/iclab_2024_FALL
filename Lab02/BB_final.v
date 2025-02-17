module BB(
    //Input Ports
    input clk,
    input rst_n,
    input in_valid,
    input [1:0] inning,   // Current inning number
    input half,           // 0: top of the inning, 1: bottom of the inning
    input [2:0] action,   // Action code

    //Output Ports
    output reg out_valid,  // Result output valid
    output reg [7:0] score_A,  // Score of team A (guest team)
    output reg [7:0] score_B,  // Score of team B (home team)
    output reg [1:0] result    // 0: Team A wins, 1: Team B wins, 2: Draw
);
//==============================================//

//==============================================//
//             Parameter and Integer            //
//==============================================//
// State declaration for FSM
// Example: parameter IDLE = 3'b000;
localparam IDLE = 2'b00;
localparam PLAY = 2'b01;
localparam OUT = 2'b10;

//==============================================//
//                 reg declaration              //
//==============================================//
reg [1:0]   cs, ns;

// base
reg         base1, base2, base3, ns_base1, ns_base2, ns_base3;

// out
reg [1:0]   out, ns_out;

// score
wire[3:0]   team_score, new_team_score;
reg [3:0]   a_score, ns_a_score;
reg [2:0]   b_score, ns_b_score, ns_get_score;

reg         B_already_won, ns_B_already_won;
//==============================================//
//                    design                    //
//==============================================//
// FSM and input buffer
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
            if(in_valid)begin
                ns = PLAY;
            end else begin
                ns = cs;
            end
        end
        PLAY:begin
            if(!in_valid)begin
                ns = OUT;
            end else begin
                ns = cs;
            end
        end
        OUT:begin
            ns = IDLE;
        end
        default:begin
            ns = cs;
        end
    endcase
end

// base
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        base1 <= 0;
        base2 <= 0;
        base3 <= 0;
    end else begin
        base1 <= ns_base1;
        base2 <= ns_base2;
        base3 <= ns_base3;
    end
end

always @(*) begin
    case (ns)
        PLAY:begin
            if(ns_out == 2'd3)begin
                {ns_base3, ns_base2, ns_base1} = 3'b000;
            end else begin
                case (action)
                    3'd0:begin
                        if(base1 && base2)begin
                            ns_base3 = 1'b1;
                        end else begin
                            ns_base3 = base3;
                        end
                        if(base1)begin
                            ns_base2 = 1'b1;
                        end else begin
                            ns_base2 = base2;
                        end
                        ns_base1 = 1'b1;
                    end 
                    3'd1:begin
                        if(out[1])begin
                            ns_base3 = base1;
                            ns_base2 = 1'b0;
                        end else begin
                            ns_base3 = base2;
                            ns_base2 = base1;
                        end
                        ns_base1 = 1'b1;
                    end
                    3'd2:begin
                        if(out[1])begin
                            ns_base3 = 1'b0;
                        end else begin
                            ns_base3 = base1;
                        end
                        ns_base2 = 1'b1;
                        ns_base1 = 1'b0;
                    end
                    3'd3:begin
                        {ns_base3, ns_base2, ns_base1} = 3'b100;
                    end
                    3'd4:begin
                        {ns_base3, ns_base2, ns_base1} = 3'b000;
                    end
                    3'd5:begin
                        {ns_base3, ns_base2, ns_base1} = {base2, base1, 1'b0};
                    end
                    3'd6:begin
                        {ns_base3, ns_base2, ns_base1} = {base2, 2'b00};
                    end
                    3'd7:begin
                        {ns_base3, ns_base2, ns_base1} = {1'b0, base2, base1};
                    end
                    default:begin
                        {ns_base3, ns_base2, ns_base1} = 3'b000;
                    end 
                endcase
            end
        end
        default:begin
            {ns_base3, ns_base2, ns_base1} = 3'b000;
        end
    endcase
end

// out
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        out <= 0;
    end else begin
        case (ns)
            IDLE:begin
                out <= 0;
            end
            PLAY:begin
                if(ns_out == 2'd3)begin
                    out <= 0;
                end else begin
                    out <= ns_out;
                end
            end
            default:begin
                out <= ns_out;
            end 
        endcase
    end
end

always @(*) begin
    case (action)
        3'd5, 3'd7:begin
            ns_out = out + 'd1;
        end
        3'd6:begin
            if(base1 && !out[1])begin
                ns_out = out + 'd2;
            end else begin
                ns_out = out + 'd1;
            end
        end
        default:begin
            ns_out = out;
        end 
    endcase
end

// score
assign team_score = (!half) ? a_score : b_score;
assign new_team_score = team_score + ns_get_score;

// ab score
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        a_score <= 0;
        b_score <= 0;
    end else begin
        a_score <= ns_a_score;   
        b_score <= ns_b_score;
    end
end

always @(*) begin
    case (ns)
        IDLE:begin
            ns_a_score = 0;
        end
        PLAY:begin
            if(!half)begin
                ns_a_score = new_team_score;
            end else begin
                ns_a_score = a_score;
            end
        end
        default:begin
            ns_a_score = a_score;
        end
    endcase
end
always @(*) begin
    case (ns)
        IDLE:begin
            ns_b_score = 0;
        end 
        PLAY:begin
            if(half)begin
                if(B_already_won)begin
                    ns_b_score = b_score;
                end else begin
                    ns_b_score = new_team_score;
                end
            end else begin
                ns_b_score = b_score;
            end
        end
        default:begin
            ns_b_score = b_score;
        end
    endcase
end

// next get score
always @(*) begin
    case (action)
        3'd0:begin
            ns_get_score = base1 & base2 & base3;
        end 
        3'd1:begin
            if(out[1])begin
                ns_get_score = base3 + base2;
            end else begin
                if(base3)begin
                    ns_get_score = 'd1;
                end else begin
                    ns_get_score = 0;
                end
            end
        end
        3'd2:begin
            if(out[1])begin
                ns_get_score = base3 + base2 + base1;
            end else begin
                ns_get_score = base3 + base2;
            end
        end
        3'd3:begin
            ns_get_score = base3 + base2 + base1;
        end
        3'd4:begin
            ns_get_score = base3 + base2 + base1 + 'd1;
        end
        3'd5:begin
            ns_get_score = base3;
        end
        3'd6, 3'd7:begin
            if(ns_out == 2'd3)begin
                ns_get_score = 0;
            end else begin
                ns_get_score = base3;
            end
        end
        default:begin
            ns_get_score = 0;
        end
    endcase
end

// B_already_won
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        B_already_won <= 0;
    end else begin
        B_already_won <= ns_B_already_won;
    end
end

always @(*) begin
    case (ns)
        PLAY:begin
            if(inning == 2'd3 && ns_out == 2'd3 && (b_score > a_score))begin
                ns_B_already_won = 1;
            end else begin
                ns_B_already_won = B_already_won;
            end
        end 
        default:begin
            ns_B_already_won = 0;
        end
    endcase
end

//==============================================//
//                Output Block                  //
//==============================================//
// Decide when to set out_valid high, and output score_A, score_B, and result.
// out_valid
always @(*) begin
    if(cs == OUT)begin
        out_valid = 1;
    end else begin
        out_valid = 0;
    end
end

// score_A and score_B
always @(*) begin
    if(out_valid)begin
        score_A = a_score;
        score_B = b_score;
    end else begin
        score_A = 0;
        score_B = 0;
    end
end

// result
always @(*) begin
    if(cs == OUT)begin
        if(a_score < b_score)begin
            result = 'd1;
        end else if(a_score > b_score)begin
            result = 'd0;
        end else begin
            result = 'd2;
        end
    end else begin
        result = 'd0;
    end
end
endmodule

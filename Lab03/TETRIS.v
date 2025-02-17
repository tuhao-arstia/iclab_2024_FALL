/**************************************************************************/
// Copyright (c) 2024, OASIS Lab
// MODULE: TETRIS
// FILE NAME: TETRIS.v
// VERSRION: 1.0
// DATE: August 15, 2024
// AUTHOR: Yu-Hsuan Hsu, NYCU IEE
// DESCRIPTION: ICLAB2024FALL / LAB3 / TETRIS
// MODIFICATION HISTORY:
// Date                 Description
// 
/**************************************************************************/
module TETRIS (
	//INPUT
	rst_n,
	clk,
	in_valid,
	tetrominoes,
	position,
	//OUTPUT
	tetris_valid,
	score_valid,
	fail,
	score,
	tetris
);

//---------------------------------------------------------------------
//   PORT DECLARATION          
//---------------------------------------------------------------------
input				rst_n, clk, in_valid;
input		[2:0]	tetrominoes;
input		[2:0]	position;
output reg			tetris_valid, score_valid, fail;
output reg	[3:0]	score;
output reg 	[71:0]	tetris;

//---------------------------------------------------------------------
//   PARAMETER & INTEGER DECLARATION
//---------------------------------------------------------------------
parameter IDLE     = 2'b00;
parameter ELIM_OUT = 2'b01;
parameter OUT  = 2'b11;
integer i, j;

//---------------------------------------------------------------------
//   REG & WIRE DECLARATION
//---------------------------------------------------------------------
reg [1:0]	cs, ns;
wire[2:0]	ns_domino;
wire[2:0]	ns_pos;
reg	[3:0]	ns_height		[0:5];
wire[3:0]	ns_max_height_position;
reg [24:0]	score_temp, ns_score_temp;
reg [5:0]	tetris_temp		[0:14];
reg [5:0]	ns_tetris_temp  [0:14];
reg			failed_check;

reg [3:0]	move_cnt, ns_move_cnt;
wire		elimination, elim11, elim10, elim9, elim8, elim7, elim6, elim5, elim4, elim3, elim2, elim1, elim0;
//---------------------------------------------------------------------
//   DESIGN
//---------------------------------------------------------------------
// fsm
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
				ns = ELIM_OUT;
			end else begin
				ns = cs;
			end
		end 
		ELIM_OUT:begin
			if(elimination)begin
				ns = cs;
			end else begin
				ns = OUT;
			end
		end
		OUT:begin
			if(in_valid)begin
				ns = ELIM_OUT;
			end else begin
				ns = IDLE;
			end
		end
		default:begin
			ns = cs;
		end 
	endcase
end

// input
assign ns_domino = tetrominoes;
assign ns_pos = position;
FIND_MAX_HEIGHT A1(.domino_type(ns_domino), .domino_position(ns_pos), .height(ns_height), .max_height_position(ns_max_height_position));

// tetris_temp : map refresh
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 15; i = i + 1)begin
			tetris_temp[i] <= 0;
		end
	end else begin
		for(i = 0; i < 15; i = i + 1)begin
			tetris_temp[i] <= ns_tetris_temp[i];
		end
	end
end
always @(*) begin
	ns_tetris_temp = tetris_temp;
	if(in_valid) begin
		case (ns_domino)
			3'd0:begin
				ns_tetris_temp[ns_max_height_position  ][ns_pos  ] = 1;
				ns_tetris_temp[ns_max_height_position  ][ns_pos+1] = 1;
				ns_tetris_temp[ns_max_height_position-1][ns_pos  ] = 1;
				ns_tetris_temp[ns_max_height_position-1][ns_pos+1] = 1;
			end 
			3'd1:begin
				if(tetris_temp[11][ns_pos])begin
					ns_tetris_temp[ns_max_height_position-1][ns_pos] = 1;
					ns_tetris_temp[ns_max_height_position-2][ns_pos] = 1;
					ns_tetris_temp[ns_max_height_position-3][ns_pos] = 1;
				end else begin
					ns_tetris_temp[ns_max_height_position  ][ns_pos] = 1;
					ns_tetris_temp[ns_max_height_position-1][ns_pos] = 1;
					ns_tetris_temp[ns_max_height_position-2][ns_pos] = 1;
					ns_tetris_temp[ns_max_height_position-3][ns_pos] = 1;
				end
			end
			3'd2:begin
				ns_tetris_temp[ns_max_height_position][ns_pos  ] = 1;
				ns_tetris_temp[ns_max_height_position][ns_pos+1] = 1;
				ns_tetris_temp[ns_max_height_position][ns_pos+2] = 1;
				ns_tetris_temp[ns_max_height_position][ns_pos+3] = 1;
			end
			3'd3:begin
				ns_tetris_temp[ns_max_height_position  ][ns_pos  ] = 1;
				ns_tetris_temp[ns_max_height_position  ][ns_pos+1] = 1;
				ns_tetris_temp[ns_max_height_position-1][ns_pos+1] = 1;
				ns_tetris_temp[ns_max_height_position-2][ns_pos+1] = 1;
			end
			3'd4:begin
				ns_tetris_temp[ns_max_height_position-1][ns_pos  ] = 1;
				ns_tetris_temp[ns_max_height_position  ][ns_pos  ] = 1;
				ns_tetris_temp[ns_max_height_position  ][ns_pos+1] = 1;
				ns_tetris_temp[ns_max_height_position  ][ns_pos+2] = 1;
			end
			3'd5:begin
				ns_tetris_temp[ns_max_height_position  ][ns_pos  ] = 1;
				ns_tetris_temp[ns_max_height_position-1][ns_pos  ] = 1;
				ns_tetris_temp[ns_max_height_position-2][ns_pos  ] = 1;
				ns_tetris_temp[ns_max_height_position-2][ns_pos+1] = 1;
			end
			3'd6:begin
				ns_tetris_temp[ns_max_height_position  ][ns_pos  ] = 1;
				ns_tetris_temp[ns_max_height_position-1][ns_pos  ] = 1;
				ns_tetris_temp[ns_max_height_position-1][ns_pos+1] = 1;
				ns_tetris_temp[ns_max_height_position-2][ns_pos+1] = 1;
			end
			3'd7:begin
				ns_tetris_temp[ns_max_height_position  ][ns_pos+1] = 1;
				ns_tetris_temp[ns_max_height_position  ][ns_pos+2] = 1;
				ns_tetris_temp[ns_max_height_position-1][ns_pos  ] = 1;
				ns_tetris_temp[ns_max_height_position-1][ns_pos+1] = 1;
			end
		endcase
	end else if(tetris_valid)begin
		for(i = 0; i < 15; i = i + 1)begin
			for(j = 0; j < 6; j = j + 1)begin
				ns_tetris_temp[i][j] = 0;
			end
		end
	end else if(elim1)begin
		ns_tetris_temp[0] = tetris_temp[0];
		for(i = 1; i < 14; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i+1];
		end
		ns_tetris_temp[14] = 'd0;
	end else if(elim0)begin
		for(i = 0; i < 14; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i+1];
		end
		ns_tetris_temp[14] = 'd0;
	end else if(elim3)begin
		for(i = 0; i < 3; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i];
		end
		for(i = 3; i < 14; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i+1];
		end
		ns_tetris_temp[14] = 'd0;
	end else if(elim2)begin
		for(i = 0; i < 2; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i];
		end
		for(i = 2; i < 14; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i+1];
		end
		ns_tetris_temp[14] = 'd0;
	end else if(elim7)begin
		for(i = 0; i < 7; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i];
		end
		for(i = 7; i < 14; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i+1];
		end
		ns_tetris_temp[14] = 'd0;
	end else if(elim5)begin
		for(i = 0; i < 5; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i];
		end
		for(i = 5; i < 14; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i+1];
		end
		ns_tetris_temp[14] = 'd0;
	end else if(elim6)begin
		for(i = 0; i < 6; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i];
		end
		for(i = 6; i < 14; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i+1];
		end
		
	end else if(elim4)begin
		for(i = 0; i < 4; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i];
		end
		for(i = 4; i < 14; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i+1];
		end
		ns_tetris_temp[14] = 'd0;
	end else if(elim9)begin
		for(i = 0; i < 9; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i];
		end
		for(i = 9; i < 14; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i+1];
		end
		ns_tetris_temp[14] = 'd0;
	end else if(elim8)begin
		for(i = 0; i < 8; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i];
		end
		for(i = 8; i < 14; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i+1];
		end
		ns_tetris_temp[14] = 'd0;
	end else if(elim10)begin
		for(i = 0; i < 10; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i];
		end
		for(i = 10; i < 14; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i+1];
		end
		ns_tetris_temp[14] = 'd0;
	end else if(elim11) begin
		for(i = 0; i < 11; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i];
		end
		for(i = 11; i < 14; i = i + 1)begin
			ns_tetris_temp[i] = tetris_temp[i+1];
		end
		ns_tetris_temp[14] = 'd0;
	end else begin
		ns_tetris_temp = tetris_temp;
	end
end

// score
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		score_temp <= 0;
	end else begin
		score_temp <= ns_score_temp;
	end
end
always @(*) begin
	if(tetris_valid)begin
		ns_score_temp = 0;
	end else if(!in_valid && ns == ELIM_OUT) begin
		ns_score_temp = score_temp + 3'd1;
	end else begin
		ns_score_temp = score_temp;
	end
end

// elimination signal
assign elim11 = &tetris_temp[11];
assign elim10 = &tetris_temp[10];
assign elim9  = &tetris_temp[9] ;
assign elim8  = &tetris_temp[8] ;
assign elim7  = &tetris_temp[7] ;
assign elim6  = &tetris_temp[6] ;
assign elim5  = &tetris_temp[5] ;
assign elim4  = &tetris_temp[4] ;
assign elim3  = &tetris_temp[3] ;
assign elim2  = &tetris_temp[2] ;
assign elim1  = &tetris_temp[1] ;
assign elim0  = &tetris_temp[0] ;
assign elimination = elim11 | elim10 | elim9 | elim8 | elim7 | elim6 | elim5 | elim4 | elim3 | elim2 | elim1 | elim0;

// height
always @(*) begin
	ns_height[0] = (tetris_temp[11][0])? 12: (tetris_temp[10][0])? 11: (tetris_temp[9][0])? 10: (tetris_temp[8][0])? 9: (tetris_temp[7][0])? 8: (tetris_temp[6][0])? 7: (tetris_temp[5][0])? 6: (tetris_temp[4][0])? 5: (tetris_temp[3][0])? 4: (tetris_temp[2][0])? 3: (tetris_temp[1][0])? 2: (tetris_temp[0][0])? 1: 0;
	ns_height[1] = (tetris_temp[11][1])? 12: (tetris_temp[10][1])? 11: (tetris_temp[9][1])? 10: (tetris_temp[8][1])? 9: (tetris_temp[7][1])? 8: (tetris_temp[6][1])? 7: (tetris_temp[5][1])? 6: (tetris_temp[4][1])? 5: (tetris_temp[3][1])? 4: (tetris_temp[2][1])? 3: (tetris_temp[1][1])? 2: (tetris_temp[0][1])? 1: 0;
	ns_height[2] = (tetris_temp[11][2])? 12: (tetris_temp[10][2])? 11: (tetris_temp[9][2])? 10: (tetris_temp[8][2])? 9: (tetris_temp[7][2])? 8: (tetris_temp[6][2])? 7: (tetris_temp[5][2])? 6: (tetris_temp[4][2])? 5: (tetris_temp[3][2])? 4: (tetris_temp[2][2])? 3: (tetris_temp[1][2])? 2: (tetris_temp[0][2])? 1: 0;
	ns_height[3] = (tetris_temp[11][3])? 12: (tetris_temp[10][3])? 11: (tetris_temp[9][3])? 10: (tetris_temp[8][3])? 9: (tetris_temp[7][3])? 8: (tetris_temp[6][3])? 7: (tetris_temp[5][3])? 6: (tetris_temp[4][3])? 5: (tetris_temp[3][3])? 4: (tetris_temp[2][3])? 3: (tetris_temp[1][3])? 2: (tetris_temp[0][3])? 1: 0;
	ns_height[4] = (tetris_temp[11][4])? 12: (tetris_temp[10][4])? 11: (tetris_temp[9][4])? 10: (tetris_temp[8][4])? 9: (tetris_temp[7][4])? 8: (tetris_temp[6][4])? 7: (tetris_temp[5][4])? 6: (tetris_temp[4][4])? 5: (tetris_temp[3][4])? 4: (tetris_temp[2][4])? 3: (tetris_temp[1][4])? 2: (tetris_temp[0][4])? 1: 0;
	ns_height[5] = (tetris_temp[11][5])? 12: (tetris_temp[10][5])? 11: (tetris_temp[9][5])? 10: (tetris_temp[8][5])? 9: (tetris_temp[7][5])? 8: (tetris_temp[6][5])? 7: (tetris_temp[5][5])? 6: (tetris_temp[4][5])? 5: (tetris_temp[3][5])? 4: (tetris_temp[2][5])? 3: (tetris_temp[1][5])? 2: (tetris_temp[0][5])? 1: 0;
end

// failed 
// assign failed_check = tetris_temp[12] || tetris_temp[13] || tetris_temp[14];
// assign failed_check = (|tetris_temp[12]) || (|tetris_temp[13]) || (|tetris_temp[14]);
always @(*) begin
	if(tetris_temp[12] || tetris_temp[13])begin
		failed_check = 1;
	end else begin
		failed_check = 0;
	end
end

// move counter
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        move_cnt <= 0;
    end else begin
        move_cnt <= ns_move_cnt;
    end
end
always @(*) begin
	if(tetris_valid)begin
		ns_move_cnt = 0;
	end else if(in_valid) begin
		ns_move_cnt = move_cnt + 4'd1;
	end else begin
		ns_move_cnt = move_cnt;
	end
end

// output
always @(*) begin
	if(ns == OUT)begin
		score_valid = 1;
	end else begin
		score_valid = 0;
	end
end

always @(*) begin
	if(ns == OUT)begin
		fail = failed_check;
	end else begin
		fail = 0;
	end
end

always @(*) begin
	if(ns == OUT)begin
		score = score_temp;
	end else begin
		score = 0;
	end
end

always @(*) begin
	if((ns == OUT && failed_check) || (ns == OUT && move_cnt == 'd0))begin
		tetris_valid = 1;
	end else begin
		tetris_valid = 0;
	end
end

always @(*) begin
	if((ns == OUT && failed_check) || (ns == OUT && move_cnt == 'd0))begin
		for(i = 0; i < 12; i = i + 1)begin
		    for(j = 0; j < 6; j = j + 1)begin
		        tetris[6*i + j] = tetris_temp[i][j];
		    end
		end
		// tetris = {tetris_temp[11], tetris_temp[10], tetris_temp[9], tetris_temp[8], tetris_temp[7], tetris_temp[6],tetris_temp[5], tetris_temp[4], tetris_temp[3], tetris_temp[2], tetris_temp[1], tetris_temp[0]};
	end else begin
		for(i = 0; i < 72; i = i + 1)begin
			tetris[i] = 'd0;
		end
	end
end

endmodule

module FIND_MAX_HEIGHT(domino_type, domino_position, height, max_height_position);
input	[2:0] domino_type;
input	[2:0] domino_position;
input	[3:0] height	[0:5];
output	[3:0] max_height_position;
reg		[3:0] h0, h1, h2, h3;
wire 	[3:0] b1, b2;	

always @(*) begin
	case (domino_type)
	    3'd0:begin
			h0 = height[domino_position]   + 'd1;
			h1 = height[domino_position+1] + 'd1;
			h2 = 0;
			h3 = 0;
		end
		3'd1:begin
			h0 = height[domino_position] + 'd3;
			h1 = 0;
			h2 = 0;
			h3 = 0;
		end
		3'd2:begin
			h0 = height[domino_position]  ;
			h1 = height[domino_position+1];
			h2 = height[domino_position+2];
			h3 = height[domino_position+3];
		end
		3'd3:begin
			h0 = height[domino_position];
			h1 = height[domino_position+1] + 'd2;
			h2 = 0;
			h3 = 0;
		end
		3'd4:begin
			h0 = height[domino_position]   + 'd1;
			h1 = height[domino_position+1];
			h2 = height[domino_position+2];
			h3 = 0;
		end
		3'd5:begin
			h0 = height[domino_position]   + 'd2;
			h1 = height[domino_position+1] + 'd2;
			h2 = 0;
			h3 = 0;
		end
		3'd6:begin
			h0 = height[domino_position]   + 'd1;
			h1 = height[domino_position+1] + 'd2;
			h2 = 0;
			h3 = 0;
		end
		3'd7:begin
			h0 = height[domino_position]   + 'd1;
			h1 = height[domino_position+1] + 'd1;
			h2 = height[domino_position+2];
			h3 = 0;
		end
		default:begin
			h0 = height[domino_position]  ;
			h1 = height[domino_position+1];
			h2 = height[domino_position+2];
			h3 = height[domino_position+3];
		end
	endcase
end

assign b1 = (h0 > h1) ? h0 : h1;
assign b2 = (h2 > h3) ? h2 : h3;

assign max_height_position = (b1 > b2) ? b1 : b2;
endmodule
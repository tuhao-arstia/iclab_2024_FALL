/**************************************************************************/
// Copyright (c) 2024, OASIS Lab
// MODULE: SA
// FILE NAME: SA_wocg.v
// VERSRION: 1.0
// DATE: Nov 06, 2024
// AUTHOR: Yen-Ning Tung, NYCU AIG
// CODE TYPE: RTL or Behavioral Level (Verilog)
// DESCRIPTION: 2024 Spring IC Lab / Exersise Lab08 / SA_wocg
// MODIFICATION HISTORY:
// Date                 Description
// 
/**************************************************************************/

module SA(
	// Input signals
	clk,
	rst_n,
	in_valid,
	T,
	in_data,
	w_Q,
	w_K,
	w_V,
	// Output signals
	out_valid,
	out_data
);

input clk;
input rst_n;
input in_valid;
input [3:0] T;
input signed [7:0] in_data;
input signed [7:0] w_Q;
input signed [7:0] w_K;
input signed [7:0] w_V;

output reg out_valid;
output reg signed [63:0] out_data;

//==============================================//
//       parameter & integer declaration        //
//==============================================//
parameter IDLE = 3'b000;
parameter IN_Q = 3'b001;
parameter IN_K = 3'b010;
parameter IN_V = 3'b011;
parameter  QKT = 3'b100;
parameter   XV = 3'b101;
parameter  OUT = 3'b111;
integer i, j;

//==============================================//
//           reg & wire declaration             //
//==============================================//
reg [2:0]	cs, ns;
reg [2:0]   cs_delay;
reg [3:0]	T_data;

reg [5:0]	cnt, ns_cnt;
// in_data split into [0],[1:3],[4:7] to control
reg signed [7:0]	X_data  	[0:7][0:7];

reg signed [7:0]	W_QV_data	[0:7][0:7];
reg signed [7:0]	W_K_data	[0:7][0:7];

reg signed [18:0]	Q			[0:7][0:7];
reg signed [18:0]	K			[0:7][0:7];
reg signed [18:0]	V			[0:7][0:7];

reg signed [40:0]	A			[0:7][0:7];
reg signed [61:0]	P;


//==============================================//
//                  design                      //
//==============================================//
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		cs <= IDLE;
	end else begin
		cs <= ns;
	end
end
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		cs_delay <= IDLE;
	end else begin
		cs_delay <= cs;
	end
end
always @(*) begin
	ns = cs;
	case (cs)
		IDLE:begin
			if(in_valid)begin
				ns = IN_Q;
			end
		end
		IN_Q:begin
			if(cnt == 'd63)begin
				ns = IN_K;
			end
		end
		IN_K:begin
			if(cnt == 'd63)begin
				ns = IN_V;
			end
		end
		IN_V:begin
			if(cnt == 'd63)begin
				ns = QKT;
			end
		end
		QKT:begin
			case (T_data)
				'd1:begin
					if(cnt == 'd0)begin
						ns = XV;
					end
				end
				'd4:begin
					if(cnt == 'd7)begin
						ns = XV;
					end
				end
				'd8:begin
					if(cnt == 'd31)begin
						ns = XV;
					end
				end
			endcase
		end
		XV:begin
			case (T_data)
				'd1:begin
					if(cnt == 'd3)begin
						ns = OUT;
					end
				end
				'd4:begin
					if(cnt == 'd15)begin
						ns = OUT;
					end
				end
				'd8:begin
					if(cnt == 'd31)begin
						ns = OUT;
					end
				end
			endcase
		end
		OUT:begin
			case (T_data)
				'd1:begin
					if(cnt == 'd7)begin
						ns = IDLE;
					end
				end 
				'd4:begin
					if(cnt == 'd31)begin
						ns = IDLE;
					end
				end
				'd8:begin
					if(cnt == 'd63)begin
						ns = IDLE;
					end
				end
			endcase
		end
	endcase
end

// Counter
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		cnt <= 0;
	end else begin
		cnt <= ns_cnt;
	end
end
always @(*) begin
	ns_cnt = 0;
	case (cs)
		IDLE:begin
			if(in_valid)begin
				ns_cnt = cnt + 'd1;
			end
		end 
		IN_Q:begin
			ns_cnt = cnt + 'd1;
		end
		IN_K:begin
			ns_cnt = cnt + 'd1;
		end
		IN_V:begin
			if(in_valid)begin
				ns_cnt = cnt + 'd1;
			end
		end
		QKT:begin
			case (T_data)
				'd1:begin
					ns_cnt = 'd0;
				end
				'd4:begin
					if(cnt != 'd7)begin
						ns_cnt = cnt + 'd1;
					end
				end
				'd8:begin
					if(cnt != 'd31)begin
						ns_cnt = cnt + 'd1;
					end
				end
			endcase
		end
		XV:begin
			case (T_data)
				'd1:begin
					if(cnt != 'd3)begin
						ns_cnt = cnt + 'd1;
					end
				end
				'd4:begin
					if(cnt != 'd15)begin
						ns_cnt = cnt + 'd1;
					end
				end
				'd8:begin
					if(cnt != 'd31)begin
						ns_cnt = cnt + 'd1;
					end
				end
			endcase
		end
		OUT:begin
			case (T_data)
				'd1:begin
					if(cnt != 'd7)begin
						ns_cnt = cnt + 'd1;
					end
				end
				'd4:begin
					if(cnt != 'd31)begin
						ns_cnt = cnt + 'd1;
					end
				end
				'd8:begin
					if(cnt != 'd63)begin
						ns_cnt = cnt + 'd1;
					end
				end
			endcase
		end
	endcase
end

// receive T
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		T_data <= 0;
	end else if(cs == IDLE && in_valid) begin
		T_data <= T;
	end
end

// receive in_data
// X_data 0th row
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 8; i = i + 1)begin
			X_data[0][i] <= 0;
		end
	end else begin
		case (cs)
			IDLE:begin
				if(in_valid)begin
					X_data[0][0] <= in_data;
				end else begin
					for(i = 1; i < 8; i = i + 1)begin
						X_data[0][i] <= 0;
					end
				end
			end
			IN_Q:begin
				for(i = 1; i < 8; i = i + 1)begin
					if(cnt == i)begin
						X_data[0][i] <= in_data;
					end
				end
			end
		endcase
	end
end
// X_data 1st row to 3rd row
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 8; i = i + 1)begin
			X_data[1][i] <= 0;
			X_data[2][i] <= 0;
			X_data[3][i] <= 0;
		end
	end else begin
		case (cs)
			IDLE:begin
				for(i = 0; i < 8; i = i + 1)begin
					X_data[1][i] <= 0;
					X_data[2][i] <= 0;
					X_data[3][i] <= 0;
				end
			end
			IN_Q:begin
				if(T_data == 'd4 || T_data == 'd8)begin
					for(i = 0; i < 8; i = i + 1)begin
						if(cnt == i + 8)begin
							X_data[1][i] <= in_data;
						end
						if(cnt == i + 16)begin
							X_data[2][i] <= in_data;
						end
						if(cnt == i + 24)begin
							X_data[3][i] <= in_data;
						end
					end
				end
			end
		endcase
	end
end
// X_data 4th row to 7th row
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 8; i = i + 1)begin
			X_data[4][i] <= 0;
			X_data[5][i] <= 0;
			X_data[6][i] <= 0;
			X_data[7][i] <= 0;
		end
	end else begin
		case (cs)
			IDLE:begin
				for(i = 0; i < 8; i = i + 1)begin
					X_data[4][i] <= 0;
					X_data[5][i] <= 0;
					X_data[6][i] <= 0;
					X_data[7][i] <= 0;
				end
			end
			IN_Q:begin
				if(T_data == 'd8)begin
					for(i = 0; i < 8; i = i + 1)begin
						if(cnt == i + 32)begin
							X_data[4][i] <= in_data;
						end
						if(cnt == i + 40)begin
							X_data[5][i] <= in_data;
						end
						if(cnt == i + 48)begin
							X_data[6][i] <= in_data;
						end
						if(cnt == i + 56)begin
							X_data[7][i] <= in_data;
						end
					end
				end
			end
		endcase
	end
end

// receive w_Q in in_Q state
// receibe w_V in in_V state 
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 8; i = i + 1)begin
			for(j = 0; j < 8; j = j + 1)begin
				W_QV_data[i][j] <= 0;
			end
		end
	end else begin
		case (cs)
			IDLE:begin
				if(in_valid)begin
					W_QV_data[0][0] <= w_Q;
				end
			end
			IN_Q:begin
				for(i = 0; i < 8; i = i + 1)begin
					for(j = 0; j < 8; j = j + 1)begin
						if(cnt == i * 8 + j)begin
							W_QV_data[i][j] <= w_Q;
						end
					end
				end
			end
			// gating during IN_K state(calculate XQ, cant gating?)  
			IN_V:begin
				for(i = 0; i < 8; i = i + 1)begin
					for(j = 0; j < 8; j = j + 1)begin
						if(cnt == i * 8 + j)begin
							W_QV_data[i][j] <= w_V;
						end
					end
				end
			end
		endcase
	end
end

// receive w_K in in_K state
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 8; i = i + 1)begin
			for(j = 0; j < 8; j = j + 1)begin
				W_K_data[i][j] <= 0;
			end
		end
	end else begin
		case (cs)
			IDLE:begin
				if(in_valid)begin
					W_K_data[0][0] <= w_K;
				end
			end
			// gating during IN_Q state if needed(receiving data)
			IN_K:begin
				for(i = 0; i < 8; i = i + 1)begin
					for(j = 0; j < 8; j = j + 1)begin
						if(cnt == i * 8 + j)begin
							W_K_data[i][j] <= w_K;
						end
					end
				end
			end
		endcase
	end
end

// dot product
reg [18:0]	row_s		[0:7];
reg [18:0]	col_s		[0:7];
reg [40:0]	ns_dp_out_s;
reg [39:0]	row_l		[0:7];
reg [18:0]	col_l		[0:7];
reg [61:0]	ns_dp_out_l;
dp_s SMALL(
	.r0(row_s[0]), .r1(row_s[1]), .r2(row_s[2]), .r3(row_s[3]), 
	.r4(row_s[4]), .r5(row_s[5]), .r6(row_s[6]), .r7(row_s[7]),
	.c0(col_s[0]), .c1(col_s[1]), .c2(col_s[2]), .c3(col_s[3]),
	.c4(col_s[4]), .c5(col_s[5]), .c6(col_s[6]), .c7(col_s[7]),
	.dp_out(ns_dp_out_s)
);
always @(*) begin
	for(i = 0; i < 8; i = i + 1)begin
		row_s[i] = 19'd0;
	end
	case (cs)
		IN_K, IN_V, XV:begin
			case (cnt)
				'd0, 'd1, 'd2, 'd3:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_s[i] = $signed(X_data[0][i]);
					end
				end
				'd4, 'd5, 'd6, 'd7:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_s[i] = $signed(X_data[1][i]);
					end
				end
				'd8, 'd9, 'd10, 'd11:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_s[i] = $signed(X_data[2][i]);
					end
				end
				'd12, 'd13, 'd14, 'd15:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_s[i] = $signed(X_data[3][i]);
					end
				end
				'd16, 'd17, 'd18, 'd19:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_s[i] = $signed(X_data[4][i]);
					end
				end
				'd20, 'd21, 'd22, 'd23:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_s[i] = $signed(X_data[5][i]);
					end
				end
				'd24, 'd25, 'd26, 'd27:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_s[i] = $signed(X_data[6][i]);
					end
				end
				'd28, 'd29, 'd30, 'd31:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_s[i] = $signed(X_data[7][i]);
					end
				end
			endcase
		end
		QKT:begin
			case (cnt)
				'd0, 'd1:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_s[i] = $signed(Q[0][i]);
					end
				end
				'd2, 'd3:begin
					if(T_data == 'd4)begin
						for(i = 0; i < 8; i = i + 1)begin
							row_s[i] = $signed(Q[1][i]);
						end
					end else if(T_data == 'd8)begin
						for(i = 0; i < 8; i = i + 1)begin
							row_s[i] = $signed(Q[0][i]);
						end
					end
				end
				'd4, 'd5:begin
					if(T_data == 'd4)begin
						for(i = 0; i < 8; i = i + 1)begin
							row_s[i] = $signed(Q[2][i]);
						end
					end else if(T_data == 'd8)begin
						for(i = 0; i < 8; i = i + 1)begin
							row_s[i] = $signed(Q[1][i]);
						end
					end
				end
				'd6, 'd7:begin
					if(T_data == 'd4)begin
						for(i = 0; i < 8; i = i + 1)begin
							row_s[i] = $signed(Q[3][i]);
						end
					end else if(T_data == 'd8)begin
						for(i = 0; i < 8; i = i + 1)begin
							row_s[i] = $signed(Q[1][i]);
						end
					end
				end
				'd8, 'd9, 'd10, 'd11:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_s[i] = $signed(Q[2][i]);
					end
				end
				'd12, 'd13, 'd14, 'd15:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_s[i] = $signed(Q[3][i]);
					end
				end
				'd16, 'd17, 'd18, 'd19:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_s[i] = $signed(Q[4][i]);
					end
				end
				'd20, 'd21, 'd22, 'd23:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_s[i] = $signed(Q[5][i]);
					end
				end
				'd24, 'd25, 'd26, 'd27:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_s[i] = $signed(Q[6][i]);
					end
				end
				'd28, 'd29, 'd30, 'd31:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_s[i] = $signed(Q[7][i]);
					end
				end
			endcase
		end
	endcase
end
always @(*) begin
	for(i = 0; i < 8; i = i + 1)begin
		col_s[i] = 19'd0;
	end
	case (cs)
		IN_K, XV:begin
			case (cnt)
				'd0, 'd4, 'd8, 'd12, 'd16, 'd20, 'd24, 'd28:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_s[i] = $signed(W_QV_data[i][0]);
					end
				end
				'd1, 'd5, 'd9, 'd13, 'd17, 'd21, 'd25, 'd29:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_s[i] = $signed(W_QV_data[i][2]);
					end
				end
				'd2, 'd6, 'd10, 'd14, 'd18, 'd22, 'd26, 'd30:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_s[i] = $signed(W_QV_data[i][4]);
					end
				end
				'd3, 'd7, 'd11, 'd15, 'd19, 'd23, 'd27, 'd31:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_s[i] = $signed(W_QV_data[i][6]);
					end
				end
			endcase
		end
		IN_V:begin
			case (cnt)
				'd0, 'd4, 'd8, 'd12, 'd16, 'd20, 'd24, 'd28:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_s[i] = $signed(W_K_data[i][0]);
					end
				end
				'd1, 'd5, 'd9, 'd13, 'd17, 'd21, 'd25, 'd29:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_s[i] = $signed(W_K_data[i][2]);
					end
				end
				'd2, 'd6, 'd10, 'd14, 'd18, 'd22, 'd26, 'd30:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_s[i] = $signed(W_K_data[i][4]);
					end
				end
				'd3, 'd7, 'd11, 'd15, 'd19, 'd23, 'd27, 'd31:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_s[i] = $signed(W_K_data[i][6]);
					end
				end
			endcase
		end
		QKT:begin
			case (cnt)
				'd0, 'd4, 'd8, 'd12, 'd16, 'd20, 'd24, 'd28:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_s[i] = $signed(K[0][i]);
					end
				end
				'd1, 'd5, 'd9, 'd13, 'd17, 'd21, 'd25, 'd29:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_s[i] = $signed(K[2][i]);
					end
				end
				'd2, 'd6:begin
					if(T_data == 'd4)begin
						for(i = 0; i < 8; i = i + 1)begin
							col_s[i] = $signed(K[0][i]);
						end
					end else if(T_data == 'd8)begin
						for(i = 0; i < 8; i = i + 1)begin
							col_s[i] = $signed(K[4][i]);
						end
					end
				end
				'd3, 'd7:begin
					if(T_data == 'd4)begin
						for(i = 0; i < 8; i = i + 1)begin
							col_s[i] = $signed(K[2][i]);
						end
					end else if(T_data == 'd8)begin
						for(i = 0; i < 8; i = i + 1)begin
							col_s[i] = $signed(K[6][i]);
						end
					end
				end
				'd10, 'd14, 'd18, 'd22, 'd26, 'd30:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_s[i] = $signed(K[4][i]);
					end
				end
				'd11, 'd15, 'd19, 'd23, 'd27, 'd31:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_s[i] = $signed(K[6][i]);
					end
				end
			endcase
		end
	endcase
end


dp_l LARGE(
	.r0(row_l[0]), .r1(row_l[1]), .r2(row_l[2]), .r3(row_l[3]),
	.r4(row_l[4]), .r5(row_l[5]), .r6(row_l[6]), .r7(row_l[7]),
	.c0(col_l[0]), .c1(col_l[1]), .c2(col_l[2]), .c3(col_l[3]),
	.c4(col_l[4]), .c5(col_l[5]), .c6(col_l[6]), .c7(col_l[7]),
	.dp_out(ns_dp_out_l)
);
always @(*) begin
	for(i = 0; i < 8; i = i + 1)begin
		row_l[i] = 40'd0;
	end

	case (cs)
		IN_K, IN_V, XV:begin
			case (cnt)
				'd0, 'd1, 'd2, 'd3:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(X_data[0][i]);
					end
				end
				'd4, 'd5, 'd6, 'd7:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(X_data[1][i]);
					end
				end
				'd8, 'd9, 'd10, 'd11:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(X_data[2][i]);
					end
				end
				'd12, 'd13, 'd14, 'd15:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(X_data[3][i]);
					end
				end
				'd16, 'd17, 'd18, 'd19:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(X_data[4][i]);
					end
				end
				'd20, 'd21, 'd22, 'd23:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(X_data[5][i]);
					end
				end
				'd24, 'd25, 'd26, 'd27:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(X_data[6][i]);
					end
				end
				'd28, 'd29, 'd30, 'd31:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(X_data[7][i]);
					end
				end
			endcase
		end
		QKT:begin
			case (cnt)
				'd0, 'd1:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(Q[0][i]);
					end
				end
				'd2, 'd3:begin
					if(T_data == 'd4)begin
						for(i = 0; i < 8; i = i + 1)begin
							row_l[i] = $signed(Q[1][i]);
						end
					end else if(T_data == 'd8)begin
						for(i = 0; i < 8; i = i + 1)begin
							row_l[i] = $signed(Q[0][i]);
						end
					end
				end
				'd4, 'd5:begin
					if(T_data == 'd4)begin
						for(i = 0; i < 8; i = i + 1)begin
							row_l[i] = $signed(Q[2][i]);
						end
					end else if(T_data == 'd8)begin
						for(i = 0; i < 8; i = i + 1)begin
							row_l[i] = $signed(Q[1][i]);
						end
					end
				end
				'd6, 'd7:begin
					if(T_data == 'd4)begin
						for(i = 0; i < 8; i = i + 1)begin
							row_l[i] = $signed(Q[3][i]);
						end
					end else if(T_data == 'd8)begin
						for(i = 0; i < 8; i = i + 1)begin
							row_l[i] = $signed(Q[1][i]);
						end
					end
				end
				'd8, 'd9, 'd10, 'd11:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(Q[2][i]);
					end
				end
				'd12, 'd13, 'd14, 'd15:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(Q[3][i]);
					end
				end
				'd16, 'd17, 'd18, 'd19:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(Q[4][i]);
					end
				end
				'd20, 'd21, 'd22, 'd23:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(Q[5][i]);
					end
				end
				'd24, 'd25, 'd26, 'd27:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(Q[6][i]);
					end
				end
				'd28, 'd29, 'd30, 'd31:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(Q[7][i]);
					end
				end
			endcase
		end
		OUT:begin
			case (cnt)
				'd0, 'd1, 'd2, 'd3, 'd4, 'd5, 'd6, 'd7:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(A[0][i]);
					end
				end
				'd8, 'd9, 'd10, 'd11, 'd12, 'd13, 'd14, 'd15:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(A[1][i]);
					end
				end
				'd16, 'd17, 'd18, 'd19, 'd20, 'd21, 'd22, 'd23:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(A[2][i]);
					end
				end
				'd24, 'd25, 'd26, 'd27, 'd28, 'd29, 'd30, 'd31:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(A[3][i]);
					end
				end
				'd32, 'd33, 'd34, 'd35, 'd36, 'd37, 'd38, 'd39:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(A[4][i]);
					end
				end
				'd40, 'd41, 'd42, 'd43, 'd44, 'd45, 'd46, 'd47:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(A[5][i]);
					end
				end
				'd48, 'd49, 'd50, 'd51, 'd52, 'd53, 'd54, 'd55:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(A[6][i]);
					end
				end
				'd56, 'd57, 'd58, 'd59, 'd60, 'd61, 'd62, 'd63:begin
					for(i = 0; i < 8; i = i + 1)begin
						row_l[i] = $signed(A[7][i]);
					end
				end
			endcase
		end
	endcase
end
always @(*) begin
	for(i = 0; i < 8; i = i + 1)begin
		col_l[i] = 19'd0;
	end

	case (cs)
		IN_K, XV:begin
			case (cnt)
				'd0, 'd4, 'd8, 'd12, 'd16, 'd20, 'd24, 'd28:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(W_QV_data[i][1]);
					end
				end
				'd1, 'd5, 'd9, 'd13, 'd17, 'd21, 'd25, 'd29:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(W_QV_data[i][3]);
					end
				end
				'd2, 'd6, 'd10, 'd14, 'd18, 'd22, 'd26, 'd30:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(W_QV_data[i][5]);
					end
				end
				'd3, 'd7, 'd11, 'd15, 'd19, 'd23, 'd27, 'd31:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(W_QV_data[i][7]);
					end
				end
			endcase
		end
		IN_V:begin
			case (cnt)
				'd0, 'd4, 'd8, 'd12, 'd16, 'd20, 'd24, 'd28:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(W_K_data[i][1]);
					end
				end
				'd1, 'd5, 'd9, 'd13, 'd17, 'd21, 'd25, 'd29:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(W_K_data[i][3]);
					end
				end
				'd2, 'd6, 'd10, 'd14, 'd18, 'd22, 'd26, 'd30:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(W_K_data[i][5]);
					end
				end
				'd3, 'd7, 'd11, 'd15, 'd19, 'd23, 'd27, 'd31:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(W_K_data[i][7]);
					end
				end
			endcase
		end
		QKT:begin
			case (cnt)
				'd0, 'd4, 'd8, 'd12, 'd16, 'd20, 'd24, 'd28:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(K[1][i]);
					end
				end
				'd1, 'd5, 'd9, 'd13, 'd17, 'd21, 'd25, 'd29:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(K[3][i]);
					end
				end
				'd2, 'd6:begin
					if(T_data == 'd4)begin
						for(i = 0; i < 8; i = i + 1)begin
							col_l[i] = $signed(K[1][i]);
						end
					end else if(T_data == 'd8)begin
						for(i = 0; i < 8; i = i + 1)begin
							col_l[i] = $signed(K[5][i]);
						end
					end
				end
				'd3, 'd7:begin
					if(T_data == 'd4)begin
						for(i = 0; i < 8; i = i + 1)begin
							col_l[i] = $signed(K[3][i]);
						end
					end else if(T_data == 'd8)begin
						for(i = 0; i < 8; i = i + 1)begin
							col_l[i] = $signed(K[7][i]);
						end
					end
				end
				'd10, 'd14, 'd18, 'd22, 'd26, 'd30:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(K[5][i]);
					end
				end
				'd11, 'd15, 'd19, 'd23, 'd27, 'd31:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(K[7][i]);
					end
				end
			endcase
		end
		OUT:begin
			case (cnt)
				'd0, 'd8, 'd16, 'd24, 'd32, 'd40, 'd48, 'd56:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(V[i][0]);
					end
				end
				'd1, 'd9, 'd17, 'd25, 'd33, 'd41, 'd49, 'd57:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(V[i][1]);
					end
				end
				'd2, 'd10, 'd18, 'd26, 'd34, 'd42, 'd50, 'd58:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(V[i][2]);
					end
				end
				'd3, 'd11, 'd19, 'd27, 'd35, 'd43, 'd51, 'd59:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(V[i][3]);
					end
				end
				'd4, 'd12, 'd20, 'd28, 'd36, 'd44, 'd52, 'd60:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(V[i][4]);
					end
				end
				'd5, 'd13, 'd21, 'd29, 'd37, 'd45, 'd53, 'd61:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(V[i][5]);
					end
				end
				'd6, 'd14, 'd22, 'd30, 'd38, 'd46, 'd54, 'd62:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(V[i][6]);
					end
				end
				'd7, 'd15, 'd23, 'd31, 'd39, 'd47, 'd55, 'd63:begin
					for(i = 0; i < 8; i = i + 1)begin
						col_l[i] = $signed(V[i][7]);
					end
				end
			endcase
		end
	endcase
end

// receive Q in in_K state
// Q row
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 8; i = i + 1)begin
			Q[0][i] <= 19'd0;
		end
	end else begin
		case (cs)
			IN_K:begin
				case (cnt)
					'd0:begin
						Q[0][0] <= $signed(ns_dp_out_s);
						Q[0][1] <= $signed(ns_dp_out_l[18:0]);
					end
					'd1:begin
						Q[0][2] <= $signed(ns_dp_out_s);
						Q[0][3] <= $signed(ns_dp_out_l[18:0]);
					end
					'd2:begin
						Q[0][4] <= $signed(ns_dp_out_s);
						Q[0][5] <= $signed(ns_dp_out_l[18:0]);
					end
					'd3:begin
						Q[0][6] <= $signed(ns_dp_out_s);
						Q[0][7] <= $signed(ns_dp_out_l[18:0]);
					end
				endcase
			end
		endcase
	end
end
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 8; i = i + 1)begin
			Q[1][i] <= 19'd0;
		end
	end else begin
		case (cs)
			IN_K:begin
				case (cnt)
					'd4:begin
						Q[1][0] <= $signed(ns_dp_out_s);
						Q[1][1] <= $signed(ns_dp_out_l[18:0]);
					end
					'd5:begin
						Q[1][2] <= $signed(ns_dp_out_s);
						Q[1][3] <= $signed(ns_dp_out_l[18:0]);
					end
					'd6:begin
						Q[1][4] <= $signed(ns_dp_out_s);
						Q[1][5] <= $signed(ns_dp_out_l[18:0]);
					end
					'd7:begin
						Q[1][6] <= $signed(ns_dp_out_s);
						Q[1][7] <= $signed(ns_dp_out_l[18:0]);
					end
				endcase
			end
		endcase
	end
end
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 8; i = i + 1)begin
			Q[2][i] <= 19'd0;
		end
	end else begin
		case (cs)
			IN_K:begin
				case (cnt)
					'd8:begin
						Q[2][0] <= $signed(ns_dp_out_s);
						Q[2][1] <= $signed(ns_dp_out_l[18:0]);
					end
					'd9:begin
						Q[2][2] <= $signed(ns_dp_out_s);
						Q[2][3] <= $signed(ns_dp_out_l[18:0]);
					end
					'd10:begin
						Q[2][4] <= $signed(ns_dp_out_s);
						Q[2][5] <= $signed(ns_dp_out_l[18:0]);
					end
					'd11:begin
						Q[2][6] <= $signed(ns_dp_out_s);
						Q[2][7] <= $signed(ns_dp_out_l[18:0]);
					end
				endcase
			end
		endcase
	end
end
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 8; i = i + 1)begin
			Q[3][i] <= 19'd0;
		end
	end else begin
		case (cs)
			IN_K:begin
				case (cnt)
					'd12:begin
						Q[3][0] <= $signed(ns_dp_out_s);
						Q[3][1] <= $signed(ns_dp_out_l[18:0]);
					end
					'd13:begin
						Q[3][2] <= $signed(ns_dp_out_s);
						Q[3][3] <= $signed(ns_dp_out_l[18:0]);
					end
					'd14:begin
						Q[3][4] <= $signed(ns_dp_out_s);
						Q[3][5] <= $signed(ns_dp_out_l[18:0]);
					end
					'd15:begin
						Q[3][6] <= $signed(ns_dp_out_s);
						Q[3][7] <= $signed(ns_dp_out_l[18:0]);
					end
				endcase
			end
		endcase
	end
end
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 8; i = i + 1)begin
			Q[4][i] <= 19'd0;
		end
	end else begin
		case (cs)
			IN_K:begin
				case (cnt)
					'd16:begin
						Q[4][0] <= $signed(ns_dp_out_s);
						Q[4][1] <= $signed(ns_dp_out_l[18:0]);
					end
					'd17:begin
						Q[4][2] <= $signed(ns_dp_out_s);
						Q[4][3] <= $signed(ns_dp_out_l[18:0]);
					end
					'd18:begin
						Q[4][4] <= $signed(ns_dp_out_s);
						Q[4][5] <= $signed(ns_dp_out_l[18:0]);
					end
					'd19:begin
						Q[4][6] <= $signed(ns_dp_out_s);
						Q[4][7] <= $signed(ns_dp_out_l[18:0]);
					end
				endcase
			end
		endcase
	end
end
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 8; i = i + 1)begin
			Q[5][i] <= 19'd0;
		end
	end else begin
		case (cs)
			IN_K:begin
				case (cnt)
					'd20:begin
						Q[5][0] <= $signed(ns_dp_out_s);
						Q[5][1] <= $signed(ns_dp_out_l[18:0]);
					end
					'd21:begin
						Q[5][2] <= $signed(ns_dp_out_s);
						Q[5][3] <= $signed(ns_dp_out_l[18:0]);
					end
					'd22:begin
						Q[5][4] <= $signed(ns_dp_out_s);
						Q[5][5] <= $signed(ns_dp_out_l[18:0]);
					end
					'd23:begin
						Q[5][6] <= $signed(ns_dp_out_s);
						Q[5][7] <= $signed(ns_dp_out_l[18:0]);
					end
				endcase
			end
		endcase
	end
end
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 8; i = i + 1)begin
			Q[6][i] <= 19'd0;
		end
	end else begin
		case (cs)
			IN_K:begin
				case (cnt)
					'd24:begin
						Q[6][0] <= $signed(ns_dp_out_s);
						Q[6][1] <= $signed(ns_dp_out_l[18:0]);
					end
					'd25:begin
						Q[6][2] <= $signed(ns_dp_out_s);
						Q[6][3] <= $signed(ns_dp_out_l[18:0]);
					end
					'd26:begin
						Q[6][4] <= $signed(ns_dp_out_s);
						Q[6][5] <= $signed(ns_dp_out_l[18:0]);
					end
					'd27:begin
						Q[6][6] <= $signed(ns_dp_out_s);
						Q[6][7] <= $signed(ns_dp_out_l[18:0]);
					end
				endcase
			end
		endcase
	end
end
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 8; i = i + 1)begin
			Q[7][i] <= 19'd0;
		end
	end else begin
		case (cs)
			IN_K:begin
				case (cnt)
					'd28:begin
						Q[7][0] <= $signed(ns_dp_out_s);
						Q[7][1] <= $signed(ns_dp_out_l[18:0]);
					end
					'd29:begin
						Q[7][2] <= $signed(ns_dp_out_s);
						Q[7][3] <= $signed(ns_dp_out_l[18:0]);
					end
					'd30:begin
						Q[7][4] <= $signed(ns_dp_out_s);
						Q[7][5] <= $signed(ns_dp_out_l[18:0]);
					end
					'd31:begin
						Q[7][6] <= $signed(ns_dp_out_s);
						Q[7][7] <= $signed(ns_dp_out_l[18:0]);
					end
				endcase
			end
		endcase
	end
end
// receive K in in_V state
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 8; i = i + 1)begin
			K[0][i] <= 19'd0;
		end
	end else begin
		case (cs)
			IN_V:begin
				case (cnt)
					'd0:begin
						K[0][0] <= $signed(ns_dp_out_s);
						K[0][1] <= $signed(ns_dp_out_l[18:0]);
					end
					'd1:begin
						K[0][2] <= $signed(ns_dp_out_s);
						K[0][3] <= $signed(ns_dp_out_l[18:0]);
					end
					'd2:begin
						K[0][4] <= $signed(ns_dp_out_s);
						K[0][5] <= $signed(ns_dp_out_l[18:0]);
					end
					'd3:begin
						K[0][6] <= $signed(ns_dp_out_s);
						K[0][7] <= $signed(ns_dp_out_l[18:0]);
					end
                endcase
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 8; i = i + 1)begin
            K[1][i] <= 19'd0;
        end
    end else begin
        case (cs)
            IN_V:begin
                case (cnt)
                    'd4:begin
                        K[1][0] <= $signed(ns_dp_out_s);
                        K[1][1] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd5:begin
                        K[1][2] <= $signed(ns_dp_out_s);
                        K[1][3] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd6:begin
                        K[1][4] <= $signed(ns_dp_out_s);
                        K[1][5] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd7:begin
                        K[1][6] <= $signed(ns_dp_out_s);
                        K[1][7] <= $signed(ns_dp_out_l[18:0]);
                    end
                endcase
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 8; i = i + 1)begin
            K[2][i] <= 19'd0;
        end
    end else begin
        case (cs)
            IN_V:begin
                case (cnt)
                    'd8:begin
                        K[2][0] <= $signed(ns_dp_out_s);
                        K[2][1] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd9:begin
                        K[2][2] <= $signed(ns_dp_out_s);
                        K[2][3] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd10:begin
                        K[2][4] <= $signed(ns_dp_out_s);
                        K[2][5] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd11:begin
                        K[2][6] <= $signed(ns_dp_out_s);
                        K[2][7] <= $signed(ns_dp_out_l[18:0]);
                    end
                endcase
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 8; i = i + 1)begin
            K[3][i] <= 19'd0;
        end
    end else begin
        case (cs)
            IN_V:begin
                case (cnt)
                    'd12:begin
                        K[3][0] <= $signed(ns_dp_out_s);
                        K[3][1] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd13:begin
                        K[3][2] <= $signed(ns_dp_out_s);
                        K[3][3] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd14:begin
                        K[3][4] <= $signed(ns_dp_out_s);
                        K[3][5] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd15:begin
                        K[3][6] <= $signed(ns_dp_out_s);
                        K[3][7] <= $signed(ns_dp_out_l[18:0]);
                    end
                endcase
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 8; i = i + 1)begin
            K[4][i] <= 19'd0;
        end
    end else begin
        case (cs)
            IN_V:begin
                case (cnt)
                    'd16:begin
                        K[4][0] <= $signed(ns_dp_out_s);
                        K[4][1] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd17:begin
                        K[4][2] <= $signed(ns_dp_out_s);
                        K[4][3] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd18:begin
                        K[4][4] <= $signed(ns_dp_out_s);
                        K[4][5] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd19:begin
                        K[4][6] <= $signed(ns_dp_out_s);
                        K[4][7] <= $signed(ns_dp_out_l[18:0]);
                    end
                endcase
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 8; i = i + 1)begin
            K[5][i] <= 19'd0;
        end
    end else begin
        case (cs)
            IN_V:begin
                case (cnt)
                    'd20:begin
                        K[5][0] <= $signed(ns_dp_out_s);
                        K[5][1] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd21:begin
                        K[5][2] <= $signed(ns_dp_out_s);
                        K[5][3] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd22:begin
                        K[5][4] <= $signed(ns_dp_out_s);
                        K[5][5] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd23:begin
                        K[5][6] <= $signed(ns_dp_out_s);
                        K[5][7] <= $signed(ns_dp_out_l[18:0]);
                    end
                endcase
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 8; i = i + 1)begin
            K[6][i] <= 19'd0;
        end
    end else begin
        case (cs)
            IN_V:begin
                case (cnt)
                    'd24:begin
                        K[6][0] <= $signed(ns_dp_out_s);
                        K[6][1] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd25:begin
                        K[6][2] <= $signed(ns_dp_out_s);
                        K[6][3] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd26:begin
                        K[6][4] <= $signed(ns_dp_out_s);
                        K[6][5] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd27:begin
                        K[6][6] <= $signed(ns_dp_out_s);
                        K[6][7] <= $signed(ns_dp_out_l[18:0]);
                    end
                endcase
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 8; i = i + 1)begin
            K[7][i] <= 19'd0;
        end
    end else begin
        case (cs)
            IN_V:begin
                case (cnt)
                    'd28:begin
                        K[7][0] <= $signed(ns_dp_out_s);
                        K[7][1] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd29:begin
                        K[7][2] <= $signed(ns_dp_out_s);
                        K[7][3] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd30:begin
                        K[7][4] <= $signed(ns_dp_out_s);
                        K[7][5] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd31:begin
                        K[7][6] <= $signed(ns_dp_out_s);
                        K[7][7] <= $signed(ns_dp_out_l[18:0]);
                    end
                endcase
            end
        endcase
    end
end

// QKT = A
wire signed [39:0] ns_relu_out_s, ns_relu_out_l;
div_relu R0(.in(ns_dp_out_s), .out(ns_relu_out_s));
div_relu R1(.in(ns_dp_out_l[40:0]), .out(ns_relu_out_l));
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		for(i = 0; i < 8; i = i + 1)begin
			for(j = 0; j < 8; j = j + 1)begin
				A[i][j] <= 41'd0;
			end
		end
	end else begin
		case (cs)
			QKT:begin
				case (cnt)
					'd0:begin
						A[0][0] <= ns_relu_out_s;
						if(T_data == 'd1)begin
							for(i = 1; i < 8; i = i + 1)begin
								A[0][i] <= 41'd0;
							end
							for(i = 1; i < 8; i = i + 1)begin
								for(j = 0; j < 8; j = j + 1)begin
									A[i][j] <= 41'd0;
								end
							end
						end else begin
							A[0][1] <= ns_relu_out_l;
						end
					end
					'd1:begin
						// reset 4*4 redudant data
						for(i = 0; i < 4; i = i + 1)begin
							for(j = 4; j < 8; j = j + 1)begin
								A[i][j] <= 41'd0;
							end
						end
						for(i = 4; i < 8; i = i + 1)begin
							for(j = 0; j < 8; j = j + 1)begin
								A[i][j] <= 41'd0;
							end
						end
						A[0][2] <= ns_relu_out_s;
						A[0][3] <= ns_relu_out_l;
					end
					'd2:begin
						if(T_data == 'd4)begin
							A[1][0] <= ns_relu_out_s;
							A[1][1] <= ns_relu_out_l;
						end else begin
							A[0][4] <= ns_relu_out_s;
							A[0][5] <= ns_relu_out_l;
						end
					end
					'd3:begin
						if(T_data == 'd4)begin
							A[1][2] <= ns_relu_out_s;
							A[1][3] <= ns_relu_out_l;
						end else begin
							A[0][6] <= ns_relu_out_s;
							A[0][7] <= ns_relu_out_l;
						end
					end
					'd4:begin
						if(T_data == 'd4)begin
							A[2][0] <= ns_relu_out_s;
							A[2][1] <= ns_relu_out_l;
						end else begin
							A[1][0] <= ns_relu_out_s;
							A[1][1] <= ns_relu_out_l;
						end
					end
					'd5:begin
						if(T_data == 'd4)begin
							A[2][2] <= ns_relu_out_s;
							A[2][3] <= ns_relu_out_l;
						end else begin
							A[1][2] <= ns_relu_out_s;
							A[1][3] <= ns_relu_out_l;
						end
					end
					'd6:begin
						if(T_data == 'd4)begin
							A[3][0] <= ns_relu_out_s;
							A[3][1] <= ns_relu_out_l;
						end else begin
							A[1][4] <= ns_relu_out_s;
							A[1][5] <= ns_relu_out_l;
						end
					end
					'd7:begin
						if(T_data == 'd4)begin
							A[3][2] <= ns_relu_out_s;
							A[3][3] <= ns_relu_out_l;
						end else begin
							A[1][6] <= ns_relu_out_s;
							A[1][7] <= ns_relu_out_l;
						end
					end
					'd8:begin
						A[2][0] <= ns_relu_out_s;
						A[2][1] <= ns_relu_out_l;
					end
					'd9:begin
						A[2][2] <= ns_relu_out_s;
						A[2][3] <= ns_relu_out_l;
					end
					'd10:begin
						A[2][4] <= ns_relu_out_s;
						A[2][5] <= ns_relu_out_l;
					end
					'd11:begin
						A[2][6] <= ns_relu_out_s;
						A[2][7] <= ns_relu_out_l;
					end
					'd12:begin
						A[3][0] <= ns_relu_out_s;
						A[3][1] <= ns_relu_out_l;
					end
					'd13:begin
						A[3][2] <= ns_relu_out_s;
						A[3][3] <= ns_relu_out_l;
					end
					'd14:begin
						A[3][4] <= ns_relu_out_s;
						A[3][5] <= ns_relu_out_l;
					end
					'd15:begin
						A[3][6] <= ns_relu_out_s;
						A[3][7] <= ns_relu_out_l;
					end
					'd16:begin
						A[4][0] <= ns_relu_out_s;
						A[4][1] <= ns_relu_out_l;
					end
					'd17:begin
						A[4][2] <= ns_relu_out_s;
						A[4][3] <= ns_relu_out_l;
					end
					'd18:begin
						A[4][4] <= ns_relu_out_s;
						A[4][5] <= ns_relu_out_l;
					end
					'd19:begin
						A[4][6] <= ns_relu_out_s;
						A[4][7] <= ns_relu_out_l;
					end
					'd20:begin
						A[5][0] <= ns_relu_out_s;
						A[5][1] <= ns_relu_out_l;
					end
					'd21:begin
						A[5][2] <= ns_relu_out_s;
						A[5][3] <= ns_relu_out_l;
					end
					'd22:begin
						A[5][4] <= ns_relu_out_s;
						A[5][5] <= ns_relu_out_l;
					end
					'd23:begin
						A[5][6] <= ns_relu_out_s;
						A[5][7] <= ns_relu_out_l;
					end
					'd24:begin
						A[6][0] <= ns_relu_out_s;
						A[6][1] <= ns_relu_out_l;
					end
					'd25:begin
						A[6][2] <= ns_relu_out_s;
						A[6][3] <= ns_relu_out_l;
					end
					'd26:begin
						A[6][4] <= ns_relu_out_s;
						A[6][5] <= ns_relu_out_l;
					end
					'd27:begin
						A[6][6] <= ns_relu_out_s;
						A[6][7] <= ns_relu_out_l;
					end
					'd28:begin
						A[7][0] <= ns_relu_out_s;
						A[7][1] <= ns_relu_out_l;
					end
					'd29:begin
						A[7][2] <= ns_relu_out_s;
						A[7][3] <= ns_relu_out_l;
					end
					'd30:begin
						A[7][4] <= ns_relu_out_s;
						A[7][5] <= ns_relu_out_l;
					end
					'd31:begin
						A[7][6] <= ns_relu_out_s;
						A[7][7] <= ns_relu_out_l;
					end
				endcase
			end
		endcase
	end
end

// XV
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 8; i = i + 1)begin
            V[0][i] <= 19'd0;
        end
    end else begin
        case (cs)
            XV:begin
                case (cnt)
                    'd0:begin
                        V[0][0] <= $signed(ns_dp_out_s);
                        V[0][1] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd1:begin
                        V[0][2] <= $signed(ns_dp_out_s);
                        V[0][3] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd2:begin
                        V[0][4] <= $signed(ns_dp_out_s);
                        V[0][5] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd3:begin
                        V[0][6] <= $signed(ns_dp_out_s);
                        V[0][7] <= $signed(ns_dp_out_l[18:0]);
                    end
                endcase
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 8; i = i + 1)begin
            V[1][i] <= 19'd0;
        end
    end else begin
        case (cs)
            XV:begin
                case (cnt)
                    'd4:begin
                        V[1][0] <= $signed(ns_dp_out_s);
                        V[1][1] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd5:begin
                        V[1][2] <= $signed(ns_dp_out_s);
                        V[1][3] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd6:begin
                        V[1][4] <= $signed(ns_dp_out_s);
                        V[1][5] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd7:begin
                        V[1][6] <= $signed(ns_dp_out_s);
                        V[1][7] <= $signed(ns_dp_out_l[18:0]);
                    end
                endcase
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 8; i = i + 1)begin
            V[2][i] <= 19'd0;
        end
    end else begin
        case (cs)
            XV:begin
                case (cnt)
                    'd8:begin
                        V[2][0] <= $signed(ns_dp_out_s);
                        V[2][1] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd9:begin
                        V[2][2] <= $signed(ns_dp_out_s);
                        V[2][3] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd10:begin
                        V[2][4] <= $signed(ns_dp_out_s);
                        V[2][5] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd11:begin
                        V[2][6] <= $signed(ns_dp_out_s);
                        V[2][7] <= $signed(ns_dp_out_l[18:0]);
                    end
                endcase
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 8; i = i + 1)begin
            V[3][i] <= 19'd0;
        end
    end else begin
        case (cs)
            XV:begin
                case (cnt)
                    'd12:begin
                        V[3][0] <= $signed(ns_dp_out_s);
                        V[3][1] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd13:begin
                        V[3][2] <= $signed(ns_dp_out_s);
                        V[3][3] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd14:begin
                        V[3][4] <= $signed(ns_dp_out_s);
                        V[3][5] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd15:begin
                        V[3][6] <= $signed(ns_dp_out_s);
                        V[3][7] <= $signed(ns_dp_out_l[18:0]);
                    end
                endcase
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 8; i = i + 1)begin
            V[4][i] <= 19'd0;
        end
    end else begin
        case (cs)
            XV:begin
                case (cnt)
                    'd16:begin
                        V[4][0] <= $signed(ns_dp_out_s);
                        V[4][1] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd17:begin
                        V[4][2] <= $signed(ns_dp_out_s);
                        V[4][3] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd18:begin
                        V[4][4] <= $signed(ns_dp_out_s);
                        V[4][5] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd19:begin
                        V[4][6] <= $signed(ns_dp_out_s);
                        V[4][7] <= $signed(ns_dp_out_l[18:0]);
                    end
                endcase
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 8; i = i + 1)begin
            V[5][i] <= 19'd0;
        end
    end else begin
        case (cs)
            XV:begin
                case (cnt)
                    'd20:begin
                        V[5][0] <= $signed(ns_dp_out_s);
                        V[5][1] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd21:begin
                        V[5][2] <= $signed(ns_dp_out_s);
                        V[5][3] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd22:begin
                        V[5][4] <= $signed(ns_dp_out_s);
                        V[5][5] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd23:begin
                        V[5][6] <= $signed(ns_dp_out_s);
                        V[5][7] <= $signed(ns_dp_out_l[18:0]);
                    end
                endcase
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 8; i = i + 1)begin
            V[6][i] <= 19'd0;
        end
    end else begin
        case (cs)
            XV:begin
                case (cnt)
                    'd24:begin
                        V[6][0] <= $signed(ns_dp_out_s);
                        V[6][1] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd25:begin
                        V[6][2] <= $signed(ns_dp_out_s);
                        V[6][3] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd26:begin
                        V[6][4] <= $signed(ns_dp_out_s);
                        V[6][5] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd27:begin
                        V[6][6] <= $signed(ns_dp_out_s);
                        V[6][7] <= $signed(ns_dp_out_l[18:0]);
                    end
                endcase
            end
        endcase
    end
end
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        for(i = 0; i < 8; i = i + 1)begin
            V[7][i] <= 19'd0;
        end
    end else begin
        case (cs)
            XV:begin
                case (cnt)
                    'd28:begin
                        V[7][0] <= $signed(ns_dp_out_s);
                        V[7][1] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd29:begin
                        V[7][2] <= $signed(ns_dp_out_s);
                        V[7][3] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd30:begin
                        V[7][4] <= $signed(ns_dp_out_s);
                        V[7][5] <= $signed(ns_dp_out_l[18:0]);
                    end
                    'd31:begin
                        V[7][6] <= $signed(ns_dp_out_s);
                        V[7][7] <= $signed(ns_dp_out_l[18:0]);
                    end
                endcase
            end
        endcase
    end
end

// output temp: P
always @(posedge clk or negedge rst_n) begin
	if(!rst_n)begin
		P <= 61'd0;
	end else begin
		case (cs)
			OUT:begin
				P <= ns_dp_out_l;
			end
		endcase
	end
end

// output
always @(*) begin
	if(cs_delay == OUT)begin
		out_valid = 1;
	end else begin
		out_valid = 0;
	end
end
always @(*) begin
	if(cs_delay == OUT)begin
		out_data = {{3{P[60]}}, P};
	end else begin
		out_data = 64'd0;
	end
end

endmodule



module dp_l(r0, r1, r2, r3, r4, r5, r6, r7, c0, c1, c2, c3, c4, c5, c6, c7, dp_out);
input  signed [39:0] r0, r1, r2, r3, r4, r5, r6, r7;
input  signed [18:0] c0, c1, c2, c3, c4, c5, c6, c7;
output signed [61:0] dp_out;

wire   signed [58:0] mult_0, mult_1, mult_2, mult_3, mult_4, mult_5, mult_6, mult_7;
wire   signed [59:0] add_0, add_1, add_2, add_3;
wire   signed [60:0] add_4, add_5;

assign mult_0 = $signed(r0) * $signed(c0);
assign mult_1 = $signed(r1) * $signed(c1);
assign mult_2 = $signed(r2) * $signed(c2);
assign mult_3 = $signed(r3) * $signed(c3);
assign mult_4 = $signed(r4) * $signed(c4);
assign mult_5 = $signed(r5) * $signed(c5);
assign mult_6 = $signed(r6) * $signed(c6);
assign mult_7 = $signed(r7) * $signed(c7);

assign add_0 = $signed(mult_0) + $signed(mult_1);
assign add_1 = $signed(mult_2) + $signed(mult_3);
assign add_2 = $signed(mult_4) + $signed(mult_5);
assign add_3 = $signed(mult_6) + $signed(mult_7);

assign add_4 = $signed(add_0) + $signed(add_1);
assign add_5 = $signed(add_2) + $signed(add_3);

assign dp_out = $signed(add_4) + $signed(add_5);
endmodule

module dp_s(r0, r1, r2, r3, r4, r5, r6, r7, c0, c1, c2, c3, c4, c5, c6, c7, dp_out);
input  signed [18:0] r0, r1, r2, r3, r4, r5, r6, r7;
input  signed [18:0] c0, c1, c2, c3, c4, c5, c6, c7;
output signed [40:0] dp_out;

wire   signed [37:0] mult_0, mult_1, mult_2, mult_3, mult_4, mult_5, mult_6, mult_7;
wire   signed [38:0] add_0, add_1, add_2, add_3;
wire   signed [39:0] add_4, add_5;

assign mult_0 = $signed(r0) * $signed(c0);
assign mult_1 = $signed(r1) * $signed(c1);
assign mult_2 = $signed(r2) * $signed(c2);
assign mult_3 = $signed(r3) * $signed(c3);
assign mult_4 = $signed(r4) * $signed(c4);
assign mult_5 = $signed(r5) * $signed(c5);
assign mult_6 = $signed(r6) * $signed(c6);
assign mult_7 = $signed(r7) * $signed(c7);

assign add_0 = $signed(mult_0) + $signed(mult_1);
assign add_1 = $signed(mult_2) + $signed(mult_3);
assign add_2 = $signed(mult_4) + $signed(mult_5);
assign add_3 = $signed(mult_6) + $signed(mult_7);

assign add_4 = $signed(add_0) + $signed(add_1);
assign add_5 = $signed(add_2) + $signed(add_3);

assign dp_out = $signed(add_4) + $signed(add_5);
endmodule

module div_relu(in, out);
input  signed [40:0] in;
output signed [39:0] out;

wire   signed [40:0] div_out;
wire   signed [39:0] div_truncate;


assign div_out = $signed(in[40:0])/3;
assign div_truncate = $signed(div_out[39:0]);
assign out = (div_truncate[39]) ? 40'd0 : {1'b0, div_truncate[38:0]};
endmodule
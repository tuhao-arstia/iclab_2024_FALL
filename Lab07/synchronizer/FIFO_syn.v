module FIFO_syn #(parameter WIDTH=8, parameter WORDS=64) (
    wclk,
    rclk,
    rst_n,
    winc,
    wdata,
    wfull,
    rinc,
    rdata,
    rempty,

    flag_fifo_to_clk2,
    flag_clk2_to_fifo,

    flag_fifo_to_clk1,
	flag_clk1_to_fifo
);

input wclk, rclk;
input rst_n;
input winc;
input [WIDTH-1:0] wdata;
output reg wfull;
input rinc;
output reg [WIDTH-1:0] rdata;
output reg rempty;

// You can change the input / output of the custom flag ports
output  flag_fifo_to_clk2;
input flag_clk2_to_fifo;

output flag_fifo_to_clk1;
input flag_clk1_to_fifo;

wire [WIDTH-1:0] rdata_q;

// Remember: 
//   wptr and rptr should be gray coded
//   Don't modify the signal name
reg [$clog2(WORDS):0] wptr;
reg [$clog2(WORDS):0] rptr;
//   Don't modify the signal name

wire wptr_increment, rptr_increment;

wire    [6:0]   rptr_q2;
wire    [6:0]   wptr_q2;

reg     [6:0]   wptr_bin;
wire    [6:0]   ns_wptr_bin;
wire    [6:0]   ns_wptr_gray;

reg     [6:0]   rptr_bin;
wire    [6:0]   ns_rptr_bin;
wire    [6:0]   ns_rptr_gray;

// sram
reg     [5:0]   wptr_sram_addr,rptr_sram_addr;
// delay for sram read
reg             rinc_delay;

// Synchronizers
NDFF_BUS_syn #(.WIDTH(7)) syn_wptr(.D(wptr), .Q(wptr_q2), .clk(rclk), .rst_n(rst_n));
NDFF_BUS_syn #(.WIDTH(7)) syn_rptr(.D(rptr), .Q(rptr_q2), .clk(wclk), .rst_n(rst_n));

// Write Control: binary code, gray code, wfull
assign wptr_increment = winc && ~wfull;
assign ns_wptr_bin = wptr_bin + wptr_increment;
assign ns_wptr_gray = bin2gray(ns_wptr_bin);

always @(posedge wclk or negedge rst_n) begin
    if(!rst_n)begin
        wptr <= 0;
        wptr_bin <= 0;
    end else begin
        // wptr is gray-coded
        wptr <= ns_wptr_gray;
        wptr_bin <= ns_wptr_bin;
    end
end
always @(posedge wclk or negedge rst_n) begin
    if(!rst_n)begin
        wfull <= 1'b0;
    end else begin
        // write full happens after write operation
        // if next write pointer equals synchronized read pointer "after write"
        if(ns_wptr_gray == {~rptr_q2[6], ~rptr_q2[5], rptr_q2[4:0]})begin
            wfull <= 1'b1;
        end else begin
            wfull <= 1'b0;
        end
    end
end

// Read Control: binary code, gray code, rempty, rinc_delay
assign rptr_increment = rinc && ~rempty;
assign ns_rptr_bin = rptr_bin + rptr_increment;
assign ns_rptr_gray = bin2gray(ns_rptr_bin);

always @(posedge rclk or negedge rst_n) begin
    if(!rst_n)begin
        rptr <= 0;
        rptr_bin <= 0;
    end else begin
        // rptr is gray-coded
        rptr <= ns_rptr_gray;
        rptr_bin <= ns_rptr_bin;
    end
end
always @(posedge rclk or negedge rst_n) begin
    if(!rst_n)begin
        //default is 1 because nothing writes in at first
        rempty <= 1'b1;
    end else begin
        // read empty happens after read operation
        // if next read pointer equals synchronized write pointer "after read"
        if(ns_rptr_gray == wptr_q2)begin
            rempty <= 1'b1;
        end else begin
            rempty <= 1'b0;
        end
    end
end
always @(posedge rclk or negedge rst_n) begin
    if(!rst_n)begin
        rinc_delay <= 0;
    end else begin
        rinc_delay <= rinc;
    end
end

// output: rdata
always @(posedge rclk) begin
    if(rinc || rinc_delay)begin
        rdata <= rdata_q;
    end else begin
        rdata <= rdata;
    end
end

// SRAM setting: A for write, B for read
always @(*) begin
    wptr_sram_addr = wptr_bin[5:0];
    rptr_sram_addr = rptr_bin[5:0];
end
DUAL_64X8X1BM1 mem(.A0(wptr_sram_addr[0]),  .A1(wptr_sram_addr[1]),  .A2(wptr_sram_addr[2]),  
                   .A3(wptr_sram_addr[3]),  .A4(wptr_sram_addr[4]),  .A5(wptr_sram_addr[5]),
                   .B0(rptr_sram_addr[0]),  .B1(rptr_sram_addr[1]),  .B2(rptr_sram_addr[2]),  
                   .B3(rptr_sram_addr[3]),  .B4(rptr_sram_addr[4]),  .B5(rptr_sram_addr[5]),
                   .DOA0(),.DOA1(),.DOA2(),.DOA3(),
                   .DOA4(),.DOA5(),.DOA6(),.DOA7(),
                   .DOB0(rdata_q[0]),.DOB1(rdata_q[1]),.DOB2(rdata_q[2]),.DOB3(rdata_q[3]),
                   .DOB4(rdata_q[4]),.DOB5(rdata_q[5]),.DOB6(rdata_q[6]),.DOB7(rdata_q[7]),
                   .DIA0(wdata[0]),.DIA1(wdata[1]),.DIA2(wdata[2]),.DIA3(wdata[3]),
                   .DIA4(wdata[4]),.DIA5(wdata[5]),.DIA6(wdata[6]),.DIA7(wdata[7]),
                   .DIB0(),.DIB1(),.DIB2(),.DIB3(),
                   .DIB4(),.DIB5(),.DIB6(),.DIB7(),
                   .WEAN(~winc),.WEBN(1'b1),
                   .CKA(wclk)  , .CKB(rclk),
                   .CSA(1'b1)  , .CSB(1'b1),
                   .OEA(1'b1)  , .OEB(1'b1));

function [6:0] bin2gray;
    input[6:0] binary;
    begin
        bin2gray = binary ^ (binary >> 1);
    end
endfunction

endmodule

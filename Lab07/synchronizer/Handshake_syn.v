module Handshake_syn #(parameter WIDTH=8) (
    sclk,
    dclk,
    rst_n,
    sready,
    din,
    dbusy,
    sidle,
    dvalid,
    dout,

    flag_handshake_to_clk1,
    flag_clk1_to_handshake,

    flag_handshake_to_clk2,
    flag_clk2_to_handshake 
);

input sclk, dclk;
input rst_n;
input sready;
input [WIDTH-1:0] din;
input dbusy;
output sidle;
output reg dvalid;
output reg [WIDTH-1:0] dout;

// You can change the input / output of the custom flag ports
output reg flag_handshake_to_clk1;
input flag_clk1_to_handshake;

output flag_handshake_to_clk2;
input flag_clk2_to_handshake;

// Remember:
//   Don't modify the signal name
reg sreq;
wire dreq;
reg dack;
wire sack;
//   Don't modify the signal name

// My Handshake Design
localparam IDLE = 2'b00;
localparam SEND = 2'b01;
localparam WAIT = 2'b10;
localparam  OUT = 2'b11;

reg [1:0]       src_cs, dst_cs;
reg [WIDTH-1:0] src_data, dst_data;

// Synchronizer
NDFF_syn SRC(.D(sreq), .Q(dreq), .clk(dclk), .rst_n(rst_n));
NDFF_syn DST(.D(dack), .Q(sack), .clk(sclk), .rst_n(rst_n));

// Source Control: src_cs, sreq, src_data
always @(posedge sclk or negedge rst_n) begin
    if(!rst_n)begin
        src_cs <= IDLE;
    end else begin
        case (src_cs)
            IDLE:begin
                // master and slave signals are put together to "handshake"
                if(sready && ~sreq)begin
                    src_cs <= SEND;
                end else begin
                    src_cs <= IDLE;
                end
            end
            SEND:begin
                // 3 cycle principle
                if(sreq && sack)begin
                    src_cs <= WAIT;
                end else begin
                    src_cs <= SEND;
                end
            end
            WAIT:begin
                if(~sreq && ~sack)begin
                    src_cs <= IDLE;
                end else begin
                    src_cs <= WAIT;
                end
            end
        endcase
    end
end
always @(posedge sclk or negedge rst_n) begin
    if(!rst_n)begin
        sreq <= 0;
    end else begin
        case (src_cs)
            IDLE:begin
                if(sready && ~sreq)begin
                    sreq <= 1;
                end else begin
                    sreq <= 0;
                end
            end 
            SEND:begin
                if(sreq && sack)begin
                    sreq <= 0;
                end else begin
                    sreq <= 1;
                end
            end
        endcase
    end
end
always @(posedge sclk or negedge rst_n) begin
    if(!rst_n)begin
        src_data <= 0;
    end else begin
        case (src_cs)
            IDLE:begin
                src_data <= din;
            end
        endcase
    end
end

// Destination Control: dst_cs, dack, dst_data
always @(posedge dclk or negedge rst_n) begin
    if(!rst_n)begin
        dst_cs <= IDLE;
    end else begin
        case (dst_cs)
            IDLE:begin
                if(~dbusy && dreq)begin
                    dst_cs <= SEND;
                end else begin
                    dst_cs <= IDLE;
                end
            end
            SEND:begin
                // src_cs enter WAIT state: sreq to 0, we are waiting dreq becomes 0
                if(~dreq && dack)begin
                    dst_cs <= OUT;
                end else begin
                    dst_cs <= SEND;
                end
            end
            OUT:begin
                dst_cs <= IDLE;
            end
        endcase
    end
end
always @(posedge dclk or negedge rst_n) begin
    if(!rst_n)begin
        dack <= 0;
    end else begin
        case (dst_cs)
            IDLE:begin
                if(~dbusy && dreq)begin
                    // source request: sreq to 1, dreq becomes 1
                    dack <= 1;
                end else begin
                    dack <= 0;
                end
            end 
            SEND:begin
                if(~dreq && dack)begin
                    dack <= 0;
                end else begin
                    dack <= 1;
                end
            end
        endcase
    end
end
always @(posedge dclk or negedge rst_n) begin
    if(!rst_n)begin
        dst_data <= 0;
    end else begin
        case (dst_cs)
            SEND:begin
                if(~dreq && dack)begin
                    // handshaked => recieve the data from source
                    dst_data <= src_data;
                end else begin
                    dst_data <= dst_data;
                end
            end
        endcase
    end 
end

// output for dvalid and dout
always @(posedge dclk or negedge rst_n) begin
    if(!rst_n)begin
        dvalid <= 0;
        dout <= 0;
    end else begin
        case (dst_cs)
            IDLE:begin
                dvalid <= 0;
                dout <= 0;
            end
            OUT:begin
                dvalid <= 1;
                dout <= dst_data;
            end
        endcase
    end
end

// output for sidle
assign sidle = (src_cs == IDLE);

endmodule
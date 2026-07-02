`timescale 1ns/1ps

module int8_mac_pe (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              clk_en,
    input  wire              clear,
    input  wire              valid_in,
    input  wire signed [7:0] a_in,
    input  wire signed [7:0] b_in,
    output reg               valid_out,
    output reg  signed [7:0] a_out,
    output reg  signed [7:0] b_out,
    output reg  signed [31:0] acc
);
    wire signed [15:0] product = a_in * b_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            a_out     <= 8'sd0;
            b_out     <= 8'sd0;
            acc       <= 32'sd0;
        end else if (clk_en) begin
            valid_out <= valid_in;
            a_out     <= a_in;
            b_out     <= b_in;

            if (clear) begin
                acc <= 32'sd0;
            end else if (valid_in) begin
                acc <= acc + {{16{product[15]}}, product};
            end
        end
    end
endmodule

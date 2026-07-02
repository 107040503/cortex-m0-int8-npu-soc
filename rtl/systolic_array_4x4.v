`timescale 1ns/1ps

module systolic_array_4x4 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         clk_en,
    input  wire         clear,
    input  wire         valid_in,
    input  wire [31:0]  a_west,
    input  wire [31:0]  b_north,
    output wire [511:0] acc_flat
);
    wire signed [7:0]  a_bus [0:3][0:4];
    wire signed [7:0]  b_bus [0:4][0:3];
    wire               v_bus [0:3][0:4];
    wire signed [31:0] acc_bus [0:3][0:3];

    genvar r;
    genvar c;

    generate
        for (r = 0; r < 4; r = r + 1) begin : gen_west
            assign a_bus[r][0] = a_west[r*8 +: 8];
            assign v_bus[r][0] = valid_in;
        end

        for (c = 0; c < 4; c = c + 1) begin : gen_north
            assign b_bus[0][c] = b_north[c*8 +: 8];
        end

        for (r = 0; r < 4; r = r + 1) begin : gen_rows
            for (c = 0; c < 4; c = c + 1) begin : gen_cols
                int8_mac_pe u_pe (
                    .clk       (clk),
                    .rst_n     (rst_n),
                    .clk_en    (clk_en),
                    .clear     (clear),
                    .valid_in  (v_bus[r][c]),
                    .a_in      (a_bus[r][c]),
                    .b_in      (b_bus[r][c]),
                    .valid_out (v_bus[r][c+1]),
                    .a_out     (a_bus[r][c+1]),
                    .b_out     (b_bus[r+1][c]),
                    .acc       (acc_bus[r][c])
                );

                assign acc_flat[(r*4+c)*32 +: 32] = acc_bus[r][c];
            end
        end
    endgenerate
endmodule

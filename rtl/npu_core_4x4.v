`timescale 1ns/1ps

module npu_core_4x4 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [1:0]   dfs_divider,
    input  wire [127:0] a_matrix,
    input  wire [127:0] b_matrix,
    input  wire [15:0]  pe_mask,
    output reg          busy,
    output reg          done,
    output wire         array_clk_en,
    output reg  [8:0]   active_cycles,
    output reg  [8:0]   dfs_wait_cycles,
    output reg  [511:0] c_matrix
);
    localparam ST_IDLE  = 2'd0;
    localparam ST_CLEAR = 2'd1;
    localparam ST_RUN   = 2'd2;
    localparam ST_DONE  = 2'd3;

    reg [1:0] state;
    reg [3:0] cycle_count;
    reg [1:0] dfs_count;
    reg       array_clear;
    reg       array_valid;
    reg [31:0] a_west;
    reg [31:0] b_north;

    wire [511:0] raw_acc;
    wire [511:0] masked_acc;
    wire active_state = (state == ST_CLEAR) || (state == ST_RUN);
    wire dfs_tick = active_state && (dfs_count == 2'd0);

    assign array_clk_en = dfs_tick;

    genvar mr;
    genvar mc;
    generate
        for (mr = 0; mr < 4; mr = mr + 1) begin : gen_mask_rows
            for (mc = 0; mc < 4; mc = mc + 1) begin : gen_mask_cols
                assign masked_acc[(mr*4+mc)*32 +: 32] =
                    pe_mask[mr*4+mc] ? raw_acc[(mr*4+mc)*32 +: 32] : 32'd0;
            end
        end
    endgenerate

    systolic_array_4x4 u_array (
        .clk      (clk),
        .rst_n    (rst_n),
        .clk_en   (array_clk_en),
        .clear    (array_clear),
        .valid_in (array_valid),
        .a_west   (a_west),
        .b_north  (b_north),
        .acc_flat (raw_acc)
    );

    integer i;
    integer kidx;
    always @(*) begin
        a_west = 32'd0;
        b_north = 32'd0;

        for (i = 0; i < 4; i = i + 1) begin
            kidx = cycle_count - i;
            if (kidx >= 0 && kidx < 4) begin
                a_west[i*8 +: 8] = a_matrix[(i*4+kidx)*8 +: 8];
                b_north[i*8 +: 8] = b_matrix[(kidx*4+i)*8 +: 8];
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dfs_count <= 2'd0;
        end else if (active_state) begin
            if (dfs_count == dfs_divider) begin
                dfs_count <= 2'd0;
            end else begin
                dfs_count <= dfs_count + 2'd1;
            end
        end else begin
            dfs_count <= 2'd0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            cycle_count   <= 4'd0;
            array_clear   <= 1'b0;
            array_valid   <= 1'b0;
            busy          <= 1'b0;
            done          <= 1'b0;
            active_cycles <= 9'd0;
            dfs_wait_cycles <= 9'd0;
            c_matrix      <= 512'd0;
        end else begin
            done <= 1'b0;
            if (active_state && !dfs_tick) begin
                dfs_wait_cycles <= dfs_wait_cycles + 9'd1;
            end

            case (state)
                ST_IDLE: begin
                    busy          <= 1'b0;
                    array_clear   <= 1'b0;
                    array_valid   <= 1'b0;
                    cycle_count   <= 4'd0;

                    if (start) begin
                        busy          <= 1'b1;
                        array_clear   <= 1'b1;
                        active_cycles <= 9'd0;
                        dfs_wait_cycles <= 9'd0;
                        state         <= ST_CLEAR;
                    end
                end

                ST_CLEAR: begin
                    busy <= 1'b1;
                    if (dfs_tick) begin
                        array_clear   <= 1'b0;
                        array_valid   <= 1'b1;
                        cycle_count   <= 4'd0;
                        active_cycles <= active_cycles + 9'd1;
                        state         <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    busy          <= 1'b1;
                    if (dfs_tick) begin
                        array_valid   <= 1'b1;
                        active_cycles <= active_cycles + 9'd1;

                        if (cycle_count == 4'd9) begin
                            array_valid <= 1'b0;
                            state       <= ST_DONE;
                        end else begin
                            cycle_count <= cycle_count + 4'd1;
                        end
                    end
                end

                ST_DONE: begin
                    busy     <= 1'b0;
                    done     <= 1'b1;
                    c_matrix <= masked_acc;
                    state    <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule

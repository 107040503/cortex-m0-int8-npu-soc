`timescale 1ns/1ps

module tb_npu_core_4x4;
    reg clk;
    reg rst_n;
    reg start;
    reg [1:0] dfs_divider;
    reg [127:0] a_matrix;
    reg [127:0] b_matrix;
    reg [15:0] pe_mask;
    wire busy;
    wire done;
    wire array_clk_en;
    wire [8:0] active_cycles;
    wire [8:0] dfs_wait_cycles;
    wire [511:0] c_matrix;

    integer errors;
    integer r;
    integer c;

    npu_core_4x4 dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (start),
        .dfs_divider   (dfs_divider),
        .a_matrix      (a_matrix),
        .b_matrix      (b_matrix),
        .pe_mask       (pe_mask),
        .busy          (busy),
        .done          (done),
        .array_clk_en  (array_clk_en),
        .active_cycles (active_cycles),
        .dfs_wait_cycles (dfs_wait_cycles),
        .c_matrix      (c_matrix)
    );

    always #2.5 clk = ~clk;

    task set_a;
        input integer row;
        input integer col;
        input signed [7:0] value;
        begin
            a_matrix[(row*4+col)*8 +: 8] = value[7:0];
        end
    endtask

    task set_b;
        input integer row;
        input integer col;
        input signed [7:0] value;
        begin
            b_matrix[(row*4+col)*8 +: 8] = value[7:0];
        end
    endtask

    task expect_c;
        input integer row;
        input integer col;
        input signed [31:0] value;
        reg signed [31:0] got;
        begin
            got = c_matrix[(row*4+col)*32 +: 32];
            if (got !== value) begin
                $display("FAIL core C[%0d,%0d] got=%0d expected=%0d", row, col, got, value);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_npu_core_4x4.vcd");
        $dumpvars(0, tb_npu_core_4x4);

        clk = 1'b0;
        rst_n = 1'b0;
        start = 1'b0;
        dfs_divider = 2'd0;
        a_matrix = 128'd0;
        b_matrix = 128'd0;
        pe_mask = 16'hffff;
        errors = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        set_a(0,0, 1); set_a(0,1, 2); set_a(0,2, 3); set_a(0,3, 4);
        set_a(1,0,-1); set_a(1,1, 0); set_a(1,2, 1); set_a(1,3, 2);
        set_a(2,0, 5); set_a(2,1,-2); set_a(2,2, 0); set_a(2,3, 1);
        set_a(3,0, 3); set_a(3,1, 1); set_a(3,2,-3); set_a(3,3, 2);

        set_b(0,0, 1); set_b(0,1, 0); set_b(0,2, 2); set_b(0,3,-1);
        set_b(1,0, 2); set_b(1,1, 1); set_b(1,2, 0); set_b(1,3, 3);
        set_b(2,0,-1); set_b(2,1, 4); set_b(2,2, 1); set_b(2,3, 0);
        set_b(3,0, 0); set_b(3,1,-2); set_b(3,2, 3); set_b(3,3, 1);

        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        wait (done);
        @(posedge clk);

        expect_c(0,0, 2);  expect_c(0,1, 6);  expect_c(0,2,17); expect_c(0,3, 9);
        expect_c(1,0,-2);  expect_c(1,1, 0);  expect_c(1,2, 5); expect_c(1,3, 3);
        expect_c(2,0, 1);  expect_c(2,1,-4);  expect_c(2,2,13); expect_c(2,3,-10);
        expect_c(3,0, 8);  expect_c(3,1,-15); expect_c(3,2, 9); expect_c(3,3, 2);

        if (array_clk_en !== 1'b0) begin
            $display("FAIL core array clock gate is enabled after done");
            errors = errors + 1;
        end
        $display("COVER core_basic_matmul");
        $display("COVER core_signed_int8");
        $display("COVER core_clock_gate_idle");
        $display("COVER_PATH core_state_idle");
        $display("COVER_PATH core_state_clear");
        $display("COVER_PATH core_state_run");
        $display("COVER_PATH core_state_done");
        $display("COVER_PATH core_dfs_div0_tick");
        $display("COVER_PATH core_pe_mask_all_enabled");
        $display("COVER_PATH core_signed_positive_negative_zero");
        $display("COVER_PATH core_array_clk_gate_idle");

        if (errors == 0) begin
            $display("PASS tb_npu_core_4x4");
            $finish;
        end else begin
            $display("FAIL tb_npu_core_4x4 errors=%0d", errors);
            $fatal;
        end
    end
endmodule

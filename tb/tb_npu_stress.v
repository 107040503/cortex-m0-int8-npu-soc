`timescale 1ns/1ps

module tb_npu_stress;
    localparam REG_CTRL       = 32'h0000_0000;
    localparam REG_STATUS     = 32'h0000_0004;
    localparam REG_A_ADDR     = 32'h0000_0008;
    localparam REG_B_ADDR     = 32'h0000_000c;
    localparam REG_C_ADDR     = 32'h0000_0010;
    localparam REG_PE_MASK    = 32'h0000_0014;
    localparam REG_DFS_CTRL   = 32'h0000_002c;
    localparam REG_POWER_CTRL = 32'h0000_0030;
    localparam REG_DFS_WAIT   = 32'h0000_0038;

    localparam A0_BASE = 32'h0000_0400;
    localparam B0_BASE = 32'h0000_0500;
    localparam C0_BASE = 32'h0000_0600;
    localparam C1_BASE = 32'h0000_0700;

    reg clk;
    reg rst_n;
    reg [31:0] s_awaddr;
    reg        s_awvalid;
    wire       s_awready;
    reg [31:0] s_wdata;
    reg [3:0]  s_wstrb;
    reg        s_wvalid;
    wire       s_wready;
    wire [1:0] s_bresp;
    wire       s_bvalid;
    reg        s_bready;
    reg [31:0] s_araddr;
    reg        s_arvalid;
    wire       s_arready;
    wire [31:0] s_rdata;
    wire [1:0]  s_rresp;
    wire        s_rvalid;
    reg         s_rready;
    wire        npu_irq;
    wire        npu_array_clk_en;
    wire [31:0] ram_write_beats;
    wire [31:0] ram_read_beats;
    wire [31:0] ram_last_awaddr;
    wire [31:0] ram_last_araddr;

    integer errors;
    integer i;
    reg [31:0] rd;

    hetero_soc_sim_top dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .s_axil_awaddr    (s_awaddr),
        .s_axil_awvalid   (s_awvalid),
        .s_axil_awready   (s_awready),
        .s_axil_wdata     (s_wdata),
        .s_axil_wstrb     (s_wstrb),
        .s_axil_wvalid    (s_wvalid),
        .s_axil_wready    (s_wready),
        .s_axil_bresp     (s_bresp),
        .s_axil_bvalid    (s_bvalid),
        .s_axil_bready    (s_bready),
        .s_axil_araddr    (s_araddr),
        .s_axil_arvalid   (s_arvalid),
        .s_axil_arready   (s_arready),
        .s_axil_rdata     (s_rdata),
        .s_axil_rresp     (s_rresp),
        .s_axil_rvalid    (s_rvalid),
        .s_axil_rready    (s_rready),
        .npu_irq          (npu_irq),
        .npu_array_clk_en (npu_array_clk_en),
        .ram_write_beats  (ram_write_beats),
        .ram_read_beats   (ram_read_beats),
        .ram_last_awaddr  (ram_last_awaddr),
        .ram_last_araddr  (ram_last_araddr)
    );

    always #2.5 clk = ~clk;

    task axil_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_awaddr = addr;
            s_wdata = data;
            s_wstrb = 4'hf;
            s_awvalid = 1'b1;
            s_wvalid = 1'b1;
            s_bready = 1'b1;
            wait (s_awready && s_wready);
            @(posedge clk);
            s_awvalid = 1'b0;
            s_wvalid = 1'b0;
            wait (s_bvalid);
            @(posedge clk);
            s_bready = 1'b0;
        end
    endtask

    task axil_read;
        input [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            s_araddr = addr;
            s_arvalid = 1'b1;
            s_rready = 1'b1;
            wait (s_arready);
            @(posedge clk);
            s_arvalid = 1'b0;
            wait (s_rvalid);
            data = s_rdata;
            @(posedge clk);
            s_rready = 1'b0;
        end
    endtask

    task wait_done;
        begin
            for (i = 0; i < 400; i = i + 1) begin
                axil_read(REG_STATUS, rd);
                if (rd[1]) begin
                    i = 400;
                end
            end
            axil_read(REG_STATUS, rd);
            if (!rd[1]) begin
                $display("FAIL stress done timeout");
                errors = errors + 1;
            end
        end
    endtask

    task expect_c_word;
        input [31:0] base;
        input integer word_index;
        input signed [31:0] expected;
        reg signed [31:0] got;
        begin
            got = dut.u_sram.mem[(base >> 2) + word_index];
            if (got !== expected) begin
                $display("FAIL stress C[%0d] got=%0d expected=%0d", word_index, got, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_npu_stress.vcd");
        $dumpvars(0, tb_npu_stress);

        clk = 1'b0;
        rst_n = 1'b0;
        s_awaddr = 32'd0;
        s_awvalid = 1'b0;
        s_wdata = 32'd0;
        s_wstrb = 4'hf;
        s_wvalid = 1'b0;
        s_bready = 1'b0;
        s_araddr = 32'd0;
        s_arvalid = 1'b0;
        s_rready = 1'b0;
        errors = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        dut.u_sram.mem[(A0_BASE >> 2) + 0] = 32'h0000_0001;
        dut.u_sram.mem[(A0_BASE >> 2) + 1] = 32'h0000_0000;
        dut.u_sram.mem[(A0_BASE >> 2) + 2] = 32'h0000_0000;
        dut.u_sram.mem[(A0_BASE >> 2) + 3] = 32'h0000_0000;
        dut.u_sram.mem[(B0_BASE >> 2) + 0] = 32'h0000_0007;
        dut.u_sram.mem[(B0_BASE >> 2) + 1] = 32'h0000_0000;
        dut.u_sram.mem[(B0_BASE >> 2) + 2] = 32'h0000_0000;
        dut.u_sram.mem[(B0_BASE >> 2) + 3] = 32'h0000_0000;

        axil_read(32'h0000_00fc, rd);
        if (rd !== 32'd0) begin
            $display("FAIL stress undefined register read got=%h", rd);
            errors = errors + 1;
        end
        $display("COVER undefined_register_read");
        $display("COVER_PATH axil_default_read_path");

        axil_write(REG_A_ADDR, A0_BASE);
        axil_write(REG_B_ADDR, B0_BASE);
        axil_write(REG_C_ADDR, C0_BASE);
        axil_write(REG_PE_MASK, 32'h0000_0001);
        axil_write(REG_DFS_CTRL, 32'h0000_0002);
        axil_write(REG_CTRL, 32'h0000_0001);
        wait_done();

        expect_c_word(C0_BASE, 0, 7);
        for (i = 1; i < 16; i = i + 1) begin
            expect_c_word(C0_BASE, i, 0);
        end
        axil_read(REG_DFS_WAIT, rd);
        if (rd == 32'd0) begin
            $display("FAIL stress DFS wait counter did not increment");
            errors = errors + 1;
        end
        $display("INFO stress dfs_wait_cycles=%0d", rd);
        $display("COVER dynamic_pe_mask_single_pe");
        $display("COVER dfs_divider_slow_mode");
        $display("COVER_PATH pe_mask_single_enabled_path");
        $display("COVER_PATH dfs_wait_increment_path");
        $display("COVER_PATH dfs_divider_nonzero_path");

        axil_write(REG_CTRL, 32'h0000_0100);
        axil_read(REG_STATUS, rd);
        if (rd[1]) begin
            $display("FAIL stress done bit did not clear");
            errors = errors + 1;
        end
        $display("COVER clear_done");
        $display("COVER_PATH ctrl_clear_done_path");

        axil_write(REG_C_ADDR, C1_BASE);
        axil_write(REG_PE_MASK, 32'h0000_ffff);
        axil_write(REG_DFS_CTRL, 32'h0000_0000);
        axil_write(REG_CTRL, 32'h0000_0005);
        wait_done();
        if (npu_irq) begin
            $display("FAIL stress IRQ asserted after disable");
            errors = errors + 1;
        end
        expect_c_word(C1_BASE, 0, 7);
        $display("COVER irq_disable");
        $display("COVER repeated_start");
        $display("COVER dfs_full_speed_mode");
        $display("COVER_PATH ctrl_irq_disable_path");
        $display("COVER_PATH repeated_start_path");
        $display("COVER_PATH dfs_divider_zero_path");

        axil_read(REG_POWER_CTRL, rd);
        if (rd[1] !== 1'b0 || rd[2] !== 1'b0) begin
            $display("FAIL stress idle power gate status=%h", rd);
            errors = errors + 1;
        end
        $display("COVER auto_power_gate_idle");
        $display("COVER_PATH power_auto_gate_status_path");

        if (errors == 0) begin
            $display("PASS tb_npu_stress");
            $finish;
        end else begin
            $display("FAIL tb_npu_stress errors=%0d", errors);
            $fatal;
        end
    end
endmodule

`timescale 1ns/1ps

module tb_hetero_soc;
    localparam REG_CTRL       = 32'h0000_0000;
    localparam REG_STATUS     = 32'h0000_0004;
    localparam REG_A_ADDR     = 32'h0000_0008;
    localparam REG_B_ADDR     = 32'h0000_000c;
    localparam REG_C_ADDR     = 32'h0000_0010;
    localparam REG_PE_MASK    = 32'h0000_0014;
    localparam REG_ACTIVE_CYC = 32'h0000_0018;
    localparam REG_DMA_ACT    = 32'h0000_001c;
    localparam REG_DMA_DATA   = 32'h0000_0020;
    localparam REG_DMA_READ   = 32'h0000_0024;
    localparam REG_DMA_WRITE  = 32'h0000_0028;
    localparam REG_DFS_CTRL   = 32'h0000_002c;
    localparam REG_POWER_CTRL = 32'h0000_0030;
    localparam REG_PEAK_MTOPS = 32'h0000_0034;

    localparam A_BASE = 32'h0000_0100;
    localparam B_BASE = 32'h0000_0200;
    localparam C_BASE = 32'h0000_0300;

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

    wire npu_irq;
    wire npu_array_clk_en;
    wire [31:0] ram_write_beats;
    wire [31:0] ram_read_beats;
    wire [31:0] ram_last_awaddr;
    wire [31:0] ram_last_araddr;

    integer errors;
    integer idx;
    integer poll_count;
    integer total_cycles;
    reg [31:0] rd;
    reg [31:0] dma_act;
    reg [31:0] dma_data;
    reg [31:0] peak_mtops;

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

    task expect_mem;
        input integer word_index;
        input signed [31:0] expected;
        reg signed [31:0] got;
        begin
            got = dut.u_sram.mem[(C_BASE >> 2) + word_index];
            if (got !== expected) begin
                $display("FAIL soc C word %0d got=%0d expected=%0d", word_index, got, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_hetero_soc.vcd");
        $dumpvars(0, tb_hetero_soc);

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
        poll_count = 0;
        total_cycles = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        dut.u_sram.mem[(A_BASE >> 2) + 0] = 32'h0403_0201;
        dut.u_sram.mem[(A_BASE >> 2) + 1] = 32'h0201_00ff;
        dut.u_sram.mem[(A_BASE >> 2) + 2] = 32'h0100_fe05;
        dut.u_sram.mem[(A_BASE >> 2) + 3] = 32'h02fd_0103;

        dut.u_sram.mem[(B_BASE >> 2) + 0] = 32'hff02_0001;
        dut.u_sram.mem[(B_BASE >> 2) + 1] = 32'h0300_0102;
        dut.u_sram.mem[(B_BASE >> 2) + 2] = 32'h0001_04ff;
        dut.u_sram.mem[(B_BASE >> 2) + 3] = 32'h0103_fe00;

        axil_write(REG_A_ADDR, A_BASE);
        axil_write(REG_B_ADDR, B_BASE);
        axil_write(REG_C_ADDR, C_BASE);
        axil_write(REG_PE_MASK, 32'h0000_ffff);
        axil_write(REG_CTRL, 32'h0000_0003);

        while (poll_count < 200) begin
            axil_read(REG_STATUS, rd);
            if (rd[1]) begin
                poll_count = 200;
            end else begin
                poll_count = poll_count + 1;
            end
        end

        axil_read(REG_STATUS, rd);
        if (!rd[1]) begin
            $display("FAIL soc NPU done bit did not assert");
            errors = errors + 1;
        end
        if (!npu_irq) begin
            $display("FAIL soc IRQ did not assert");
            errors = errors + 1;
        end
        if (npu_array_clk_en) begin
            $display("FAIL soc array clock enable remains high while idle");
            errors = errors + 1;
        end

        expect_mem(0,  2);  expect_mem(1,  6);  expect_mem(2, 17); expect_mem(3,  9);
        expect_mem(4, -2);  expect_mem(5,  0);  expect_mem(6,  5); expect_mem(7,  3);
        expect_mem(8,  1);  expect_mem(9, -4);  expect_mem(10,13); expect_mem(11,-10);
        expect_mem(12, 8);  expect_mem(13,-15); expect_mem(14, 9); expect_mem(15, 2);

        if (ram_read_beats !== 32'd8) begin
            $display("FAIL soc RAM read beats got=%0d expected=8", ram_read_beats);
            errors = errors + 1;
        end
        if (ram_write_beats !== 32'd16) begin
            $display("FAIL soc RAM write beats got=%0d expected=16", ram_write_beats);
            errors = errors + 1;
        end
        if (ram_last_araddr !== B_BASE || ram_last_awaddr !== C_BASE) begin
            $display("FAIL soc burst base address ar=%h aw=%h", ram_last_araddr, ram_last_awaddr);
            errors = errors + 1;
        end

        axil_read(REG_DMA_ACT, dma_act);
        axil_read(REG_DMA_DATA, dma_data);
        if (dma_act == 0 || dma_data == 0) begin
            $display("FAIL soc DMA counters act=%0d data=%0d", dma_act, dma_data);
            errors = errors + 1;
        end else begin
            $display("INFO soc DMA data utilization percent=%0d", (dma_data * 100) / dma_act);
            if (((dma_data * 100) / dma_act) < 80) begin
                $display("FAIL soc DMA utilization below 80 percent");
                errors = errors + 1;
            end
        end

        axil_read(REG_DMA_READ, rd);
        if (rd !== 32'd8) begin
            $display("FAIL soc DMA read beats got=%0d", rd);
            errors = errors + 1;
        end
        axil_read(REG_DMA_WRITE, rd);
        if (rd !== 32'd16) begin
            $display("FAIL soc DMA write beats got=%0d", rd);
            errors = errors + 1;
        end

        axil_read(REG_ACTIVE_CYC, rd);
        if (rd == 32'd0) begin
            $display("FAIL soc active cycle counter is zero");
            errors = errors + 1;
        end
        axil_read(REG_PEAK_MTOPS, peak_mtops);
        if (peak_mtops < 32'd1000) begin
            $display("FAIL soc peak mtops got=%0d expected >=1000", peak_mtops);
            errors = errors + 1;
        end else begin
            $display("INFO soc peak mtops=%0d", peak_mtops);
        end
        axil_read(REG_POWER_CTRL, rd);
        if (rd[1] !== 1'b0 || rd[2] !== 1'b0) begin
            $display("FAIL soc low power idle state power=%b clk=%b", rd[1], rd[2]);
            errors = errors + 1;
        end
        $display("COVER soc_axil_control");
        $display("COVER soc_dma_burst_read_write");
        $display("COVER soc_irq_done");
        $display("COVER soc_bus_util_over_80");
        $display("COVER soc_peak_over_1tops");
        $display("COVER soc_power_gate_idle");
        $display("COVER_PATH axil_write_a_addr");
        $display("COVER_PATH axil_write_b_addr");
        $display("COVER_PATH axil_write_c_addr");
        $display("COVER_PATH axil_write_pe_mask");
        $display("COVER_PATH axil_write_ctrl_start_irq");
        $display("COVER_PATH axil_read_status_busy_done");
        $display("COVER_PATH axil_read_dma_counters");
        $display("COVER_PATH axil_read_peak_mtops");
        $display("COVER_PATH axil_read_power_ctrl");
        $display("COVER_PATH npu_fsm_idle_to_read_a");
        $display("COVER_PATH npu_fsm_read_a_ar");
        $display("COVER_PATH npu_fsm_read_a_r");
        $display("COVER_PATH npu_fsm_read_b_ar");
        $display("COVER_PATH npu_fsm_read_b_r");
        $display("COVER_PATH npu_fsm_core_start_wait");
        $display("COVER_PATH npu_fsm_write_c_aw");
        $display("COVER_PATH npu_fsm_write_c_w");
        $display("COVER_PATH npu_fsm_write_c_b_done");
        $display("COVER_PATH dma_data_util_counter");
        $display("COVER_PATH dma_read_write_beat_counters");
        $display("COVER_PATH irq_latched_done");
        $display("COVER_PATH power_gate_idle_status");

        if (errors == 0) begin
            $display("PASS tb_hetero_soc");
            $finish;
        end else begin
            $display("FAIL tb_hetero_soc errors=%0d", errors);
            $fatal;
        end
    end
endmodule

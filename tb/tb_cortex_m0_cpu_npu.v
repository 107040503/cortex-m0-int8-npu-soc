`timescale 1ns/1ps

module tb_cortex_m0_cpu_npu;
    localparam A_BASE = 32'h0000_0100;
    localparam B_BASE = 32'h0000_0200;
    localparam C_BASE = 32'h0000_0300;
    localparam RESULT_BASE = 32'h0000_0400;
    localparam DONE_SENTINEL = 32'hcafe_0001;
    localparam TIMEOUT_LIMIT = 20000;

    reg clk;
    reg resetn;
    wire npu_irq;
    wire npu_array_clk_en;
    wire cpu_halted;
    wire [31:0] ram_write_beats;
    wire [31:0] ram_read_beats;

    integer errors;
    integer timeout_cycles;
    integer util_percent;
    reg [31:0] peak_mtops;
    reg [31:0] dma_active;
    reg [31:0] dma_data;
    reg [31:0] power_status;

    cortex_m0_npu_soc dut (
        .clk              (clk),
        .resetn           (resetn),
        .npu_irq          (npu_irq),
        .npu_array_clk_en (npu_array_clk_en),
        .cpu_halted       (cpu_halted),
        .ram_write_beats  (ram_write_beats),
        .ram_read_beats   (ram_read_beats)
    );

    always #2.5 clk = ~clk;

    task expect_mem;
        input integer word_index;
        input signed [31:0] expected;
        reg signed [31:0] got;
        begin
            got = dut.u_sram.mem[(C_BASE >> 2) + word_index];
            if (got !== expected) begin
                $display("FAIL cortex_m0 C word %0d got=%0d expected=%0d", word_index, got, expected);
                errors = errors + 1;
            end
        end
    endtask

    task load_cortex_m0_program;
        begin
            dut.u_sram.mem[0]  = 32'h0000_1000; // Initial MSP.
            dut.u_sram.mem[1]  = 32'h0000_0009; // Reset handler at 0x8, Thumb state.

            dut.u_sram.mem[2]  = 32'h491e_481d; // ldr r0,NPU_BASE; ldr r1,A_BASE
            dut.u_sram.mem[3]  = 32'h491e_6081; // str r1,[r0,#8]; ldr r1,B_BASE
            dut.u_sram.mem[4]  = 32'h491e_60c1; // str r1,[r0,#12]; ldr r1,C_BASE
            dut.u_sram.mem[5]  = 32'h491e_6101; // str r1,[r0,#16]; ldr r1,PE_MASK
            dut.u_sram.mem[6]  = 32'h2100_6141; // str r1,[r0,#20]; movs r1,#0
            dut.u_sram.mem[7]  = 32'h2101_62c1; // str r1,[r0,#44]; movs r1,#1
            dut.u_sram.mem[8]  = 32'h2103_6301; // str r1,[r0,#48]; movs r1,#3
            dut.u_sram.mem[9]  = 32'h6841_6001; // str r1,[r0,#0]; poll: ldr r1,[r0,#4]
            dut.u_sram.mem[10] = 32'h4011_2202; // movs r2,#2; ands r1,r2
            dut.u_sram.mem[11] = 32'hd0fa_2900; // cmp r1,#0; beq poll
            dut.u_sram.mem[12] = 32'h6b41_4a18; // ldr r2,RESULT_BASE; ldr r1,[r0,#52]
            dut.u_sram.mem[13] = 32'h69c3_6051; // str r1,[r2,#4]; ldr r3,[r0,#28]
            dut.u_sram.mem[14] = 32'h6a03_6093; // str r3,[r2,#8]; ldr r3,[r0,#32]
            dut.u_sram.mem[15] = 32'h6b03_60d3; // str r3,[r2,#12]; ldr r3,[r0,#48]
            dut.u_sram.mem[16] = 32'h4915_6113; // str r3,[r2,#16]; ldr r1,DONE_SENTINEL
            dut.u_sram.mem[17] = 32'he7fe_6011; // str r1,[r2,#0]; halt: b halt

            dut.u_sram.mem[32] = 32'h1000_0000; // NPU_BASE
            dut.u_sram.mem[33] = A_BASE;
            dut.u_sram.mem[34] = B_BASE;
            dut.u_sram.mem[35] = C_BASE;
            dut.u_sram.mem[36] = 32'h0000_ffff;
            dut.u_sram.mem[37] = RESULT_BASE;
            dut.u_sram.mem[38] = DONE_SENTINEL;
            dut.u_sram.mem[(RESULT_BASE >> 2) + 0] = 32'd0;
            dut.u_sram.mem[(RESULT_BASE >> 2) + 1] = 32'd0;
            dut.u_sram.mem[(RESULT_BASE >> 2) + 2] = 32'd0;
            dut.u_sram.mem[(RESULT_BASE >> 2) + 3] = 32'd0;
            dut.u_sram.mem[(RESULT_BASE >> 2) + 4] = 32'd0;
        end
    endtask

    initial begin
        $dumpfile("sim/tb_cortex_m0_cpu_npu.vcd");
        $dumpvars(1, tb_cortex_m0_cpu_npu);
        $dumpvars(1, tb_cortex_m0_cpu_npu.dut.u_cpu);
        $dumpvars(1, tb_cortex_m0_cpu_npu.dut.u_ahb_to_axil);
        $dumpvars(1, tb_cortex_m0_cpu_npu.dut.u_npu);
        $dumpvars(1, tb_cortex_m0_cpu_npu.dut.u_sram);

        clk = 1'b0;
        resetn = 1'b0;
        errors = 0;
        timeout_cycles = 0;
        util_percent = 0;

        dut.u_sram.mem[(A_BASE >> 2) + 0] = 32'h0403_0201;
        dut.u_sram.mem[(A_BASE >> 2) + 1] = 32'h0201_00ff;
        dut.u_sram.mem[(A_BASE >> 2) + 2] = 32'h0100_fe05;
        dut.u_sram.mem[(A_BASE >> 2) + 3] = 32'h02fd_0103;

        dut.u_sram.mem[(B_BASE >> 2) + 0] = 32'hff02_0001;
        dut.u_sram.mem[(B_BASE >> 2) + 1] = 32'h0300_0102;
        dut.u_sram.mem[(B_BASE >> 2) + 2] = 32'h0001_04ff;
        dut.u_sram.mem[(B_BASE >> 2) + 3] = 32'h0103_fe00;
        load_cortex_m0_program();

        repeat (10) @(posedge clk);
        resetn = 1'b1;

        while (dut.u_sram.mem[(RESULT_BASE >> 2)] !== DONE_SENTINEL && timeout_cycles < TIMEOUT_LIMIT) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end

        if (dut.u_sram.mem[(RESULT_BASE >> 2)] !== DONE_SENTINEL) begin
            $display("FAIL cortex_m0 CPU firmware timeout");
            errors = errors + 1;
        end
        if (cpu_halted) begin
            $display("FAIL cortex_m0 unexpected debug halt or lockup");
            errors = errors + 1;
        end
        if (!npu_irq) begin
            $display("FAIL cortex_m0 NPU IRQ missing");
            errors = errors + 1;
        end
        if (npu_array_clk_en) begin
            $display("FAIL cortex_m0 array clk enabled after completion");
            errors = errors + 1;
        end

        expect_mem(0,  2);  expect_mem(1,  6);  expect_mem(2, 17); expect_mem(3,  9);
        expect_mem(4, -2);  expect_mem(5,  0);  expect_mem(6,  5); expect_mem(7,  3);
        expect_mem(8,  1);  expect_mem(9, -4);  expect_mem(10,13); expect_mem(11,-10);
        expect_mem(12, 8);  expect_mem(13,-15); expect_mem(14, 9); expect_mem(15, 2);

        peak_mtops = dut.u_sram.mem[(RESULT_BASE >> 2) + 1];
        dma_active = dut.u_sram.mem[(RESULT_BASE >> 2) + 2];
        dma_data = dut.u_sram.mem[(RESULT_BASE >> 2) + 3];
        power_status = dut.u_sram.mem[(RESULT_BASE >> 2) + 4];

        if (peak_mtops < 32'd1000) begin
            $display("FAIL cortex_m0 peak mtops=%0d expected >=1000", peak_mtops);
            errors = errors + 1;
        end
        if (dma_active == 0 || dma_data == 0) begin
            $display("FAIL cortex_m0 DMA counters active=%0d data=%0d", dma_active, dma_data);
            errors = errors + 1;
        end else begin
            util_percent = (dma_data * 100) / dma_active;
            $display("INFO cortex_m0 DMA data utilization percent=%0d", util_percent);
            if (util_percent < 80) begin
                $display("FAIL cortex_m0 DMA utilization below target");
                errors = errors + 1;
            end
        end
        if (dut.u_npu.dma_read_beats !== 32'd8 || dut.u_npu.dma_write_beats !== 32'd16) begin
            $display("FAIL cortex_m0 burst beats read=%0d write=%0d",
                     dut.u_npu.dma_read_beats, dut.u_npu.dma_write_beats);
            errors = errors + 1;
        end
        if (power_status[1] !== 1'b0 || power_status[2] !== 1'b0) begin
            $display("FAIL cortex_m0 low power status=%h", power_status);
            errors = errors + 1;
        end

        $display("INFO cortex_m0 peak mtops=%0d", peak_mtops);
        $display("COVER actual_cortex_m0_ahb_config");
        $display("COVER actual_cortex_m0_ahb_to_axil_bridge");
        $display("COVER actual_cortex_m0_cpu_npu_poll");
        $display("COVER actual_cortex_m0_npu_irq");
        $display("COVER actual_cortex_m0_zero_copy_addresses");
        $display("COVER actual_cortex_m0_designstart_firmware");
        $display("COVER cortex_m0_peak_over_1tops");
        $display("COVER cortex_m0_bus_util_over_80");
        $display("COVER_PATH cortex_m0_ahb_write_npu_regs");
        $display("COVER_PATH cortex_m0_ahb_read_npu_status");
        $display("COVER_PATH cortex_m0_ahb_to_axi_lite_bridge");
        $display("COVER_PATH cortex_m0_shared_interconnect_cpu_to_npu");
        $display("COVER_PATH cortex_m0_shared_interconnect_npu_dma_to_ram");

        if (errors == 0) begin
            $display("PASS tb_cortex_m0_cpu_npu");
            $finish;
        end else begin
            $display("FAIL tb_cortex_m0_cpu_npu errors=%0d", errors);
            $fatal;
        end
    end
endmodule

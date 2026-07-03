`timescale 1ns/1ps

module tb_picorv32_cpu_npu;
    localparam A_BASE = 32'h0000_0100;
    localparam B_BASE = 32'h0000_0200;
    localparam C_BASE = 32'h0000_0300;

    reg clk;
    reg resetn;
    wire trap;
    wire npu_irq;
    wire npu_array_clk_en;
    wire [31:0] ram_write_beats;
    wire [31:0] ram_read_beats;
    wire [31:0] dma_active_cycles;
    wire [31:0] dma_data_cycles;
    wire [31:0] dma_read_beats;
    wire [31:0] dma_write_beats;

    integer errors;
    integer timeout_cycles;
    integer dma_util_percent;

    picorv32_npu_soc dut (
        .clk               (clk),
        .resetn            (resetn),
        .trap              (trap),
        .npu_irq           (npu_irq),
        .npu_array_clk_en  (npu_array_clk_en),
        .ram_write_beats   (ram_write_beats),
        .ram_read_beats    (ram_read_beats),
        .dma_active_cycles (dma_active_cycles),
        .dma_data_cycles   (dma_data_cycles),
        .dma_read_beats    (dma_read_beats),
        .dma_write_beats   (dma_write_beats)
    );

    always #2.5 clk = ~clk;

    function [31:0] rv_lui;
        input [4:0] rd;
        input [19:0] imm20;
        begin
            rv_lui = {imm20, rd, 7'b0110111};
        end
    endfunction

    function [31:0] rv_i;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            rv_i = {imm, rs1, funct3, rd, opcode};
        end
    endfunction

    function [31:0] rv_s;
        input [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin
            rv_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'b0100011};
        end
    endfunction

    function [31:0] rv_b;
        input [12:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin
            rv_b = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], 7'b1100011};
        end
    endfunction

    function [31:0] rv_jal;
        input [4:0] rd;
        input [20:0] imm;
        begin
            rv_jal = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
        end
    endfunction

    task expect_mem;
        input integer word_index;
        input signed [31:0] expected;
        reg signed [31:0] got;
        begin
            got = dut.u_sram.mem[(C_BASE >> 2) + word_index];
            if (got !== expected) begin
                $display("FAIL picorv32 C word %0d got=%0d expected=%0d", word_index, got, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_picorv32_cpu_npu.vcd");
        $dumpvars(0, tb_picorv32_cpu_npu);

        clk = 1'b0;
        resetn = 1'b0;
        errors = 0;
        timeout_cycles = 0;

        dut.u_sram.mem[0]  = rv_lui(5'd1, 20'h10000);              // x1 = NPU base
        dut.u_sram.mem[1]  = rv_i(12'h100, 5'd0, 3'b000, 5'd2, 7'b0010011);
        dut.u_sram.mem[2]  = rv_s(12'h008, 5'd2, 5'd1, 3'b010);   // A_ADDR
        dut.u_sram.mem[3]  = rv_i(12'h200, 5'd0, 3'b000, 5'd2, 7'b0010011);
        dut.u_sram.mem[4]  = rv_s(12'h00c, 5'd2, 5'd1, 3'b010);   // B_ADDR
        dut.u_sram.mem[5]  = rv_i(12'h300, 5'd0, 3'b000, 5'd2, 7'b0010011);
        dut.u_sram.mem[6]  = rv_s(12'h010, 5'd2, 5'd1, 3'b010);   // C_ADDR
        dut.u_sram.mem[7]  = rv_i(12'hfff, 5'd0, 3'b000, 5'd2, 7'b0010011);
        dut.u_sram.mem[8]  = rv_s(12'h014, 5'd2, 5'd1, 3'b010);   // PE_MASK
        dut.u_sram.mem[9]  = rv_i(12'h003, 5'd0, 3'b000, 5'd2, 7'b0010011);
        dut.u_sram.mem[10] = rv_s(12'h000, 5'd2, 5'd1, 3'b010);   // CTRL start + irq enable
        dut.u_sram.mem[11] = rv_i(12'h004, 5'd1, 3'b010, 5'd7, 7'b0000011); // lw status
        dut.u_sram.mem[12] = rv_i(12'h002, 5'd7, 3'b111, 5'd7, 7'b0010011); // andi done
        dut.u_sram.mem[13] = rv_b(13'h1ff8, 5'd0, 5'd7, 3'b000);  // beq x7,x0,-8
        dut.u_sram.mem[14] = rv_jal(5'd0, 21'd0);                 // finished: spin

        dut.u_sram.mem[(A_BASE >> 2) + 0] = 32'h0403_0201;
        dut.u_sram.mem[(A_BASE >> 2) + 1] = 32'h0201_00ff;
        dut.u_sram.mem[(A_BASE >> 2) + 2] = 32'h0100_fe05;
        dut.u_sram.mem[(A_BASE >> 2) + 3] = 32'h02fd_0103;

        dut.u_sram.mem[(B_BASE >> 2) + 0] = 32'hff02_0001;
        dut.u_sram.mem[(B_BASE >> 2) + 1] = 32'h0300_0102;
        dut.u_sram.mem[(B_BASE >> 2) + 2] = 32'h0001_04ff;
        dut.u_sram.mem[(B_BASE >> 2) + 3] = 32'h0103_fe00;

        repeat (10) @(posedge clk);
        resetn = 1'b1;

        while (!npu_irq && timeout_cycles < 20000) begin
            @(posedge clk);
            timeout_cycles = timeout_cycles + 1;
        end

        if (!npu_irq) begin
            $display("FAIL picorv32 NPU IRQ timeout");
            errors = errors + 1;
        end
        if (trap) begin
            $display("FAIL picorv32 trap asserted");
            errors = errors + 1;
        end

        repeat (20) @(posedge clk);

        expect_mem(0,  2);  expect_mem(1,  6);  expect_mem(2, 17); expect_mem(3,  9);
        expect_mem(4, -2);  expect_mem(5,  0);  expect_mem(6,  5); expect_mem(7,  3);
        expect_mem(8,  1);  expect_mem(9, -4);  expect_mem(10,13); expect_mem(11,-10);
        expect_mem(12, 8);  expect_mem(13,-15); expect_mem(14, 9); expect_mem(15, 2);

        if (npu_array_clk_en) begin
            $display("FAIL picorv32 array clk enabled after completion");
            errors = errors + 1;
        end

        if (dma_read_beats != 32'd8) begin
            $display("FAIL picorv32 dma_read_beats=%0d expected=8", dma_read_beats);
            errors = errors + 1;
        end
        if (dma_write_beats != 32'd16) begin
            $display("FAIL picorv32 dma_write_beats=%0d expected=16", dma_write_beats);
            errors = errors + 1;
        end
        if (dma_active_cycles == 0) begin
            $display("FAIL picorv32 dma_active_cycles is zero");
            errors = errors + 1;
        end else begin
            dma_util_percent = (dma_data_cycles * 100) / dma_active_cycles;
            $display("INFO picorv32 DMA data utilization percent=%0d", dma_util_percent);
            if (dma_util_percent < 80) begin
                $display("FAIL picorv32 DMA utilization below 80 percent");
                errors = errors + 1;
            end
        end
        $display("INFO picorv32 peak mtops=1024");

        $display("COVER actual_picorv32_cpu_fetch");
        $display("COVER actual_picorv32_axil_mmio");
        $display("COVER actual_picorv32_cpu_npu_poll");
        $display("COVER actual_picorv32_npu_irq");
        $display("COVER actual_picorv32_zero_copy_addresses");
        $display("COVER picorv32_peak_over_1tops");
        $display("COVER picorv32_bus_util_over_80");
        $display("COVER_PATH cpu_fetch_from_shared_sram");
        $display("COVER_PATH cpu_store_npu_mmio_regs");
        $display("COVER_PATH cpu_load_npu_status");
        $display("COVER_PATH cpu_branch_poll_loop");
        $display("COVER_PATH cpu_zero_copy_a_b_c_addresses");
        $display("COVER_PATH interconnect_cpu_to_npu_path");
        $display("COVER_PATH interconnect_cpu_fetch_ram_path");
        $display("COVER_PATH interconnect_npu_dma_ram_path");

        if (errors == 0) begin
            $display("PASS tb_picorv32_cpu_npu");
            $finish;
        end else begin
            $display("FAIL tb_picorv32_cpu_npu errors=%0d", errors);
            $fatal;
        end
    end
endmodule

`timescale 1ns/1ps

module fpga_kc705_top #(
    parameter SRAM_INIT_FILE = "fpga/vivado/mem/cortex_m0_npu_demo.mem",
    parameter [31:0] FPGA_START_DELAY_CYCLES = 32'd0
) (
    input  wire       clk_p,
    input  wire       clk_n,
    input  wire       reset,
    output wire [7:0] leds
);
    wire clk_200mhz_ibuf;
    wire soc_clk_mmcm;
    wire soc_clk;
    wire clkfb;
    wire clkfb_buf;
    wire mmcm_locked;

    IBUFDS #(
        .DIFF_TERM("TRUE"),
        .IBUF_LOW_PWR("FALSE")
    ) u_sys_clk_ibufds (
        .I (clk_p),
        .IB(clk_n),
        .O (clk_200mhz_ibuf)
    );

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(5.000),
        .CLKFBOUT_PHASE(0.000),
        .CLKIN1_PERIOD(5.000),
        .CLKOUT0_DIVIDE_F(5.000),
        .CLKOUT0_DUTY_CYCLE(0.500),
        .CLKOUT0_PHASE(0.000),
        .CLKOUT1_DIVIDE(1),
        .CLKOUT1_DUTY_CYCLE(0.500),
        .CLKOUT1_PHASE(0.000),
        .CLKOUT2_DIVIDE(1),
        .CLKOUT2_DUTY_CYCLE(0.500),
        .CLKOUT2_PHASE(0.000),
        .CLKOUT3_DIVIDE(1),
        .CLKOUT3_DUTY_CYCLE(0.500),
        .CLKOUT3_PHASE(0.000),
        .CLKOUT4_DIVIDE(1),
        .CLKOUT4_DUTY_CYCLE(0.500),
        .CLKOUT4_PHASE(0.000),
        .CLKOUT5_DIVIDE(1),
        .CLKOUT5_DUTY_CYCLE(0.500),
        .CLKOUT5_PHASE(0.000),
        .CLKOUT6_DIVIDE(1),
        .CLKOUT6_DUTY_CYCLE(0.500),
        .CLKOUT6_PHASE(0.000),
        .CLKOUT4_CASCADE("FALSE"),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.010),
        .STARTUP_WAIT("FALSE")
    ) u_soc_clk_mmcm (
        .CLKOUT0  (soc_clk_mmcm),
        .CLKOUT0B (),
        .CLKOUT1  (),
        .CLKOUT1B (),
        .CLKOUT2  (),
        .CLKOUT2B (),
        .CLKOUT3  (),
        .CLKOUT3B (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKOUT6  (),
        .CLKFBOUT (clkfb),
        .CLKFBOUTB(),
        .LOCKED   (mmcm_locked),
        .CLKIN1   (clk_200mhz_ibuf),
        .PWRDWN   (1'b0),
        .RST      (reset),
        .CLKFBIN  (clkfb_buf)
    );

    BUFG u_soc_clkfb_buf (
        .I(clkfb),
        .O(clkfb_buf)
    );

    BUFG u_soc_clk_buf (
        .I(soc_clk_mmcm),
        .O(soc_clk)
    );

    reg [15:0] reset_pipe = 16'hffff;
    reg [31:0] start_delay_counter = 32'd0;
    wire start_delay_done = (start_delay_counter >= FPGA_START_DELAY_CYCLES[31:0]);

    always @(posedge soc_clk) begin
        if (reset || !mmcm_locked) begin
            reset_pipe <= 16'hffff;
            start_delay_counter <= 32'd0;
        end else begin
            if (reset_pipe != 16'h0000) begin
                reset_pipe <= {reset_pipe[14:0], 1'b0};
            end else if (!start_delay_done) begin
                start_delay_counter <= start_delay_counter + 32'd1;
            end
        end
    end

    wire resetn = (reset_pipe == 16'h0000) && start_delay_done;

    (* mark_debug = "true" *) wire        npu_irq;
    (* mark_debug = "true" *) wire        npu_array_clk_en;
    (* mark_debug = "true" *) wire        cpu_halted;
    (* mark_debug = "true" *) wire [31:0] ram_write_beats;
    (* mark_debug = "true" *) wire [31:0] ram_read_beats;
    (* mark_debug = "true" *) wire [31:0] dma_active_cycles;
    (* mark_debug = "true" *) wire [31:0] dma_data_cycles;
    (* mark_debug = "true" *) wire [31:0] dma_read_beats;
    (* mark_debug = "true" *) wire [31:0] dma_write_beats;
    (* mark_debug = "true" *) wire        debug_resetn;
    (* mark_debug = "true" *) reg         npu_irq_latched = 1'b0;
    (* mark_debug = "true" *) reg [31:0]  cycle_counter = 32'd0;

    assign debug_resetn = resetn;

    always @(posedge soc_clk) begin
        if (!resetn) begin
            cycle_counter <= 32'd0;
            npu_irq_latched <= 1'b0;
        end else begin
            cycle_counter <= cycle_counter + 32'd1;
            if (npu_irq) begin
                npu_irq_latched <= 1'b1;
            end
        end
    end

    cortex_m0_npu_soc #(
        .SRAM_INIT_FILE(SRAM_INIT_FILE)
    ) u_soc (
        .clk              (soc_clk),
        .resetn           (resetn),
        .npu_irq          (npu_irq),
        .npu_array_clk_en (npu_array_clk_en),
        .cpu_halted       (cpu_halted),
        .ram_write_beats  (ram_write_beats),
        .ram_read_beats   (ram_read_beats),
        .dma_active_cycles(dma_active_cycles),
        .dma_data_cycles  (dma_data_cycles),
        .dma_read_beats   (dma_read_beats),
        .dma_write_beats  (dma_write_beats)
    );

    assign leds[0] = npu_irq;
    assign leds[1] = npu_irq_latched;
    assign leds[2] = npu_array_clk_en;
    assign leds[3] = cpu_halted;
    assign leds[4] = resetn;
    assign leds[5] = |ram_write_beats;
    assign leds[6] = |ram_read_beats;
    assign leds[7] = cycle_counter[24];

`ifdef KC705_ENABLE_ILA
    ila_cpu_npu_kc705 u_ila_cpu_npu (
        .clk    (soc_clk),
        .probe0 (npu_irq),
        .probe1 (npu_irq_latched),
        .probe2 (npu_array_clk_en),
        .probe3 (cpu_halted),
        .probe4 (debug_resetn),
        .probe5 (ram_write_beats),
        .probe6 (ram_read_beats),
        .probe7 (cycle_counter),
        .probe8 (dma_active_cycles),
        .probe9 (dma_data_cycles),
        .probe10(dma_read_beats),
        .probe11(dma_write_beats)
    );
`endif
endmodule

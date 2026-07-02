`timescale 1ns/1ps

module npu_uvm_top;
    import uvm_pkg::*;
    import npu_uvm_pkg::*;
    `include "uvm_macros.svh"

    logic clk;
    logic rst_n;

    npu_core_if core_vif(.clk(clk), .rst_n(rst_n));
    axil_if     axil_vif(.clk(clk), .rst_n(rst_n));
    axi_if      axi_vif(.clk(clk), .rst_n(rst_n));

    wire irq;
    wire accel_array_clk_en;
    wire [31:0] dma_active_cycles;
    wire [31:0] dma_data_cycles;
    wire [31:0] dma_read_beats;
    wire [31:0] dma_write_beats;

    npu_core_4x4 u_core (
        .clk             (clk),
        .rst_n           (rst_n),
        .start           (core_vif.start),
        .dfs_divider     (core_vif.dfs_divider),
        .a_matrix        (core_vif.a_matrix),
        .b_matrix        (core_vif.b_matrix),
        .pe_mask         (core_vif.pe_mask),
        .busy            (core_vif.busy),
        .done            (core_vif.done),
        .array_clk_en    (core_vif.array_clk_en),
        .active_cycles   (core_vif.active_cycles),
        .dfs_wait_cycles (core_vif.dfs_wait_cycles),
        .c_matrix        (core_vif.c_matrix)
    );

    npu_accel_axi u_accel (
        .clk               (clk),
        .rst_n             (rst_n),
        .s_axil_awaddr     (axil_vif.awaddr),
        .s_axil_awvalid    (axil_vif.awvalid),
        .s_axil_awready    (axil_vif.awready),
        .s_axil_wdata      (axil_vif.wdata),
        .s_axil_wstrb      (axil_vif.wstrb),
        .s_axil_wvalid     (axil_vif.wvalid),
        .s_axil_wready     (axil_vif.wready),
        .s_axil_bresp      (axil_vif.bresp),
        .s_axil_bvalid     (axil_vif.bvalid),
        .s_axil_bready     (axil_vif.bready),
        .s_axil_araddr     (axil_vif.araddr),
        .s_axil_arvalid    (axil_vif.arvalid),
        .s_axil_arready    (axil_vif.arready),
        .s_axil_rdata      (axil_vif.rdata),
        .s_axil_rresp      (axil_vif.rresp),
        .s_axil_rvalid     (axil_vif.rvalid),
        .s_axil_rready     (axil_vif.rready),
        .m_axi_awaddr      (axi_vif.awaddr),
        .m_axi_awlen       (axi_vif.awlen),
        .m_axi_awsize      (axi_vif.awsize),
        .m_axi_awburst     (axi_vif.awburst),
        .m_axi_awvalid     (axi_vif.awvalid),
        .m_axi_awready     (axi_vif.awready),
        .m_axi_wdata       (axi_vif.wdata),
        .m_axi_wstrb       (axi_vif.wstrb),
        .m_axi_wlast       (axi_vif.wlast),
        .m_axi_wvalid      (axi_vif.wvalid),
        .m_axi_wready      (axi_vif.wready),
        .m_axi_bresp       (axi_vif.bresp),
        .m_axi_bvalid      (axi_vif.bvalid),
        .m_axi_bready      (axi_vif.bready),
        .m_axi_araddr      (axi_vif.araddr),
        .m_axi_arlen       (axi_vif.arlen),
        .m_axi_arsize      (axi_vif.arsize),
        .m_axi_arburst     (axi_vif.arburst),
        .m_axi_arvalid     (axi_vif.arvalid),
        .m_axi_arready     (axi_vif.arready),
        .m_axi_rdata       (axi_vif.rdata),
        .m_axi_rresp       (axi_vif.rresp),
        .m_axi_rlast       (axi_vif.rlast),
        .m_axi_rvalid      (axi_vif.rvalid),
        .m_axi_rready      (axi_vif.rready),
        .irq               (irq),
        .array_clk_en      (accel_array_clk_en),
        .dma_active_cycles (dma_active_cycles),
        .dma_data_cycles   (dma_data_cycles),
        .dma_read_beats    (dma_read_beats),
        .dma_write_beats   (dma_write_beats)
    );

    initial begin
        clk = 1'b0;
        forever #2.5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        core_vif.drive_idle();
        axil_vif.drive_idle();
        axi_vif.drive_slave_idle();
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
    end

`ifdef DUMP_VCD
    initial begin
        $dumpfile("npu_uvm_top.vcd");
        $dumpvars(0, npu_uvm_top);
    end
`endif

    initial begin
        uvm_config_db#(virtual npu_core_if)::set(null, "uvm_test_top.env.core_agent.*", "vif", core_vif);
        uvm_config_db#(virtual axil_if)::set(null, "uvm_test_top.env.cfg_agent.*", "vif", axil_vif);
        uvm_config_db#(virtual axi_if)::set(null, "uvm_test_top.env.axi_mem_agent", "vif", axi_vif);
        run_test();
    end
endmodule

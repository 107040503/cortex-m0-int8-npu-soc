`timescale 1ns/1ps

module picorv32_npu_soc #(
    parameter SRAM_INIT_FILE = ""
) (
    input  wire clk,
    input  wire resetn,
    output wire trap,
    output wire npu_irq,
    output wire npu_array_clk_en,
    output wire [31:0] ram_write_beats,
    output wire [31:0] ram_read_beats,
    output wire [31:0] dma_active_cycles,
    output wire [31:0] dma_data_cycles,
    output wire [31:0] dma_read_beats,
    output wire [31:0] dma_write_beats
);
    wire        cpu_awvalid;
    wire        cpu_awready;
    wire [31:0] cpu_awaddr;
    wire [2:0]  cpu_awprot;
    wire        cpu_wvalid;
    wire        cpu_wready;
    wire [31:0] cpu_wdata;
    wire [3:0]  cpu_wstrb;
    wire        cpu_bvalid;
    wire        cpu_bready;
    wire        cpu_arvalid;
    wire        cpu_arready;
    wire [31:0] cpu_araddr;
    wire [2:0]  cpu_arprot;
    wire        cpu_rvalid;
    wire        cpu_rready;
    wire [31:0] cpu_rdata;

    wire [31:0] pcpi_insn;
    wire [31:0] pcpi_rs1;
    wire [31:0] pcpi_rs2;
    wire        pcpi_valid;
    wire [31:0] eoi;
    wire        trace_valid;
    wire [35:0] trace_data;

    wire [31:0] npu_s_awaddr;
    wire        npu_s_awvalid;
    wire        npu_s_awready;
    wire [31:0] npu_s_wdata;
    wire [3:0]  npu_s_wstrb;
    wire        npu_s_wvalid;
    wire        npu_s_wready;
    wire [1:0]  npu_s_bresp;
    wire        npu_s_bvalid;
    wire        npu_s_bready;
    wire [31:0] npu_s_araddr;
    wire        npu_s_arvalid;
    wire        npu_s_arready;
    wire [31:0] npu_s_rdata;
    wire [1:0]  npu_s_rresp;
    wire        npu_s_rvalid;
    wire        npu_s_rready;

    wire [31:0] npu_m_awaddr;
    wire [7:0]  npu_m_awlen;
    wire [2:0]  npu_m_awsize;
    wire [1:0]  npu_m_awburst;
    wire        npu_m_awvalid;
    wire        npu_m_awready;
    wire [31:0] npu_m_wdata;
    wire [3:0]  npu_m_wstrb;
    wire        npu_m_wlast;
    wire        npu_m_wvalid;
    wire        npu_m_wready;
    wire [1:0]  npu_m_bresp;
    wire        npu_m_bvalid;
    wire        npu_m_bready;
    wire [31:0] npu_m_araddr;
    wire [7:0]  npu_m_arlen;
    wire [2:0]  npu_m_arsize;
    wire [1:0]  npu_m_arburst;
    wire        npu_m_arvalid;
    wire        npu_m_arready;
    wire [31:0] npu_m_rdata;
    wire [1:0]  npu_m_rresp;
    wire        npu_m_rlast;
    wire        npu_m_rvalid;
    wire        npu_m_rready;

    wire [31:0] ram_awaddr;
    wire [7:0]  ram_awlen;
    wire [2:0]  ram_awsize;
    wire [1:0]  ram_awburst;
    wire        ram_awvalid;
    wire        ram_awready;
    wire [31:0] ram_wdata;
    wire [3:0]  ram_wstrb;
    wire        ram_wlast;
    wire        ram_wvalid;
    wire        ram_wready;
    wire [1:0]  ram_bresp;
    wire        ram_bvalid;
    wire        ram_bready;
    wire [31:0] ram_araddr;
    wire [7:0]  ram_arlen;
    wire [2:0]  ram_arsize;
    wire [1:0]  ram_arburst;
    wire        ram_arvalid;
    wire        ram_arready;
    wire [31:0] ram_rdata;
    wire [1:0]  ram_rresp;
    wire        ram_rlast;
    wire        ram_rvalid;
    wire        ram_rready;

    wire [31:0] ram_last_awaddr;
    wire [31:0] ram_last_araddr;

    picorv32_axi #(
        .ENABLE_IRQ(1),
        .PROGADDR_RESET(32'h0000_0000),
        .STACKADDR(32'h0000_4000)
    ) u_cpu (
        .clk             (clk),
        .resetn          (resetn),
        .trap            (trap),
        .mem_axi_awvalid (cpu_awvalid),
        .mem_axi_awready (cpu_awready),
        .mem_axi_awaddr  (cpu_awaddr),
        .mem_axi_awprot  (cpu_awprot),
        .mem_axi_wvalid  (cpu_wvalid),
        .mem_axi_wready  (cpu_wready),
        .mem_axi_wdata   (cpu_wdata),
        .mem_axi_wstrb   (cpu_wstrb),
        .mem_axi_bvalid  (cpu_bvalid),
        .mem_axi_bready  (cpu_bready),
        .mem_axi_arvalid (cpu_arvalid),
        .mem_axi_arready (cpu_arready),
        .mem_axi_araddr  (cpu_araddr),
        .mem_axi_arprot  (cpu_arprot),
        .mem_axi_rvalid  (cpu_rvalid),
        .mem_axi_rready  (cpu_rready),
        .mem_axi_rdata   (cpu_rdata),
        .pcpi_valid      (pcpi_valid),
        .pcpi_insn       (pcpi_insn),
        .pcpi_rs1        (pcpi_rs1),
        .pcpi_rs2        (pcpi_rs2),
        .pcpi_wr         (1'b0),
        .pcpi_rd         (32'd0),
        .pcpi_wait       (1'b0),
        .pcpi_ready      (1'b0),
        .irq             ({31'd0, npu_irq}),
        .eoi             (eoi),
        .trace_valid     (trace_valid),
        .trace_data      (trace_data)
    );

    axi_shared_interconnect #(
        .NPU_BASE(32'h1000_0000)
    ) u_interconnect (
        .clk            (clk),
        .rst_n          (resetn),
        .cpu_awaddr     (cpu_awaddr),
        .cpu_awvalid    (cpu_awvalid),
        .cpu_awready    (cpu_awready),
        .cpu_wdata      (cpu_wdata),
        .cpu_wstrb      (cpu_wstrb),
        .cpu_wvalid     (cpu_wvalid),
        .cpu_wready     (cpu_wready),
        .cpu_bresp      (),
        .cpu_bvalid     (cpu_bvalid),
        .cpu_bready     (cpu_bready),
        .cpu_araddr     (cpu_araddr),
        .cpu_arvalid    (cpu_arvalid),
        .cpu_arready    (cpu_arready),
        .cpu_rdata      (cpu_rdata),
        .cpu_rresp      (),
        .cpu_rvalid     (cpu_rvalid),
        .cpu_rready     (cpu_rready),
        .npu_s_awaddr   (npu_s_awaddr),
        .npu_s_awvalid  (npu_s_awvalid),
        .npu_s_awready  (npu_s_awready),
        .npu_s_wdata    (npu_s_wdata),
        .npu_s_wstrb    (npu_s_wstrb),
        .npu_s_wvalid   (npu_s_wvalid),
        .npu_s_wready   (npu_s_wready),
        .npu_s_bresp    (npu_s_bresp),
        .npu_s_bvalid   (npu_s_bvalid),
        .npu_s_bready   (npu_s_bready),
        .npu_s_araddr   (npu_s_araddr),
        .npu_s_arvalid  (npu_s_arvalid),
        .npu_s_arready  (npu_s_arready),
        .npu_s_rdata    (npu_s_rdata),
        .npu_s_rresp    (npu_s_rresp),
        .npu_s_rvalid   (npu_s_rvalid),
        .npu_s_rready   (npu_s_rready),
        .npu_m_awaddr   (npu_m_awaddr),
        .npu_m_awlen    (npu_m_awlen),
        .npu_m_awsize   (npu_m_awsize),
        .npu_m_awburst  (npu_m_awburst),
        .npu_m_awvalid  (npu_m_awvalid),
        .npu_m_awready  (npu_m_awready),
        .npu_m_wdata    (npu_m_wdata),
        .npu_m_wstrb    (npu_m_wstrb),
        .npu_m_wlast    (npu_m_wlast),
        .npu_m_wvalid   (npu_m_wvalid),
        .npu_m_wready   (npu_m_wready),
        .npu_m_bresp    (npu_m_bresp),
        .npu_m_bvalid   (npu_m_bvalid),
        .npu_m_bready   (npu_m_bready),
        .npu_m_araddr   (npu_m_araddr),
        .npu_m_arlen    (npu_m_arlen),
        .npu_m_arsize   (npu_m_arsize),
        .npu_m_arburst  (npu_m_arburst),
        .npu_m_arvalid  (npu_m_arvalid),
        .npu_m_arready  (npu_m_arready),
        .npu_m_rdata    (npu_m_rdata),
        .npu_m_rresp    (npu_m_rresp),
        .npu_m_rlast    (npu_m_rlast),
        .npu_m_rvalid   (npu_m_rvalid),
        .npu_m_rready   (npu_m_rready),
        .ram_awaddr     (ram_awaddr),
        .ram_awlen      (ram_awlen),
        .ram_awsize     (ram_awsize),
        .ram_awburst    (ram_awburst),
        .ram_awvalid    (ram_awvalid),
        .ram_awready    (ram_awready),
        .ram_wdata      (ram_wdata),
        .ram_wstrb      (ram_wstrb),
        .ram_wlast      (ram_wlast),
        .ram_wvalid     (ram_wvalid),
        .ram_wready     (ram_wready),
        .ram_bresp      (ram_bresp),
        .ram_bvalid     (ram_bvalid),
        .ram_bready     (ram_bready),
        .ram_araddr     (ram_araddr),
        .ram_arlen      (ram_arlen),
        .ram_arsize     (ram_arsize),
        .ram_arburst    (ram_arburst),
        .ram_arvalid    (ram_arvalid),
        .ram_arready    (ram_arready),
        .ram_rdata      (ram_rdata),
        .ram_rresp      (ram_rresp),
        .ram_rlast      (ram_rlast),
        .ram_rvalid     (ram_rvalid),
        .ram_rready     (ram_rready)
    );

    npu_accel_axi u_npu (
        .clk               (clk),
        .rst_n             (resetn),
        .s_axil_awaddr     (npu_s_awaddr),
        .s_axil_awvalid    (npu_s_awvalid),
        .s_axil_awready    (npu_s_awready),
        .s_axil_wdata      (npu_s_wdata),
        .s_axil_wstrb      (npu_s_wstrb),
        .s_axil_wvalid     (npu_s_wvalid),
        .s_axil_wready     (npu_s_wready),
        .s_axil_bresp      (npu_s_bresp),
        .s_axil_bvalid     (npu_s_bvalid),
        .s_axil_bready     (npu_s_bready),
        .s_axil_araddr     (npu_s_araddr),
        .s_axil_arvalid    (npu_s_arvalid),
        .s_axil_arready    (npu_s_arready),
        .s_axil_rdata      (npu_s_rdata),
        .s_axil_rresp      (npu_s_rresp),
        .s_axil_rvalid     (npu_s_rvalid),
        .s_axil_rready     (npu_s_rready),
        .m_axi_awaddr      (npu_m_awaddr),
        .m_axi_awlen       (npu_m_awlen),
        .m_axi_awsize      (npu_m_awsize),
        .m_axi_awburst     (npu_m_awburst),
        .m_axi_awvalid     (npu_m_awvalid),
        .m_axi_awready     (npu_m_awready),
        .m_axi_wdata       (npu_m_wdata),
        .m_axi_wstrb       (npu_m_wstrb),
        .m_axi_wlast       (npu_m_wlast),
        .m_axi_wvalid      (npu_m_wvalid),
        .m_axi_wready      (npu_m_wready),
        .m_axi_bresp       (npu_m_bresp),
        .m_axi_bvalid      (npu_m_bvalid),
        .m_axi_bready      (npu_m_bready),
        .m_axi_araddr      (npu_m_araddr),
        .m_axi_arlen       (npu_m_arlen),
        .m_axi_arsize      (npu_m_arsize),
        .m_axi_arburst     (npu_m_arburst),
        .m_axi_arvalid     (npu_m_arvalid),
        .m_axi_arready     (npu_m_arready),
        .m_axi_rdata       (npu_m_rdata),
        .m_axi_rresp       (npu_m_rresp),
        .m_axi_rlast       (npu_m_rlast),
        .m_axi_rvalid      (npu_m_rvalid),
        .m_axi_rready      (npu_m_rready),
        .irq               (npu_irq),
        .array_clk_en      (npu_array_clk_en),
        .dma_active_cycles (dma_active_cycles),
        .dma_data_cycles   (dma_data_cycles),
        .dma_read_beats    (dma_read_beats),
        .dma_write_beats   (dma_write_beats)
    );

`ifdef FPGA_USE_AXI_BRAM
    axi_bram #(
        .INIT_FILE(SRAM_INIT_FILE)
    ) u_sram (
`else
    axi_ram #(
        .INIT_FILE(SRAM_INIT_FILE)
    ) u_sram (
`endif
        .clk              (clk),
        .rst_n            (resetn),
        .s_axi_awaddr     (ram_awaddr),
        .s_axi_awlen      (ram_awlen),
        .s_axi_awsize     (ram_awsize),
        .s_axi_awburst    (ram_awburst),
        .s_axi_awvalid    (ram_awvalid),
        .s_axi_awready    (ram_awready),
        .s_axi_wdata      (ram_wdata),
        .s_axi_wstrb      (ram_wstrb),
        .s_axi_wlast      (ram_wlast),
        .s_axi_wvalid     (ram_wvalid),
        .s_axi_wready     (ram_wready),
        .s_axi_bresp      (ram_bresp),
        .s_axi_bvalid     (ram_bvalid),
        .s_axi_bready     (ram_bready),
        .s_axi_araddr     (ram_araddr),
        .s_axi_arlen      (ram_arlen),
        .s_axi_arsize     (ram_arsize),
        .s_axi_arburst    (ram_arburst),
        .s_axi_arvalid    (ram_arvalid),
        .s_axi_arready    (ram_arready),
        .s_axi_rdata      (ram_rdata),
        .s_axi_rresp      (ram_rresp),
        .s_axi_rlast      (ram_rlast),
        .s_axi_rvalid     (ram_rvalid),
        .s_axi_rready     (ram_rready),
        .write_beat_count (ram_write_beats),
        .read_beat_count  (ram_read_beats),
        .last_awaddr      (ram_last_awaddr),
        .last_araddr      (ram_last_araddr)
    );
endmodule

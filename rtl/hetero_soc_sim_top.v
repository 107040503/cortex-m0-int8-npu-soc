`timescale 1ns/1ps

module hetero_soc_sim_top (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [31:0]  s_axil_awaddr,
    input  wire         s_axil_awvalid,
    output wire         s_axil_awready,
    input  wire [31:0]  s_axil_wdata,
    input  wire [3:0]   s_axil_wstrb,
    input  wire         s_axil_wvalid,
    output wire         s_axil_wready,
    output wire [1:0]   s_axil_bresp,
    output wire         s_axil_bvalid,
    input  wire         s_axil_bready,

    input  wire [31:0]  s_axil_araddr,
    input  wire         s_axil_arvalid,
    output wire         s_axil_arready,
    output wire [31:0]  s_axil_rdata,
    output wire [1:0]   s_axil_rresp,
    output wire         s_axil_rvalid,
    input  wire         s_axil_rready,

    output wire         npu_irq,
    output wire         npu_array_clk_en,
    output wire [31:0]  ram_write_beats,
    output wire [31:0]  ram_read_beats,
    output wire [31:0]  ram_last_awaddr,
    output wire [31:0]  ram_last_araddr
);
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

    wire [31:0] dma_active_cycles;
    wire [31:0] dma_data_cycles;
    wire [31:0] dma_read_beats;
    wire [31:0] dma_write_beats;

    npu_accel_axi u_npu (
        .clk               (clk),
        .rst_n             (rst_n),
        .s_axil_awaddr     (s_axil_awaddr),
        .s_axil_awvalid    (s_axil_awvalid),
        .s_axil_awready    (s_axil_awready),
        .s_axil_wdata      (s_axil_wdata),
        .s_axil_wstrb      (s_axil_wstrb),
        .s_axil_wvalid     (s_axil_wvalid),
        .s_axil_wready     (s_axil_wready),
        .s_axil_bresp      (s_axil_bresp),
        .s_axil_bvalid     (s_axil_bvalid),
        .s_axil_bready     (s_axil_bready),
        .s_axil_araddr     (s_axil_araddr),
        .s_axil_arvalid    (s_axil_arvalid),
        .s_axil_arready    (s_axil_arready),
        .s_axil_rdata      (s_axil_rdata),
        .s_axil_rresp      (s_axil_rresp),
        .s_axil_rvalid     (s_axil_rvalid),
        .s_axil_rready     (s_axil_rready),
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

    axi_ram u_sram (
        .clk              (clk),
        .rst_n            (rst_n),
        .s_axi_awaddr     (npu_m_awaddr),
        .s_axi_awlen      (npu_m_awlen),
        .s_axi_awsize     (npu_m_awsize),
        .s_axi_awburst    (npu_m_awburst),
        .s_axi_awvalid    (npu_m_awvalid),
        .s_axi_awready    (npu_m_awready),
        .s_axi_wdata      (npu_m_wdata),
        .s_axi_wstrb      (npu_m_wstrb),
        .s_axi_wlast      (npu_m_wlast),
        .s_axi_wvalid     (npu_m_wvalid),
        .s_axi_wready     (npu_m_wready),
        .s_axi_bresp      (npu_m_bresp),
        .s_axi_bvalid     (npu_m_bvalid),
        .s_axi_bready     (npu_m_bready),
        .s_axi_araddr     (npu_m_araddr),
        .s_axi_arlen      (npu_m_arlen),
        .s_axi_arsize     (npu_m_arsize),
        .s_axi_arburst    (npu_m_arburst),
        .s_axi_arvalid    (npu_m_arvalid),
        .s_axi_arready    (npu_m_arready),
        .s_axi_rdata      (npu_m_rdata),
        .s_axi_rresp      (npu_m_rresp),
        .s_axi_rlast      (npu_m_rlast),
        .s_axi_rvalid     (npu_m_rvalid),
        .s_axi_rready     (npu_m_rready),
        .write_beat_count (ram_write_beats),
        .read_beat_count  (ram_read_beats),
        .last_awaddr      (ram_last_awaddr),
        .last_araddr      (ram_last_araddr)
    );
endmodule

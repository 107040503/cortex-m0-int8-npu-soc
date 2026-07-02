`timescale 1ns/1ps

module axi_shared_interconnect #(
    parameter NPU_BASE = 32'h1000_0000
) (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [31:0]  cpu_awaddr,
    input  wire         cpu_awvalid,
    output wire         cpu_awready,
    input  wire [31:0]  cpu_wdata,
    input  wire [3:0]   cpu_wstrb,
    input  wire         cpu_wvalid,
    output wire         cpu_wready,
    output wire [1:0]   cpu_bresp,
    output wire         cpu_bvalid,
    input  wire         cpu_bready,
    input  wire [31:0]  cpu_araddr,
    input  wire         cpu_arvalid,
    output wire         cpu_arready,
    output wire [31:0]  cpu_rdata,
    output wire [1:0]   cpu_rresp,
    output wire         cpu_rvalid,
    input  wire         cpu_rready,

    output wire [31:0]  npu_s_awaddr,
    output wire         npu_s_awvalid,
    input  wire         npu_s_awready,
    output wire [31:0]  npu_s_wdata,
    output wire [3:0]   npu_s_wstrb,
    output wire         npu_s_wvalid,
    input  wire         npu_s_wready,
    input  wire [1:0]   npu_s_bresp,
    input  wire         npu_s_bvalid,
    output wire         npu_s_bready,
    output wire [31:0]  npu_s_araddr,
    output wire         npu_s_arvalid,
    input  wire         npu_s_arready,
    input  wire [31:0]  npu_s_rdata,
    input  wire [1:0]   npu_s_rresp,
    input  wire         npu_s_rvalid,
    output wire         npu_s_rready,

    input  wire [31:0]  npu_m_awaddr,
    input  wire [7:0]   npu_m_awlen,
    input  wire [2:0]   npu_m_awsize,
    input  wire [1:0]   npu_m_awburst,
    input  wire         npu_m_awvalid,
    output wire         npu_m_awready,
    input  wire [31:0]  npu_m_wdata,
    input  wire [3:0]   npu_m_wstrb,
    input  wire         npu_m_wlast,
    input  wire         npu_m_wvalid,
    output wire         npu_m_wready,
    output wire [1:0]   npu_m_bresp,
    output wire         npu_m_bvalid,
    input  wire         npu_m_bready,
    input  wire [31:0]  npu_m_araddr,
    input  wire [7:0]   npu_m_arlen,
    input  wire [2:0]   npu_m_arsize,
    input  wire [1:0]   npu_m_arburst,
    input  wire         npu_m_arvalid,
    output wire         npu_m_arready,
    output wire [31:0]  npu_m_rdata,
    output wire [1:0]   npu_m_rresp,
    output wire         npu_m_rlast,
    output wire         npu_m_rvalid,
    input  wire         npu_m_rready,

    output wire [31:0]  ram_awaddr,
    output wire [7:0]   ram_awlen,
    output wire [2:0]   ram_awsize,
    output wire [1:0]   ram_awburst,
    output wire         ram_awvalid,
    input  wire         ram_awready,
    output wire [31:0]  ram_wdata,
    output wire [3:0]   ram_wstrb,
    output wire         ram_wlast,
    output wire         ram_wvalid,
    input  wire         ram_wready,
    input  wire [1:0]   ram_bresp,
    input  wire         ram_bvalid,
    output wire         ram_bready,
    output wire [31:0]  ram_araddr,
    output wire [7:0]   ram_arlen,
    output wire [2:0]   ram_arsize,
    output wire [1:0]   ram_arburst,
    output wire         ram_arvalid,
    input  wire         ram_arready,
    input  wire [31:0]  ram_rdata,
    input  wire [1:0]   ram_rresp,
    input  wire         ram_rlast,
    input  wire         ram_rvalid,
    output wire         ram_rready
);
    localparam WR_IDLE = 2'd0;
    localparam WR_AW   = 2'd1;
    localparam WR_W    = 2'd2;
    localparam WR_RESP = 2'd3;

    localparam RD_IDLE = 2'd0;
    localparam RD_AR   = 2'd1;
    localparam RD_RESP = 2'd2;

    wire cpu_wr_to_npu = (cpu_awaddr[31:16] == NPU_BASE[31:16]);
    wire cpu_rd_to_npu = (cpu_araddr[31:16] == NPU_BASE[31:16]);
    wire npu_dma_req =
        npu_m_awvalid || npu_m_wvalid || npu_m_bready ||
        npu_m_arvalid || npu_m_rready;

    reg        cpu_wr_pending_npu;
    reg        cpu_rd_pending_npu;

    reg [1:0]  wr_state;
    reg [31:0] wr_addr;
    reg [31:0] wr_data;
    reg [3:0]  wr_strb;
    reg [1:0]  wr_resp;
    reg [1:0]  rd_state;
    reg [31:0] rd_addr;
    reg [31:0] rd_data;
    reg [1:0]  rd_resp;

    wire cpu_ram_busy = (wr_state != WR_IDLE) || (rd_state != RD_IDLE);
    wire npu_dma_grant = !cpu_ram_busy && npu_dma_req;
    wire cpu_ram_can_accept = !cpu_ram_busy && !npu_dma_req;

    wire cpu_wr_accept_npu = !cpu_wr_pending_npu && cpu_wr_to_npu &&
        cpu_awvalid && cpu_wvalid && npu_s_awready && npu_s_wready;
    wire cpu_rd_accept_npu = !cpu_rd_pending_npu && cpu_rd_to_npu &&
        cpu_arvalid && npu_s_arready;
    wire cpu_wr_accept_ram = cpu_ram_can_accept && !cpu_wr_to_npu &&
        cpu_awvalid && cpu_wvalid;
    wire cpu_rd_accept_ram = cpu_ram_can_accept && !cpu_rd_to_npu &&
        cpu_arvalid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_wr_pending_npu <= 1'b0;
            cpu_rd_pending_npu <= 1'b0;
        end else begin
            if (cpu_wr_accept_npu) begin
                cpu_wr_pending_npu <= 1'b1;
            end
            if (cpu_wr_pending_npu && npu_s_bvalid && npu_s_bready) begin
                cpu_wr_pending_npu <= 1'b0;
            end

            if (cpu_rd_accept_npu) begin
                cpu_rd_pending_npu <= 1'b1;
            end
            if (cpu_rd_pending_npu && npu_s_rvalid && npu_s_rready) begin
                cpu_rd_pending_npu <= 1'b0;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state <= WR_IDLE;
            wr_addr  <= 32'd0;
            wr_data  <= 32'd0;
            wr_strb  <= 4'd0;
            wr_resp  <= 2'b00;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    if (cpu_wr_accept_ram) begin
                        wr_addr  <= cpu_awaddr;
                        wr_data  <= cpu_wdata;
                        wr_strb  <= cpu_wstrb;
                        wr_state <= WR_AW;
                    end
                end

                WR_AW: begin
                    if (ram_awready) begin
                        wr_state <= WR_W;
                    end
                end

                WR_W: begin
                    if (ram_wready) begin
                        wr_state <= WR_RESP;
                    end
                end

                WR_RESP: begin
                    if (ram_bvalid) begin
                        wr_resp <= ram_bresp;
                    end
                    if (ram_bvalid && cpu_bready) begin
                        wr_state <= WR_IDLE;
                    end
                end

                default: begin
                    wr_state <= WR_IDLE;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state <= RD_IDLE;
            rd_addr  <= 32'd0;
            rd_data  <= 32'd0;
            rd_resp  <= 2'b00;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    if (cpu_rd_accept_ram) begin
                        rd_addr  <= cpu_araddr;
                        rd_state <= RD_AR;
                    end
                end

                RD_AR: begin
                    if (ram_arready) begin
                        rd_state <= RD_RESP;
                    end
                end

                RD_RESP: begin
                    if (ram_rvalid) begin
                        rd_data <= ram_rdata;
                        rd_resp <= ram_rresp;
                    end
                    if (ram_rvalid && cpu_rready) begin
                        rd_state <= RD_IDLE;
                    end
                end

                default: begin
                    rd_state <= RD_IDLE;
                end
            endcase
        end
    end

    assign npu_s_awaddr  = cpu_awaddr - NPU_BASE;
    assign npu_s_awvalid = !cpu_wr_pending_npu && cpu_wr_to_npu && cpu_awvalid && cpu_wvalid;
    assign npu_s_wdata   = cpu_wdata;
    assign npu_s_wstrb   = cpu_wstrb;
    assign npu_s_wvalid  = !cpu_wr_pending_npu && cpu_wr_to_npu && cpu_awvalid && cpu_wvalid;
    assign npu_s_bready  = cpu_wr_pending_npu && cpu_bready;
    assign npu_s_araddr  = cpu_araddr - NPU_BASE;
    assign npu_s_arvalid = !cpu_rd_pending_npu && cpu_rd_to_npu && cpu_arvalid;
    assign npu_s_rready  = cpu_rd_pending_npu && cpu_rready;

    assign cpu_awready = cpu_wr_to_npu
        ? (!cpu_wr_pending_npu && cpu_wvalid && npu_s_awready && npu_s_wready)
        : (cpu_ram_can_accept && cpu_wvalid);
    assign cpu_wready = cpu_wr_to_npu
        ? (!cpu_wr_pending_npu && cpu_awvalid && npu_s_awready && npu_s_wready)
        : (cpu_ram_can_accept && cpu_awvalid);
    assign cpu_bvalid = cpu_wr_pending_npu ? npu_s_bvalid :
                        (wr_state == WR_RESP) ? ram_bvalid : 1'b0;
    assign cpu_bresp  = cpu_wr_pending_npu ? npu_s_bresp :
                        (wr_state == WR_RESP) ? ram_bresp : wr_resp;

    assign cpu_arready = cpu_rd_to_npu
        ? (!cpu_rd_pending_npu && npu_s_arready)
        : cpu_ram_can_accept;
    assign cpu_rvalid = cpu_rd_pending_npu ? npu_s_rvalid :
                        (rd_state == RD_RESP) ? ram_rvalid : 1'b0;
    assign cpu_rdata  = cpu_rd_pending_npu ? npu_s_rdata :
                        (rd_state == RD_RESP) ? ram_rdata : rd_data;
    assign cpu_rresp  = cpu_rd_pending_npu ? npu_s_rresp :
                        (rd_state == RD_RESP) ? ram_rresp : rd_resp;

    assign ram_awaddr  = npu_dma_grant ? npu_m_awaddr  : wr_addr;
    assign ram_awlen   = npu_dma_grant ? npu_m_awlen   : 8'd0;
    assign ram_awsize  = npu_dma_grant ? npu_m_awsize  : 3'd2;
    assign ram_awburst = npu_dma_grant ? npu_m_awburst : 2'b01;
    assign ram_awvalid = npu_dma_grant ? npu_m_awvalid : (wr_state == WR_AW);
    assign ram_wdata   = npu_dma_grant ? npu_m_wdata   : wr_data;
    assign ram_wstrb   = npu_dma_grant ? npu_m_wstrb   : wr_strb;
    assign ram_wlast   = npu_dma_grant ? npu_m_wlast   : 1'b1;
    assign ram_wvalid  = npu_dma_grant ? npu_m_wvalid  : (wr_state == WR_W);
    assign ram_bready  = npu_dma_grant ? npu_m_bready  : ((wr_state == WR_RESP) && cpu_bready);

    assign ram_araddr  = npu_dma_grant ? npu_m_araddr  : rd_addr;
    assign ram_arlen   = npu_dma_grant ? npu_m_arlen   : 8'd0;
    assign ram_arsize  = npu_dma_grant ? npu_m_arsize  : 3'd2;
    assign ram_arburst = npu_dma_grant ? npu_m_arburst : 2'b01;
    assign ram_arvalid = npu_dma_grant ? npu_m_arvalid : (rd_state == RD_AR);
    assign ram_rready  = npu_dma_grant ? npu_m_rready  : ((rd_state == RD_RESP) && cpu_rready);

    assign npu_m_awready = npu_dma_grant ? ram_awready : 1'b0;
    assign npu_m_wready  = npu_dma_grant ? ram_wready  : 1'b0;
    assign npu_m_bresp   = ram_bresp;
    assign npu_m_bvalid  = npu_dma_grant ? ram_bvalid  : 1'b0;
    assign npu_m_arready = npu_dma_grant ? ram_arready : 1'b0;
    assign npu_m_rdata   = ram_rdata;
    assign npu_m_rresp   = ram_rresp;
    assign npu_m_rlast   = ram_rlast;
    assign npu_m_rvalid  = npu_dma_grant ? ram_rvalid  : 1'b0;
endmodule

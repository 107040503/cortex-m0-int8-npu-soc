`timescale 1ns/1ps

module axil_cdc_bridge (
    input  wire        s_clk,
    input  wire        s_rst_n,
    input  wire [31:0] s_axil_awaddr,
    input  wire        s_axil_awvalid,
    output wire        s_axil_awready,
    input  wire [31:0] s_axil_wdata,
    input  wire [3:0]  s_axil_wstrb,
    input  wire        s_axil_wvalid,
    output wire        s_axil_wready,
    output reg  [1:0]  s_axil_bresp,
    output reg         s_axil_bvalid,
    input  wire        s_axil_bready,
    input  wire [31:0] s_axil_araddr,
    input  wire        s_axil_arvalid,
    output wire        s_axil_arready,
    output reg  [31:0] s_axil_rdata,
    output reg  [1:0]  s_axil_rresp,
    output reg         s_axil_rvalid,
    input  wire        s_axil_rready,

    input  wire        m_clk,
    input  wire        m_rst_n,
    output reg  [31:0] m_axil_awaddr,
    output reg         m_axil_awvalid,
    input  wire        m_axil_awready,
    output reg  [31:0] m_axil_wdata,
    output reg  [3:0]  m_axil_wstrb,
    output reg         m_axil_wvalid,
    input  wire        m_axil_wready,
    input  wire [1:0]  m_axil_bresp,
    input  wire        m_axil_bvalid,
    output reg         m_axil_bready,
    output reg  [31:0] m_axil_araddr,
    output reg         m_axil_arvalid,
    input  wire        m_axil_arready,
    input  wire [31:0] m_axil_rdata,
    input  wire [1:0]  m_axil_rresp,
    input  wire        m_axil_rvalid,
    output reg         m_axil_rready
);
    localparam WR_IDLE = 2'd0;
    localparam WR_ADDR = 2'd1;
    localparam WR_RESP = 2'd2;

    localparam RD_IDLE = 2'd0;
    localparam RD_ADDR = 2'd1;
    localparam RD_RESP = 2'd2;

    reg        s_wr_busy;
    reg        s_wr_req_toggle;
    reg        s_wr_done_meta;
    reg        s_wr_done_sync;
    reg        s_wr_done_seen;
    reg [31:0] s_wr_addr_hold;
    reg [31:0] s_wr_data_hold;
    reg [3:0]  s_wr_strb_hold;

    reg        s_rd_busy;
    reg        s_rd_req_toggle;
    reg        s_rd_done_meta;
    reg        s_rd_done_sync;
    reg        s_rd_done_seen;
    reg [31:0] s_rd_addr_hold;

    reg        m_wr_req_meta;
    reg        m_wr_req_sync;
    reg        m_wr_req_seen;
    reg        m_wr_done_toggle;
    reg [1:0]  m_wr_resp_hold;
    reg [1:0]  m_wr_state;

    reg        m_rd_req_meta;
    reg        m_rd_req_sync;
    reg        m_rd_req_seen;
    reg        m_rd_done_toggle;
    reg [31:0] m_rd_data_hold;
    reg [1:0]  m_rd_resp_hold;
    reg [1:0]  m_rd_state;

    assign s_axil_awready = !s_wr_busy && !s_axil_bvalid;
    assign s_axil_wready  = !s_wr_busy && !s_axil_bvalid;
    assign s_axil_arready = !s_rd_busy && !s_axil_rvalid;

    always @(posedge s_clk or negedge s_rst_n) begin
        if (!s_rst_n) begin
            s_wr_busy       <= 1'b0;
            s_wr_req_toggle <= 1'b0;
            s_wr_done_meta  <= 1'b0;
            s_wr_done_sync  <= 1'b0;
            s_wr_done_seen  <= 1'b0;
            s_wr_addr_hold  <= 32'd0;
            s_wr_data_hold  <= 32'd0;
            s_wr_strb_hold  <= 4'd0;
            s_axil_bresp    <= 2'b00;
            s_axil_bvalid   <= 1'b0;
        end else begin
            s_wr_done_meta <= m_wr_done_toggle;
            s_wr_done_sync <= s_wr_done_meta;

            if (!s_wr_busy && !s_axil_bvalid && s_axil_awvalid && s_axil_wvalid) begin
                s_wr_addr_hold  <= s_axil_awaddr;
                s_wr_data_hold  <= s_axil_wdata;
                s_wr_strb_hold  <= s_axil_wstrb;
                s_wr_busy       <= 1'b1;
                s_wr_req_toggle <= ~s_wr_req_toggle;
            end

            if (s_wr_busy && (s_wr_done_sync != s_wr_done_seen)) begin
                s_wr_done_seen <= s_wr_done_sync;
                s_axil_bresp   <= m_wr_resp_hold;
                s_axil_bvalid  <= 1'b1;
            end

            if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
                s_wr_busy     <= 1'b0;
            end
        end
    end

    always @(posedge s_clk or negedge s_rst_n) begin
        if (!s_rst_n) begin
            s_rd_busy       <= 1'b0;
            s_rd_req_toggle <= 1'b0;
            s_rd_done_meta  <= 1'b0;
            s_rd_done_sync  <= 1'b0;
            s_rd_done_seen  <= 1'b0;
            s_rd_addr_hold  <= 32'd0;
            s_axil_rdata    <= 32'd0;
            s_axil_rresp    <= 2'b00;
            s_axil_rvalid   <= 1'b0;
        end else begin
            s_rd_done_meta <= m_rd_done_toggle;
            s_rd_done_sync <= s_rd_done_meta;

            if (!s_rd_busy && !s_axil_rvalid && s_axil_arvalid) begin
                s_rd_addr_hold  <= s_axil_araddr;
                s_rd_busy       <= 1'b1;
                s_rd_req_toggle <= ~s_rd_req_toggle;
            end

            if (s_rd_busy && (s_rd_done_sync != s_rd_done_seen)) begin
                s_rd_done_seen <= s_rd_done_sync;
                s_axil_rdata   <= m_rd_data_hold;
                s_axil_rresp   <= m_rd_resp_hold;
                s_axil_rvalid  <= 1'b1;
            end

            if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
                s_rd_busy     <= 1'b0;
            end
        end
    end

    always @(posedge m_clk or negedge m_rst_n) begin
        if (!m_rst_n) begin
            m_wr_req_meta   <= 1'b0;
            m_wr_req_sync   <= 1'b0;
            m_wr_req_seen   <= 1'b0;
            m_wr_done_toggle <= 1'b0;
            m_wr_resp_hold  <= 2'b00;
            m_wr_state      <= WR_IDLE;
            m_axil_awaddr   <= 32'd0;
            m_axil_awvalid  <= 1'b0;
            m_axil_wdata    <= 32'd0;
            m_axil_wstrb    <= 4'd0;
            m_axil_wvalid   <= 1'b0;
            m_axil_bready   <= 1'b0;
        end else begin
            m_wr_req_meta <= s_wr_req_toggle;
            m_wr_req_sync <= m_wr_req_meta;

            case (m_wr_state)
                WR_IDLE: begin
                    m_axil_awvalid <= 1'b0;
                    m_axil_wvalid  <= 1'b0;
                    m_axil_bready  <= 1'b0;
                    if (m_wr_req_sync != m_wr_req_seen) begin
                        m_wr_req_seen  <= m_wr_req_sync;
                        m_axil_awaddr  <= s_wr_addr_hold;
                        m_axil_wdata   <= s_wr_data_hold;
                        m_axil_wstrb   <= s_wr_strb_hold;
                        m_axil_awvalid <= 1'b1;
                        m_axil_wvalid  <= 1'b1;
                        m_wr_state     <= WR_ADDR;
                    end
                end

                WR_ADDR: begin
                    if (m_axil_awvalid && m_axil_awready) begin
                        m_axil_awvalid <= 1'b0;
                    end
                    if (m_axil_wvalid && m_axil_wready) begin
                        m_axil_wvalid <= 1'b0;
                    end
                    if ((!m_axil_awvalid || m_axil_awready) &&
                        (!m_axil_wvalid || m_axil_wready)) begin
                        m_axil_bready <= 1'b1;
                        m_wr_state    <= WR_RESP;
                    end
                end

                WR_RESP: begin
                    if (m_axil_bvalid) begin
                        m_wr_resp_hold   <= m_axil_bresp;
                        m_axil_bready    <= 1'b0;
                        m_wr_done_toggle <= ~m_wr_done_toggle;
                        m_wr_state       <= WR_IDLE;
                    end
                end

                default: begin
                    m_wr_state <= WR_IDLE;
                end
            endcase
        end
    end

    always @(posedge m_clk or negedge m_rst_n) begin
        if (!m_rst_n) begin
            m_rd_req_meta    <= 1'b0;
            m_rd_req_sync    <= 1'b0;
            m_rd_req_seen    <= 1'b0;
            m_rd_done_toggle <= 1'b0;
            m_rd_data_hold   <= 32'd0;
            m_rd_resp_hold   <= 2'b00;
            m_rd_state       <= RD_IDLE;
            m_axil_araddr    <= 32'd0;
            m_axil_arvalid   <= 1'b0;
            m_axil_rready    <= 1'b0;
        end else begin
            m_rd_req_meta <= s_rd_req_toggle;
            m_rd_req_sync <= m_rd_req_meta;

            case (m_rd_state)
                RD_IDLE: begin
                    m_axil_arvalid <= 1'b0;
                    m_axil_rready  <= 1'b0;
                    if (m_rd_req_sync != m_rd_req_seen) begin
                        m_rd_req_seen  <= m_rd_req_sync;
                        m_axil_araddr  <= s_rd_addr_hold;
                        m_axil_arvalid <= 1'b1;
                        m_rd_state     <= RD_ADDR;
                    end
                end

                RD_ADDR: begin
                    if (m_axil_arvalid && m_axil_arready) begin
                        m_axil_arvalid <= 1'b0;
                        m_axil_rready  <= 1'b1;
                        m_rd_state     <= RD_RESP;
                    end
                end

                RD_RESP: begin
                    if (m_axil_rvalid) begin
                        m_rd_data_hold   <= m_axil_rdata;
                        m_rd_resp_hold   <= m_axil_rresp;
                        m_axil_rready    <= 1'b0;
                        m_rd_done_toggle <= ~m_rd_done_toggle;
                        m_rd_state       <= RD_IDLE;
                    end
                end

                default: begin
                    m_rd_state <= RD_IDLE;
                end
            endcase
        end
    end
endmodule

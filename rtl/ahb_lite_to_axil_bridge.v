`timescale 1ns/1ps

module ahb_lite_to_axil_bridge (
    input  wire        hclk,
    input  wire        hresetn,

    input  wire [31:0] haddr,
    input  wire [1:0]  htrans,
    input  wire        hwrite,
    input  wire [2:0]  hsize,
    input  wire [31:0] hwdata,
    output wire [31:0] hrdata,
    output wire        hreadyout,
    output wire        hresp,

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
    localparam ST_IDLE      = 3'd0;
    localparam ST_W_CAPTURE = 3'd1;
    localparam ST_W_ADDR    = 3'd2;
    localparam ST_W_RESP    = 3'd3;
    localparam ST_R_ADDR    = 3'd4;
    localparam ST_R_DATA    = 3'd5;

    reg [2:0]  state;
    reg [31:0] read_data;
    reg        error_resp;
    reg [31:0] latched_haddr;
    reg [2:0]  latched_hsize;

    wire ahb_valid = htrans[1];
    wire ahb_done = (state == ST_W_RESP && m_axil_bvalid) ||
                    (state == ST_R_DATA && m_axil_rvalid);
    wire ahb_accept = (state == ST_IDLE || ahb_done) && ahb_valid;

    assign hrdata = (state == ST_R_DATA && m_axil_rvalid) ? m_axil_rdata : read_data;
    assign hreadyout = (state == ST_IDLE) ||
                       ahb_done;
    assign hresp = error_resp;

    function [3:0] ahb_wstrb;
        input [2:0] size;
        input [1:0] addr_lsb;
        begin
            case (size)
                3'd0: begin
                    ahb_wstrb = 4'b0001 << addr_lsb;
                end
                3'd1: begin
                    ahb_wstrb = addr_lsb[1] ? 4'b1100 : 4'b0011;
                end
                default: begin
                    ahb_wstrb = 4'b1111;
                end
            endcase
        end
    endfunction

    task start_accepted_transfer;
        begin
            latched_haddr <= haddr;
            latched_hsize <= hsize;
            error_resp    <= 1'b0;
            if (hwrite) begin
                state <= ST_W_CAPTURE;
            end else begin
                m_axil_araddr  <= haddr;
                m_axil_arvalid <= 1'b1;
                state          <= ST_R_ADDR;
            end
        end
    endtask

    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            state          <= ST_IDLE;
            read_data      <= 32'd0;
            error_resp     <= 1'b0;
            latched_haddr  <= 32'd0;
            latched_hsize  <= 3'd2;
            m_axil_awaddr  <= 32'd0;
            m_axil_awvalid <= 1'b0;
            m_axil_wdata   <= 32'd0;
            m_axil_wstrb   <= 4'h0;
            m_axil_wvalid  <= 1'b0;
            m_axil_bready  <= 1'b0;
            m_axil_araddr  <= 32'd0;
            m_axil_arvalid <= 1'b0;
            m_axil_rready  <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    error_resp     <= 1'b0;
                    m_axil_awvalid <= 1'b0;
                    m_axil_wvalid  <= 1'b0;
                    m_axil_bready  <= 1'b0;
                    m_axil_arvalid <= 1'b0;
                    m_axil_rready  <= 1'b0;

                    if (ahb_accept) begin
                        start_accepted_transfer();
                    end
                end

                ST_W_CAPTURE: begin
                    m_axil_awaddr  <= latched_haddr;
                    m_axil_awvalid <= 1'b1;
                    m_axil_wdata   <= hwdata;
                    m_axil_wstrb   <= ahb_wstrb(latched_hsize, latched_haddr[1:0]);
                    m_axil_wvalid  <= 1'b1;
                    state          <= ST_W_ADDR;
                end

                ST_W_ADDR: begin
                    if ((!m_axil_awvalid || m_axil_awready) &&
                        (!m_axil_wvalid || m_axil_wready)) begin
                        m_axil_awvalid <= 1'b0;
                        m_axil_wvalid <= 1'b0;
                        m_axil_bready <= 1'b1;
                        state         <= ST_W_RESP;
                    end else begin
                        if (m_axil_awvalid && m_axil_awready) begin
                            m_axil_awvalid <= 1'b0;
                        end
                        if (m_axil_wvalid && m_axil_wready) begin
                            m_axil_wvalid <= 1'b0;
                        end
                    end
                end

                ST_W_RESP: begin
                    if (m_axil_bvalid) begin
                        error_resp    <= |m_axil_bresp;
                        m_axil_bready <= 1'b0;
                        if (ahb_valid) begin
                            start_accepted_transfer();
                        end else begin
                            state <= ST_IDLE;
                        end
                    end
                end

                ST_R_ADDR: begin
                    if (m_axil_arvalid && m_axil_arready) begin
                        m_axil_arvalid <= 1'b0;
                        m_axil_rready  <= 1'b1;
                        state          <= ST_R_DATA;
                    end
                end

                ST_R_DATA: begin
                    if (m_axil_rvalid) begin
                        read_data     <= m_axil_rdata;
                        error_resp    <= |m_axil_rresp;
                        m_axil_rready <= 1'b0;
                        if (ahb_valid) begin
                            start_accepted_transfer();
                        end else begin
                            state <= ST_IDLE;
                        end
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule

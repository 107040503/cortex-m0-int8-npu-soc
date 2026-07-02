`timescale 1ns/1ps

module cortex_m0_ahb_stub #(
    parameter A_BASE = 32'h0000_0100,
    parameter B_BASE = 32'h0000_0200,
    parameter C_BASE = 32'h0000_0300,
    parameter NPU_BASE = 32'h1000_0000
) (
    input  wire        hclk,
    input  wire        hresetn,
    output reg  [31:0] haddr,
    output reg  [1:0]  htrans,
    output reg         hwrite,
    output reg  [2:0]  hsize,
    output reg  [31:0] hwdata,
    input  wire [31:0] hrdata,
    input  wire        hready,
    input  wire        hresp,
    input  wire        irq,
    output reg         halted
);
    localparam HT_IDLE   = 2'b00;
    localparam HT_NONSEQ = 2'b10;

    localparam ST_CFG_A      = 5'd0;
    localparam ST_CFG_B      = 5'd1;
    localparam ST_CFG_C      = 5'd2;
    localparam ST_CFG_MASK   = 5'd3;
    localparam ST_CFG_DFS    = 5'd4;
    localparam ST_CFG_PWR    = 5'd5;
    localparam ST_START      = 5'd6;
    localparam ST_POLL       = 5'd7;
    localparam ST_READ_PEAK  = 5'd8;
    localparam ST_READ_UTILA = 5'd9;
    localparam ST_READ_UTILD = 5'd10;
    localparam ST_DONE       = 5'd11;

    reg [4:0] state;
    reg [4:0] pending_next_state;
    reg       bus_busy;
    reg       bus_read;
    reg       seen_wait;
    reg [31:0] last_peak_mtops;
    reg [31:0] last_dma_active;
    reg [31:0] last_dma_data;

    task issue_write;
        input [31:0] addr;
        input [31:0] data;
        input [4:0]  next_state;
        begin
            haddr              <= addr;
            hwdata             <= data;
            hwrite             <= 1'b1;
            htrans             <= HT_NONSEQ;
            bus_busy           <= 1'b1;
            bus_read           <= 1'b0;
            seen_wait          <= 1'b0;
            pending_next_state <= next_state;
        end
    endtask

    task issue_read;
        input [31:0] addr;
        begin
            haddr              <= addr;
            hwrite             <= 1'b0;
            htrans             <= HT_NONSEQ;
            bus_busy           <= 1'b1;
            bus_read           <= 1'b1;
            seen_wait          <= 1'b0;
            pending_next_state <= state;
        end
    endtask

    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            state              <= ST_CFG_A;
            pending_next_state <= ST_CFG_A;
            bus_busy           <= 1'b0;
            bus_read           <= 1'b0;
            seen_wait          <= 1'b0;
            haddr              <= 32'd0;
            htrans             <= HT_IDLE;
            hwrite             <= 1'b0;
            hsize              <= 3'd2;
            hwdata             <= 32'd0;
            halted             <= 1'b0;
            last_peak_mtops    <= 32'd0;
            last_dma_active    <= 32'd0;
            last_dma_data      <= 32'd0;
        end else begin
            if (bus_busy) begin
                htrans <= HT_IDLE;

                if (!hready) begin
                    seen_wait <= 1'b1;
                end

                if (seen_wait && hready) begin
                    bus_busy  <= 1'b0;
                    seen_wait <= 1'b0;

                    if (bus_read) begin
                        case (state)
                            ST_POLL: begin
                                if (hrdata[1] || irq) begin
                                    state <= ST_READ_PEAK;
                                end else begin
                                    state <= ST_POLL;
                                end
                            end

                            ST_READ_PEAK: begin
                                last_peak_mtops <= hrdata;
                                state <= ST_READ_UTILA;
                            end

                            ST_READ_UTILA: begin
                                last_dma_active <= hrdata;
                                state <= ST_READ_UTILD;
                            end

                            ST_READ_UTILD: begin
                                last_dma_data <= hrdata;
                                state <= ST_DONE;
                            end

                            default: begin
                                state <= pending_next_state;
                            end
                        endcase
                    end else begin
                        state <= pending_next_state;
                    end
                end
            end else begin
                htrans <= HT_IDLE;
                hwrite <= 1'b0;

                case (state)
                    ST_CFG_A: begin
                        halted <= 1'b0;
                        issue_write(NPU_BASE + 32'h08, A_BASE, ST_CFG_B);
                    end

                    ST_CFG_B: begin
                        issue_write(NPU_BASE + 32'h0c, B_BASE, ST_CFG_C);
                    end

                    ST_CFG_C: begin
                        issue_write(NPU_BASE + 32'h10, C_BASE, ST_CFG_MASK);
                    end

                    ST_CFG_MASK: begin
                        issue_write(NPU_BASE + 32'h14, 32'h0000_ffff, ST_CFG_DFS);
                    end

                    ST_CFG_DFS: begin
                        issue_write(NPU_BASE + 32'h2c, 32'h0000_0000, ST_CFG_PWR);
                    end

                    ST_CFG_PWR: begin
                        issue_write(NPU_BASE + 32'h30, 32'h0000_0001, ST_START);
                    end

                    ST_START: begin
                        issue_write(NPU_BASE + 32'h00, 32'h0000_0003, ST_POLL);
                    end

                    ST_POLL: begin
                        issue_read(NPU_BASE + 32'h04);
                    end

                    ST_READ_PEAK: begin
                        issue_read(NPU_BASE + 32'h34);
                    end

                    ST_READ_UTILA: begin
                        issue_read(NPU_BASE + 32'h1c);
                    end

                    ST_READ_UTILD: begin
                        issue_read(NPU_BASE + 32'h20);
                    end

                    ST_DONE: begin
                        halted <= 1'b1;
                    end

                    default: begin
                        state <= ST_CFG_A;
                    end
                endcase
            end
        end
    end
endmodule

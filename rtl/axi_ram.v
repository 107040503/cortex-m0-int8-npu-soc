`timescale 1ns/1ps

module axi_ram #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter DEPTH_WORDS = 4096
) (
    input  wire                     clk,
    input  wire                     rst_n,

    input  wire [31:0]              s_axi_awaddr,
    input  wire [7:0]               s_axi_awlen,
    input  wire [2:0]               s_axi_awsize,
    input  wire [1:0]               s_axi_awburst,
    input  wire                     s_axi_awvalid,
    output wire                     s_axi_awready,
    input  wire [DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                     s_axi_wlast,
    input  wire                     s_axi_wvalid,
    output wire                     s_axi_wready,
    output reg  [1:0]               s_axi_bresp,
    output reg                      s_axi_bvalid,
    input  wire                     s_axi_bready,

    input  wire [31:0]              s_axi_araddr,
    input  wire [7:0]               s_axi_arlen,
    input  wire [2:0]               s_axi_arsize,
    input  wire [1:0]               s_axi_arburst,
    input  wire                     s_axi_arvalid,
    output wire                     s_axi_arready,
    output reg  [DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]               s_axi_rresp,
    output reg                      s_axi_rlast,
    output reg                      s_axi_rvalid,
    input  wire                     s_axi_rready,

    output reg  [31:0]              write_beat_count,
    output reg  [31:0]              read_beat_count,
    output reg  [31:0]              last_awaddr,
    output reg  [31:0]              last_araddr
);
    localparam STRB_WIDTH = DATA_WIDTH/8;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH_WORDS-1];

    reg        wr_active;
    reg [31:0] wr_addr;
    reg [7:0]  wr_len;
    reg [7:0]  wr_count;

    reg        rd_active;
    reg [31:0] rd_addr;
    reg [7:0]  rd_len;
    reg [7:0]  rd_count;
    reg [31:0] rd_next_addr;

    wire [31:0] wr_word_addr = wr_addr[ADDR_WIDTH-1:2];
    wire [31:0] rd_word_addr = rd_addr[ADDR_WIDTH-1:2];

    assign s_axi_awready = !wr_active && !s_axi_bvalid;
    assign s_axi_wready  = wr_active;
    assign s_axi_arready = !rd_active && !s_axi_rvalid;

    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1) begin
            mem[i] = {DATA_WIDTH{1'b0}};
        end
    end

    integer byte_idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_active        <= 1'b0;
            wr_addr          <= 32'd0;
            wr_len           <= 8'd0;
            wr_count         <= 8'd0;
            s_axi_bresp      <= 2'b00;
            s_axi_bvalid     <= 1'b0;
            write_beat_count <= 32'd0;
            last_awaddr      <= 32'd0;
        end else begin
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (s_axi_awvalid && s_axi_awready) begin
                wr_active   <= 1'b1;
                wr_addr     <= s_axi_awaddr;
                wr_len      <= s_axi_awlen;
                wr_count    <= 8'd0;
                last_awaddr <= s_axi_awaddr;
            end

            if (s_axi_wvalid && s_axi_wready) begin
                for (byte_idx = 0; byte_idx < STRB_WIDTH; byte_idx = byte_idx + 1) begin
                    if (s_axi_wstrb[byte_idx]) begin
                        mem[wr_word_addr][byte_idx*8 +: 8] <= s_axi_wdata[byte_idx*8 +: 8];
                    end
                end

                write_beat_count <= write_beat_count + 32'd1;

                if (s_axi_wlast || wr_count == wr_len) begin
                    wr_active    <= 1'b0;
                    s_axi_bresp  <= 2'b00;
                    s_axi_bvalid <= 1'b1;
                end else begin
                    wr_count <= wr_count + 8'd1;
                    if (s_axi_awburst == 2'b01) begin
                        wr_addr <= wr_addr + (32'd1 << s_axi_awsize);
                    end
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_active       <= 1'b0;
            rd_addr         <= 32'd0;
            rd_len          <= 8'd0;
            rd_count        <= 8'd0;
            s_axi_rdata     <= {DATA_WIDTH{1'b0}};
            s_axi_rresp     <= 2'b00;
            s_axi_rlast     <= 1'b0;
            s_axi_rvalid    <= 1'b0;
            read_beat_count <= 32'd0;
            last_araddr     <= 32'd0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                rd_active   <= 1'b1;
                rd_addr     <= s_axi_araddr;
                rd_len      <= s_axi_arlen;
                rd_count    <= 8'd0;
                last_araddr <= s_axi_araddr;
                s_axi_rdata <= mem[s_axi_araddr[ADDR_WIDTH-1:2]];
                s_axi_rresp <= 2'b00;
                s_axi_rlast <= (s_axi_arlen == 8'd0);
                s_axi_rvalid <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                read_beat_count <= read_beat_count + 32'd1;

                if (s_axi_rlast) begin
                    s_axi_rvalid <= 1'b0;
                    s_axi_rlast  <= 1'b0;
                    rd_active    <= 1'b0;
                end else begin
                    rd_count <= rd_count + 8'd1;
                    if (s_axi_arburst == 2'b01) begin
                        rd_next_addr = rd_addr + (32'd1 << s_axi_arsize);
                        rd_addr <= rd_next_addr;
                        s_axi_rdata <= mem[rd_next_addr[ADDR_WIDTH-1:2]];
                    end else begin
                        s_axi_rdata <= mem[rd_word_addr];
                    end
                    s_axi_rlast <= (rd_count + 8'd1 == rd_len);
                end
            end
        end
    end
endmodule

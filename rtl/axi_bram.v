`timescale 1ns/1ps

module axi_bram #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32,
    parameter DEPTH_WORDS = 4096,
    parameter INIT_FILE = ""
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

`ifdef FPGA_SYNTH_BRAM
    (* ram_style = "block" *) reg [7:0] mem0 [0:DEPTH_WORDS-1];
    (* ram_style = "block" *) reg [7:0] mem1 [0:DEPTH_WORDS-1];
    (* ram_style = "block" *) reg [7:0] mem2 [0:DEPTH_WORDS-1];
    (* ram_style = "block" *) reg [7:0] mem3 [0:DEPTH_WORDS-1];
    reg [DATA_WIDTH-1:0] init_mem [0:DEPTH_WORDS-1];
`else
    reg [DATA_WIDTH-1:0] mem [0:DEPTH_WORDS-1];
`endif

    reg        wr_active;
    reg [31:0] wr_addr;
    reg [7:0]  wr_len;
    reg [7:0]  wr_count;

    reg        rd_active;
    reg [31:0] rd_addr;
    reg [7:0]  rd_len;
    reg [7:0]  rd_count;
    reg [2:0]  rd_size;
    reg [1:0]  rd_burst;
    reg [31:0] rd_next_addr;
    reg [31:0] rd_pipe_addr;
    reg        rd_pipe_valid;
    reg        rd_pipe_last;

    wire [31:0] wr_word_addr = wr_addr[ADDR_WIDTH-1:2];
    wire [31:0] rd_step = (32'd1 << rd_size);
    wire        rd_output_ready = !s_axi_rvalid || s_axi_rready;

    assign s_axi_awready = !wr_active && !s_axi_bvalid;
    assign s_axi_wready  = wr_active;
    assign s_axi_arready = !rd_active && !rd_pipe_valid && !s_axi_rvalid;

    integer i;
    initial begin
        for (i = 0; i < DEPTH_WORDS; i = i + 1) begin
`ifdef FPGA_SYNTH_BRAM
            init_mem[i] = {DATA_WIDTH{1'b0}};
            mem0[i] = 8'd0;
            mem1[i] = 8'd0;
            mem2[i] = 8'd0;
            mem3[i] = 8'd0;
`else
            mem[i] = {DATA_WIDTH{1'b0}};
`endif
        end
        if (INIT_FILE != "") begin
`ifdef FPGA_SYNTH_BRAM
            $readmemh(INIT_FILE, init_mem);
            for (i = 0; i < DEPTH_WORDS; i = i + 1) begin
                mem0[i] = init_mem[i][7:0];
                mem1[i] = init_mem[i][15:8];
                mem2[i] = init_mem[i][23:16];
                mem3[i] = init_mem[i][31:24];
            end
`else
            $readmemh(INIT_FILE, mem);
`endif
        end
    end

    always @(posedge clk) begin
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
`ifdef FPGA_SYNTH_BRAM
                if (s_axi_wstrb[0]) begin
                    mem0[wr_word_addr] <= s_axi_wdata[7:0];
                end
                if (s_axi_wstrb[1]) begin
                    mem1[wr_word_addr] <= s_axi_wdata[15:8];
                end
                if (s_axi_wstrb[2]) begin
                    mem2[wr_word_addr] <= s_axi_wdata[23:16];
                end
                if (s_axi_wstrb[3]) begin
                    mem3[wr_word_addr] <= s_axi_wdata[31:24];
                end
`else
                if (s_axi_wstrb[0]) begin
                    mem[wr_word_addr][7:0] <= s_axi_wdata[7:0];
                end
                if (s_axi_wstrb[1]) begin
                    mem[wr_word_addr][15:8] <= s_axi_wdata[15:8];
                end
                if (s_axi_wstrb[2]) begin
                    mem[wr_word_addr][23:16] <= s_axi_wdata[23:16];
                end
                if (s_axi_wstrb[3]) begin
                    mem[wr_word_addr][31:24] <= s_axi_wdata[31:24];
                end
`endif

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

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_active       <= 1'b0;
            rd_addr         <= 32'd0;
            rd_len          <= 8'd0;
            rd_count        <= 8'd0;
            rd_size         <= 3'd2;
            rd_burst        <= 2'b01;
            rd_next_addr    <= 32'd0;
            rd_pipe_addr    <= 32'd0;
            rd_pipe_valid   <= 1'b0;
            rd_pipe_last    <= 1'b0;
            s_axi_rdata     <= {DATA_WIDTH{1'b0}};
            s_axi_rresp     <= 2'b00;
            s_axi_rlast     <= 1'b0;
            s_axi_rvalid    <= 1'b0;
            read_beat_count <= 32'd0;
            last_araddr     <= 32'd0;
        end else begin
            if (s_axi_rvalid && s_axi_rready) begin
                read_beat_count <= read_beat_count + 32'd1;
                s_axi_rvalid <= 1'b0;
                if (s_axi_rlast && !rd_pipe_valid) begin
                    s_axi_rlast <= 1'b0;
                    rd_active   <= 1'b0;
                end
            end

            if (rd_output_ready && rd_pipe_valid) begin
`ifdef FPGA_SYNTH_BRAM
                s_axi_rdata  <= {
                    mem3[rd_pipe_addr[ADDR_WIDTH-1:2]],
                    mem2[rd_pipe_addr[ADDR_WIDTH-1:2]],
                    mem1[rd_pipe_addr[ADDR_WIDTH-1:2]],
                    mem0[rd_pipe_addr[ADDR_WIDTH-1:2]]
                };
`else
                s_axi_rdata  <= mem[rd_pipe_addr[ADDR_WIDTH-1:2]];
`endif
                s_axi_rresp  <= 2'b00;
                s_axi_rlast  <= rd_pipe_last;
                s_axi_rvalid <= 1'b1;

                if (rd_pipe_last) begin
                    rd_pipe_valid <= 1'b0;
                end else begin
                    rd_count <= rd_count + 8'd1;
                    if (rd_burst == 2'b01) begin
                        rd_next_addr = rd_addr + rd_step;
                        rd_addr <= rd_next_addr;
                    end else begin
                        rd_next_addr = rd_addr;
                    end
                    rd_pipe_addr  <= rd_next_addr;
                    rd_pipe_last  <= (rd_count + 8'd1 == rd_len);
                    rd_pipe_valid <= 1'b1;
                end
            end

            if (s_axi_arvalid && s_axi_arready) begin
                rd_active    <= 1'b1;
                rd_addr      <= s_axi_araddr;
                rd_len       <= s_axi_arlen;
                rd_count     <= 8'd0;
                rd_size      <= s_axi_arsize;
                rd_burst     <= s_axi_arburst;
                last_araddr  <= s_axi_araddr;
                rd_pipe_addr  <= s_axi_araddr;
                rd_pipe_last  <= (s_axi_arlen == 8'd0);
                rd_pipe_valid <= 1'b1;
            end
        end
    end
endmodule

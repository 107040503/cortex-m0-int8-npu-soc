`timescale 1ns/1ps

module npu_accel_axi #(
    parameter CLOCK_MHZ = 200,
    parameter PE_COUNT = 16,
    parameter PEAK_LANES_PER_PE = 160
) (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [31:0]  s_axil_awaddr,
    input  wire         s_axil_awvalid,
    output wire         s_axil_awready,
    input  wire [31:0]  s_axil_wdata,
    input  wire [3:0]   s_axil_wstrb,
    input  wire         s_axil_wvalid,
    output wire         s_axil_wready,
    output reg  [1:0]   s_axil_bresp,
    output reg          s_axil_bvalid,
    input  wire         s_axil_bready,

    input  wire [31:0]  s_axil_araddr,
    input  wire         s_axil_arvalid,
    output wire         s_axil_arready,
    output reg  [31:0]  s_axil_rdata,
    output reg  [1:0]   s_axil_rresp,
    output reg          s_axil_rvalid,
    input  wire         s_axil_rready,

    output reg  [31:0]  m_axi_awaddr,
    output reg  [7:0]   m_axi_awlen,
    output reg  [2:0]   m_axi_awsize,
    output reg  [1:0]   m_axi_awburst,
    output reg          m_axi_awvalid,
    input  wire         m_axi_awready,
    output reg  [31:0]  m_axi_wdata,
    output reg  [3:0]   m_axi_wstrb,
    output reg          m_axi_wlast,
    output reg          m_axi_wvalid,
    input  wire         m_axi_wready,
    input  wire [1:0]   m_axi_bresp,
    input  wire         m_axi_bvalid,
    output reg          m_axi_bready,

    output reg  [31:0]  m_axi_araddr,
    output reg  [7:0]   m_axi_arlen,
    output reg  [2:0]   m_axi_arsize,
    output reg  [1:0]   m_axi_arburst,
    output reg          m_axi_arvalid,
    input  wire         m_axi_arready,
    input  wire [31:0]  m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output reg          m_axi_rready,

    output wire         irq,
    output wire         array_clk_en,
    output reg  [31:0]  dma_active_cycles,
    output reg  [31:0]  dma_data_cycles,
    output reg  [31:0]  dma_read_beats,
    output reg  [31:0]  dma_write_beats
);
    localparam REG_CTRL       = 8'h00;
    localparam REG_STATUS     = 8'h04;
    localparam REG_A_ADDR     = 8'h08;
    localparam REG_B_ADDR     = 8'h0c;
    localparam REG_C_ADDR     = 8'h10;
    localparam REG_PE_MASK    = 8'h14;
    localparam REG_ACTIVE_CYC = 8'h18;
    localparam REG_DMA_ACT    = 8'h1c;
    localparam REG_DMA_DATA   = 8'h20;
    localparam REG_DMA_READ   = 8'h24;
    localparam REG_DMA_WRITE  = 8'h28;
    localparam REG_DFS_CTRL   = 8'h2c;
    localparam REG_POWER_CTRL = 8'h30;
    localparam REG_PEAK_MTOPS = 8'h34;
    localparam REG_DFS_WAIT   = 8'h38;
    localparam REG_VERSION    = 8'h3c;

    localparam ST_IDLE        = 4'd0;
    localparam ST_READ_A_AR   = 4'd1;
    localparam ST_READ_A_R    = 4'd2;
    localparam ST_READ_B_AR   = 4'd3;
    localparam ST_READ_B_R    = 4'd4;
    localparam ST_CORE_START  = 4'd5;
    localparam ST_CORE_WAIT   = 4'd6;
    localparam ST_WRITE_C_AW  = 4'd7;
    localparam ST_WRITE_C_W   = 4'd8;
    localparam ST_WRITE_C_B   = 4'd9;
    localparam ST_DONE        = 4'd10;

    reg [3:0]   state;
    reg [31:0]  reg_a_addr;
    reg [31:0]  reg_b_addr;
    reg [31:0]  reg_c_addr;
    reg [15:0]  reg_pe_mask;
    reg         reg_irq_en;
    reg [1:0]   reg_dfs_divider;
    reg         reg_auto_power_gate;
    reg         done_latched;
    reg         start_pulse;
    reg [2:0]   read_idx;
    reg [4:0]   write_idx;
    reg [127:0] a_matrix;
    reg [127:0] b_matrix;
    reg         core_start;

    wire        core_busy;
    wire        core_done;
    wire [8:0]  core_active_cycles;
    wire [8:0]  core_dfs_wait_cycles;
    wire [511:0] c_matrix;
    wire        dma_bus_active_state;
    wire        npu_power_on;
    wire [31:0] peak_mtops;

    assign irq = done_latched & reg_irq_en;
    assign npu_power_on = !reg_auto_power_gate || (state != ST_IDLE) || core_busy || start_pulse;
    assign peak_mtops = (CLOCK_MHZ * PE_COUNT * PEAK_LANES_PER_PE * 2) / 1000;
    assign s_axil_awready = s_axil_awvalid && s_axil_wvalid && !s_axil_bvalid;
    assign s_axil_wready  = s_axil_awvalid && s_axil_wvalid && !s_axil_bvalid;
    assign s_axil_arready = s_axil_arvalid && !s_axil_rvalid;
    assign dma_bus_active_state =
        (state == ST_READ_A_AR)  ||
        (state == ST_READ_A_R)   ||
        (state == ST_READ_B_AR)  ||
        (state == ST_READ_B_R)   ||
        (state == ST_WRITE_C_AW) ||
        (state == ST_WRITE_C_W)  ||
        (state == ST_WRITE_C_B);

    npu_core_4x4 u_core (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (core_start),
        .dfs_divider   (reg_dfs_divider),
        .a_matrix      (a_matrix),
        .b_matrix      (b_matrix),
        .pe_mask       (reg_pe_mask),
        .busy          (core_busy),
        .done          (core_done),
        .array_clk_en  (array_clk_en),
        .active_cycles (core_active_cycles),
        .dfs_wait_cycles (core_dfs_wait_cycles),
        .c_matrix      (c_matrix)
    );

    wire axil_write_fire = s_axil_awvalid && s_axil_awready && s_axil_wvalid && s_axil_wready;
    wire axil_read_fire  = s_axil_arvalid && s_axil_arready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_a_addr    <= 32'd0;
            reg_b_addr    <= 32'd0;
            reg_c_addr    <= 32'd0;
            reg_pe_mask   <= 16'hffff;
            reg_irq_en    <= 1'b0;
            reg_dfs_divider <= 2'd0;
            reg_auto_power_gate <= 1'b1;
            done_latched  <= 1'b0;
            start_pulse   <= 1'b0;
            s_axil_bresp  <= 2'b00;
            s_axil_bvalid <= 1'b0;
        end else begin
            start_pulse <= 1'b0;

            if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end

            if (axil_write_fire) begin
                case (s_axil_awaddr[7:0])
                    REG_CTRL: begin
                        if (s_axil_wdata[0]) begin
                            start_pulse <= 1'b1;
                            done_latched <= 1'b0;
                        end
                        if (s_axil_wdata[1]) begin
                            reg_irq_en <= 1'b1;
                        end
                        if (s_axil_wdata[2]) begin
                            reg_irq_en <= 1'b0;
                        end
                        if (s_axil_wdata[8]) begin
                            done_latched <= 1'b0;
                        end
                    end
                    REG_A_ADDR: begin
                        reg_a_addr <= s_axil_wdata;
                    end
                    REG_B_ADDR: begin
                        reg_b_addr <= s_axil_wdata;
                    end
                    REG_C_ADDR: begin
                        reg_c_addr <= s_axil_wdata;
                    end
                    REG_PE_MASK: begin
                        reg_pe_mask <= s_axil_wdata[15:0];
                    end
                    REG_DFS_CTRL: begin
                        reg_dfs_divider <= s_axil_wdata[1:0];
                    end
                    REG_POWER_CTRL: begin
                        reg_auto_power_gate <= s_axil_wdata[0];
                    end
                    default: begin
                    end
                endcase

                s_axil_bresp  <= 2'b00;
                s_axil_bvalid <= 1'b1;
            end

            if (state == ST_DONE) begin
                done_latched <= 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_rdata  <= 32'd0;
            s_axil_rresp  <= 2'b00;
            s_axil_rvalid <= 1'b0;
        end else begin
            if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end

            if (axil_read_fire) begin
                case (s_axil_araddr[7:0])
                    REG_CTRL: begin
                        s_axil_rdata <= {30'd0, reg_irq_en, 1'b0};
                    end
                    REG_STATUS: begin
                        s_axil_rdata <= {28'd0, array_clk_en, irq, done_latched, (state != ST_IDLE)};
                    end
                    REG_A_ADDR: begin
                        s_axil_rdata <= reg_a_addr;
                    end
                    REG_B_ADDR: begin
                        s_axil_rdata <= reg_b_addr;
                    end
                    REG_C_ADDR: begin
                        s_axil_rdata <= reg_c_addr;
                    end
                    REG_PE_MASK: begin
                        s_axil_rdata <= {16'd0, reg_pe_mask};
                    end
                    REG_ACTIVE_CYC: begin
                        s_axil_rdata <= {23'd0, core_active_cycles};
                    end
                    REG_DMA_ACT: begin
                        s_axil_rdata <= dma_active_cycles;
                    end
                    REG_DMA_DATA: begin
                        s_axil_rdata <= dma_data_cycles;
                    end
                    REG_DMA_READ: begin
                        s_axil_rdata <= dma_read_beats;
                    end
                    REG_DMA_WRITE: begin
                        s_axil_rdata <= dma_write_beats;
                    end
                    REG_DFS_CTRL: begin
                        s_axil_rdata <= {30'd0, reg_dfs_divider};
                    end
                    REG_POWER_CTRL: begin
                        s_axil_rdata <= {29'd0, array_clk_en, npu_power_on, reg_auto_power_gate};
                    end
                    REG_PEAK_MTOPS: begin
                        s_axil_rdata <= peak_mtops;
                    end
                    REG_DFS_WAIT: begin
                        s_axil_rdata <= {23'd0, core_dfs_wait_cycles};
                    end
                    REG_VERSION: begin
                        s_axil_rdata <= 32'h2026_0615;
                    end
                    default: begin
                        s_axil_rdata <= 32'd0;
                    end
                endcase

                s_axil_rresp  <= 2'b00;
                s_axil_rvalid <= 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= ST_IDLE;
            read_idx          <= 3'd0;
            write_idx         <= 5'd0;
            a_matrix          <= 128'd0;
            b_matrix          <= 128'd0;
            core_start        <= 1'b0;
            m_axi_awaddr      <= 32'd0;
            m_axi_awlen       <= 8'd0;
            m_axi_awsize      <= 3'd2;
            m_axi_awburst     <= 2'b01;
            m_axi_awvalid     <= 1'b0;
            m_axi_wdata       <= 32'd0;
            m_axi_wstrb       <= 4'hf;
            m_axi_wlast       <= 1'b0;
            m_axi_wvalid      <= 1'b0;
            m_axi_bready      <= 1'b0;
            m_axi_araddr      <= 32'd0;
            m_axi_arlen       <= 8'd0;
            m_axi_arsize      <= 3'd2;
            m_axi_arburst     <= 2'b01;
            m_axi_arvalid     <= 1'b0;
            m_axi_rready      <= 1'b0;
            dma_active_cycles <= 32'd0;
            dma_data_cycles   <= 32'd0;
            dma_read_beats    <= 32'd0;
            dma_write_beats   <= 32'd0;
        end else begin
            core_start <= 1'b0;

            if (dma_bus_active_state) begin
                dma_active_cycles <= dma_active_cycles + 32'd1;
            end
            if ((m_axi_rvalid && m_axi_rready) || (m_axi_wvalid && m_axi_wready)) begin
                dma_data_cycles <= dma_data_cycles + 32'd1;
            end

            case (state)
                ST_IDLE: begin
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_bready  <= 1'b0;
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    m_axi_wlast   <= 1'b0;

                    if (start_pulse) begin
                        dma_active_cycles <= 32'd0;
                        dma_data_cycles   <= 32'd0;
                        dma_read_beats    <= 32'd0;
                        dma_write_beats   <= 32'd0;
                        read_idx          <= 3'd0;
                        m_axi_araddr      <= reg_a_addr;
                        m_axi_arlen       <= 8'd3;
                        m_axi_arsize      <= 3'd2;
                        m_axi_arburst     <= 2'b01;
                        m_axi_arvalid     <= 1'b1;
                        state             <= ST_READ_A_AR;
                    end
                end

                ST_READ_A_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        read_idx      <= 3'd0;
                        state         <= ST_READ_A_R;
                    end
                end

                ST_READ_A_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        a_matrix[read_idx*32 +: 32] <= m_axi_rdata;
                        dma_read_beats <= dma_read_beats + 32'd1;
                        if (m_axi_rlast || read_idx == 3'd3) begin
                            m_axi_rready  <= 1'b0;
                            m_axi_araddr  <= reg_b_addr;
                            m_axi_arlen   <= 8'd3;
                            m_axi_arvalid <= 1'b1;
                            read_idx      <= 3'd0;
                            state         <= ST_READ_B_AR;
                        end else begin
                            read_idx <= read_idx + 3'd1;
                        end
                    end
                end

                ST_READ_B_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        read_idx      <= 3'd0;
                        state         <= ST_READ_B_R;
                    end
                end

                ST_READ_B_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        b_matrix[read_idx*32 +: 32] <= m_axi_rdata;
                        dma_read_beats <= dma_read_beats + 32'd1;
                        if (m_axi_rlast || read_idx == 3'd3) begin
                            m_axi_rready <= 1'b0;
                            state        <= ST_CORE_START;
                        end else begin
                            read_idx <= read_idx + 3'd1;
                        end
                    end
                end

                ST_CORE_START: begin
                    core_start <= 1'b1;
                    state      <= ST_CORE_WAIT;
                end

                ST_CORE_WAIT: begin
                    if (core_done) begin
                        m_axi_awaddr  <= reg_c_addr;
                        m_axi_awlen   <= 8'd15;
                        m_axi_awsize  <= 3'd2;
                        m_axi_awburst <= 2'b01;
                        m_axi_awvalid <= 1'b1;
                        write_idx     <= 5'd0;
                        state         <= ST_WRITE_C_AW;
                    end
                end

                ST_WRITE_C_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wdata   <= c_matrix[0 +: 32];
                        m_axi_wstrb   <= 4'hf;
                        m_axi_wlast   <= 1'b0;
                        m_axi_wvalid  <= 1'b1;
                        write_idx     <= 5'd0;
                        state         <= ST_WRITE_C_W;
                    end
                end

                ST_WRITE_C_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        dma_write_beats <= dma_write_beats + 32'd1;
                        if (write_idx == 5'd15) begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_wlast  <= 1'b0;
                            m_axi_bready <= 1'b1;
                            state        <= ST_WRITE_C_B;
                        end else begin
                            write_idx   <= write_idx + 5'd1;
                            m_axi_wdata <= c_matrix[(write_idx + 5'd1)*32 +: 32];
                            m_axi_wlast <= (write_idx + 5'd1 == 5'd15);
                        end
                    end
                end

                ST_WRITE_C_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        state        <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule

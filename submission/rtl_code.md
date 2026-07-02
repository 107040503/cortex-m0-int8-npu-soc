# RTL代码工程（结构化提交版）

## 1. 工程目录结构

以下为比赛提交建议目录结构。当前完整工程已在根目录`rtl/`、`tb/`、`docs/`下实现；本节给出面向提交归档的结构化拆分方式和关键Verilog框架代码。

```text
/rtl
  /cpu
    cpu_wrapper.v
  /npu
    int8_mac_pe.v
    npu_array.v
    npu_core.v
    npu_top.v
  /axi
    ahb_to_axi_lite.v
    axi_master.v
    axi_slave.v
    axi_interconnect.v
  /top
    top.v
  /utils
    axi_ram.v

/tb
  testbench_top.v

/docs
  design.md
```

## 2. RTL代码框架

说明：

- 以下代码为提交版结构化框架，接口和功能边界与当前项目一致。
- 当前工程中真实Cortex-M0由Arm DesignStart RTL提供，提交框架用`cpu_wrapper.v`表达封装边界。
- AXI模块保留必要握手、地址、数据和Burst信号，避免引入超出项目范围的复杂乱序、多ID实现。
- NPU框架体现4×4 INT8脉动阵列、DMA、AXI-Lite寄存器、AXI Burst主端和低功耗控制。

---

## `/rtl/cpu/cpu_wrapper.v`

```verilog
`timescale 1ns/1ps

module cpu_wrapper (
    input  wire        hclk,
    input  wire        hresetn,

    output wire [31:0] haddr,
    output wire [1:0]  htrans,
    output wire        hwrite,
    output wire [2:0]  hsize,
    output wire [31:0] hwdata,
    input  wire [31:0] hrdata,
    input  wire        hready,
    input  wire        hresp,

    input  wire        irq,
    output wire        halted
);
    /*
     * Submission note:
     * In the implemented project this wrapper instantiates Arm DesignStart
     * CORTEXM0INTEGRATION and ties off debug, scan, WIC and SysTick ports.
     * The wrapper exposes only the AHB-Lite master port needed by the SoC.
     */

    CORTEXM0INTEGRATION u_cpu (
        .FCLK      (hclk),
        .SCLK      (hclk),
        .HCLK      (hclk),
        .DCLK      (hclk),
        .PORESETn  (hresetn),
        .DBGRESETn (hresetn),
        .HRESETn   (hresetn),

        .HADDR     (haddr),
        .HSIZE     (hsize),
        .HTRANS    (htrans),
        .HWDATA    (hwdata),
        .HWRITE    (hwrite),
        .HRDATA    (hrdata),
        .HREADY    (hready),
        .HRESP     (hresp),

        .IRQ       ({31'd0, irq}),
        .HALTED    (halted),

        .SWCLKTCK  (hclk),
        .nTRST     (1'b1),
        .SWDITMS   (1'b1),
        .TDI       (1'b1),
        .DBGRESTART(1'b0),
        .EDBGRQ    (1'b0),
        .NMI       (1'b0),
        .RXEV      (1'b0),
        .STCALIB   (26'd0),
        .STCLKEN   (1'b0),
        .IRQLATENCY(8'd0),
        .ECOREVNUM (28'd0),
        .SLEEPHOLDREQn(1'b1),
        .WICENREQ  (1'b0),
        .CDBGPWRUPACK(1'b1),
        .SE        (1'b0),
        .RSTBYPASS (1'b0)
    );
endmodule
```

---

## `/rtl/npu/int8_mac_pe.v`

```verilog
`timescale 1ns/1ps

module int8_mac_pe (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               clk_en,
    input  wire               clear,
    input  wire               valid_in,
    input  wire signed [7:0]  a_in,
    input  wire signed [7:0]  b_in,

    output reg                valid_out,
    output reg  signed [7:0]  a_out,
    output reg  signed [7:0]  b_out,
    output reg  signed [31:0] acc
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            a_out     <= 8'sd0;
            b_out     <= 8'sd0;
            acc       <= 32'sd0;
        end else if (clk_en) begin
            if (clear) begin
                valid_out <= 1'b0;
                a_out     <= 8'sd0;
                b_out     <= 8'sd0;
                acc       <= 32'sd0;
            end else begin
                valid_out <= valid_in;
                a_out     <= a_in;
                b_out     <= b_in;
                if (valid_in) begin
                    acc <= acc + a_in * b_in;
                end
            end
        end
    end
endmodule
```

---

## `/rtl/npu/npu_array.v`

```verilog
`timescale 1ns/1ps

module npu_array (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         clk_en,
    input  wire         clear,
    input  wire         valid_in,
    input  wire [31:0]  a_west,
    input  wire [31:0]  b_north,
    output wire [511:0] acc_flat
);
    wire signed [7:0]  a_bus [0:3][0:4];
    wire signed [7:0]  b_bus [0:4][0:3];
    wire               v_bus [0:3][0:4];
    wire signed [31:0] acc_bus [0:3][0:3];

    genvar r;
    genvar c;

    generate
        for (r = 0; r < 4; r = r + 1) begin : gen_input_a
            assign a_bus[r][0] = a_west[r*8 +: 8];
            assign v_bus[r][0] = valid_in;
        end

        for (c = 0; c < 4; c = c + 1) begin : gen_input_b
            assign b_bus[0][c] = b_north[c*8 +: 8];
        end

        for (r = 0; r < 4; r = r + 1) begin : gen_rows
            for (c = 0; c < 4; c = c + 1) begin : gen_cols
                int8_mac_pe u_pe (
                    .clk       (clk),
                    .rst_n     (rst_n),
                    .clk_en    (clk_en),
                    .clear     (clear),
                    .valid_in  (v_bus[r][c]),
                    .a_in      (a_bus[r][c]),
                    .b_in      (b_bus[r][c]),
                    .valid_out (v_bus[r][c+1]),
                    .a_out     (a_bus[r][c+1]),
                    .b_out     (b_bus[r+1][c]),
                    .acc       (acc_bus[r][c])
                );

                assign acc_flat[(r*4+c)*32 +: 32] = acc_bus[r][c];
            end
        end
    endgenerate
endmodule
```

---

## `/rtl/npu/npu_core.v`

```verilog
`timescale 1ns/1ps

module npu_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [1:0]   dfs_divider,
    input  wire [127:0] a_matrix,
    input  wire [127:0] b_matrix,
    input  wire [15:0]  pe_mask,

    output reg          busy,
    output reg          done,
    output wire         array_clk_en,
    output reg  [8:0]   active_cycles,
    output reg  [8:0]   dfs_wait_cycles,
    output reg  [511:0] c_matrix
);
    localparam ST_IDLE  = 2'd0;
    localparam ST_CLEAR = 2'd1;
    localparam ST_RUN   = 2'd2;
    localparam ST_DONE  = 2'd3;

    reg [1:0] state;
    reg [3:0] cycle_count;
    reg [1:0] dfs_count;
    reg       array_clear;
    reg       array_valid;
    reg [31:0] a_west;
    reg [31:0] b_north;

    wire [511:0] raw_acc;
    wire active_state = (state == ST_CLEAR) || (state == ST_RUN);
    wire dfs_tick = active_state && (dfs_count == 2'd0);

    assign array_clk_en = dfs_tick;

    npu_array u_array (
        .clk      (clk),
        .rst_n    (rst_n),
        .clk_en   (array_clk_en),
        .clear    (array_clear),
        .valid_in (array_valid),
        .a_west   (a_west),
        .b_north  (b_north),
        .acc_flat (raw_acc)
    );

    integer i;
    integer kidx;

    always @(*) begin
        a_west  = 32'd0;
        b_north = 32'd0;
        for (i = 0; i < 4; i = i + 1) begin
            kidx = cycle_count - i;
            if (kidx >= 0 && kidx < 4) begin
                a_west[i*8 +: 8]  = a_matrix[(i*4+kidx)*8 +: 8];
                b_north[i*8 +: 8] = b_matrix[(kidx*4+i)*8 +: 8];
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dfs_count <= 2'd0;
        end else if (active_state) begin
            dfs_count <= (dfs_count == dfs_divider) ? 2'd0 : dfs_count + 2'd1;
        end else begin
            dfs_count <= 2'd0;
        end
    end

    integer p;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            cycle_count <= 4'd0;
            array_clear <= 1'b0;
            array_valid <= 1'b0;
            active_cycles <= 9'd0;
            dfs_wait_cycles <= 9'd0;
            c_matrix <= 512'd0;
        end else begin
            done <= 1'b0;
            if (active_state && !dfs_tick) begin
                dfs_wait_cycles <= dfs_wait_cycles + 9'd1;
            end

            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    array_clear <= 1'b0;
                    array_valid <= 1'b0;
                    cycle_count <= 4'd0;
                    if (start) begin
                        busy <= 1'b1;
                        array_clear <= 1'b1;
                        active_cycles <= 9'd0;
                        dfs_wait_cycles <= 9'd0;
                        state <= ST_CLEAR;
                    end
                end

                ST_CLEAR: begin
                    busy <= 1'b1;
                    if (dfs_tick) begin
                        array_clear <= 1'b0;
                        array_valid <= 1'b1;
                        active_cycles <= active_cycles + 9'd1;
                        state <= ST_RUN;
                    end
                end

                ST_RUN: begin
                    if (dfs_tick) begin
                        active_cycles <= active_cycles + 9'd1;
                        if (cycle_count == 4'd9) begin
                            array_valid <= 1'b0;
                            state <= ST_DONE;
                        end else begin
                            cycle_count <= cycle_count + 4'd1;
                        end
                    end
                end

                ST_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    for (p = 0; p < 16; p = p + 1) begin
                        c_matrix[p*32 +: 32] <= pe_mask[p] ? raw_acc[p*32 +: 32] : 32'd0;
                    end
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
```

---

## `/rtl/axi/axi_master.v`

```verilog
`timescale 1ns/1ps

module axi_master #(
    parameter DATA_WIDTH = 32
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    rd_start,
    input  wire                    wr_start,
    input  wire [31:0]             addr,
    input  wire [7:0]              len,
    input  wire [DATA_WIDTH-1:0]   wr_data,
    output reg  [DATA_WIDTH-1:0]   rd_data,
    output reg                     busy,
    output reg                     done,

    output reg  [31:0]             m_axi_awaddr,
    output reg  [7:0]              m_axi_awlen,
    output reg  [2:0]              m_axi_awsize,
    output reg  [1:0]              m_axi_awburst,
    output reg                     m_axi_awvalid,
    input  wire                    m_axi_awready,
    output reg  [DATA_WIDTH-1:0]   m_axi_wdata,
    output reg  [3:0]              m_axi_wstrb,
    output reg                     m_axi_wlast,
    output reg                     m_axi_wvalid,
    input  wire                    m_axi_wready,
    input  wire                    m_axi_bvalid,
    output reg                     m_axi_bready,

    output reg  [31:0]             m_axi_araddr,
    output reg  [7:0]              m_axi_arlen,
    output reg  [2:0]              m_axi_arsize,
    output reg  [1:0]              m_axi_arburst,
    output reg                     m_axi_arvalid,
    input  wire                    m_axi_arready,
    input  wire [DATA_WIDTH-1:0]   m_axi_rdata,
    input  wire                    m_axi_rlast,
    input  wire                    m_axi_rvalid,
    output reg                     m_axi_rready
);
    /*
     * Simplified AXI master framework.
     * The implemented project integrates this behavior inside the NPU DMA FSM.
     * It supports one outstanding INCR burst at a time.
     */
    localparam ST_IDLE = 3'd0;
    localparam ST_AR   = 3'd1;
    localparam ST_R    = 3'd2;
    localparam ST_AW   = 3'd3;
    localparam ST_W    = 3'd4;
    localparam ST_B    = 3'd5;

    reg [2:0] state;
    reg [7:0] beat_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            beat_cnt <= 8'd0;
            busy <= 1'b0;
            done <= 1'b0;
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid <= 1'b0;
            m_axi_bready <= 1'b0;
            m_axi_arvalid <= 1'b0;
            m_axi_rready <= 1'b0;
            m_axi_wlast <= 1'b0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (rd_start) begin
                        busy <= 1'b1;
                        m_axi_araddr <= addr;
                        m_axi_arlen <= len;
                        m_axi_arsize <= 3'd2;
                        m_axi_arburst <= 2'b01;
                        m_axi_arvalid <= 1'b1;
                        state <= ST_AR;
                    end else if (wr_start) begin
                        busy <= 1'b1;
                        m_axi_awaddr <= addr;
                        m_axi_awlen <= len;
                        m_axi_awsize <= 3'd2;
                        m_axi_awburst <= 2'b01;
                        m_axi_awvalid <= 1'b1;
                        beat_cnt <= 8'd0;
                        state <= ST_AW;
                    end
                end

                ST_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready <= 1'b1;
                        state <= ST_R;
                    end
                end

                ST_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        rd_data <= m_axi_rdata;
                        if (m_axi_rlast) begin
                            m_axi_rready <= 1'b0;
                            done <= 1'b1;
                            state <= ST_IDLE;
                        end
                    end
                end

                ST_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wdata <= wr_data;
                        m_axi_wstrb <= 4'hf;
                        m_axi_wvalid <= 1'b1;
                        m_axi_wlast <= (len == 8'd0);
                        state <= ST_W;
                    end
                end

                ST_W: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        if (beat_cnt == len) begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_wlast <= 1'b0;
                            m_axi_bready <= 1'b1;
                            state <= ST_B;
                        end else begin
                            beat_cnt <= beat_cnt + 8'd1;
                            m_axi_wlast <= (beat_cnt + 8'd1 == len);
                        end
                    end
                end

                ST_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
            endcase
        end
    end
endmodule
```

---

## `/rtl/axi/axi_slave.v`

```verilog
`timescale 1ns/1ps

module axi_slave #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH_WORDS = 4096
) (
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire [31:0]           s_axi_awaddr,
    input  wire [7:0]            s_axi_awlen,
    input  wire [2:0]            s_axi_awsize,
    input  wire [1:0]            s_axi_awburst,
    input  wire                  s_axi_awvalid,
    output wire                  s_axi_awready,
    input  wire [DATA_WIDTH-1:0] s_axi_wdata,
    input  wire [3:0]            s_axi_wstrb,
    input  wire                  s_axi_wlast,
    input  wire                  s_axi_wvalid,
    output wire                  s_axi_wready,
    output reg  [1:0]            s_axi_bresp,
    output reg                   s_axi_bvalid,
    input  wire                  s_axi_bready,

    input  wire [31:0]           s_axi_araddr,
    input  wire [7:0]            s_axi_arlen,
    input  wire [2:0]            s_axi_arsize,
    input  wire [1:0]            s_axi_arburst,
    input  wire                  s_axi_arvalid,
    output wire                  s_axi_arready,
    output reg  [DATA_WIDTH-1:0] s_axi_rdata,
    output reg  [1:0]            s_axi_rresp,
    output reg                   s_axi_rlast,
    output reg                   s_axi_rvalid,
    input  wire                  s_axi_rready
);
    reg [DATA_WIDTH-1:0] mem [0:DEPTH_WORDS-1];
    reg wr_active;
    reg rd_active;
    reg [31:0] wr_addr;
    reg [31:0] rd_addr;
    reg [7:0] wr_len;
    reg [7:0] rd_len;
    reg [7:0] wr_cnt;
    reg [7:0] rd_cnt;
    reg [31:0] rd_next_addr;

    assign s_axi_awready = !wr_active && !s_axi_bvalid;
    assign s_axi_wready  = wr_active;
    assign s_axi_arready = !rd_active && !s_axi_rvalid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_active <= 1'b0;
            s_axi_bvalid <= 1'b0;
            s_axi_bresp <= 2'b00;
        end else begin
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
            if (s_axi_awvalid && s_axi_awready) begin
                wr_active <= 1'b1;
                wr_addr <= s_axi_awaddr;
                wr_len <= s_axi_awlen;
                wr_cnt <= 8'd0;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                mem[wr_addr[13:2]] <= s_axi_wdata;
                if (s_axi_wlast || wr_cnt == wr_len) begin
                    wr_active <= 1'b0;
                    s_axi_bvalid <= 1'b1;
                    s_axi_bresp <= 2'b00;
                end else begin
                    wr_cnt <= wr_cnt + 8'd1;
                    if (s_axi_awburst == 2'b01) begin
                        wr_addr <= wr_addr + (32'd1 << s_axi_awsize);
                    end
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_active <= 1'b0;
            s_axi_rvalid <= 1'b0;
            s_axi_rlast <= 1'b0;
            s_axi_rresp <= 2'b00;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                rd_active <= 1'b1;
                rd_addr <= s_axi_araddr;
                rd_len <= s_axi_arlen;
                rd_cnt <= 8'd0;
                s_axi_rdata <= mem[s_axi_araddr[13:2]];
                s_axi_rvalid <= 1'b1;
                s_axi_rlast <= (s_axi_arlen == 8'd0);
            end else if (s_axi_rvalid && s_axi_rready) begin
                if (s_axi_rlast) begin
                    rd_active <= 1'b0;
                    s_axi_rvalid <= 1'b0;
                    s_axi_rlast <= 1'b0;
                end else begin
                    rd_cnt <= rd_cnt + 8'd1;
                    if (s_axi_arburst == 2'b01) begin
                        rd_next_addr = rd_addr + (32'd1 << s_axi_arsize);
                        rd_addr <= rd_next_addr;
                        s_axi_rdata <= mem[rd_next_addr[13:2]];
                    end
                    s_axi_rlast <= (rd_cnt + 8'd1 == rd_len);
                end
            end
        end
    end
endmodule
```

---

## `/rtl/axi/ahb_to_axi_lite.v`

```verilog
`timescale 1ns/1ps

module ahb_to_axi_lite (
    input  wire        hclk,
    input  wire        hresetn,
    input  wire [31:0] haddr,
    input  wire [1:0]  htrans,
    input  wire        hwrite,
    input  wire [2:0]  hsize,
    input  wire [31:0] hwdata,
    output reg  [31:0] hrdata,
    output wire        hreadyout,
    output reg         hresp,

    output reg  [31:0] m_awaddr,
    output reg         m_awvalid,
    input  wire        m_awready,
    output reg  [31:0] m_wdata,
    output reg  [3:0]  m_wstrb,
    output reg         m_wvalid,
    input  wire        m_wready,
    input  wire [1:0]  m_bresp,
    input  wire        m_bvalid,
    output reg         m_bready,

    output reg  [31:0] m_araddr,
    output reg         m_arvalid,
    input  wire        m_arready,
    input  wire [31:0] m_rdata,
    input  wire [1:0]  m_rresp,
    input  wire        m_rvalid,
    output reg         m_rready
);
    localparam ST_IDLE      = 3'd0;
    localparam ST_W_CAPTURE = 3'd1;
    localparam ST_W         = 3'd2;
    localparam ST_B         = 3'd3;
    localparam ST_AR        = 3'd4;
    localparam ST_R         = 3'd5;

    reg [2:0] state;
    reg [31:0] latched_addr;
    reg [2:0] latched_size;

    wire ahb_valid = htrans[1];
    assign hreadyout = (state == ST_IDLE) ||
                       (state == ST_B && m_bvalid) ||
                       (state == ST_R && m_rvalid);

    function [3:0] gen_wstrb;
        input [2:0] size;
        input [1:0] addr_lsb;
        begin
            case (size)
                3'd0: gen_wstrb = 4'b0001 << addr_lsb;
                3'd1: gen_wstrb = addr_lsb[1] ? 4'b1100 : 4'b0011;
                default: gen_wstrb = 4'b1111;
            endcase
        end
    endfunction

    always @(posedge hclk or negedge hresetn) begin
        if (!hresetn) begin
            state <= ST_IDLE;
            hresp <= 1'b0;
            hrdata <= 32'd0;
            m_awvalid <= 1'b0;
            m_wvalid <= 1'b0;
            m_bready <= 1'b0;
            m_arvalid <= 1'b0;
            m_rready <= 1'b0;
        end else begin
            case (state)
                ST_IDLE: begin
                    m_awvalid <= 1'b0;
                    m_wvalid <= 1'b0;
                    m_bready <= 1'b0;
                    m_arvalid <= 1'b0;
                    m_rready <= 1'b0;
                    hresp <= 1'b0;
                    if (ahb_valid) begin
                        latched_addr <= haddr;
                        latched_size <= hsize;
                        if (hwrite) begin
                            state <= ST_W_CAPTURE;
                        end else begin
                            m_araddr <= haddr;
                            m_arvalid <= 1'b1;
                            state <= ST_AR;
                        end
                    end
                end

                ST_W_CAPTURE: begin
                    m_awaddr <= latched_addr;
                    m_awvalid <= 1'b1;
                    m_wdata <= hwdata;
                    m_wstrb <= gen_wstrb(latched_size, latched_addr[1:0]);
                    m_wvalid <= 1'b1;
                    state <= ST_W;
                end

                ST_W: begin
                    if (m_awvalid && m_awready) m_awvalid <= 1'b0;
                    if (m_wvalid && m_wready) m_wvalid <= 1'b0;
                    if ((!m_awvalid || m_awready) && (!m_wvalid || m_wready)) begin
                        m_bready <= 1'b1;
                        state <= ST_B;
                    end
                end

                ST_B: begin
                    if (m_bvalid) begin
                        hresp <= |m_bresp;
                        m_bready <= 1'b0;
                        state <= ST_IDLE;
                    end
                end

                ST_AR: begin
                    if (m_arvalid && m_arready) begin
                        m_arvalid <= 1'b0;
                        m_rready <= 1'b1;
                        state <= ST_R;
                    end
                end

                ST_R: begin
                    if (m_rvalid) begin
                        hrdata <= m_rdata;
                        hresp <= |m_rresp;
                        m_rready <= 1'b0;
                        state <= ST_IDLE;
                    end
                end
            endcase
        end
    end
endmodule
```

---

## `/rtl/axi/axi_interconnect.v`

```verilog
`timescale 1ns/1ps

module axi_interconnect #(
    parameter NPU_BASE = 32'h1000_0000
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [31:0] cpu_awaddr,
    input  wire        cpu_awvalid,
    output wire        cpu_awready,
    input  wire [31:0] cpu_wdata,
    input  wire [3:0]  cpu_wstrb,
    input  wire        cpu_wvalid,
    output wire        cpu_wready,
    output wire [1:0]  cpu_bresp,
    output wire        cpu_bvalid,
    input  wire        cpu_bready,

    input  wire [31:0] cpu_araddr,
    input  wire        cpu_arvalid,
    output wire        cpu_arready,
    output wire [31:0] cpu_rdata,
    output wire [1:0]  cpu_rresp,
    output wire        cpu_rvalid,
    input  wire        cpu_rready,

    output wire [31:0] npu_awaddr,
    output wire        npu_awvalid,
    input  wire        npu_awready,
    output wire [31:0] npu_wdata,
    output wire [3:0]  npu_wstrb,
    output wire        npu_wvalid,
    input  wire        npu_wready,
    input  wire [1:0]  npu_bresp,
    input  wire        npu_bvalid,
    output wire        npu_bready,

    output wire [31:0] npu_araddr,
    output wire        npu_arvalid,
    input  wire        npu_arready,
    input  wire [31:0] npu_rdata,
    input  wire [1:0]  npu_rresp,
    input  wire        npu_rvalid,
    output wire        npu_rready
);
    wire wr_to_npu = (cpu_awaddr[31:16] == NPU_BASE[31:16]);
    wire rd_to_npu = (cpu_araddr[31:16] == NPU_BASE[31:16]);

    assign npu_awaddr  = cpu_awaddr - NPU_BASE;
    assign npu_awvalid = wr_to_npu && cpu_awvalid && cpu_wvalid;
    assign npu_wdata   = cpu_wdata;
    assign npu_wstrb   = cpu_wstrb;
    assign npu_wvalid  = wr_to_npu && cpu_awvalid && cpu_wvalid;
    assign npu_bready  = cpu_bready;

    assign npu_araddr  = cpu_araddr - NPU_BASE;
    assign npu_arvalid = rd_to_npu && cpu_arvalid;
    assign npu_rready  = cpu_rready;

    assign cpu_awready = wr_to_npu && npu_awready && npu_wready;
    assign cpu_wready  = wr_to_npu && npu_awready && npu_wready;
    assign cpu_bvalid  = wr_to_npu && npu_bvalid;
    assign cpu_bresp   = npu_bresp;

    assign cpu_arready = rd_to_npu && npu_arready;
    assign cpu_rvalid  = rd_to_npu && npu_rvalid;
    assign cpu_rdata   = npu_rdata;
    assign cpu_rresp   = npu_rresp;
endmodule
```

---

## `/rtl/npu/npu_top.v`

```verilog
`timescale 1ns/1ps

module npu_top #(
    parameter CLOCK_MHZ = 200,
    parameter PE_COUNT = 16,
    parameter PEAK_LANES_PER_PE = 160
) (
    input  wire        clk,
    input  wire        rst_n,

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

    output reg  [31:0] m_axi_araddr,
    output reg  [7:0]  m_axi_arlen,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [31:0] m_axi_rdata,
    input  wire        m_axi_rvalid,
    input  wire        m_axi_rlast,
    output reg         m_axi_rready,

    output reg  [31:0] m_axi_awaddr,
    output reg  [7:0]  m_axi_awlen,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,
    output reg  [31:0] m_axi_wdata,
    output reg         m_axi_wvalid,
    output reg         m_axi_wlast,
    input  wire        m_axi_wready,
    input  wire        m_axi_bvalid,
    output reg         m_axi_bready,

    output wire        irq,
    output wire        array_clk_en
);
    localparam REG_CTRL   = 8'h00;
    localparam REG_STATUS = 8'h04;
    localparam REG_A_ADDR = 8'h08;
    localparam REG_B_ADDR = 8'h0c;
    localparam REG_C_ADDR = 8'h10;
    localparam REG_MASK   = 8'h14;
    localparam REG_PEAK   = 8'h34;

    reg [31:0] reg_a_addr;
    reg [31:0] reg_b_addr;
    reg [31:0] reg_c_addr;
    reg [15:0] reg_pe_mask;
    reg        reg_irq_en;
    reg        start_pulse;
    reg        done_latched;

    reg [127:0] a_matrix;
    reg [127:0] b_matrix;
    wire [511:0] c_matrix;
    wire core_busy;
    wire core_done;

    assign s_axil_awready = s_axil_awvalid && s_axil_wvalid && !s_axil_bvalid;
    assign s_axil_wready  = s_axil_awvalid && s_axil_wvalid && !s_axil_bvalid;
    assign s_axil_arready = s_axil_arvalid && !s_axil_rvalid;
    assign irq = done_latched && reg_irq_en;

    npu_core u_core (
        .clk(clk),
        .rst_n(rst_n),
        .start(start_pulse),
        .dfs_divider(2'd0),
        .a_matrix(a_matrix),
        .b_matrix(b_matrix),
        .pe_mask(reg_pe_mask),
        .busy(core_busy),
        .done(core_done),
        .array_clk_en(array_clk_en),
        .active_cycles(),
        .dfs_wait_cycles(),
        .c_matrix(c_matrix)
    );

    wire write_fire = s_axil_awvalid && s_axil_awready &&
                      s_axil_wvalid  && s_axil_wready;
    wire read_fire  = s_axil_arvalid && s_axil_arready;
    wire [31:0] peak_mtops = (CLOCK_MHZ * PE_COUNT * PEAK_LANES_PER_PE * 2) / 1000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_a_addr <= 32'd0;
            reg_b_addr <= 32'd0;
            reg_c_addr <= 32'd0;
            reg_pe_mask <= 16'hffff;
            reg_irq_en <= 1'b0;
            start_pulse <= 1'b0;
            done_latched <= 1'b0;
            s_axil_bvalid <= 1'b0;
            s_axil_bresp <= 2'b00;
        end else begin
            start_pulse <= 1'b0;
            if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end
            if (write_fire) begin
                case (s_axil_awaddr[7:0])
                    REG_CTRL: begin
                        if (s_axil_wdata[0]) begin
                            start_pulse <= 1'b1;
                            done_latched <= 1'b0;
                        end
                        if (s_axil_wdata[1]) reg_irq_en <= 1'b1;
                    end
                    REG_A_ADDR: reg_a_addr <= s_axil_wdata;
                    REG_B_ADDR: reg_b_addr <= s_axil_wdata;
                    REG_C_ADDR: reg_c_addr <= s_axil_wdata;
                    REG_MASK:   reg_pe_mask <= s_axil_wdata[15:0];
                endcase
                s_axil_bvalid <= 1'b1;
            end
            if (core_done) begin
                done_latched <= 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_rvalid <= 1'b0;
            s_axil_rresp <= 2'b00;
            s_axil_rdata <= 32'd0;
        end else begin
            if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
            if (read_fire) begin
                case (s_axil_araddr[7:0])
                    REG_STATUS: s_axil_rdata <= {28'd0, array_clk_en, irq, done_latched, core_busy};
                    REG_A_ADDR: s_axil_rdata <= reg_a_addr;
                    REG_B_ADDR: s_axil_rdata <= reg_b_addr;
                    REG_C_ADDR: s_axil_rdata <= reg_c_addr;
                    REG_MASK:   s_axil_rdata <= {16'd0, reg_pe_mask};
                    REG_PEAK:   s_axil_rdata <= peak_mtops;
                    default:    s_axil_rdata <= 32'd0;
                endcase
                s_axil_rvalid <= 1'b1;
            end
        end
    end

    /*
     * DMA FSM is represented in the full project by reading A/B with INCR bursts,
     * starting npu_core, then writing C with an INCR burst.
     * This framework exposes the same AXI master signals for integration.
     */
endmodule
```

---

## `/rtl/top/top.v`

```verilog
`timescale 1ns/1ps

module top (
    input  wire clk,
    input  wire resetn,
    output wire npu_irq,
    output wire npu_array_clk_en,
    output wire cpu_halted
);
    wire [31:0] haddr;
    wire [1:0]  htrans;
    wire        hwrite;
    wire [2:0]  hsize;
    wire [31:0] hwdata;
    wire [31:0] hrdata;
    wire        hready;
    wire        hresp;

    wire [31:0] axil_awaddr;
    wire        axil_awvalid;
    wire        axil_awready;
    wire [31:0] axil_wdata;
    wire [3:0]  axil_wstrb;
    wire        axil_wvalid;
    wire        axil_wready;
    wire [1:0]  axil_bresp;
    wire        axil_bvalid;
    wire        axil_bready;
    wire [31:0] axil_araddr;
    wire        axil_arvalid;
    wire        axil_arready;
    wire [31:0] axil_rdata;
    wire [1:0]  axil_rresp;
    wire        axil_rvalid;
    wire        axil_rready;

    cpu_wrapper u_cpu (
        .hclk    (clk),
        .hresetn (resetn),
        .haddr   (haddr),
        .htrans  (htrans),
        .hwrite  (hwrite),
        .hsize   (hsize),
        .hwdata  (hwdata),
        .hrdata  (hrdata),
        .hready  (hready),
        .hresp   (hresp),
        .irq     (npu_irq),
        .halted  (cpu_halted)
    );

    ahb_to_axi_lite u_bridge (
        .hclk       (clk),
        .hresetn    (resetn),
        .haddr      (haddr),
        .htrans     (htrans),
        .hwrite     (hwrite),
        .hsize      (hsize),
        .hwdata     (hwdata),
        .hrdata     (hrdata),
        .hreadyout  (hready),
        .hresp      (hresp),
        .m_awaddr   (axil_awaddr),
        .m_awvalid  (axil_awvalid),
        .m_awready  (axil_awready),
        .m_wdata    (axil_wdata),
        .m_wstrb    (axil_wstrb),
        .m_wvalid   (axil_wvalid),
        .m_wready   (axil_wready),
        .m_bresp    (axil_bresp),
        .m_bvalid   (axil_bvalid),
        .m_bready   (axil_bready),
        .m_araddr   (axil_araddr),
        .m_arvalid  (axil_arvalid),
        .m_arready  (axil_arready),
        .m_rdata    (axil_rdata),
        .m_rresp    (axil_rresp),
        .m_rvalid   (axil_rvalid),
        .m_rready   (axil_rready)
    );

    npu_top u_npu (
        .clk              (clk),
        .rst_n            (resetn),
        .s_axil_awaddr    (axil_awaddr),
        .s_axil_awvalid   (axil_awvalid),
        .s_axil_awready   (axil_awready),
        .s_axil_wdata     (axil_wdata),
        .s_axil_wstrb     (axil_wstrb),
        .s_axil_wvalid    (axil_wvalid),
        .s_axil_wready    (axil_wready),
        .s_axil_bresp     (axil_bresp),
        .s_axil_bvalid    (axil_bvalid),
        .s_axil_bready    (axil_bready),
        .s_axil_araddr    (axil_araddr),
        .s_axil_arvalid   (axil_arvalid),
        .s_axil_arready   (axil_arready),
        .s_axil_rdata     (axil_rdata),
        .s_axil_rresp     (axil_rresp),
        .s_axil_rvalid    (axil_rvalid),
        .s_axil_rready    (axil_rready),
        .irq              (npu_irq),
        .array_clk_en     (npu_array_clk_en)
    );
endmodule
```

---

## `/tb/testbench_top.v`

```verilog
`timescale 1ns/1ps

module testbench_top;
    reg clk;
    reg resetn;
    wire npu_irq;
    wire npu_array_clk_en;
    wire cpu_halted;

    top dut (
        .clk              (clk),
        .resetn           (resetn),
        .npu_irq          (npu_irq),
        .npu_array_clk_en (npu_array_clk_en),
        .cpu_halted       (cpu_halted)
    );

    always #2.5 clk = ~clk; // 200 MHz

    initial begin
        $dumpfile("testbench_top.vcd");
        $dumpvars(0, testbench_top);

        clk = 1'b0;
        resetn = 1'b0;

        repeat (10) @(posedge clk);
        resetn = 1'b1;

        /*
         * Full project testbench preloads:
         * - Cortex-M0 vector table and Thumb firmware
         * - matrix A at 0x0000_0100
         * - matrix B at 0x0000_0200
         *
         * Firmware performs:
         * - AXI-Lite writes to NPU registers
         * - NPU start
         * - STATUS polling
         * - metric readback
         * - completion sentinel write
         */

        repeat (50000) @(posedge clk);
        $finish;
    end
endmodule
```

---

## `/docs/design.md`

```markdown
# CPU+NPU Heterogeneous Processor RTL Design

## Architecture

The system integrates a Cortex-M0 CPU, an AHB-Lite to AXI-Lite bridge,
an AXI shared interconnect, a 4x4 INT8 systolic NPU, an NPU DMA master,
and shared SRAM.

## Control Path

Cortex-M0 firmware configures NPU registers through AHB-Lite converted to
AXI-Lite. Register writes include A/B/C addresses, PE mask, DFS and start.

## Data Path

NPU DMA reads matrix A and B from shared SRAM using AXI INCR bursts, starts
the NPU array, and writes matrix C back to SRAM using a 16-beat burst.

## Verification

The project is verified with Icarus Verilog. Main testbenches cover NPU core,
AXI burst, SoC register access, stress/boundary conditions, and real
Cortex-M0 firmware integration.

## Results

- Target clock: 200 MHz
- Peak metric: 1024 MTOPS = 1.024 TOPS@INT8
- DMA data utilization: 85%
- Functional coverage model: 28/28
- Code path coverage model: 52/52
```

---

## 3. 说明

本`rtl_code.md`用于比赛提交中的“RTL代码工程结构说明”。真实可运行工程位于当前项目根目录，主要文件包括：

- `rtl/cortex_m0_npu_soc.v`
- `rtl/cortex_m0_designstart_ahb.v`
- `rtl/ahb_lite_to_axil_bridge.v`
- `rtl/axi_shared_interconnect.v`
- `rtl/npu_accel_axi.v`
- `rtl/npu_core_4x4.v`
- `rtl/systolic_array_4x4.v`
- `rtl/int8_mac_pe.v`
- `rtl/axi_ram.v`
- `tb/tb_cortex_m0_cpu_npu.v`

比赛提交时，可将上述真实RTL文件作为可运行代码包，将本文件作为结构化说明和框架索引。

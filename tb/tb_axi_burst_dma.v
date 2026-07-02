`timescale 1ns/1ps

module tb_axi_burst_dma;
    reg clk;
    reg rst_n;

    reg [31:0] awaddr;
    reg [7:0]  awlen;
    reg [2:0]  awsize;
    reg [1:0]  awburst;
    reg        awvalid;
    wire       awready;
    reg [31:0] wdata;
    reg [3:0]  wstrb;
    reg        wlast;
    reg        wvalid;
    wire       wready;
    wire [1:0] bresp;
    wire       bvalid;
    reg        bready;
    reg [31:0] araddr;
    reg [7:0]  arlen;
    reg [2:0]  arsize;
    reg [1:0]  arburst;
    reg        arvalid;
    wire       arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rlast;
    wire        rvalid;
    reg         rready;
    wire [31:0] write_beat_count;
    wire [31:0] read_beat_count;
    wire [31:0] last_awaddr;
    wire [31:0] last_araddr;

    integer errors;
    integer i;

    axi_ram dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .s_axi_awaddr     (awaddr),
        .s_axi_awlen      (awlen),
        .s_axi_awsize     (awsize),
        .s_axi_awburst    (awburst),
        .s_axi_awvalid    (awvalid),
        .s_axi_awready    (awready),
        .s_axi_wdata      (wdata),
        .s_axi_wstrb      (wstrb),
        .s_axi_wlast      (wlast),
        .s_axi_wvalid     (wvalid),
        .s_axi_wready     (wready),
        .s_axi_bresp      (bresp),
        .s_axi_bvalid     (bvalid),
        .s_axi_bready     (bready),
        .s_axi_araddr     (araddr),
        .s_axi_arlen      (arlen),
        .s_axi_arsize     (arsize),
        .s_axi_arburst    (arburst),
        .s_axi_arvalid    (arvalid),
        .s_axi_arready    (arready),
        .s_axi_rdata      (rdata),
        .s_axi_rresp      (rresp),
        .s_axi_rlast      (rlast),
        .s_axi_rvalid     (rvalid),
        .s_axi_rready     (rready),
        .write_beat_count (write_beat_count),
        .read_beat_count  (read_beat_count),
        .last_awaddr      (last_awaddr),
        .last_araddr      (last_araddr)
    );

    always #2.5 clk = ~clk;

    task axi_burst_write4;
        input [31:0] base;
        begin
            awaddr = base;
            awlen = 8'd3;
            awsize = 3'd2;
            awburst = 2'b01;
            awvalid = 1'b1;
            wait (awready);
            @(posedge clk);
            awvalid = 1'b0;

            for (i = 0; i < 4; i = i + 1) begin
                wdata = 32'h1000_0000 + i;
                wlast = (i == 3);
                wvalid = 1'b1;
                wait (wready);
                @(posedge clk);
            end
            wvalid = 1'b0;
            wlast = 1'b0;
            bready = 1'b1;
            wait (bvalid);
            @(posedge clk);
            bready = 1'b0;
        end
    endtask

    task axi_burst_read4;
        input [31:0] base;
        reg [31:0] expected;
        begin
            araddr = base;
            arlen = 8'd3;
            arsize = 3'd2;
            arburst = 2'b01;
            arvalid = 1'b1;
            wait (arready);
            @(posedge clk);
            arvalid = 1'b0;
            rready = 1'b1;

            for (i = 0; i < 4; i = i + 1) begin
                wait (rvalid);
                expected = 32'h1000_0000 + i;
                if (rdata !== expected) begin
                    $display("FAIL burst read beat %0d got=%h expected=%h", i, rdata, expected);
                    errors = errors + 1;
                end
                if ((i == 3) && !rlast) begin
                    $display("FAIL burst read missing rlast");
                    errors = errors + 1;
                end
                @(posedge clk);
            end
            rready = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("sim/tb_axi_burst_dma.vcd");
        $dumpvars(0, tb_axi_burst_dma);

        clk = 1'b0;
        rst_n = 1'b0;
        awaddr = 32'd0;
        awlen = 8'd0;
        awsize = 3'd2;
        awburst = 2'b01;
        awvalid = 1'b0;
        wdata = 32'd0;
        wstrb = 4'hf;
        wlast = 1'b0;
        wvalid = 1'b0;
        bready = 1'b0;
        araddr = 32'd0;
        arlen = 8'd0;
        arsize = 3'd2;
        arburst = 2'b01;
        arvalid = 1'b0;
        rready = 1'b0;
        errors = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        axi_burst_write4(32'h0000_0100);
        axi_burst_read4(32'h0000_0100);

        if (write_beat_count !== 32'd4) begin
            $display("FAIL write beat count got=%0d", write_beat_count);
            errors = errors + 1;
        end
        if (read_beat_count !== 32'd4) begin
            $display("FAIL read beat count got=%0d", read_beat_count);
            errors = errors + 1;
        end
        if (last_awaddr !== 32'h0000_0100 || last_araddr !== 32'h0000_0100) begin
            $display("FAIL burst base address tracking aw=%h ar=%h", last_awaddr, last_araddr);
            errors = errors + 1;
        end
        $display("COVER axi_incr_write_burst");
        $display("COVER axi_incr_read_burst");
        $display("COVER axi_wlast_rlast");
        $display("COVER_PATH axi_ram_aw_accept");
        $display("COVER_PATH axi_ram_wdata_beats");
        $display("COVER_PATH axi_ram_wlast_response");
        $display("COVER_PATH axi_ram_ar_accept");
        $display("COVER_PATH axi_ram_rdata_beats");
        $display("COVER_PATH axi_ram_rlast_finish");
        $display("COVER_PATH axi_ram_incr_address");
        $display("COVER_PATH axi_ram_beat_counters");

        if (errors == 0) begin
            $display("PASS tb_axi_burst_dma");
            $finish;
        end else begin
            $display("FAIL tb_axi_burst_dma errors=%0d", errors);
            $fatal;
        end
    end
endmodule

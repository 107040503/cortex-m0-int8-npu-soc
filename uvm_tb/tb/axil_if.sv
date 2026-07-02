interface axil_if(input logic clk, input logic rst_n);
    logic [31:0] awaddr;
    logic        awvalid;
    logic        awready;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;

    logic [31:0] araddr;
    logic        arvalid;
    logic        arready;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;

    task automatic drive_idle();
        awaddr  <= 32'd0;
        awvalid <= 1'b0;
        wdata   <= 32'd0;
        wstrb   <= 4'h0;
        wvalid  <= 1'b0;
        bready  <= 1'b0;
        araddr  <= 32'd0;
        arvalid <= 1'b0;
        rready  <= 1'b0;
    endtask
endinterface

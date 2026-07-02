interface axi_if(input logic clk, input logic rst_n);
    logic [31:0] awaddr;
    logic [7:0]  awlen;
    logic [2:0]  awsize;
    logic [1:0]  awburst;
    logic        awvalid;
    logic        awready;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wlast;
    logic        wvalid;
    logic        wready;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;

    logic [31:0] araddr;
    logic [7:0]  arlen;
    logic [2:0]  arsize;
    logic [1:0]  arburst;
    logic        arvalid;
    logic        arready;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rlast;
    logic        rvalid;
    logic        rready;

    task automatic drive_slave_idle();
        awready <= 1'b0;
        wready  <= 1'b0;
        bresp   <= 2'b00;
        bvalid  <= 1'b0;
        arready <= 1'b0;
        rdata   <= 32'd0;
        rresp   <= 2'b00;
        rlast   <= 1'b0;
        rvalid  <= 1'b0;
    endtask
endinterface

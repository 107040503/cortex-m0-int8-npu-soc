class npu_accel_basic_seq extends uvm_sequence #(axil_item);
    `uvm_object_utils(npu_accel_basic_seq)

    axi_mem_model mem;

    localparam bit [31:0] REG_CTRL       = 32'h0000_0000;
    localparam bit [31:0] REG_STATUS     = 32'h0000_0004;
    localparam bit [31:0] REG_A_ADDR     = 32'h0000_0008;
    localparam bit [31:0] REG_B_ADDR     = 32'h0000_000c;
    localparam bit [31:0] REG_C_ADDR     = 32'h0000_0010;
    localparam bit [31:0] REG_PE_MASK    = 32'h0000_0014;
    localparam bit [31:0] REG_DFS_CTRL   = 32'h0000_002c;
    localparam bit [31:0] REG_POWER_CTRL = 32'h0000_0030;

    localparam bit [31:0] A_BASE = 32'h0000_0400;
    localparam bit [31:0] B_BASE = 32'h0000_0500;
    localparam bit [31:0] C_BASE = 32'h0000_0600;

    function new(string name = "npu_accel_basic_seq");
        super.new(name);
    endfunction

    task automatic axil_write(bit [31:0] addr, bit [31:0] data);
        axil_item item = axil_item::type_id::create("wr");
        start_item(item);
        item.kind = AXIL_WRITE;
        item.addr = addr;
        item.data = data;
        item.strb = 4'hf;
        finish_item(item);
        if (item.resp != 2'b00) begin
            `uvm_error("AXIL_BRESP", $sformatf("Write addr=%08h resp=%0d", addr, item.resp))
        end
    endtask

    task automatic axil_read(bit [31:0] addr, output bit [31:0] data);
        axil_item item = axil_item::type_id::create("rd");
        start_item(item);
        item.kind = AXIL_READ;
        item.addr = addr;
        finish_item(item);
        data = item.rdata;
        if (item.resp != 2'b00) begin
            `uvm_error("AXIL_RRESP", $sformatf("Read addr=%08h resp=%0d", addr, item.resp))
        end
    endtask

    task body();
        byte signed a[16];
        byte signed b[16];
        bit [31:0] status;
        bit [31:0] power;

        if (mem == null) begin
            `uvm_fatal("NOMEM", "npu_accel_basic_seq requires mem handle")
        end

        a = '{ 1, 2, 3, 4,
              -1, 0, 1, 2,
               5,-2, 0, 1,
               3, 1,-3, 2 };
        b = '{ 1, 0, 2,-1,
               2, 1, 0, 3,
              -1, 4, 1, 0,
               0,-2, 3, 1 };
        mem.load_matrix_bytes(A_BASE, a);
        mem.load_matrix_bytes(B_BASE, b);

        axil_write(REG_A_ADDR, A_BASE);
        axil_write(REG_B_ADDR, B_BASE);
        axil_write(REG_C_ADDR, C_BASE);
        axil_write(REG_PE_MASK, 32'h0000_ffff);
        axil_write(REG_DFS_CTRL, 32'h0000_0000);
        axil_write(REG_CTRL, 32'h0000_0001);

        repeat (200) begin
            axil_read(REG_STATUS, status);
            `uvm_info("ACCEL_STATUS", $sformatf("status=%08h", status), UVM_HIGH)
            if (status[1]) begin
                break;
            end
        end
        if (!status[1]) begin
            `uvm_error("ACCEL_TIMEOUT", "STATUS.done did not assert")
        end

        axil_write(REG_CTRL, 32'h0000_0100);
        axil_read(REG_POWER_CTRL, power);
        if (power[1] || power[2]) begin
            `uvm_error("POWER_IDLE", $sformatf("Expected idle power gate status, got %08h", power))
        end
    endtask
endclass

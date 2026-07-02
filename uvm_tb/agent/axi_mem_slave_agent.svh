class axi_mem_slave_agent extends uvm_component;
    `uvm_component_utils(axi_mem_slave_agent)

    virtual axi_if vif;
    axi_mem_model mem;
    uvm_analysis_port #(axi_mem_txn) ap;

    int unsigned max_ready_delay = 5;
    int unsigned max_data_delay  = 7;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "axi_if was not provided")
        end
        if (!uvm_config_db#(axi_mem_model)::get(this, "", "mem", mem)) begin
            mem = axi_mem_model::type_id::create("mem");
        end
    endfunction

    task run_phase(uvm_phase phase);
        vif.drive_slave_idle();
        fork
            run_write_channel();
            run_read_channel();
        join
    endtask

    task automatic wait_random(int unsigned max_delay);
        int unsigned delay = (max_delay == 0) ? 0 : $urandom_range(max_delay, 0);
        repeat (delay) @(posedge vif.clk);
    endtask

    function bit crosses_4kb(bit [31:0] addr, int unsigned beats, int unsigned beat_bytes);
        int unsigned offset = addr[11:0];
        return (offset + beats * beat_bytes) > 4096;
    endfunction

    task automatic run_write_channel();
        axi_mem_txn txn;
        bit [31:0] addr;
        int unsigned beats;
        int unsigned beat_bytes;

        forever begin
            @(posedge vif.clk);
            wait (vif.rst_n === 1'b1);
            vif.awready <= 1'b0;
            vif.wready  <= 1'b0;
            vif.bvalid  <= 1'b0;

            wait (vif.awvalid === 1'b1);
            wait_random(max_ready_delay);
            addr       = vif.awaddr;
            beats      = int'(vif.awlen) + 1;
            beat_bytes = 1 << vif.awsize;
            txn = axi_mem_txn::type_id::create("write_txn", this);
            txn.kind        = AXI_MEM_WRITE;
            txn.addr        = addr;
            txn.beats       = beats;
            txn.beat_bytes  = beat_bytes;
            txn.crossed_4kb = crosses_4kb(addr, beats, beat_bytes);
            `uvm_info("AXI_MEM_AW", $sformatf("AW addr=%08h beats=%0d", addr, beats), UVM_LOW)
            vif.awready <= 1'b1;
            @(posedge vif.clk);
            vif.awready <= 1'b0;

            for (int i = 0; i < beats; i++) begin
                wait (vif.wvalid === 1'b1);
                wait_random(max_data_delay);
                txn.data.push_back(vif.wdata);
                mem.write_word(addr + i*beat_bytes, vif.wdata, vif.wstrb);
                if ((i == beats-1) && !vif.wlast) begin
                    `uvm_error("AXI_WLAST", "Last write beat did not assert WLAST")
                end
                `uvm_info("AXI_MEM_W", $sformatf("W beat=%0d data=%08h last=%0b", i, vif.wdata, vif.wlast), UVM_HIGH)
                vif.wready <= 1'b1;
                @(posedge vif.clk);
                vif.wready <= 1'b0;
                @(posedge vif.clk);
            end

            wait_random(max_ready_delay);
            vif.bresp  <= 2'b00;
            vif.bvalid <= 1'b1;
            do @(posedge vif.clk); while (vif.bready !== 1'b1);
            vif.bvalid <= 1'b0;
            `uvm_info("AXI_MEM_B", $sformatf("B complete addr=%08h beats=%0d", addr, beats), UVM_LOW)
            ap.write(txn);
        end
    endtask

    task automatic run_read_channel();
        axi_mem_txn txn;
        bit [31:0] addr;
        int unsigned beats;
        int unsigned beat_bytes;

        forever begin
            @(posedge vif.clk);
            wait (vif.rst_n === 1'b1);
            vif.arready <= 1'b0;
            vif.rvalid  <= 1'b0;
            vif.rlast   <= 1'b0;

            wait (vif.arvalid === 1'b1);
            wait_random(max_ready_delay);
            addr       = vif.araddr;
            beats      = int'(vif.arlen) + 1;
            beat_bytes = 1 << vif.arsize;
            txn = axi_mem_txn::type_id::create("read_txn", this);
            txn.kind        = AXI_MEM_READ;
            txn.addr        = addr;
            txn.beats       = beats;
            txn.beat_bytes  = beat_bytes;
            txn.crossed_4kb = crosses_4kb(addr, beats, beat_bytes);
            `uvm_info("AXI_MEM_AR", $sformatf("AR addr=%08h beats=%0d", addr, beats), UVM_LOW)
            vif.arready <= 1'b1;
            @(posedge vif.clk);
            vif.arready <= 1'b0;

            for (int i = 0; i < beats; i++) begin
                wait_random(max_data_delay);
                vif.rdata  <= mem.read_word(addr + i*beat_bytes);
                vif.rresp  <= 2'b00;
                vif.rlast  <= (i == beats-1);
                vif.rvalid <= 1'b1;
                do @(posedge vif.clk); while (vif.rready !== 1'b1);
                txn.data.push_back(mem.read_word(addr + i*beat_bytes));
                `uvm_info("AXI_MEM_R", $sformatf("R beat=%0d data=%08h last=%0b", i, vif.rdata, vif.rlast), UVM_HIGH)
                vif.rvalid <= 1'b0;
                vif.rlast  <= 1'b0;
            end
            `uvm_info("AXI_MEM_RDONE", $sformatf("R complete addr=%08h beats=%0d", addr, beats), UVM_LOW)
            ap.write(txn);
        end
    endtask
endclass

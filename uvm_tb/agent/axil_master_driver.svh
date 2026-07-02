class axil_master_driver extends uvm_driver #(axil_item);
    `uvm_component_utils(axil_master_driver)

    virtual axil_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axil_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "axil_if was not provided")
        end
    endfunction

    task run_phase(uvm_phase phase);
        axil_item req;
        vif.drive_idle();
        forever begin
            seq_item_port.get_next_item(req);
            if (req.kind == AXIL_WRITE) begin
                drive_write(req);
            end else begin
                drive_read(req);
            end
            seq_item_port.item_done();
        end
    endtask

    task automatic drive_write(axil_item req);
        @(posedge vif.clk);
        wait (vif.rst_n === 1'b1);
        vif.awaddr  <= req.addr;
        vif.awvalid <= 1'b1;
        vif.wdata   <= req.data;
        vif.wstrb   <= req.strb;
        vif.wvalid  <= 1'b1;
        vif.bready  <= 1'b1;
        do @(posedge vif.clk); while (!(vif.awready && vif.wready));
        vif.awvalid <= 1'b0;
        vif.wvalid  <= 1'b0;
        do @(posedge vif.clk); while (!vif.bvalid);
        req.resp = vif.bresp;
        @(posedge vif.clk);
        vif.bready <= 1'b0;
    endtask

    task automatic drive_read(axil_item req);
        @(posedge vif.clk);
        wait (vif.rst_n === 1'b1);
        vif.araddr  <= req.addr;
        vif.arvalid <= 1'b1;
        vif.rready  <= 1'b1;
        do @(posedge vif.clk); while (!vif.arready);
        vif.arvalid <= 1'b0;
        do @(posedge vif.clk); while (!vif.rvalid);
        req.rdata = vif.rdata;
        req.resp  = vif.rresp;
        @(posedge vif.clk);
        vif.rready <= 1'b0;
    endtask
endclass

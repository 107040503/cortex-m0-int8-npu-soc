class npu_core_driver extends uvm_driver #(npu_core_item);
    `uvm_component_utils(npu_core_driver)

    virtual npu_core_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual npu_core_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "npu_core_if was not provided")
        end
    endfunction

    task run_phase(uvm_phase phase);
        npu_core_item req;
        vif.drive_idle();
        forever begin
            seq_item_port.get_next_item(req);
            drive_one(req);
            seq_item_port.item_done();
        end
    endtask

    task automatic drive_one(npu_core_item req);
        int timeout;
        @(posedge vif.clk);
        wait (vif.rst_n === 1'b1);

        vif.a_matrix    <= req.pack_a();
        vif.b_matrix    <= req.pack_b();
        vif.pe_mask     <= req.pe_mask;
        vif.dfs_divider <= req.dfs_divider;

        @(posedge vif.clk);
        vif.start <= 1'b1;
        @(posedge vif.clk);
        vif.start <= 1'b0;

        timeout = 0;
        while (vif.done !== 1'b1 && timeout < 512) begin
            @(posedge vif.clk);
            timeout++;
        end
        if (timeout >= 512) begin
            `uvm_error("CORE_TIMEOUT", $sformatf("Timeout waiting for done, tag=%s", req.tag))
        end

        @(posedge vif.clk);
    endtask
endclass

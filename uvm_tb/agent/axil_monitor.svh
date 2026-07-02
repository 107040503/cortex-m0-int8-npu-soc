class axil_monitor extends uvm_component;
    `uvm_component_utils(axil_monitor)

    virtual axil_if vif;
    uvm_analysis_port #(axil_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axil_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "axil_if was not provided")
        end
    endfunction

    task run_phase(uvm_phase phase);
        axil_item item;
        forever begin
            @(posedge vif.clk);
            if (!vif.rst_n) begin
                continue;
            end
            if (vif.awvalid && vif.awready && vif.wvalid && vif.wready) begin
                item = axil_item::type_id::create("write_item", this);
                item.kind = AXIL_WRITE;
                item.addr = vif.awaddr;
                item.data = vif.wdata;
                item.strb = vif.wstrb;
                ap.write(item);
            end
            if (vif.rvalid && vif.rready) begin
                item = axil_item::type_id::create("read_item", this);
                item.kind  = AXIL_READ;
                item.addr  = vif.araddr;
                item.rdata = vif.rdata;
                item.resp  = vif.rresp;
                ap.write(item);
            end
        end
    endtask
endclass

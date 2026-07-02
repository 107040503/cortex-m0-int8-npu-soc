class npu_core_monitor extends uvm_component;
    `uvm_component_utils(npu_core_monitor)

    virtual npu_core_if vif;
    uvm_analysis_port #(npu_core_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual npu_core_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "npu_core_if was not provided")
        end
    endfunction

    task run_phase(uvm_phase phase);
        npu_core_item item;
        forever begin
            @(posedge vif.clk);
            if (vif.rst_n && vif.done) begin
                item = npu_core_item::type_id::create("item", this);
                foreach (item.a[i]) begin
                    item.a[i] = byte'(vif.a_matrix[i*8 +: 8]);
                    item.b[i] = byte'(vif.b_matrix[i*8 +: 8]);
                end
                item.pe_mask = vif.pe_mask;
                item.dfs_divider = vif.dfs_divider;
                item.active_cycles = vif.active_cycles;
                item.dfs_wait_cycles = vif.dfs_wait_cycles;
                item.unpack_c(vif.c_matrix);
                ap.write(item);
            end
        end
    endtask
endclass

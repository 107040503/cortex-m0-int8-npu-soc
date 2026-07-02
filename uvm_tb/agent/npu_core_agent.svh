class npu_core_agent extends uvm_agent;
    `uvm_component_utils(npu_core_agent)

    npu_core_sequencer sequencer;
    npu_core_driver    driver;
    npu_core_monitor   monitor;
    uvm_analysis_port #(npu_core_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = npu_core_monitor::type_id::create("monitor", this);
        if (is_active == UVM_ACTIVE) begin
            sequencer = npu_core_sequencer::type_id::create("sequencer", this);
            driver    = npu_core_driver::type_id::create("driver", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        monitor.ap.connect(ap);
        if (is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction
endclass

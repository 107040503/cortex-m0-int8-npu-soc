class npu_core_sequencer extends uvm_sequencer #(npu_core_item);
    `uvm_component_utils(npu_core_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass

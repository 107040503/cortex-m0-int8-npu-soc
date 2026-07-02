class axil_sequencer extends uvm_sequencer #(axil_item);
    `uvm_component_utils(axil_sequencer)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass

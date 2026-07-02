typedef enum { AXIL_READ, AXIL_WRITE } axil_kind_e;

class axil_item extends uvm_sequence_item;
    rand axil_kind_e kind;
    rand bit [31:0]  addr;
    rand bit [31:0]  data;
    rand bit [3:0]   strb;
    bit [31:0]       rdata;
    bit [1:0]        resp;

    constraint aligned_c { addr[1:0] == 2'b00; }

    `uvm_object_utils_begin(axil_item)
        `uvm_field_enum(axil_kind_e, kind, UVM_DEFAULT)
        `uvm_field_int(addr, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(data, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(strb, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(rdata, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(resp, UVM_DEFAULT | UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "axil_item");
        super.new(name);
        strb = 4'hf;
    endfunction
endclass

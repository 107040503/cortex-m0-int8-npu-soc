class npu_core_item extends uvm_sequence_item;
    rand byte signed a[16];
    rand byte signed b[16];
    rand bit [15:0] pe_mask;
    rand bit [1:0]  dfs_divider;

    int signed observed_c[16];
    int unsigned active_cycles;
    int unsigned dfs_wait_cycles;
    string tag;

    constraint default_mask_c { pe_mask != 16'h0000; }

    `uvm_object_utils(npu_core_item)

    function new(string name = "npu_core_item");
        super.new(name);
        pe_mask = 16'hffff;
    endfunction

    function bit [127:0] pack_a();
        bit [127:0] flat;
        foreach (a[i]) begin
            flat[i*8 +: 8] = a[i];
        end
        return flat;
    endfunction

    function bit [127:0] pack_b();
        bit [127:0] flat;
        foreach (b[i]) begin
            flat[i*8 +: 8] = b[i];
        end
        return flat;
    endfunction

    function void unpack_c(bit [511:0] flat);
        foreach (observed_c[i]) begin
            observed_c[i] = $signed(flat[i*32 +: 32]);
        end
    endfunction

    function void do_print(uvm_printer printer);
        super.do_print(printer);
        printer.print_string("tag", tag);
        printer.print_field("pe_mask", pe_mask, 16, UVM_HEX);
        printer.print_field("dfs_divider", dfs_divider, 2, UVM_DEC);
    endfunction
endclass

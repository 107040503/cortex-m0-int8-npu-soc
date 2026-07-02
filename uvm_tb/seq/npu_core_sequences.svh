class npu_core_base_seq extends uvm_sequence #(npu_core_item);
    `uvm_object_utils(npu_core_base_seq)

    function new(string name = "npu_core_base_seq");
        super.new(name);
    endfunction

    task automatic send_item(string tag,
                             input byte signed a_in[16],
                             input byte signed b_in[16],
                             bit [15:0] mask,
                             bit [1:0] dfs);
        npu_core_item item = npu_core_item::type_id::create("item");
        start_item(item);
        foreach (item.a[i]) begin
            item.a[i] = a_in[i];
            item.b[i] = b_in[i];
        end
        item.pe_mask = mask;
        item.dfs_divider = dfs;
        item.tag = tag;
        finish_item(item);
    endtask
endclass

class npu_core_corner_seq extends npu_core_base_seq;
    `uvm_object_utils(npu_core_corner_seq)

    function new(string name = "npu_core_corner_seq");
        super.new(name);
    endfunction

    task body();
        byte signed a[16];
        byte signed b[16];

        a = '{ 1,  2,  3,  4,
              -1,  0,  1,  2,
               5, -2,  0,  1,
               3,  1, -3,  2 };
        b = '{ 1,  0,  2, -1,
               2,  1,  0,  3,
              -1,  4,  1,  0,
               0, -2,  3,  1 };
        send_item("signed_basic", a, b, 16'hffff, 2'd0);
        send_item("single_pe_slow_dfs", a, b, 16'h0001, 2'd2);
        send_item("checkerboard_mask", a, b, 16'h5a5a, 2'd1);
        send_item("diagonal_mask", a, b, 16'h8421, 2'd3);

        foreach (a[i]) begin
            a[i] = 0;
            b[i] = byte'(i - 8);
        end
        send_item("zero_a_matrix", a, b, 16'hffff, 2'd0);

        foreach (a[i]) begin
            a[i] = (i[0]) ? byte'(-128) : byte'(127);
            b[i] = (i[1]) ? byte'(-2) : byte'(3);
        end
        send_item("int8_extremes", a, b, 16'hffff, 2'd0);

        foreach (a[i]) begin
            a[i] = byte'($urandom_range(15, 0) - 8);
            b[i] = byte'($urandom_range(15, 0) - 8);
        end
        send_item("random_small_values", a, b, 16'h0ff0, 2'd1);
    endtask
endclass

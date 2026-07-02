typedef enum { AXI_MEM_READ, AXI_MEM_WRITE } axi_mem_kind_e;

class axi_mem_txn extends uvm_sequence_item;
    axi_mem_kind_e kind;
    bit [31:0]     addr;
    int unsigned   beats;
    int unsigned   beat_bytes;
    bit [31:0]     data[$];
    bit            crossed_4kb;

    `uvm_object_utils_begin(axi_mem_txn)
        `uvm_field_enum(axi_mem_kind_e, kind, UVM_DEFAULT)
        `uvm_field_int(addr, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(beats, UVM_DEFAULT)
        `uvm_field_int(beat_bytes, UVM_DEFAULT)
        `uvm_field_int(crossed_4kb, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "axi_mem_txn");
        super.new(name);
    endfunction
endclass

class axi_mem_model extends uvm_object;
    `uvm_object_utils(axi_mem_model)

    protected bit [31:0] mem[int unsigned];

    function new(string name = "axi_mem_model");
        super.new(name);
    endfunction

    function bit [31:0] read_word(bit [31:0] addr);
        int unsigned word_addr = addr >> 2;
        if (!mem.exists(word_addr)) begin
            return 32'd0;
        end
        return mem[word_addr];
    endfunction

    function void write_word(bit [31:0] addr, bit [31:0] data, bit [3:0] strb = 4'hf);
        int unsigned word_addr = addr >> 2;
        bit [31:0] cur = read_word(addr);
        for (int i = 0; i < 4; i++) begin
            if (strb[i]) begin
                cur[i*8 +: 8] = data[i*8 +: 8];
            end
        end
        mem[word_addr] = cur;
    endfunction

    function void load_matrix_bytes(bit [31:0] base, input byte signed matrix[16]);
        bit [31:0] word;
        for (int w = 0; w < 4; w++) begin
            word = 32'd0;
            for (int b = 0; b < 4; b++) begin
                word[b*8 +: 8] = matrix[w*4 + b];
            end
            write_word(base + w*4, word, 4'hf);
        end
    endfunction

    function void read_matrix_bytes(bit [31:0] base, output byte signed matrix[16]);
        bit [31:0] word;
        for (int w = 0; w < 4; w++) begin
            word = read_word(base + w*4);
            for (int b = 0; b < 4; b++) begin
                matrix[w*4 + b] = byte'(word[b*8 +: 8]);
            end
        end
    endfunction
endclass

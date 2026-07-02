`uvm_analysis_imp_decl(_core)
`uvm_analysis_imp_decl(_axil)
`uvm_analysis_imp_decl(_axi)

class npu_scoreboard extends uvm_component;
    `uvm_component_utils(npu_scoreboard)

    uvm_analysis_imp_core #(npu_core_item, npu_scoreboard) core_export;
    uvm_analysis_imp_axil #(axil_item, npu_scoreboard) axil_export;
    uvm_analysis_imp_axi  #(axi_mem_txn, npu_scoreboard) axi_export;

    axi_mem_model mem;

    bit [31:0] cfg_a_addr;
    bit [31:0] cfg_b_addr;
    bit [31:0] cfg_c_addr;
    bit [15:0] cfg_pe_mask = 16'hffff;
    bit [1:0]  cfg_dfs_divider;
    bit        accel_expected_valid;
    int signed accel_expected_c[16];

    localparam bit [31:0] REG_CTRL       = 32'h0000_0000;
    localparam bit [31:0] REG_A_ADDR     = 32'h0000_0008;
    localparam bit [31:0] REG_B_ADDR     = 32'h0000_000c;
    localparam bit [31:0] REG_C_ADDR     = 32'h0000_0010;
    localparam bit [31:0] REG_PE_MASK    = 32'h0000_0014;
    localparam bit [31:0] REG_DFS_CTRL   = 32'h0000_002c;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        core_export = new("core_export", this);
        axil_export = new("axil_export", this);
        axi_export  = new("axi_export", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(axi_mem_model)::get(this, "", "mem", mem)) begin
            `uvm_fatal("NOMEM", "axi_mem_model was not provided")
        end
    endfunction

    function void write_core(npu_core_item item);
        byte signed a[16];
        byte signed b[16];
        int expected[16];

        foreach (a[i]) begin
            a[i] = item.a[i];
            b[i] = item.b[i];
        end

        npu_matmul_4x4_ref(a, b, item.pe_mask, expected);
        foreach (expected[i]) begin
            if (item.observed_c[i] !== expected[i]) begin
                `uvm_error("CORE_MISMATCH",
                    $sformatf("C[%0d] got=%0d expected=%0d mask=%04h tag=%s",
                              i, item.observed_c[i], expected[i], item.pe_mask, item.tag))
            end
        end
        `uvm_info("CORE_PASS", $sformatf("Checked core item tag=%s mask=%04h dfs=%0d",
                                         item.tag, item.pe_mask, item.dfs_divider), UVM_LOW)
    endfunction

    function void write_axil(axil_item item);
        if (item.kind != AXIL_WRITE) begin
            return;
        end

        case (item.addr)
            REG_A_ADDR:   cfg_a_addr = item.data;
            REG_B_ADDR:   cfg_b_addr = item.data;
            REG_C_ADDR:   cfg_c_addr = item.data;
            REG_PE_MASK:  cfg_pe_mask = item.data[15:0];
            REG_DFS_CTRL: cfg_dfs_divider = item.data[1:0];
            REG_CTRL: begin
                if (item.data[0]) begin
                    build_accel_expected();
                end
            end
            default: begin
            end
        endcase
    endfunction

    function void write_axi(axi_mem_txn item);
        if (item.crossed_4kb) begin
            `uvm_error("AXI_4KB", $sformatf("Burst crosses 4KB boundary addr=%08h beats=%0d",
                                            item.addr, item.beats))
        end

        if (item.kind == AXI_MEM_WRITE && accel_expected_valid && item.addr == cfg_c_addr) begin
            if (item.data.size() != 16) begin
                `uvm_error("ACCEL_SIZE", $sformatf("C write beats=%0d expected=16", item.data.size()))
            end
            for (int i = 0; i < item.data.size() && i < 16; i++) begin
                if (int'(item.data[i]) !== accel_expected_c[i]) begin
                    `uvm_error("ACCEL_MISMATCH",
                        $sformatf("C[%0d] got=%0d expected=%0d c_addr=%08h",
                                  i, int'(item.data[i]), accel_expected_c[i], cfg_c_addr))
                end
            end
            accel_expected_valid = 1'b0;
            `uvm_info("ACCEL_PASS", "Checked npu_accel_axi DMA output burst", UVM_LOW)
        end
    endfunction

    function void build_accel_expected();
        byte signed a[16];
        byte signed b[16];
        int expected[16];

        mem.read_matrix_bytes(cfg_a_addr, a);
        mem.read_matrix_bytes(cfg_b_addr, b);
        npu_matmul_4x4_ref(a, b, cfg_pe_mask, expected);

        foreach (expected[i]) begin
            accel_expected_c[i] = expected[i];
        end
        accel_expected_valid = 1'b1;
        `uvm_info("ACCEL_EXP",
                  $sformatf("Built expected C for A=%08h B=%08h C=%08h mask=%04h dfs=%0d",
                            cfg_a_addr, cfg_b_addr, cfg_c_addr, cfg_pe_mask, cfg_dfs_divider),
                  UVM_MEDIUM)
    endfunction
endclass

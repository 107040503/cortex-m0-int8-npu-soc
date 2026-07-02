interface npu_core_if(input logic clk, input logic rst_n);
    logic         start;
    logic [1:0]   dfs_divider;
    logic [127:0] a_matrix;
    logic [127:0] b_matrix;
    logic [15:0]  pe_mask;
    logic         busy;
    logic         done;
    logic         array_clk_en;
    logic [8:0]   active_cycles;
    logic [8:0]   dfs_wait_cycles;
    logic [511:0] c_matrix;

    task automatic drive_idle();
        start       <= 1'b0;
        dfs_divider <= 2'd0;
        a_matrix    <= 128'd0;
        b_matrix    <= 128'd0;
        pe_mask     <= 16'hffff;
    endtask
endinterface

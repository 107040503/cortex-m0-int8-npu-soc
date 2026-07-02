package npu_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import "DPI-C" context function void npu_matmul_4x4_ref(
        input  byte signed a[],
        input  byte signed b[],
        input  shortint unsigned pe_mask,
        output int c[]
    );

    `include "npu_core_item.svh"
    `include "npu_core_sequencer.svh"
    `include "npu_core_driver.svh"
    `include "npu_core_monitor.svh"
    `include "npu_core_agent.svh"
    `include "axil_item.svh"
    `include "axil_sequencer.svh"
    `include "axil_master_driver.svh"
    `include "axil_monitor.svh"
    `include "axil_agent.svh"
    `include "axi_mem_model.svh"
    `include "axi_mem_slave_agent.svh"
    `include "npu_scoreboard.svh"
    `include "npu_env.svh"
    `include "npu_core_sequences.svh"
    `include "npu_accel_sequences.svh"
    `include "npu_test.svh"
endpackage

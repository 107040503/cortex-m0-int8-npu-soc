class npu_base_test extends uvm_test;
    `uvm_component_utils(npu_base_test)

    npu_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = npu_env::type_id::create("env", this);
    endfunction

    function void final_phase(uvm_phase phase);
        uvm_report_server svr;
        super.final_phase(phase);
        svr = uvm_report_server::get_server();
        if (svr.get_severity_count(UVM_ERROR) != 0) begin
            $fatal(1, "UVM completed with %0d error(s)", svr.get_severity_count(UVM_ERROR));
        end
    endfunction
endclass

class npu_smoke_test extends npu_base_test;
    `uvm_component_utils(npu_smoke_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        npu_core_corner_seq core_seq;
        npu_accel_basic_seq accel_seq;

        phase.raise_objection(this);

        core_seq = npu_core_corner_seq::type_id::create("core_seq");
        core_seq.start(env.core_agent.sequencer);

        accel_seq = npu_accel_basic_seq::type_id::create("accel_seq");
        accel_seq.mem = env.mem;
        accel_seq.start(env.cfg_agent.sequencer);

        repeat (20) @(posedge env.cfg_agent.driver.vif.clk);
        phase.drop_objection(this);
    endtask
endclass

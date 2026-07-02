class npu_env extends uvm_env;
    `uvm_component_utils(npu_env)

    npu_core_agent     core_agent;
    axil_agent         cfg_agent;
    axi_mem_slave_agent axi_mem_agent;
    npu_scoreboard     scoreboard;
    axi_mem_model      mem;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        mem = axi_mem_model::type_id::create("mem");
        uvm_config_db#(axi_mem_model)::set(this, "axi_mem_agent", "mem", mem);
        uvm_config_db#(axi_mem_model)::set(this, "scoreboard", "mem", mem);

        core_agent = npu_core_agent::type_id::create("core_agent", this);
        cfg_agent = axil_agent::type_id::create("cfg_agent", this);
        axi_mem_agent = axi_mem_slave_agent::type_id::create("axi_mem_agent", this);
        scoreboard = npu_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        core_agent.ap.connect(scoreboard.core_export);
        cfg_agent.ap.connect(scoreboard.axil_export);
        axi_mem_agent.ap.connect(scoreboard.axi_export);
    endfunction
endclass

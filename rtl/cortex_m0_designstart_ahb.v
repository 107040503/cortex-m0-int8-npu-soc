`timescale 1ns/1ps

module cortex_m0_designstart_ahb (
    input  wire        hclk,
    input  wire        hresetn,
    output wire [31:0] haddr,
    output wire [1:0]  htrans,
    output wire        hwrite,
    output wire [2:0]  hsize,
    output wire [31:0] hwdata,
    input  wire [31:0] hrdata,
    input  wire        hready,
    input  wire        hresp,
    input  wire        irq,
    output wire        halted
);
    wire [2:0]  hburst_unused;
    wire        hmastlock_unused;
    wire [3:0]  hprot_unused;
    wire        hmaster_unused;
    wire        codenseq_unused;
    wire [2:0]  codehintde_unused;
    wire        spechtrans_unused;
    wire        swdo_unused;
    wire        swdoen_unused;
    wire        tdo_unused;
    wire        ntdoen_unused;
    wire        dbgrestarted_unused;
    wire        txev_unused;
    wire        lockup;
    wire        sysresetreq_unused;
    wire        gatehclk_unused;
    wire        sleeping_unused;
    wire        sleepdeep_unused;
    wire        wakeup_unused;
    wire [33:0] wicsense_unused;
    wire        sleepholdackn_unused;
    wire        wicenack_unused;
    wire        cdbgpwrupreq_unused;
    wire        core_halted;

    CORTEXM0INTEGRATION u_cortexm0integration (
        .FCLK           (hclk),
        .SCLK           (hclk),
        .HCLK           (hclk),
        .DCLK           (hclk),
        .PORESETn       (hresetn),
        .DBGRESETn      (hresetn),
        .HRESETn        (hresetn),
        .SWCLKTCK       (hclk),
        .nTRST          (1'b1),

        .HADDR          (haddr),
        .HBURST         (hburst_unused),
        .HMASTLOCK      (hmastlock_unused),
        .HPROT          (hprot_unused),
        .HSIZE          (hsize),
        .HTRANS         (htrans),
        .HWDATA         (hwdata),
        .HWRITE         (hwrite),
        .HRDATA         (hrdata),
        .HREADY         (hready),
        .HRESP          (hresp),
        .HMASTER        (hmaster_unused),

        .CODENSEQ       (codenseq_unused),
        .CODEHINTDE     (codehintde_unused),
        .SPECHTRANS     (spechtrans_unused),

        .SWDITMS        (1'b1),
        .TDI            (1'b1),
        .SWDO           (swdo_unused),
        .SWDOEN         (swdoen_unused),
        .TDO            (tdo_unused),
        .nTDOEN         (ntdoen_unused),
        .DBGRESTART     (1'b0),
        .DBGRESTARTED   (dbgrestarted_unused),
        .EDBGRQ         (1'b0),
        .HALTED         (core_halted),

        .NMI            (1'b0),
        .IRQ            ({31'd0, irq}),
        .TXEV           (txev_unused),
        .RXEV           (1'b0),
        .LOCKUP         (lockup),
        .SYSRESETREQ    (sysresetreq_unused),
        .STCALIB        (26'd0),
        .STCLKEN        (1'b0),
        .IRQLATENCY     (8'd0),
        .ECOREVNUM      (28'd0),

        .GATEHCLK       (gatehclk_unused),
        .SLEEPING       (sleeping_unused),
        .SLEEPDEEP      (sleepdeep_unused),
        .WAKEUP         (wakeup_unused),
        .WICSENSE       (wicsense_unused),
        .SLEEPHOLDREQn  (1'b1),
        .SLEEPHOLDACKn  (sleepholdackn_unused),
        .WICENREQ       (1'b0),
        .WICENACK       (wicenack_unused),
        .CDBGPWRUPREQ   (cdbgpwrupreq_unused),
        .CDBGPWRUPACK   (1'b1),

        .SE             (1'b0),
        .RSTBYPASS      (1'b0)
    );

    assign halted = core_halted | lockup;
endmodule

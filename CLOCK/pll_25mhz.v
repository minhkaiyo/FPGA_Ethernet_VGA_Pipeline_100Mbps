// File: pll_25mhz.v
// Mo ta: PLL 50MHz -> 25MHz (VGA) + 125MHz (RGMII) + 125MHz+90deg (RGMII TX)
// Board: DE2i-150, Cyclone IV GX
// Ngay: 16/05/2026

module pll_25mhz (
    input  wire inclk0,    // 50 MHz input
    output wire c0,        // 25 MHz output (VGA)
    output wire c1,        // 125 MHz output (RGMII logic)
    output wire c2,        // 125 MHz + 90° phase (RGMII TX clock)
    output wire locked     // PLL locked indicator
);

    wire [4:0] clk_out;
    assign c0 = clk_out[0];
    assign c1 = clk_out[1];
    assign c2 = clk_out[2];

    altpll #(
        .bandwidth_type          ("AUTO"),
        .clk0_divide_by          (2),
        .clk0_duty_cycle         (50),
        .clk0_multiply_by        (1),
        .clk0_phase_shift        ("0"),        // 25 MHz = 50/2
        .clk1_divide_by          (2),
        .clk1_duty_cycle         (50),
        .clk1_multiply_by        (5),
        .clk1_phase_shift        ("0"),        // 125 MHz = 50*5/2
        .clk2_divide_by          (2),
        .clk2_duty_cycle         (50),
        .clk2_multiply_by        (5),
        .clk2_phase_shift        ("2000"),     // 125 MHz + 90° = 2000ps @ 125MHz (T=8ns, 90°=2ns=2000ps)
        .compensate_clock        ("CLK0"),
        .inclk0_input_frequency  (20000),      // 50 MHz = 20000 ps period
        .intended_device_family  ("Cyclone IV GX"),
        .lpm_hint                ("CBX_MODULE_PREFIX=pll_25mhz"),
        .lpm_type                ("altpll"),
        .operation_mode          ("NORMAL"),
        .pll_type                ("AUTO"),
        .port_activeclock        ("PORT_UNUSED"),
        .port_areset             ("PORT_UNUSED"),
        .port_clkbad0            ("PORT_UNUSED"),
        .port_clkbad1            ("PORT_UNUSED"),
        .port_clkloss            ("PORT_UNUSED"),
        .port_clkswitch          ("PORT_UNUSED"),
        .port_configupdate       ("PORT_UNUSED"),
        .port_fbin               ("PORT_UNUSED"),
        .port_inclk0             ("PORT_USED"),
        .port_inclk1             ("PORT_UNUSED"),
        .port_locked             ("PORT_USED"),
        .port_pfdena             ("PORT_UNUSED"),
        .port_phasecounterselect ("PORT_UNUSED"),
        .port_phasedone          ("PORT_UNUSED"),
        .port_phasestep          ("PORT_UNUSED"),
        .port_phaseupdown        ("PORT_UNUSED"),
        .port_pllena             ("PORT_UNUSED"),
        .port_scanaclr           ("PORT_UNUSED"),
        .port_scanclk            ("PORT_UNUSED"),
        .port_scanclkena         ("PORT_UNUSED"),
        .port_scandata           ("PORT_UNUSED"),
        .port_scandataout        ("PORT_UNUSED"),
        .port_scandone           ("PORT_UNUSED"),
        .port_scanread           ("PORT_UNUSED"),
        .port_scanwrite          ("PORT_UNUSED"),
        .port_clk0               ("PORT_USED"),
        .port_clk1               ("PORT_USED"),
        .port_clk2               ("PORT_USED"),
        .port_clk3               ("PORT_UNUSED"),
        .port_clk4               ("PORT_UNUSED"),
        .port_clk5               ("PORT_UNUSED"),
        .port_clkena0            ("PORT_UNUSED"),
        .port_clkena1            ("PORT_UNUSED"),
        .port_clkena2            ("PORT_UNUSED"),
        .port_clkena3            ("PORT_UNUSED"),
        .port_clkena4            ("PORT_UNUSED"),
        .port_clkena5            ("PORT_UNUSED"),
        .port_extclk0            ("PORT_UNUSED"),
        .port_extclk1            ("PORT_UNUSED"),
        .port_extclk2            ("PORT_UNUSED"),
        .port_extclk3            ("PORT_UNUSED"),
        .self_reset_on_loss_lock ("OFF"),
        .width_clock             (5)
    ) altpll_inst (
        .inclk  ({1'b0, inclk0}),
        .clk    (clk_out),
        .locked (locked),
        .activeclock (),
        .areset (1'b0),
        .clkbad (),
        .clkena ({6{1'b1}}),
        .clkloss (),
        .clkswitch (1'b0),
        .configupdate (1'b0),
        .enable0 (),
        .enable1 (),
        .extclk (),
        .extclkena ({4{1'b1}}),
        .fbin (1'b1),
        .fbmimicbidir (),
        .fbout (),
        .fref (),
        .icdrclk (),
        .pfdena (1'b1),
        .phasecounterselect ({4{1'b1}}),
        .phasedone (),
        .phasestep (1'b1),
        .phaseupdown (1'b1),
        .pllena (1'b1),
        .scanaclr (1'b0),
        .scanclk (1'b0),
        .scanclkena (1'b1),
        .scandata (1'b0),
        .scandataout (),
        .scandone (),
        .scanread (1'b0),
        .scanwrite (1'b0),
        .sclkout0 (),
        .sclkout1 (),
        .vcooverrange (),
        .vcounderrange ()
    );

endmodule

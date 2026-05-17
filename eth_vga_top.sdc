# Timing Constraints
# File: eth_vga_top.sdc
# Mo ta: SDC cho pipeline 1Gbps RGMII -> BRAM -> VGA tren DE2i-150
# Quartus 13 SP1 — Cyclone IV GX
# Ngay: 17/05/2026
#
# LUU Y: Quartus 13 dung 'derive_pll_clocks' thay vi 'create_generated_clock'
# vi hierarchy cua altpll thay doi theo version. derive_pll_clocks tu dong
# tim tat ca PLL output va tao clock tuong ung.

# =====================================================================
# CLOCK DEFINITIONS
# =====================================================================

# Board oscillator 50 MHz
create_clock -name CLOCK_50 -period 20.0 [get_ports CLOCK_50]

# RGMII RX Clock: 125 MHz tu PHY (recovered clock)
create_clock -name rgmii_rx_clk -period 8.0 [get_ports ENET_RX_CLK]

# Tao tu dong PLL output clocks (clk_25, clk_125, clk_125_90)
# Day la cach dung chuan cho Quartus 13 + altpll
derive_pll_clocks

# =====================================================================
# CLOCK UNCERTAINTY
# =====================================================================
derive_clock_uncertainty

# =====================================================================
# CLOCK GROUPS (CDC isolation — cut timing analysis qua ranh gioi domain)
# =====================================================================
set_clock_groups -asynchronous \
    -group { CLOCK_50 } \
    -group { rgmii_rx_clk } \
    -group { pll_inst|altpll_inst|auto_generated|pll1|clk[0] } \
    -group { pll_inst|altpll_inst|auto_generated|pll1|clk[1] \
             pll_inst|altpll_inst|auto_generated|pll1|clk[2] }

# =====================================================================
# RGMII INPUT TIMING (PHY -> FPGA via DDR)
# RGMII spec: data centered on clock edge with +-1.2ns skew
# =====================================================================
set_input_delay -clock rgmii_rx_clk -max  1.2 [get_ports {ENET_RX_DATA[*] ENET_RX_DV}]
set_input_delay -clock rgmii_rx_clk -min -1.2 [get_ports {ENET_RX_DATA[*] ENET_RX_DV}]
set_input_delay -clock rgmii_rx_clk -max  1.2 -clock_fall [get_ports {ENET_RX_DATA[*] ENET_RX_DV}] -add_delay
set_input_delay -clock rgmii_rx_clk -min -1.2 -clock_fall [get_ports {ENET_RX_DATA[*] ENET_RX_DV}] -add_delay

# =====================================================================
# RGMII OUTPUT TIMING (FPGA -> PHY via DDR, relative to GTX_CLK)
# =====================================================================
set_output_delay -clock { pll_inst|altpll_inst|auto_generated|pll1|clk[2] } \
    -max  1.0 [get_ports {ENET_TX_DATA[*] ENET_TX_EN ENET_GTX_CLK}]
set_output_delay -clock { pll_inst|altpll_inst|auto_generated|pll1|clk[2] } \
    -min -1.0 [get_ports {ENET_TX_DATA[*] ENET_TX_EN ENET_GTX_CLK}]

# =====================================================================
# VGA OUTPUT TIMING (relaxed — 25MHz pixel clock)
# =====================================================================
set_output_delay -clock { pll_inst|altpll_inst|auto_generated|pll1|clk[0] } \
    -max 2.0 [get_ports {VGA_R[*] VGA_G[*] VGA_B[*]}]
set_output_delay -clock { pll_inst|altpll_inst|auto_generated|pll1|clk[0] } \
    -max 2.0 [get_ports {VGA_HS VGA_VS VGA_BLANK_N VGA_SYNC_N VGA_CLK}]

# =====================================================================
# FALSE PATHS — Relaxed paths khong can timing analysis
# =====================================================================
# Button inputs: async, ignore
set_false_path -from [get_ports {KEY[*]}]

# MDIO / RST: slow signals, ignore timing
set_false_path -to [get_ports ENET_MDC]
set_false_path -to [get_ports ENET_RST_N]
set_false_path -to [get_ports ENET_MDIO]

# LEDs: output only, no timing requirement
set_false_path -to [get_ports {LEDR[*] LEDG[*]}]

# SDRAM: tied off, ignore all
set_false_path -to [get_ports {DRAM_ADDR[*] DRAM_BA[*] DRAM_CAS_N DRAM_CKE \
    DRAM_CLK DRAM_CS_N DRAM_DQM[*] DRAM_RAS_N DRAM_WE_N}]
set_false_path -from [get_ports {DRAM_DQ[*]}]
set_false_path -to   [get_ports {DRAM_DQ[*]}]

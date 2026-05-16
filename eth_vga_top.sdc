# Timing Constraints
# File: eth_vga_top.sdc
# Mo ta: SDC cho pipeline Ethernet 100Mbps -> VGA tren DE2i-150
# Ngay: 16/05/2026

# =====================================================================
# CLOCK DEFINITIONS
# =====================================================================

# Board oscillator 50 MHz
create_clock -name CLOCK_50 -period 20.0 [get_ports CLOCK_50]

# PLL output: 25 MHz (VGA pixel clock)
create_generated_clock \
    -name clk_25 \
    -source [get_pins {pll_inst|altpll_inst|inclk[0]}] \
    -divide_by 2 \
    [get_pins {pll_inst|altpll_inst|clk[0]}]

# MII RX Clock: cung cap boi PHY, 25 MHz o 100Mbps
create_clock -name mii_rx_clk -period 40.0 [get_ports ENET_RX_CLK]

# MII TX Clock: cung cap boi PHY, 25 MHz o 100Mbps
create_clock -name mii_tx_clk -period 40.0 [get_ports ENET_TX_CLK]

# =====================================================================
# CLOCK GROUPS (CDC isolation)
# =====================================================================
# Ba mien clock doc lap: Ethernet RX, VGA (clk_25), System (CLOCK_50)
# Cac ket noi xuyen mien clock da duoc xu ly boi BRAM voi async port
set_clock_groups -asynchronous \
    -group { mii_rx_clk } \
    -group { mii_tx_clk } \
    -group { clk_25 } \
    -group { CLOCK_50 }

# =====================================================================
# MII INPUT TIMING (PHY -> FPGA)
# =====================================================================
# Theo chuẩn MII IEEE 802.3, data ổn định 10ns trước rising edge của RX_CLK
# Chấp nhận setup 5ns, hold 5ns so với mii_rx_clk

set_input_delay -clock mii_rx_clk -max 10.0 [get_ports {ENET_RX_DATA[*] ENET_RX_DV ENET_RX_ER}]
set_input_delay -clock mii_rx_clk -min  2.0  [get_ports {ENET_RX_DATA[*] ENET_RX_DV ENET_RX_ER}]

# =====================================================================
# MII OUTPUT TIMING (FPGA -> PHY)
# =====================================================================
# TX data phai on dinh truoc rising edge cua TX_CLK it nhat 5ns
set_output_delay -clock mii_tx_clk -max 15.0 [get_ports {ENET_TX_DATA[*] ENET_TX_EN ENET_TX_ER}]
set_output_delay -clock mii_tx_clk -min  2.0  [get_ports {ENET_TX_DATA[*] ENET_TX_EN ENET_TX_ER}]

# =====================================================================
# VGA OUTPUT TIMING
# =====================================================================
# VGA output du la combinational tu clk_25, relax timing
set_output_delay -clock clk_25 -max 2.0 [get_ports {VGA_R[*] VGA_G[*] VGA_B[*]}]
set_output_delay -clock clk_25 -max 2.0 [get_ports {VGA_HS VGA_VS VGA_BLANK_N VGA_SYNC_N VGA_CLK}]

# =====================================================================
# FALSE PATHS
# =====================================================================
# Reset va cac tin hieu cham khong can phan tich timing
set_false_path -from [get_ports {KEY[*]}]

# MDIO / MDC cham, khong quan trong timing
set_false_path -to   [get_ports ENET_MDC]
set_false_path -to   [get_ports ENET_RST_N]

# Debug LEDs
set_false_path -to   [get_ports {LEDR[*] LEDG[*]}]

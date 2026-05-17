vlib work
vmap work work

# Compile Clock
vlog -work work CLOCK/pll_25mhz.v

# Compile Ethernet
vlog -work work ETHERNET/phy_init_88e1111.v
vlog -work work ETHERNET/eth_mac_1g_rgmii_fifo.v
vlog -work work ETHERNET/eth_mac_1g_rgmii.v
vlog -work work ETHERNET/eth_mac_1g.v
vlog -work work ETHERNET/rgmii_phy_if.v
vlog -work work ETHERNET/axis_gmii_rx.v
vlog -work work ETHERNET/axis_gmii_tx.v
vlog -work work ETHERNET/lfsr.v
vlog -work work ETHERNET/iddr.v
vlog -work work ETHERNET/oddr.v
vlog -work work ETHERNET/ssio_ddr_in.v
vlog -work work ETHERNET/ssio_ddr_out.v
vlog -work work ETHERNET/axis/axis_async_fifo.v
vlog -work work ETHERNET/axis/axis_async_fifo_adapter.v
vlog -work work ETHERNET/axis/axis_fifo.v
vlog -work work ETHERNET/axis/arbiter.v
vlog -work work ETHERNET/axis/priority_encoder.v
vlog -work work ETHERNET/axis/sync_reset.v

# Compile SDRAM Framebuffer and VGA Output
vlog -work work SDRAM/framebuffer_pingpong.v
vlog -work work VGA/vga_output.v

# Compile Top Module and Testbench
vlog -work work SOURCE_P/top_eth_vga_sdram.v
vlog -work work tb_top_eth_vga_sdram.v

# Start Simulation in GUI mode
vsim -L altera_mf_ver work.tb_top_eth_vga_sdram

# Add waves
add wave -position insertpoint sim:/tb_top_eth_vga_sdram/*

# Run
run -all

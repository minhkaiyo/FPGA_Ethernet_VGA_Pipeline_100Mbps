vlib work
vmap work work

# Compile Ethernet MAC modules (referencing parent folder)
vlog -work work ../ETHERNET/eth_mac_1g_rgmii_fifo.v
vlog -work work ../ETHERNET/eth_mac_1g_rgmii.v
vlog -work work ../ETHERNET/eth_mac_1g.v
vlog -work work ../ETHERNET/rgmii_phy_if.v
vlog -work work ../ETHERNET/axis_gmii_rx.v
vlog -work work ../ETHERNET/axis_gmii_tx.v
vlog -work work ../ETHERNET/lfsr.v
vlog -work work ../ETHERNET/iddr.v
vlog -work work ../ETHERNET/oddr.v
vlog -work work ../ETHERNET/ssio_ddr_in.v
vlog -work work ../ETHERNET/ssio_ddr_out.v
vlog -work work ../ETHERNET/axis/axis_async_fifo.v
vlog -work work ../ETHERNET/axis/axis_async_fifo_adapter.v
vlog -work work ../ETHERNET/axis/axis_fifo.v
vlog -work work ../ETHERNET/axis/arbiter.v
vlog -work work ../ETHERNET/axis/priority_encoder.v
vlog -work work ../ETHERNET/axis/sync_reset.v

# Compile testbench
vlog -work work tb_eth_loopback.v

# Start Simulation in GUI mode
vsim -L altera_mf_ver work.tb_eth_loopback

# Add waves
add wave -position insertpoint sim:/tb_eth_loopback/*

# Add internal RGMII loopback signals explicitly for visibility
add wave -divider "RGMII Loopback Physical Pins"
add wave sim:/tb_eth_loopback/rgmii_tx_clk
add wave sim:/tb_eth_loopback/rgmii_txd
add wave sim:/tb_eth_loopback/rgmii_tx_ctl

# Run
run -all

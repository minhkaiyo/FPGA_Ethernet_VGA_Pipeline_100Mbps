// File: top_eth_vga_sdram.v
// Mo ta: Top-level — GigE 1Gbps (RGMII) -> BRAM ping-pong -> VGA 640x480
//        Board : DE2i-150 (EP4CGX150DF31C7)
//        PHY   : Marvell 88E1111 in RGMII mode
//        MAC   : Alex Forencich eth_mac_1g_rgmii_fifo (RX FIFO 4096 words)
//        PHY init: phy_init_88e1111 — auto-scan MDIO addr, Reg20 timing delay,
//                  Reg0 soft-reset + force 1Gbps
// Clock: 50MHz -> PLL -> 25MHz(VGA), 125MHz(RGMII), 125MHz+90°(RGMII TX)
// Ngay: 17/05/2026

module top_eth_vga_sdram (
    // --- Clock ---
    input  wire        CLOCK_50,

    // --- Push-buttons (active-low) ---
    input  wire [3:0]  KEY,

    // --- LEDs ---
    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,

    // --- Ethernet RGMII (88E1111 PHY) ---
    output wire        ENET_GTX_CLK,    // RGMII TX Clock (FPGA -> PHY)
    input  wire        ENET_RX_CLK,     // RGMII RX Clock (PHY -> FPGA)
    input  wire [3:0]  ENET_RX_DATA,    // RGMII RX Data (DDR 4-bit)
    input  wire        ENET_RX_DV,      // RGMII RX Control
    output wire [3:0]  ENET_TX_DATA,    // RGMII TX Data (DDR 4-bit)
    output wire        ENET_TX_EN,      // RGMII TX Control
    output wire        ENET_RST_N,      // PHY Reset (active-low)
    output wire        ENET_MDC,        // MDIO Clock
    inout  wire        ENET_MDIO,       // MDIO Data

    // --- VGA ---
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_CLK,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N,

    // --- SDRAM (tied off — chưa dùng) ---
    output wire [12:0] DRAM_ADDR,
    output wire [1:0]  DRAM_BA,
    output wire        DRAM_CAS_N,
    output wire        DRAM_CKE,
    output wire        DRAM_CLK,
    output wire        DRAM_CS_N,
    inout  wire [31:0] DRAM_DQ,
    output wire [3:0]  DRAM_DQM,
    output wire        DRAM_RAS_N,
    output wire        DRAM_WE_N
);

// ==========================================================================
// 1. CLOCK + RESET
//    PLL: 50MHz -> c0(25MHz VGA) + c1(125MHz RGMII) + c2(125MHz+90° RGMII TX)
// ==========================================================================
wire clk_25, clk_125, clk_125_90, pll_locked;

pll_25mhz pll_inst (
    .inclk0 (CLOCK_50),
    .c0     (clk_25),        // 25  MHz  — VGA pixel clock
    .c1     (clk_125),       // 125 MHz  — RGMII MAC logic
    .c2     (clk_125_90),    // 125 MHz + 90° — RGMII TX clock
    .locked (pll_locked)
);

// Reset: KEY[0] active-low AND pll locked
wire rst_n    = KEY[0] & pll_locked;
wire sys_rst  = ~rst_n;

// ==========================================================================
// 2. PHY MANAGEMENT — phy_init_88e1111
//    Auto-scan MDIO address, read Reg20, OR with 0x0082 (TX+RX delay),
//    write back, then write Reg0 = 0x9140 (soft reset + 1Gbps AN)
//    Clock: CLOCK_50 (50MHz) — same as v4 reference design
// ==========================================================================
wire phy_ready;
wire [3:0] phy_dbg_fsm;
wire [4:0] phy_dbg_addr;

phy_init_88e1111 #(
    .CLK_MHZ (50),    // 50MHz input
    .CLK_DIV (100)    // MDC = 50MHz / 100 = 500kHz
) phy_init_inst (
    .clk        (CLOCK_50),
    .rst_n      (KEY[0]),        // phy init uses raw KEY[0], NOT pll-gated reset
    .phy_rst_n  (ENET_RST_N),
    .mdc        (ENET_MDC),
    .mdio       (ENET_MDIO),
    .configured (phy_ready),
    .debug_fsm  (phy_dbg_fsm),
    .debug_addr (phy_dbg_addr)
);

// MAC reset: wait for PLL locked AND PHY configured
wire mac_rst = sys_rst | ~phy_ready | ~pll_locked;

// ==========================================================================
// 3. SDRAM TIED OFF
// ==========================================================================
assign DRAM_ADDR  = 13'd0;
assign DRAM_BA    = 2'd0;
assign DRAM_CAS_N = 1'b1;
assign DRAM_CKE   = 1'b0;
assign DRAM_CLK   = 1'b0;
assign DRAM_CS_N  = 1'b1;
assign DRAM_DQ    = 32'bz;
assign DRAM_DQM   = 4'b1111;
assign DRAM_RAS_N = 1'b1;
assign DRAM_WE_N  = 1'b1;

// ==========================================================================
// 4. ETHERNET MAC — eth_mac_1g_rgmii_fifo
//    - RX FIFO 4096 words (cross-domain RX_CLK -> clk_125 safe)
//    - TX FIFO 4096 words
//    - logic_clk = clk_125 (same as gtx_clk — simplest, như v4)
// ==========================================================================
wire [7:0]  rx_axis_tdata;
wire        rx_axis_tvalid;
wire        rx_axis_tready;
wire        rx_axis_tlast;
wire        rx_axis_tuser;
wire        rx_axis_tkeep;   // NC (8-bit width, always 1)
wire [1:0]  phy_speed;

eth_mac_1g_rgmii_fifo #(
    .TARGET              ("ALTERA"),
    .IODDR_STYLE         ("IODDR2"),
    .CLOCK_INPUT_STYLE   ("BUFG"),
    .USE_CLK90           ("TRUE"),
    .ENABLE_PADDING      (1),
    .MIN_FRAME_LENGTH    (64),
    .TX_FIFO_DEPTH       (256),      // TX khong dung -> minimize FIFO size
    .TX_FRAME_FIFO       (1),
    .TX_DROP_BAD_FRAME   (1),
    .RX_FIFO_DEPTH       (4096),     // RX buffer 4K words cho 1Gbps burst
    .RX_FRAME_FIFO       (1),
    .RX_DROP_BAD_FRAME   (0)
) mac_inst (
    // Clock / reset
    .gtx_clk            (clk_125),
    .gtx_clk90          (clk_125_90),
    .gtx_rst            (mac_rst),
    .logic_clk          (clk_125),      // same domain, simplest CDC
    .logic_rst          (mac_rst),

    // TX AXI (not used — tie off)
    .tx_axis_tdata      (8'd0),
    .tx_axis_tkeep      (1'b1),
    .tx_axis_tvalid     (1'b0),
    .tx_axis_tready     (),
    .tx_axis_tlast      (1'b0),
    .tx_axis_tuser      (1'b0),

    // RX AXI output (to UDP parser)
    .rx_axis_tdata      (rx_axis_tdata),
    .rx_axis_tkeep      (rx_axis_tkeep),
    .rx_axis_tvalid     (rx_axis_tvalid),
    .rx_axis_tready     (1'b1),          // always ready — parser absorbs data
    .rx_axis_tlast      (rx_axis_tlast),
    .rx_axis_tuser      (rx_axis_tuser),

    // RGMII pins
    .rgmii_rx_clk       (ENET_RX_CLK),
    .rgmii_rxd          (ENET_RX_DATA),
    .rgmii_rx_ctl       (ENET_RX_DV),
    .rgmii_tx_clk       (ENET_GTX_CLK),
    .rgmii_txd          (ENET_TX_DATA),
    .rgmii_tx_ctl       (ENET_TX_EN),

    // Status
    .tx_error_underflow (),
    .tx_fifo_overflow   (),
    .tx_fifo_bad_frame  (),
    .tx_fifo_good_frame (),
    .rx_error_bad_frame (),
    .rx_error_bad_fcs   (),
    .rx_fifo_overflow   (),
    .rx_fifo_bad_frame  (),
    .rx_fifo_good_frame (),
    .speed              (phy_speed),

    // Config
    .cfg_ifg            (8'd12),
    .cfg_tx_enable      (1'b0),
    .cfg_rx_enable      (1'b1)
);

// ==========================================================================
// 5. UDP PIXEL RECEIVER (inline FSM — tham khảo v4 reference design)
//    Packet format: [Eth 14B][IP 20B][UDP 8B][row_idx: 2B][640 bytes Mono8]
//    Parses raw Ethernet frame byte-stream, ghi byte-by-byte vào BRAM
//    All signals in clk_125 domain
// ==========================================================================
reg [3:0]  dbg_fsm           = 0;
reg [11:0] byte_cnt          = 0;
reg        fb_wr_en_r        = 0;  // BRAM write enable
reg [18:0] fb_wr_addr_r      = 0;  // BRAM write address (byte index)
reg [7:0]  fb_wr_data_r      = 0;  // BRAM write data
reg        frame_start_pulse = 0;
reg [15:0] rx_frame_cnt      = 0;
reg [15:0] row_idx           = 0;  // current row being received
reg [18:0] row_base_addr     = 0;  // base byte addr = row * 640

always @(posedge clk_125) begin
    if (mac_rst) begin
        dbg_fsm           <= 0; byte_cnt <= 0;
        fb_wr_en_r        <= 0; fb_wr_addr_r <= 0; fb_wr_data_r <= 0;
        frame_start_pulse <= 0; rx_frame_cnt <= 0;
        row_idx           <= 0; row_base_addr <= 0;
    end else begin
        fb_wr_en_r        <= 0;
        frame_start_pulse <= 0;

        if (rx_axis_tlast) begin
            // End of packet — reset FSM để tránh lệch byte
            dbg_fsm  <= 0;
        end else if (rx_axis_tvalid) begin
            case (dbg_fsm)
                // State 0: first byte — reset byte counter
                4'd0: begin dbg_fsm <= 1; byte_cnt <= 1; end

                // State 1: skip Ethernet header (14 bytes total, đã nhận 1)
                4'd1: begin
                    if (byte_cnt == 13) begin dbg_fsm <= 2; byte_cnt <= 0; end
                    else byte_cnt <= byte_cnt + 1;
                end

                // State 2: skip IP header (20 bytes)
                4'd2: begin
                    if (byte_cnt == 19) begin dbg_fsm <= 3; byte_cnt <= 0; end
                    else byte_cnt <= byte_cnt + 1;
                end

                // State 3: skip UDP header (8 bytes)
                4'd3: begin
                    if (byte_cnt == 7) begin dbg_fsm <= 4; byte_cnt <= 0; end
                    else byte_cnt <= byte_cnt + 1;
                end

                // State 4: UDP payload
                //   byte 0   : row_idx[15:8]
                //   byte 1   : row_idx[7:0]  -> tính base addr
                //   byte 2..641: 640 pixel bytes (Mono8)
                4'd4: begin
                    if (byte_cnt == 0) begin
                        row_idx[15:8] <= rx_axis_tdata;
                        byte_cnt      <= byte_cnt + 1;
                    end else if (byte_cnt == 1) begin
                        row_idx[7:0]  <= rx_axis_tdata;
                        // row_base = row * 640 = row * 512 + row * 128
                        if ({row_idx[15:8], rx_axis_tdata} < 16'd480) begin
                            row_base_addr <= ({3'd0, row_idx[15:8], rx_axis_tdata} << 9)
                                           + ({6'd0, row_idx[15:8], rx_axis_tdata} << 7);
                        end else begin
                            row_base_addr <= 19'h7FFFF; // dummy — hàng không hợp lệ
                        end
                        byte_cnt <= byte_cnt + 1;

                        // frame_start_pulse khi nhận row 0
                        if ({row_idx[15:8], rx_axis_tdata} == 16'd0) begin
                            frame_start_pulse <= 1;
                            rx_frame_cnt      <= rx_frame_cnt + 1;
                        end
                    end else if (byte_cnt >= 2 && byte_cnt <= 641) begin
                        // Pixel byte (0-indexed: byte_cnt-2 = col index)
                        fb_wr_en_r   <= (row_base_addr != 19'h7FFFF); // chỉ ghi nếu row hợp lệ
                        fb_wr_addr_r <= row_base_addr + (byte_cnt - 2);
                        fb_wr_data_r <= rx_axis_tdata;
                        byte_cnt     <= byte_cnt + 1;
                    end
                end

                default: dbg_fsm <= 0;
            endcase
        end
    end
end

// ==========================================================================
// 6. BRAM PING-PONG FRAME BUFFER (8-bit, 307200 bytes x2 banks)
// ==========================================================================
wire [18:0] bram_rd_addr;
wire [7:0]  bram_rd_data;

framebuffer_pingpong #(
    .FRAME_PIXELS (307200)
) bram_buf_inst (
    .wr_clk         (clk_125),
    .wr_en          (fb_wr_en_r),
    .wr_addr        (fb_wr_addr_r),
    .wr_data        (fb_wr_data_r),
    .eth_frame_done (frame_start_pulse),
    .rd_clk         (clk_25),
    .rd_addr        (bram_rd_addr),
    .rd_data        (bram_rd_data),
    .wr_bank        (),
    .rd_bank        ()
);

// ==========================================================================
// 7. VGA OUTPUT
// ==========================================================================
assign VGA_SYNC_N = 1'b0;

vga_output vga_inst (
    .clk         (clk_25),
    .rst_n       (rst_n),
    .fb_rd_addr  (bram_rd_addr),
    .fb_rd_data  (bram_rd_data),
    .vga_vsync_raw (),
    .vga_r       (VGA_R),
    .vga_g       (VGA_G),
    .vga_b       (VGA_B),
    .vga_hs      (VGA_HS),
    .vga_vs      (VGA_VS),
    .vga_blank_n (VGA_BLANK_N),
    .vga_sync_n  (),
    .vga_clk     (VGA_CLK)
);

// ==========================================================================
// 8. DEBUG LEDs
// ==========================================================================
assign LEDR[15:0] = rx_frame_cnt;

// Ethernet RX clock alive indicator (blinks nếu PHY clock chạy)
reg [23:0] eth_alive_cnt = 0;
always @(posedge ENET_RX_CLK)
    eth_alive_cnt <= eth_alive_cnt + 1'b1;
assign LEDR[16] = eth_alive_cnt[23];
assign LEDR[17] = pll_locked;

// LEDG status mapping (giống v4 reference)
assign LEDG[0] = rst_n;
assign LEDG[1] = rx_axis_tvalid;           // nhấp nháy = đang nhận data
assign LEDG[2] = (phy_speed == 2'b10);     // 1 = 1Gbps link ✅
assign LEDG[3] = (phy_speed == 2'b01);     // 1 = 100Mbps link
assign LEDG[4] = (phy_speed == 2'b00);     // 1 = 10Mbps link
assign LEDG[5] = phy_ready;                // 1 = PHY đã cấu hình RGMII xong
assign LEDG[6] = frame_start_pulse;        // pulse mỗi frame mới
assign LEDG[8:7] = 2'd0;

endmodule

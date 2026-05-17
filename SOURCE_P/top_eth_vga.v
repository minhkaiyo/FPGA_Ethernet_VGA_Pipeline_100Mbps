// File: top_eth_vga.v
// Mo ta: Top-level module ket noi pipeline Ethernet 100Mbps -> BRAM -> VGA
//        Board: DE2i-150 (EP4CE115F29C7)
//        Luong: PC(UDP) -> PHY(MII) -> MAC -> eth_pixel_rx -> BRAM -> VGA
// Ngay: 16/05/2026

module top_eth_vga (
    // --- Clock ---
    input  wire        CLOCK_50,       // 50 MHz

    // --- Push-buttons (active-low) ---
    input  wire [3:0]  KEY,            // KEY[0] = reset

    // --- LEDs ---
    output wire [17:0] LEDR,
    output wire [8:0]  LEDG,

    // --- Ethernet MII (ENET0, 88E1111 PHY) ---
    output wire        ENET_GTX_CLK,   // MII: khong dung, nhung van gan
    input  wire        ENET_RX_CLK,    // 25 MHz tu PHY (100Mbps)
    input  wire        ENET_TX_CLK,    // 25 MHz tu PHY
    input  wire [3:0]  ENET_RX_DATA,
    input  wire        ENET_RX_DV,
    input  wire        ENET_RX_ER,
    output wire [3:0]  ENET_TX_DATA,
    output wire        ENET_TX_EN,
    output wire        ENET_TX_ER,
    output wire        ENET_RST_N,     // PHY reset (active-low)
    output wire        ENET_MDC,       // MDIO clock
    inout  wire        ENET_MDIO,      // MDIO data

    // --- VGA (ADV7123 DAC) ---
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_CLK,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N,
    
    // --- SDRAM (IS42S16320D, use 16-bit) ---
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

    // ==========================================================
    // CLOCK GENERATION
    // ==========================================================
    // PLL: 50MHz -> 25MHz (VGA pixel clock)
    wire clk_25;
    wire pll_locked;

    pll_25mhz pll_inst (
        .inclk0 (CLOCK_50),
        .c0     (clk_25),
        .locked (pll_locked)
    );

    // Reset synchronizer
    wire sys_rst_n = KEY[0] & pll_locked;
    wire sys_rst   = ~sys_rst_n;

    // SDRAM not used — clock tied off in BRAM buffer section


    // ==========================================================
    // PHY MANAGEMENT
    // ==========================================================
    // Giu PHY khong bi reset
    assign ENET_RST_N = sys_rst_n;

    // MDIO: khong cau hinh gi -> mac dinh PHY auto-negotiate 100Mbps
    assign ENET_MDC  = 1'b0;
    assign ENET_MDIO = 1'bz;   // tri-state

    // GTX_CLK: khong can cho MII mode, nhung gan clock de tranh floating
    assign ENET_GTX_CLK = clk_25;

    // ==========================================================
    // ETHERNET MAC (MII, 100Mbps)
    // ==========================================================
    wire       eth_rx_clk;
    wire       eth_rx_rst;
    wire       eth_tx_clk;
    wire       eth_tx_rst;

    wire [7:0] rx_axis_tdata;
    wire       rx_axis_tvalid;
    wire       rx_axis_tlast;
    wire       rx_axis_tuser;

    // TX side: khong truyen gi, tie off
    wire       tx_axis_tready;

    eth_mac_mii #(
        .TARGET             ("ALTERA"),
        .CLOCK_INPUT_STYLE  ("BUFG"),     // Ignored for ALTERA
        .ENABLE_PADDING     (1),
        .MIN_FRAME_LENGTH   (64)
    ) eth_mac_inst (
        .rst                (sys_rst),
        .rx_clk             (eth_rx_clk),
        .rx_rst             (eth_rx_rst),
        .tx_clk             (eth_tx_clk),
        .tx_rst             (eth_tx_rst),

        // AXI-Stream RX output
        .rx_axis_tdata      (rx_axis_tdata),
        .rx_axis_tvalid     (rx_axis_tvalid),
        .rx_axis_tlast      (rx_axis_tlast),
        .rx_axis_tuser      (rx_axis_tuser),

        // AXI-Stream TX input — tie off (khong gui)
        .tx_axis_tdata      (8'd0),
        .tx_axis_tvalid     (1'b0),
        .tx_axis_tready     (tx_axis_tready),
        .tx_axis_tlast      (1'b0),
        .tx_axis_tuser      (1'b0),

        // MII interface to PHY
        .mii_rx_clk         (ENET_RX_CLK),
        .mii_rxd            (ENET_RX_DATA),
        .mii_rx_dv          (ENET_RX_DV),
        .mii_rx_er          (ENET_RX_ER),
        .mii_tx_clk         (ENET_TX_CLK),
        .mii_txd            (ENET_TX_DATA),
        .mii_tx_en          (ENET_TX_EN),
        .mii_tx_er          (ENET_TX_ER),

        // Status (unused)
        .tx_start_packet    (),
        .tx_error_underflow (),
        .rx_start_packet    (),
        .rx_error_bad_frame (),
        .rx_error_bad_fcs   (),

        // Config
        .cfg_ifg            (8'd12),
        .cfg_tx_enable      (1'b0),    // TX disabled
        .cfg_rx_enable      (1'b1)     // RX enabled
    );

    // ==========================================================
    // UDP PIXEL RECEIVER
    // ==========================================================
    wire        fb_wr_en;
    wire [18:0] fb_wr_addr;
    wire [7:0]  fb_wr_data;
    wire [15:0] rx_frame_cnt;
    wire        eth_frame_done;

    eth_pixel_rx #(
        .UDP_PORT     (16'd1234),
        .FRAME_WIDTH  (640),
        .FRAME_HEIGHT (480)
    ) pixel_rx_inst (
        .clk            (eth_rx_clk),
        .rst            (eth_rx_rst),

        .s_axis_tdata   (rx_axis_tdata),
        .s_axis_tvalid  (rx_axis_tvalid),
        .s_axis_tlast   (rx_axis_tlast),
        .s_axis_tuser   (rx_axis_tuser),

        .fb_wr_en       (fb_wr_en),
        .fb_wr_addr     (fb_wr_addr),
        .fb_wr_data     (fb_wr_data),

        .rx_frame_cnt   (rx_frame_cnt),
        .eth_frame_done (eth_frame_done)
    );

    // ==========================================================
    // BRAM PING-PONG FRAME BUFFER
    // ==========================================================
    wire [18:0] fb_rd_addr;
    wire [7:0]  fb_rd_data;
    wire        vga_vsync_raw;

    framebuffer_pingpong #(
        .FRAME_PIXELS(307200)
    ) bram_buf_inst (
        // Write port (Ethernet domain)
        .wr_clk         (eth_rx_clk),
        .wr_en          (fb_wr_en),
        .wr_addr        (fb_wr_addr),
        .wr_data        (fb_wr_data),
        .eth_frame_done (eth_frame_done),

        // Read port (VGA domain)
        .rd_clk         (clk_25),
        .rd_addr        (fb_rd_addr),
        .rd_data        (fb_rd_data),

        // Bank debug
        .wr_bank        (LEDG[2]),
        .rd_bank        (LEDG[3])
    );

    // Tie off unused SDRAM pins (keep board safe)
    assign DRAM_ADDR   = 13'd0;
    assign DRAM_BA     = 2'd0;
    assign DRAM_CAS_N  = 1'b1;
    assign DRAM_CKE    = 1'b0;
    assign DRAM_CLK    = 1'b0;
    assign DRAM_CS_N   = 1'b1;
    assign DRAM_DQ     = 32'bz;
    assign DRAM_DQM    = 4'b1111;
    assign DRAM_RAS_N  = 1'b1;
    assign DRAM_WE_N   = 1'b1;

    // ==========================================================
    // VGA OUTPUT
    // ==========================================================
    vga_output vga_inst (
        .clk          (clk_25),
        .rst_n        (sys_rst_n),

        .fb_rd_addr   (fb_rd_addr),
        .fb_rd_data   (fb_rd_data),
        .vga_vsync_raw(vga_vsync_raw),

        .vga_r        (VGA_R),
        .vga_g        (VGA_G),
        .vga_b        (VGA_B),
        .vga_hs       (VGA_HS),
        .vga_vs       (VGA_VS),
        .vga_blank_n  (VGA_BLANK_N),
        .vga_sync_n   (VGA_SYNC_N),
        .vga_clk      (VGA_CLK)
    );

    // ==========================================================
    // DEBUG LEDs
    // ==========================================================
    // LEDR[15:0] = so luong frame UDP da nhan
    assign LEDR[15:0] = rx_frame_cnt;
    // LEDR[16] = Ethernet link (RX clock dang chay)
    reg [23:0] eth_alive_cnt;
    always @(posedge eth_rx_clk or posedge eth_rx_rst) begin
        if (eth_rx_rst) eth_alive_cnt <= 0;
        else eth_alive_cnt <= eth_alive_cnt + 1'b1;
    end
    assign LEDR[16] = eth_alive_cnt[23]; // nhay ~1.5Hz neu co RX clock
    assign LEDR[17] = pll_locked;

    // LEDG
    assign LEDG[0] = sys_rst_n;         // Reset da xong
    assign LEDG[1] = rx_axis_tvalid;    // Dang nhan du lieu
    // LEDG[2] = wr_bank (assigned by bram_buf_inst)
    // LEDG[3] = rd_bank (assigned by bram_buf_inst)
    assign LEDG[8:4] = 5'd0;

endmodule

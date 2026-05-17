`timescale 1ns/1ps

module tb_top_eth_vga_sdram;
    // --- Inputs ---
    reg CLOCK_50;
    reg [3:0] KEY;
    reg ENET_RX_CLK;
    reg [3:0] ENET_RX_DATA;
    reg ENET_RX_DV;

    // --- Outputs ---
    wire [17:0] LEDR;
    wire [8:0] LEDG;
    wire ENET_GTX_CLK, ENET_TX_EN, ENET_RST_N, ENET_MDC;
    wire [3:0] ENET_TX_DATA;
    wire ENET_MDIO;
    wire [7:0] VGA_R, VGA_G, VGA_B;
    wire VGA_CLK, VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N;

    // --- SDRAM Ports (tied off internally) ---
    wire [12:0] DRAM_ADDR;
    wire [1:0]  DRAM_BA;
    wire        DRAM_CAS_N;
    wire        DRAM_CKE;
    wire        DRAM_CLK;
    wire        DRAM_CS_N;
    wire [31:0] DRAM_DQ;
    wire [3:0]  DRAM_DQM;
    wire        DRAM_RAS_N;
    wire        DRAM_WE_N;

    // Instantiate Top Module
    top_eth_vga_sdram dut (
        .CLOCK_50(CLOCK_50),
        .KEY(KEY),
        .LEDR(LEDR),
        .LEDG(LEDG),
        .ENET_GTX_CLK(ENET_GTX_CLK),
        .ENET_RX_CLK(ENET_RX_CLK),
        .ENET_RX_DATA(ENET_RX_DATA),
        .ENET_RX_DV(ENET_RX_DV),
        .ENET_TX_DATA(ENET_TX_DATA),
        .ENET_TX_EN(ENET_TX_EN),
        .ENET_RST_N(ENET_RST_N),
        .ENET_MDC(ENET_MDC),
        .ENET_MDIO(ENET_MDIO),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B),
        .VGA_CLK(VGA_CLK),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS),
        .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N),
        .DRAM_ADDR(DRAM_ADDR),
        .DRAM_BA(DRAM_BA),
        .DRAM_CAS_N(DRAM_CAS_N),
        .DRAM_CKE(DRAM_CKE),
        .DRAM_CLK(DRAM_CLK),
        .DRAM_CS_N(DRAM_CS_N),
        .DRAM_DQ(DRAM_DQ),
        .DRAM_DQM(DRAM_DQM),
        .DRAM_RAS_N(DRAM_RAS_N),
        .DRAM_WE_N(DRAM_WE_N)
    );

    // Clock generation: 50 MHz
    always #10 CLOCK_50 = ~CLOCK_50;
    
    // Ethernet RX Clock generation: 125 MHz
    always #4 ENET_RX_CLK = ~ENET_RX_CLK;

    initial begin
        $display("=== BẮT ĐẦU MÔ PHỎNG TOP_ETH_VGA_SDRAM ===");
        
        // Initial state
        CLOCK_50 = 0;
        ENET_RX_CLK = 0;
        ENET_RX_DATA = 4'b0000;
        ENET_RX_DV = 0;
        KEY = 4'b1111;
        
        // Assert Reset (KEY[0] is active-low)
        #20 KEY[0] = 0;
        #100 KEY[0] = 1;
        
        // Wait 17ms to let PLL lock and modules initialize, cover a full VGA frame
        #17000000;
        
        $display("=== KẾT THÚC MÔ PHỎNG MẪU (17ms) ===");
        $stop;
    end

    // --- DEBUG LOGGING ---
    always @(posedge dut.pll_locked) begin
        $display("[%0t ns] INFO: Khối PLL đã LOCK. Các module bắt đầu hoạt động!", $time);
    end

    always @(negedge VGA_VS) begin
        $display("[%0t ns] VGA_VS: Bắt đầu một khung hình mới (New Frame)!", $time);
    end

    integer hs_count = 0;
    always @(negedge VGA_HS) begin
        hs_count = hs_count + 1;
        // In ra mỗi 100 dòng để tránh trôi log
        if (hs_count % 100 == 0) begin
            $display("[%0t ns] VGA_HS: Đang quét dòng thứ %0d. (R=%0h, G=%0h, B=%0h)", $time, hs_count, VGA_R, VGA_G, VGA_B);
        end
    end
endmodule

// File: vga_output.v
// Mo ta: Doc pixel tu framebuffer BRAM Ping-Pong, xuat tin hieu VGA 640x480@60Hz
//        Mono8: R = G = B = pixel_value (anh xam)
// Ngay: 16/05/2026

module vga_output (
    input  wire        clk,        // 25 MHz pixel clock
    input  wire        rst_n,      // active-low reset

    // Framebuffer BRAM read port (1-cycle latency)
    output wire [18:0] fb_rd_addr, // linear address = v*640 + h
    input  wire [7:0]  fb_rd_data, // pixel data (1 cycle delayed)

    // VSYNC raw output (active-low) - kept for compatibility
    output wire        vga_vsync_raw,

    // VGA DAC signals (ADV7123 tren DE2i-150)
    output wire [7:0]  vga_r,
    output wire [7:0]  vga_g,
    output wire [7:0]  vga_b,
    output wire        vga_hs,
    output wire        vga_vs,
    output wire        vga_blank_n,
    output wire        vga_sync_n,
    output wire        vga_clk
);

    // --- VGA 640x480 @ 60Hz timing ---
    localparam H_ACTIVE = 640;
    localparam H_FP     = 16;
    localparam H_SYNC   = 96;
    localparam H_BP     = 48;
    localparam H_TOTAL  = 800;

    localparam V_ACTIVE = 480;
    localparam V_FP     = 10;
    localparam V_SYNC   = 2;
    localparam V_BP     = 33;
    localparam V_TOTAL  = 525;

    // Counters
    reg [9:0] h_cnt;
    reg [9:0] v_cnt;

    // Horizontal counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            h_cnt <= 10'd0;
        else if (h_cnt == H_TOTAL - 1)
            h_cnt <= 10'd0;
        else
            h_cnt <= h_cnt + 1'b1;
    end

    // Vertical counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            v_cnt <= 10'd0;
        else if (h_cnt == H_TOTAL - 1) begin
            if (v_cnt == V_TOTAL - 1)
                v_cnt <= 10'd0;
            else
                v_cnt <= v_cnt + 1'b1;
        end
    end

    // Active video area
    wire h_active = (h_cnt < H_ACTIVE);
    wire v_active = (v_cnt < V_ACTIVE);
    wire active   = h_active & v_active;

    // Sync signals (active-low cho VGA standard)
    wire hsync = ~((h_cnt >= H_ACTIVE + H_FP) && (h_cnt < H_ACTIVE + H_FP + H_SYNC));
    wire vsync = ~((v_cnt >= V_ACTIVE + V_FP) && (v_cnt < V_ACTIVE + V_FP + V_SYNC));

    // VSYNC raw (for bank-switch, unused now since BRAM doesn't need it)
    assign vga_vsync_raw = vsync;

    // Linear pixel address = v * 640 + h
    // Pre-calculate 1 clock ahead to compensate for BRAM 1-cycle read latency
    wire [9:0] h_next = (h_cnt == H_TOTAL-1) ? 10'd0 : h_cnt + 1'b1;
    wire [9:0] v_next = (h_cnt == H_TOTAL-1) ?
                            ((v_cnt == V_TOTAL-1) ? 10'd0 : v_cnt + 1'b1)
                            : v_cnt;

    wire h_active_next = (h_next < H_ACTIVE);
    wire v_active_next = (v_next < V_ACTIVE);
    wire active_next   = h_active_next & v_active_next;

    // Look-ahead address: v_next*640 + h_next  (max = 479*640+639 = 306879 < 2^19)
    wire [19:0] pixel_addr_next = (v_next * 10'd640) + {10'd0, h_next};
    assign fb_rd_addr = active_next ? pixel_addr_next[18:0] : 19'd0;

    // Pipeline delay 1 clk (BRAM has 1-cycle read latency)
    reg active_d1;
    reg hsync_d1, vsync_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_d1 <= 0;
            hsync_d1  <= 1;
            vsync_d1  <= 1;
        end else begin
            active_d1 <= active;
            hsync_d1  <= hsync;
            vsync_d1  <= vsync;
        end
    end

    // VGA output — Mono8: R=G=B=pixel
    assign vga_r = active_d1 ? fb_rd_data : 8'd0;
    assign vga_g = active_d1 ? fb_rd_data : 8'd0;
    assign vga_b = active_d1 ? fb_rd_data : 8'd0;

    assign vga_hs      = hsync_d1;
    assign vga_vs      = vsync_d1;
    assign vga_blank_n = active_d1;
    assign vga_sync_n  = 1'b0;       // Composite sync khong dung, dat 0
    assign vga_clk     = clk;        // Pixel clock truc tiep cho DAC

endmodule

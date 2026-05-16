// File: vga_output.v
// Mo ta: Doc pixel tu framebuffer BRAM, xuat tin hieu VGA 640x480@60Hz
//        Mono8: R = G = B = pixel_value (anh xam)
// Ngay: 16/05/2026

module vga_output (
    input  wire        clk,        // 25 MHz pixel clock
    input  wire        rst_n,      // active-low reset

    // Framebuffer read port
    output wire [18:0] fb_rd_addr,
    input  wire [7:0]  fb_rd_data,

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

    // BRAM read address: row * 640 + col
    // 640 = 512 + 128, nen row*640 = (row << 9) + (row << 7)
    wire [18:0] row_base = {v_cnt[8:0], 9'd0} + {v_cnt[8:0], 7'd0, 2'd0};
    // Luu y: v_cnt max = 479, can 9 bit. h_cnt max = 639, can 10 bit
    // row_base = v_cnt * 512 + v_cnt * 128 = v_cnt * 640
    // Nhung phai tinh dung bit width:
    // v_cnt[8:0] << 9 = {v_cnt[8:0], 9'b0} = 18 bits
    // v_cnt[8:0] << 7 = {v_cnt[8:0], 7'b0} = 16 bits
    // Tong co the len 19 bits

    // Tinh lai cho chinh xac:
    wire [18:0] addr_row = ({1'b0, v_cnt[8:0], 9'd0}) + ({3'd0, v_cnt[8:0], 7'd0});
    assign fb_rd_addr = active ? (addr_row + {9'd0, h_cnt}) : 19'd0;

    // Pipeline delay 1 clk (BRAM co 1 cycle read latency)
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

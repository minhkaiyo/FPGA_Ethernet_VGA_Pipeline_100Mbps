// File: vga_output_lb.v
// Mo ta: VGA controller 640x480@60Hz voi giao dien Line Buffer
//        Thay vi doc BRAM truc tiep, module nay:
//        1. Tao timing signal (HS, VS, DE)
//        2. Vao dau moi dong blanking -> phat vga_line_req de Arbiter prefetch
//        3. Trong active area -> doc pixel tu line buffer cua Arbiter
// Ngay: 16/05/2026
//
// Timing 640x480@60Hz (pixel clock = 25.175 MHz ~ 25 MHz):
//   H: 640 active + 16 FP + 96 SYNC + 48 BP = 800 total
//   V: 480 active + 10 FP + 2  SYNC + 33 BP = 525 total

module vga_output_lb (
    input  wire        clk,        // 25 MHz pixel clock
    input  wire        rst_n,

    // --- Line Buffer interface (from sdram_frame_arbiter) ---
    output reg         vga_line_req,   // pulse: request prefetch of next line
    output reg  [8:0]  vga_line_num,   // which line to prefetch (0-479)
    input  wire [7:0]  px_data,        // pixel from line buffer (Mono8)
    input  wire        px_valid,       // data valid
    output reg  [9:0]  vga_px_col,     // column being displayed (for lbuf index)

    // --- VGA physical outputs ---
    output wire [7:0]  VGA_R,
    output wire [7:0]  VGA_G,
    output wire [7:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,
    output wire        VGA_BLANK_N,
    output wire        VGA_SYNC_N,
    output wire        VGA_CLK
);

    // -----------------------------------------------------------------------
    // Timing parameters
    localparam H_ACTIVE = 640;
    localparam H_FP     = 16;
    localparam H_SYNC   = 96;
    localparam H_BP     = 48;
    localparam H_TOTAL  = H_ACTIVE + H_FP + H_SYNC + H_BP;  // 800

    localparam V_ACTIVE = 480;
    localparam V_FP     = 10;
    localparam V_SYNC   = 2;
    localparam V_BP     = 33;
    localparam V_TOTAL  = V_ACTIVE + V_FP + V_SYNC + V_BP;  // 525

    // Sync polarities (VGA 640x480: both negative)
    localparam HS_POL = 0;  // 0 = active-low
    localparam VS_POL = 0;

    // -----------------------------------------------------------------------
    // Counters
    reg [9:0] hcnt;  // 0..799
    reg [9:0] vcnt;  // 0..524

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hcnt <= 10'd0;
            vcnt <= 10'd0;
        end else begin
            if (hcnt == H_TOTAL - 1) begin
                hcnt <= 10'd0;
                if (vcnt == V_TOTAL - 1)
                    vcnt <= 10'd0;
                else
                    vcnt <= vcnt + 1'b1;
            end else begin
                hcnt <= hcnt + 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Sync signals
    wire h_sync_active = (hcnt >= H_ACTIVE + H_FP) && (hcnt < H_ACTIVE + H_FP + H_SYNC);
    wire v_sync_active = (vcnt >= V_ACTIVE + V_FP) && (vcnt < V_ACTIVE + V_FP + V_SYNC);

    reg hs_r, vs_r;
    always @(posedge clk) begin
        hs_r <= HS_POL ? h_sync_active : ~h_sync_active;
        vs_r <= VS_POL ? v_sync_active : ~v_sync_active;
    end

    // Active area
    wire h_active = (hcnt < H_ACTIVE);
    wire v_active = (vcnt < V_ACTIVE);
    wire de = h_active && v_active;

    reg de_r;
    always @(posedge clk) de_r <= de;

    // -----------------------------------------------------------------------
    // Line request: at START of horizontal blanking (hcnt == H_ACTIVE)
    // for line (vcnt): request prefetch of NEXT line if not in vsync
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vga_line_req <= 1'b0;
            vga_line_num <= 9'd0;
        end else begin
            vga_line_req <= 1'b0;
            // Prefetch during horizontal blanking, for current vcnt
            // (arbiter needs the line ready before hcnt loops back to 0)
            if (hcnt == H_ACTIVE && v_active) begin
                vga_line_req <= 1'b1;
                vga_line_num <= vcnt[8:0];
            end
        end
    end

    // -----------------------------------------------------------------------
    // Column index for line buffer
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vga_px_col <= 10'd0;
        end else begin
            if (!h_active)
                vga_px_col <= 10'd0;
            else
                vga_px_col <= hcnt;
        end
    end

    // -----------------------------------------------------------------------
    // Pixel output: Mono8 -> RGB (grayscale)
    reg [7:0] px_r;
    always @(posedge clk) begin
        if (de_r && px_valid)
            px_r <= px_data;
        else
            px_r <= 8'd0;
    end

    assign VGA_R      = de_r ? px_r : 8'd0;
    assign VGA_G      = de_r ? px_r : 8'd0;
    assign VGA_B      = de_r ? px_r : 8'd0;
    assign VGA_HS     = hs_r;
    assign VGA_VS     = vs_r;
    assign VGA_BLANK_N= de_r;
    assign VGA_SYNC_N = 1'b0;   // composite sync not used
    assign VGA_CLK    = clk;

endmodule

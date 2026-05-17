// File: framebuffer_pingpong.v
// Mo ta: BRAM Single buffer 640x480 Mono8 (Giam tu 2 bank xuong 1 bank)
//        De giam tai routing congestion va compile nhanh hon.
// Ngay: 17/05/2026

module framebuffer_pingpong #(
    parameter FRAME_PIXELS = 307200   // 640 x 480
) (
    // --- Write port (Ethernet domain) ---
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,
    input  wire [7:0]  wr_data,
    input  wire        eth_frame_done, // 1-cycle pulse: frame done

    // --- Read port (VGA domain, 25MHz) ---
    input  wire        rd_clk,
    input  wire [18:0] rd_addr,
    output wire [7:0]  rd_data,

    // --- Debug ---
    output wire        wr_bank,
    output wire        rd_bank
);

    // Debug signals (fake ping-pong toggle for LEDs)
    reg bank_wr = 1'b0;
    always @(posedge wr_clk)
        if (eth_frame_done) bank_wr <= ~bank_wr;

    assign wr_bank = bank_wr;
    assign rd_bank = ~bank_wr;

    // -------------------------------------------------------
    // Single BRAM (Giam 50% tai nguyen so voi Ping-Pong)
    // -------------------------------------------------------
    (* ramstyle = "M9K" *) reg [7:0] mem0 [0:FRAME_PIXELS-1];

    // --- Write ---
    always @(posedge wr_clk) begin
        if (wr_en) begin
            mem0[wr_addr] <= wr_data; // Chi ghi vao mem0
        end
    end

    // --- Read ---
    reg [7:0] rd_out0;
    always @(posedge rd_clk) begin
        rd_out0 <= mem0[rd_addr];
    end

    assign rd_data = rd_out0;

endmodule

// File: framebuffer_bram.v
// Mo ta: True Dual-Port Block RAM, 640x480 x 8-bit (Mono8 framebuffer)
//        Port A = Write (Ethernet), Port B = Read (VGA)
// Ngay: 16/05/2026

module framebuffer_bram (
    // Write port (Ethernet RX clock domain)
    input  wire        wr_clk,
    input  wire        wr_en,
    input  wire [18:0] wr_addr,   // clog2(307200) = 19 bits
    input  wire [7:0]  wr_data,

    // Read port (VGA pixel clock domain)
    input  wire        rd_clk,
    input  wire [18:0] rd_addr,
    output reg  [7:0]  rd_data
);

    // 640 * 480 = 307200 bytes
    // EP4CE115 co 3,981,312 bit M9K => du chua 307200*8 = 2,457,600 bit (61.7%)
    (* ramstyle = "M9K" *) reg [7:0] mem [0:307199];

    // Khoi tao toan bo ve mau den
    integer i;
    initial begin
        for (i = 0; i < 307200; i = i + 1)
            mem[i] = 8'd0;
    end

    // Port A: Write
    always @(posedge wr_clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    // Port B: Read (1 clock latency)
    always @(posedge rd_clk) begin
        rd_data <= mem[rd_addr];
    end

endmodule

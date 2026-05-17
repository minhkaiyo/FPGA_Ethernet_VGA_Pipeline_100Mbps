// File: eth_pixel_rx.v
// Mo ta: Nhan raw Ethernet frame tu MAC, parse header IP/UDP,
//        extract pixel data va ghi vao framebuffer BRAM.
//        Khong can full UDP/IP/ARP stack — chi can nhan (RX only).
// Ngay: 16/05/2026
//
// Ethernet frame layout (tu MAC, da strip Preamble/SFD/CRC):
//   Byte  0- 5: Dest MAC
//   Byte  6-11: Src MAC
//   Byte 12-13: EtherType (0x0800 = IPv4)
//   Byte 14-33: IP Header (20 bytes, no options)
//     Byte 23: Protocol (0x11 = UDP)
//   Byte 34-41: UDP Header (8 bytes)
//     Byte 36-37: Dest Port
//   Byte 42-43: Row Index (2 bytes, big-endian) -- start of UDP payload
//   Byte 44+  : Pixel data (FRAME_WIDTH bytes)

module eth_pixel_rx #(
    parameter UDP_PORT    = 16'd1234,
    parameter FRAME_WIDTH = 640,
    parameter FRAME_HEIGHT = 480
)(
    input  wire        clk,           // rx_clk tu MAC (25MHz @ 100Mbps)
    input  wire        rst,

    // AXI-Stream input tu eth_mac_mii
    input  wire [7:0]  s_axis_tdata,
    input  wire        s_axis_tvalid,
    input  wire        s_axis_tlast,
    input  wire        s_axis_tuser,  // 1 = bad frame (on tlast)

    // Framebuffer write port
    output reg         fb_wr_en,
    output reg  [18:0] fb_wr_addr,
    output reg  [7:0]  fb_wr_data,

    // Debug / status
    output reg  [15:0] rx_frame_cnt,  // dem so frame nhan duoc
    
    // SDRAM Ping-Pong Control
    output reg         eth_frame_done // Pulse khi nhan xong 1 frame
);

    // Byte counter trong frame hien tai
    reg [10:0] byte_cnt;    // max ~1500 bytes/frame

    // Cac truong can kiem tra
    reg        is_ipv4;     // EtherType == 0x0800
    reg        is_udp;      // Protocol == 0x11
    reg        port_match;  // Dest Port == UDP_PORT
    reg        frame_valid; // tat ca dieu kien thoa man

    // Row index tu UDP payload (2 bytes big-endian)
    reg [15:0] row_idx;

    // Base address = row_idx * 640 = row_idx * (512 + 128)
    wire [18:0] row_base = {row_idx[9:0], 9'd0} + {row_idx[9:0], 7'd0};
    // row_idx << 9 = row_idx * 512
    // row_idx << 7 = row_idx * 128
    // Tong = row_idx * 640

    // Pixel offset trong dong hien tai
    reg [9:0]  pixel_offset;

    always @(posedge clk) begin
        if (rst) begin
            byte_cnt     <= 0;
            is_ipv4      <= 0;
            is_udp       <= 0;
            port_match   <= 0;
            frame_valid  <= 0;
            row_idx      <= 0;
            pixel_offset <= 0;
            fb_wr_en     <= 0;
            rx_frame_cnt <= 0;
            eth_frame_done <= 0;
        end else begin
            fb_wr_en <= 1'b0; // mac dinh khong ghi
            eth_frame_done <= 1'b0;

            if (s_axis_tvalid) begin
                byte_cnt <= byte_cnt + 1'b1;

                // --- Parse header ---
                case (byte_cnt)
                    // EtherType byte 12 (high)
                    11'd12: is_ipv4 <= (s_axis_tdata == 8'h08);
                    // EtherType byte 13 (low) — kiem tra ca 2 byte
                    11'd13: is_ipv4 <= is_ipv4 & (s_axis_tdata == 8'h00);

                    // IP Protocol byte 23
                    11'd23: is_udp <= (s_axis_tdata == 8'h11);

                    // UDP Dest Port byte 36 (high)
                    11'd36: port_match <= (s_axis_tdata == UDP_PORT[15:8]);
                    // UDP Dest Port byte 37 (low)
                    11'd37: begin
                        port_match <= port_match & (s_axis_tdata == UDP_PORT[7:0]);
                        // Xac nhan tat ca dieu kien
                        frame_valid <= is_ipv4 & is_udp;
                    end

                    // Row Index byte 42 (high byte)
                    11'd42: row_idx[15:8] <= s_axis_tdata;
                    // Row Index byte 43 (low byte)
                    11'd43: begin
                        row_idx[7:0] <= s_axis_tdata;
                        pixel_offset <= 0;
                    end

                    default: ;
                endcase

                // --- Ghi pixel data (bat dau tu byte 44) ---
                if (byte_cnt >= 11'd44 && frame_valid && port_match) begin
                    if (pixel_offset < FRAME_WIDTH && row_idx < FRAME_HEIGHT) begin
                        fb_wr_en   <= 1'b1;
                        fb_wr_addr <= row_base + {9'd0, pixel_offset};
                        fb_wr_data <= s_axis_tdata;
                        pixel_offset <= pixel_offset + 1'b1;
                    end
                end

                // --- End of frame ---
                if (s_axis_tlast) begin
                    if (frame_valid && port_match && !s_axis_tuser) begin
                        rx_frame_cnt <= rx_frame_cnt + 1'b1;
                        if (row_idx == FRAME_HEIGHT - 1) begin
                            eth_frame_done <= 1'b1;
                        end
                    end

                    // Reset cho frame tiep theo
                    byte_cnt     <= 0;
                    is_ipv4      <= 0;
                    is_udp       <= 0;
                    port_match   <= 0;
                    frame_valid  <= 0;
                    pixel_offset <= 0;
                end
            end
        end
    end

endmodule

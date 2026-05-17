// File: sdram_frame_arbiter.v
// Mo ta: Double Frame Buffer Arbiter — simple, reliable version
//        - Ethernet ghi pixel -> FIFO (CDC) -> pack 4 bytes = 1 word 32-bit -> ghi SDRAM
//        - VGA doc: prefetch 1 dong (640 byte = 160 word) vao BRAM line buffer
//        - Bank swap khi Ethernet gui xong 1 frame
// Ngay: 16/05/2026

module sdram_frame_arbiter #(
    parameter FRAME_W    = 640,
    parameter FRAME_H    = 480
) (
    // --- Clocks ---
    input  wire        clk_sdram,   // 100 MHz
    input  wire        clk_eth,     // 25 MHz
    input  wire        clk_vga,     // 25 MHz
    input  wire        rst_n,       // sync to clk_sdram

    // --- Ethernet Write Port (clk_eth domain) ---
    input  wire        eth_px_valid,
    input  wire [7:0]  eth_px_data,
    input  wire [18:0] eth_px_addr,     // 0..307199
    input  wire        eth_frame_done,

    // --- VGA Read Port (clk_vga domain) ---
    input  wire        vga_line_req,    // pulse at start of hblank
    input  wire [8:0]  vga_line_num,    // 0..479
    input  wire [9:0]  vga_px_col,      // 0..639
    output wire [7:0]  vga_px_data,     // pixel out

    // --- SDRAM Controller (clk_sdram domain) ---
    output reg         sdram_wr_req,
    output reg  [24:0] sdram_wr_addr,
    output reg  [31:0] sdram_wr_data,
    input  wire        sdram_wr_ack,

    output reg         sdram_rd_req,
    output reg  [24:0] sdram_rd_addr,
    input  wire [31:0] sdram_rd_data,
    input  wire        sdram_rd_valid,

    input  wire        sdram_ready,

    // --- Debug ---
    output reg         wr_bank,
    output reg         rd_bank
);

    // Frame size in 32-bit words: 640*480/4 = 76800 words/frame
    localparam FRAME_WORDS = (FRAME_W * FRAME_H) / 4;  // 76800
    localparam LINE_WORDS  = FRAME_W / 4;               // 160 words/line
    localparam [24:0] BANK_A_BASE = 25'd0;
    localparam [24:0] BANK_B_BASE = FRAME_WORDS;        // 76800

    // =================================================================
    // CDC: eth_frame_done (clk_eth) -> clk_sdram
    // =================================================================
    reg [2:0] fd_sync;
    always @(posedge clk_sdram or negedge rst_n) begin
        if (!rst_n) fd_sync <= 3'b0;
        else        fd_sync <= {fd_sync[1:0], eth_frame_done};
    end
    // Rising edge detect: fd_sync[1] is new, fd_sync[2] is old
    wire frame_done_rise = fd_sync[1] & ~fd_sync[2];

    // =================================================================
    // CDC: vga_line_req (clk_vga) -> clk_sdram
    // =================================================================
    reg [2:0] lr_sync;
    always @(posedge clk_sdram or negedge rst_n) begin
        if (!rst_n) lr_sync <= 3'b0;
        else        lr_sync <= {lr_sync[1:0], vga_line_req};
    end
    wire line_req_rise = lr_sync[1] & ~lr_sync[2];

    // Latch line number (sync to clk_sdram)
    reg [8:0] line_num_lat;
    always @(posedge clk_sdram) begin
        if (line_req_rise) line_num_lat <= vga_line_num;
    end

    // =================================================================
    // BANK SWAP
    // =================================================================
    always @(posedge clk_sdram or negedge rst_n) begin
        if (!rst_n) begin
            wr_bank <= 1'b0;
            rd_bank <= 1'b0;  // both start at 0, first frame writes to A
        end else if (frame_done_rise) begin
            wr_bank <= ~wr_bank;
            rd_bank <= wr_bank;  // VGA now reads the bank that was just written
        end
    end

    // =================================================================
    // WRITE FIFO (clk_eth -> clk_sdram)
    // Pack: {addr[18:0], data[7:0]} = 27 bits
    // =================================================================
    wire        wfifo_full, wfifo_empty;
    wire [26:0] wfifo_dout;
    wire [5:0]  wfifo_rfill;

    fifo_async #(
        .DATA_WIDTH         (27),
        .PTR_WIDTH          (6),
        .ALMOSTFULL_OFFSET  (4),
        .ALMOSTEMPTY_OFFSET (4)
    ) write_fifo (
        .i_wclk  (clk_eth),
        .i_wrstn (rst_n),
        .i_wr    (eth_px_valid & ~wfifo_full),
        .i_wdata ({eth_px_addr, eth_px_data}),
        .o_wfull (wfifo_full),
        .o_walmostfull (),
        .o_wfill (),
        .i_rclk  (clk_sdram),
        .i_rrstn (rst_n),
        .i_rd    (wfifo_rd_en),
        .o_rdata (wfifo_dout),
        .o_rempty(wfifo_empty),
        .o_ralmostempty (),
        .o_rfill (wfifo_rfill)
    );

    // =================================================================
    // MAIN ARBITER FSM (clk_sdram)
    // Priority: Refresh (in controller) > VGA Read > Ethernet Write
    // =================================================================
    localparam [2:0]
        ARB_IDLE      = 3'd0,
        ARB_WR_PACK   = 3'd1,
        ARB_WR_ISSUE  = 3'd2,
        ARB_RD_ISSUE  = 3'd3,
        ARB_RD_WAIT   = 3'd4;

    reg [2:0]  arb_state;
    reg        wfifo_rd_en;

    // Write packing: collect 4 bytes -> 1 word (32-bit)
    reg [7:0]  wr_byte_buf [0:3];
    reg [1:0]  wr_byte_cnt;       // 0..3
    reg [18:0] wr_first_addr;     // pixel address of first byte in group
    reg        wr_pack_valid;     // 4 bytes collected

    // Read state
    reg [7:0]  rd_line_cnt;       // words read so far (0..159)
    reg        rd_pending;        // line prefetch requested
    reg [8:0]  rd_line_num;       // which line to prefetch

    // Line Buffer: True dual-port BRAM style
    // Write port: clk_sdram, 32-bit words -> unpack to 4 bytes
    // Read port: clk_vga, 8-bit pixels
    reg [7:0] line_buf [0:FRAME_W-1];
    reg [9:0] lbuf_wr_addr;

    // VGA read port (clk_vga domain) — safe because write completes in hblank
    reg [7:0] vga_px_reg;
    always @(posedge clk_vga) begin
        vga_px_reg <= line_buf[vga_px_col];
    end
    assign vga_px_data = vga_px_reg;

    // Mark pending read
    always @(posedge clk_sdram or negedge rst_n) begin
        if (!rst_n) rd_pending <= 1'b0;
        else begin
            if (line_req_rise) begin
                rd_pending  <= 1'b1;
                rd_line_num <= line_num_lat;
            end
            if (arb_state == ARB_RD_ISSUE && rd_line_cnt == 0)
                ; // keep pending until done
            if (arb_state == ARB_IDLE && rd_pending && rd_line_cnt >= LINE_WORDS)
                rd_pending <= 1'b0;
        end
    end

    // FSM
    always @(posedge clk_sdram or negedge rst_n) begin
        if (!rst_n) begin
            arb_state    <= ARB_IDLE;
            wfifo_rd_en  <= 1'b0;
            sdram_wr_req <= 1'b0;
            sdram_rd_req <= 1'b0;
            wr_byte_cnt  <= 2'd0;
            wr_pack_valid<= 1'b0;
            rd_line_cnt  <= 8'd0;
            lbuf_wr_addr <= 10'd0;
        end else begin
            wfifo_rd_en  <= 1'b0;
            sdram_wr_req <= 1'b0;
            sdram_rd_req <= 1'b0;

            case (arb_state)
            ARB_IDLE: begin
                // Priority 1: VGA line prefetch
                if (rd_pending && rd_line_cnt < LINE_WORDS && sdram_ready) begin
                    arb_state <= ARB_RD_ISSUE;
                end
                // Priority 2: Write pixels (need 4 bytes in FIFO)
                else if (!wfifo_empty && sdram_ready) begin
                    wfifo_rd_en <= 1'b1;
                    arb_state   <= ARB_WR_PACK;
                end
            end

            // ---- WRITE: pack 4 bytes ----
            ARB_WR_PACK: begin
                // wfifo_dout is valid 1 cycle after rd_en
                if (wr_byte_cnt == 0) wr_first_addr <= wfifo_dout[26:8];
                wr_byte_buf[wr_byte_cnt] <= wfifo_dout[7:0];
                wr_byte_cnt <= wr_byte_cnt + 1'b1;

                if (wr_byte_cnt == 2'd3) begin
                    // Got 4 bytes -> issue write
                    wr_pack_valid <= 1'b1;
                    arb_state     <= ARB_WR_ISSUE;
                end else if (!wfifo_empty) begin
                    wfifo_rd_en <= 1'b1;  // read next byte
                end else begin
                    arb_state <= ARB_IDLE;  // not enough data, go back
                end
            end

            ARB_WR_ISSUE: begin
                if (sdram_ready) begin
                    sdram_wr_req  <= 1'b1;
                    // Word address = pixel_addr / 4 + bank base
                    sdram_wr_addr <= (wr_bank ? BANK_B_BASE : BANK_A_BASE)
                                    + wr_first_addr[18:2];  // pixel_addr / 4
                    sdram_wr_data <= {wr_byte_buf[3], wr_byte_buf[2],
                                     wr_byte_buf[1], wr_byte_buf[0]};
                    wr_pack_valid <= 1'b0;
                    wr_byte_cnt   <= 2'd0;
                    arb_state     <= ARB_IDLE;
                end
            end

            // ---- READ: prefetch line ----
            ARB_RD_ISSUE: begin
                if (sdram_ready) begin
                    sdram_rd_req  <= 1'b1;
                    sdram_rd_addr <= (rd_bank ? BANK_B_BASE : BANK_A_BASE)
                                    + rd_line_num * LINE_WORDS
                                    + rd_line_cnt;
                    arb_state <= ARB_RD_WAIT;
                end
            end

            ARB_RD_WAIT: begin
                if (sdram_rd_valid) begin
                    // Unpack 32-bit word -> 4 bytes into line buffer
                    lbuf_wr_addr = rd_line_cnt * 4;
                    line_buf[lbuf_wr_addr]     <= sdram_rd_data[7:0];
                    line_buf[lbuf_wr_addr + 1] <= sdram_rd_data[15:8];
                    line_buf[lbuf_wr_addr + 2] <= sdram_rd_data[23:16];
                    line_buf[lbuf_wr_addr + 3] <= sdram_rd_data[31:24];
                    rd_line_cnt <= rd_line_cnt + 1'b1;

                    if (rd_line_cnt + 1 >= LINE_WORDS) begin
                        rd_pending <= 1'b0;
                        arb_state  <= ARB_IDLE;
                    end else begin
                        arb_state <= ARB_RD_ISSUE;  // next word
                    end
                end
            end

            default: arb_state <= ARB_IDLE;
            endcase

            // Reset read counter when new line request arrives
            if (line_req_rise) begin
                rd_line_cnt <= 8'd0;
            end
        end
    end

endmodule

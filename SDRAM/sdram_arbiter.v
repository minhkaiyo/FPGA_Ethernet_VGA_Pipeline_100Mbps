/*
 * File: sdram_arbiter.v
 * Description: SDRAM Multi-Port Arbiter with Ping-Pong Buffer support.
 * Maps Ethernet (Write) and VGA (Read) to the SDRAM Controller.
 */

module sdram_arbiter (
    input  wire rst_n,

    // SDRAM Controller Interface (50MHz)
    input  wire        clk_sdram,
    output reg  [23:0] wr_addr,
    output reg  [15:0] wr_data,
    output reg         wr_enable,
    output reg  [23:0] rd_addr,
    input  wire [15:0] rd_data,
    input  wire        rd_ready,
    output reg         rd_enable,
    input  wire        sdram_busy,

    // Ethernet Write Interface (25MHz)
    input  wire        clk_eth,
    input  wire  [7:0] eth_pixel,
    input  wire        eth_valid,
    input  wire        eth_frame_done,

    // VGA Read Interface (25MHz)
    input  wire        clk_vga,
    output wire  [7:0] vga_pixel,
    output wire        vga_fifo_empty, // high when VGA FIFO is empty (underrun)
    input  wire        vga_read,
    input  wire        vga_vsync
);

    // ==========================================
    // 1. Clock Domain Crossing: Ethernet -> SDRAM
    // ==========================================
    wire       wr_fifo_empty;
    wire [7:0] wr_fifo_data;
    reg        wr_fifo_rd;

    fifo_async #(
        .DATA_WIDTH(8),
        .PTR_WIDTH(9), // 512 depth
        .ALMOSTFULL_OFFSET(4),
        .ALMOSTEMPTY_OFFSET(4)
    ) eth_to_sdram_fifo (
        .i_wclk(clk_eth),
        .i_wrstn(rst_n),
        .i_wr(eth_valid),
        .i_wdata(eth_pixel),
        .o_wfull(),
        .o_walmostfull(),
        .o_wfill(),

        .i_rclk(clk_sdram),
        .i_rrstn(rst_n),
        .i_rd(wr_fifo_rd),
        .o_rdata(wr_fifo_data),
        .o_rempty(wr_fifo_empty),
        .o_ralmostempty(),
        .o_rfill()
    );

    // ==========================================
    // 2. Clock Domain Crossing: SDRAM -> VGA
    // ==========================================
    wire rd_fifo_almostfull;
    wire rd_fifo_empty;
    
    fifo_async #(
        .DATA_WIDTH(8),
        .PTR_WIDTH(9), // 512 depth
        .ALMOSTFULL_OFFSET(8),   // stop prefetch when >= 504 full
        .ALMOSTEMPTY_OFFSET(4)
    ) sdram_to_vga_fifo (
        .i_wclk(clk_sdram),
        .i_wrstn(rst_n),
        .i_wr(rd_ready),
        .i_wdata(rd_data[7:0]),
        .o_wfull(),
        .o_walmostfull(rd_fifo_almostfull),
        .o_wfill(),

        .i_rclk(clk_vga),
        .i_rrstn(rst_n),
        .i_rd(vga_read),
        .o_rdata(vga_pixel),
        .o_rempty(rd_fifo_empty),
        .o_ralmostempty(),
        .o_rfill()
    );

    assign vga_fifo_empty = rd_fifo_empty; // expose underrun status

    // ==========================================
    // 3. Ping-Pong Bank Toggling Logic
    // ==========================================
    // We use bit [21] of the SDRAM address as the bank toggle.
    // Bank 0: Addr 0 -> 307199
    // Bank 1: Addr 2^21 -> 2^21 + 307199
    
    reg eth_bank_sel;
    reg vga_bank_sel;
    
    // Toggle Write Bank on eth_frame_done
    reg eth_frame_done_d;
    always @(posedge clk_eth) begin
        if (!rst_n) begin
            eth_bank_sel <= 1'b0;
            eth_frame_done_d <= 1'b0;
        end else begin
            eth_frame_done_d <= eth_frame_done;
            if (eth_frame_done && !eth_frame_done_d) begin
                eth_bank_sel <= ~eth_bank_sel;
            end
        end
    end

    // Sync Write Bank to VGA Domain to avoid tearing
    reg [2:0] bank_sync;
    always @(posedge clk_vga) begin
        if (!rst_n) bank_sync <= 3'b0;
        else bank_sync <= {bank_sync[1:0], eth_bank_sel};
    end

    // On VSYNC, VGA adopts the opposite of the Write Bank
    reg vga_vsync_d;
    always @(posedge clk_vga) begin
        if (!rst_n) begin
            vga_bank_sel <= 1'b1;
            vga_vsync_d <= 1'b1;
        end else begin
            vga_vsync_d <= vga_vsync;
            if (!vga_vsync && vga_vsync_d) begin // falling edge
                vga_bank_sel <= ~bank_sync[2]; 
            end
        end
    end

    // Sync VGA VSYNC back to SDRAM domain to reset read pointers
    // vga_vsync is active-LOW: detect rising edge = end of sync pulse
    reg [2:0] vsync_sdram_sync;
    wire vsync_sdram_pulse = vsync_sdram_sync[2] & ~vsync_sdram_sync[1]; // rising edge of active-low
    always @(posedge clk_sdram) begin
        if (!rst_n) vsync_sdram_sync <= 3'b111;  // idle state = vsync high
        else vsync_sdram_sync <= {vsync_sdram_sync[1:0], vga_vsync};
    end

    // Sync Bank Sels to SDRAM domain
    reg [2:0] eth_bank_sdram; // 3 bits to detect edge
    reg [1:0] vga_bank_sdram;
    always @(posedge clk_sdram) begin
        eth_bank_sdram <= {eth_bank_sdram[1:0], eth_bank_sel};
        vga_bank_sdram <= {vga_bank_sdram[0], vga_bank_sel};
    end

    // Use edge of eth_bank_sdram to reset write pointer!
    wire fdone_sdram_pulse = eth_bank_sdram[1] ^ eth_bank_sdram[2];

    // ==========================================
    // 4. SDRAM Arbiter State Machine
    // ==========================================
    localparam STATE_IDLE  = 2'd0;
    localparam STATE_READ  = 2'd1;
    localparam STATE_WRITE = 2'd2;
    
    reg [1:0] state;
    reg [21:0] wr_ptr;
    reg [21:0] rd_ptr;

    always @(posedge clk_sdram) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            wr_enable <= 1'b0;
            rd_enable <= 1'b0;
            wr_ptr <= 22'd0;
            rd_ptr <= 22'd0;
            wr_fifo_rd <= 1'b0;
        end else begin
            wr_enable <= 1'b0;
            rd_enable <= 1'b0;
            wr_fifo_rd <= 1'b0;

            // Reset pointers on frame boundaries
            if (fdone_sdram_pulse) wr_ptr <= 22'd0;
            if (vsync_sdram_pulse) rd_ptr <= 22'd0;

            case (state)
                STATE_IDLE: begin
                    if (!sdram_busy) begin
                        // Priority 1: VGA Read (Prefetch into FIFO)
                        if (!rd_fifo_almostfull && rd_ptr < 22'd307200) begin
                            rd_addr <= {1'b0, vga_bank_sdram[1], rd_ptr};
                            rd_enable <= 1'b1;
                            rd_ptr <= rd_ptr + 1'b1;
                            state <= STATE_READ;
                        end 
                        // Priority 2: Ethernet Write (Flush from FIFO)
                        else if (!wr_fifo_empty && wr_ptr < 22'd307200) begin
                            state <= STATE_WRITE;
                        end
                    end
                end

                STATE_READ: begin
                    // sdram_controller accepts command in 1 cycle
                    state <= STATE_IDLE;
                end

                STATE_WRITE: begin
                    wr_data <= {8'h00, wr_fifo_data};
                    wr_addr <= {1'b0, eth_bank_sdram[1], wr_ptr};
                    wr_enable <= 1'b1;
                    wr_fifo_rd <= 1'b1; // Pop FIFO this cycle
                    wr_ptr <= wr_ptr + 1'b1;
                    state <= STATE_IDLE;
                end
                
                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule

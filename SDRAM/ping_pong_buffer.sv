/*
 * File: ping_pong_buffer.sv
 * Mo ta: Bo dem Ping-Pong (Double Buffer) chuyen doi tu logic VHDL cua PSI.
 *        Dung de dong bo du lieu giua mien clock Ethernet (Write) va VGA (Read).
 * Ngay: 16/05/2026
 */

module ping_pong_buffer #(
    parameter int DEPTH  = 1024,       // So mau tin (pixels) tren moi buffer
    parameter int WIDTH  = 16          // Do rong du lieu (RGB565 = 16-bit)
)(
    // Write Domain (Ethernet/Input)
    input  logic              clk_i,
    input  logic              rst_i,
    input  logic [WIDTH-1:0]  dat_i,   // Du lieu vao tu Ethernet
    input  logic              vld_i,   // Tin hieu Valid tu MAC/UDP
    
    // Read Domain (VGA/Output)
    input  logic              mem_clk_i,
    input  logic [$clog2(DEPTH)-1:0] mem_addr_spl_i, // Dia chi pixel tu VGA Controller
    output logic [WIDTH-1:0]  mem_dat_o,             // Du lieu pixel xuat ra VGA
    output logic              mem_irq_o              // Ngat bao hieu da doi buffer (Ping <-> Pong)
);

    localparam int ADDR_WIDTH = $clog2(DEPTH);
    localparam int RAM_DEPTH  = 2 * DEPTH;

    logic [ADDR_WIDTH-1:0] sample_cnt;
    logic                  toggle_s; 
    logic [ADDR_WIDTH:0]   write_addr;
    logic [ADDR_WIDTH:0]   read_addr;
    
    // 1. Ghi du lieu (Ethernet Clock Domain)
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            sample_cnt <= '0;
            toggle_s   <= 1'b0;
        end else if (vld_i) begin
            if (sample_cnt == DEPTH - 1) begin
                sample_cnt <= '0;
                toggle_s   <= ~toggle_s; 
            end else begin
                sample_cnt <= sample_cnt + 1'b1;
            end
        end
    end

    assign write_addr = {toggle_s, sample_cnt};

    // 2. Dong bo hoa (Clock Domain Crossing)
    logic [2:0] cdc_sync;
    always_ff @(posedge mem_clk_i) begin
        cdc_sync <= {cdc_sync[1:0], toggle_s};
    end

    assign mem_irq_o = cdc_sync[1] ^ cdc_sync[2];
    assign read_addr = {~cdc_sync[1], mem_addr_spl_i};

    // 3. Dual-Port RAM (Block RAM nội)
    logic [WIDTH-1:0] ram [0:RAM_DEPTH-1];

    always_ff @(posedge clk_i) begin
        if (vld_i) ram[write_addr] <= dat_i;
    end

    always_ff @(posedge mem_clk_i) begin
        mem_dat_o <= ram[read_addr];
    end

endmodule

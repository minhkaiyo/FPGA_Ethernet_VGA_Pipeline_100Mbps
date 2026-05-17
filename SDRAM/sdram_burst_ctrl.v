// File: sdram_burst_ctrl.v
// Mo ta: SDRAM Burst Controller cho IS42S16320D x2 (DE2i-150)
//        - 100MHz, 32-bit bus (2x 16-bit chip), 4-bank, 13-bit row, 10-bit col
//        - Single-word read/write with auto-precharge (simple, reliable)
//        - Future: nang cap burst len 8 sau khi verify single-word hoat dong
// Ngay: 16/05/2026
//
// Giao thuc SDRAM IS42S16320D:
//   tRCD = 2 cycles, CAS Latency = 2, tRP = 2, tRC = 7
//   Refresh: 8192 rows / 64ms = 1 refresh / 780 cycles @ 100MHz

module sdram_burst_ctrl #(
    parameter ROW_WIDTH   = 13,
    parameter COL_WIDTH   = 10,
    parameter BANK_WIDTH  = 2,
    parameter DATA_WIDTH  = 32     // 32-bit bus (2x IS42S16320D)
) (
    input  wire                    clk,        // 100 MHz
    input  wire                    rst_n,

    // --- Host Write Port (single word) ---
    input  wire                    wr_req,
    input  wire [24:0]             wr_addr,    // {bank[1:0], row[12:0], col[9:0]}
    input  wire [DATA_WIDTH-1:0]   wr_data,
    output reg                     wr_ack,     // write accepted

    // --- Host Read Port (single word) ---
    input  wire                    rd_req,
    input  wire [24:0]             rd_addr,
    output reg  [DATA_WIDTH-1:0]   rd_data,
    output reg                     rd_valid,   // read data valid

    output reg                     ready,      // can accept new request

    // --- SDRAM Physical Interface ---
    output reg  [ROW_WIDTH-1:0]    DRAM_ADDR,
    output reg  [BANK_WIDTH-1:0]   DRAM_BA,
    output reg                     DRAM_CAS_N,
    output reg                     DRAM_CKE,
    output reg                     DRAM_CS_N,
    inout  wire [DATA_WIDTH-1:0]   DRAM_DQ,
    output reg  [3:0]              DRAM_DQM,   // 4-bit: 32-bit bus = 4 bytes
    output reg                     DRAM_RAS_N,
    output reg                     DRAM_WE_N
);

    // Mode Register: CAS=2, Burst=1 (single), Sequential, Write burst=single
    localparam [12:0] MODE_REG = 13'b000_0_00_010_0_000;
    //                               rsv WB rsv CL=2 BT BL=1

    // Timing (cycles @ 100MHz)
    localparam T_RP   = 2;
    localparam T_RCD  = 2;
    localparam T_CL   = 2;   // CAS latency
    localparam T_WR   = 2;
    localparam T_RFC  = 7;
    localparam T_MRD  = 2;
    localparam REFRESH_PERIOD = 750;   // 7.5us, with safety margin
    localparam INIT_PAUSE = 10000;     // 100us @ 100MHz

    // FSM states
    localparam [3:0]
        S_INIT     = 4'd0,
        S_INIT_PRE = 4'd1,
        S_INIT_REF1= 4'd2,
        S_INIT_REF2= 4'd3,
        S_INIT_MRS = 4'd4,
        S_IDLE     = 4'd5,
        S_REF      = 4'd6,
        S_ACT      = 4'd7,
        S_WR       = 4'd8,
        S_WR_DONE  = 4'd9,
        S_RD       = 4'd10,
        S_RD_CL    = 4'd11,
        S_RD_DONE  = 4'd12,
        S_WAIT     = 4'd13;

    reg [3:0]  state;
    reg [13:0] wait_cnt;
    reg [9:0]  refresh_cnt;
    reg        refresh_needed;
    reg        is_write;
    reg [24:0] op_addr;
    reg [DATA_WIDTH-1:0] dq_out;
    reg        dq_oe;

    assign DRAM_DQ = dq_oe ? dq_out : {DATA_WIDTH{1'bz}};

    // Address decomposition
    wire [1:0]  a_bank = op_addr[24:23];
    wire [12:0] a_row  = op_addr[22:10];
    wire [9:0]  a_col  = op_addr[9:0];

    // SDRAM commands: {CS_N, RAS_N, CAS_N, WE_N}
    localparam [3:0] CMD_NOP  = 4'b0111,
                     CMD_PALL = 4'b0010,
                     CMD_REF  = 4'b0001,
                     CMD_MRS  = 4'b0000,
                     CMD_ACT  = 4'b0011,
                     CMD_RD   = 4'b0101,
                     CMD_WR   = 4'b0100;

    // Send command macro
    `define SEND_CMD(c) {DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N} <= (c)
    `define SEND_NOP    {DRAM_CS_N, DRAM_RAS_N, DRAM_CAS_N, DRAM_WE_N} <= CMD_NOP

    // Refresh counter
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            refresh_cnt    <= 10'd0;
            refresh_needed <= 1'b0;
        end else begin
            if (refresh_cnt >= REFRESH_PERIOD) begin
                refresh_cnt    <= 10'd0;
                refresh_needed <= 1'b1;
            end else begin
                refresh_cnt <= refresh_cnt + 1'b1;
            end
            if (state == S_REF && wait_cnt == 1)
                refresh_needed <= 1'b0;
        end
    end

    // Main FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_INIT;
            wait_cnt  <= INIT_PAUSE[13:0];
            ready     <= 1'b0;
            wr_ack    <= 1'b0;
            rd_valid  <= 1'b0;
            dq_oe     <= 1'b0;
            DRAM_CKE  <= 1'b1;
            DRAM_DQM  <= 4'b1111;
            DRAM_ADDR <= 13'd0;
            DRAM_BA   <= 2'd0;
            `SEND_NOP;
        end else begin
            // Clear pulses
            wr_ack   <= 1'b0;
            rd_valid <= 1'b0;
            `SEND_NOP;
            dq_oe    <= 1'b0;

            case (state)
            // ===== INIT SEQUENCE =====
            S_INIT: begin
                ready <= 1'b0;
                if (wait_cnt > 0)
                    wait_cnt <= wait_cnt - 1'b1;
                else begin
                    `SEND_CMD(CMD_PALL);
                    DRAM_ADDR[10] <= 1'b1;  // precharge all banks
                    wait_cnt <= T_RP;
                    state <= S_INIT_PRE;
                end
            end

            S_INIT_PRE: begin
                if (wait_cnt > 0) wait_cnt <= wait_cnt - 1'b1;
                else begin
                    `SEND_CMD(CMD_REF);
                    wait_cnt <= T_RFC;
                    state <= S_INIT_REF1;
                end
            end

            S_INIT_REF1: begin
                if (wait_cnt > 0) wait_cnt <= wait_cnt - 1'b1;
                else begin
                    `SEND_CMD(CMD_REF);
                    wait_cnt <= T_RFC;
                    state <= S_INIT_REF2;
                end
            end

            S_INIT_REF2: begin
                if (wait_cnt > 0) wait_cnt <= wait_cnt - 1'b1;
                else begin
                    `SEND_CMD(CMD_MRS);
                    DRAM_BA   <= 2'b00;
                    DRAM_ADDR <= MODE_REG;
                    wait_cnt  <= T_MRD;
                    state <= S_INIT_MRS;
                end
            end

            S_INIT_MRS: begin
                if (wait_cnt > 0) wait_cnt <= wait_cnt - 1'b1;
                else begin
                    ready <= 1'b1;
                    state <= S_IDLE;
                end
            end

            // ===== IDLE =====
            S_IDLE: begin
                ready <= 1'b1;
                if (refresh_needed) begin
                    // Refresh priority
                    `SEND_CMD(CMD_PALL);
                    DRAM_ADDR[10] <= 1'b1;
                    wait_cnt <= T_RP;
                    ready    <= 1'b0;
                    state    <= S_REF;
                end else if (wr_req) begin
                    op_addr  <= wr_addr;
                    is_write <= 1'b1;
                    ready    <= 1'b0;
                    // Activate row
                    `SEND_CMD(CMD_ACT);
                    DRAM_BA   <= wr_addr[24:23];
                    DRAM_ADDR <= wr_addr[22:10];
                    wait_cnt  <= T_RCD;
                    state     <= S_ACT;
                end else if (rd_req) begin
                    op_addr  <= rd_addr;
                    is_write <= 1'b0;
                    ready    <= 1'b0;
                    `SEND_CMD(CMD_ACT);
                    DRAM_BA   <= rd_addr[24:23];
                    DRAM_ADDR <= rd_addr[22:10];
                    wait_cnt  <= T_RCD;
                    state     <= S_ACT;
                end
            end

            // ===== REFRESH =====
            S_REF: begin
                if (wait_cnt > 0) wait_cnt <= wait_cnt - 1'b1;
                else begin
                    `SEND_CMD(CMD_REF);
                    wait_cnt <= T_RFC;
                    state    <= S_WAIT;
                end
            end

            // ===== ACTIVATE -> READ/WRITE =====
            S_ACT: begin
                if (wait_cnt > 0) wait_cnt <= wait_cnt - 1'b1;
                else begin
                    if (is_write) begin
                        `SEND_CMD(CMD_WR);
                        DRAM_BA   <= a_bank;
                        DRAM_ADDR <= {3'b010, a_col};  // A10=1 auto-precharge
                        DRAM_DQM  <= 4'b0000;
                        dq_oe     <= 1'b1;
                        dq_out    <= wr_data;
                        wr_ack    <= 1'b1;
                        wait_cnt  <= T_WR + T_RP;  // write recovery + precharge
                        state     <= S_WR_DONE;
                    end else begin
                        `SEND_CMD(CMD_RD);
                        DRAM_BA   <= a_bank;
                        DRAM_ADDR <= {3'b010, a_col};  // A10=1 auto-precharge
                        DRAM_DQM  <= 4'b0000;
                        wait_cnt  <= T_CL;  // wait CAS latency
                        state     <= S_RD_CL;
                    end
                end
            end

            // ===== WRITE DONE (wait tWR+tRP) =====
            S_WR_DONE: begin
                if (wait_cnt > 0) wait_cnt <= wait_cnt - 1'b1;
                else begin
                    state <= S_IDLE;
                    ready <= 1'b1;
                end
            end

            // ===== READ: wait CAS latency =====
            S_RD_CL: begin
                if (wait_cnt > 0) wait_cnt <= wait_cnt - 1'b1;
                else begin
                    // Data appears on DQ now
                    rd_data  <= DRAM_DQ;
                    rd_valid <= 1'b1;
                    wait_cnt <= T_RP;  // wait for auto-precharge
                    state    <= S_RD_DONE;
                end
            end

            S_RD_DONE: begin
                if (wait_cnt > 0) wait_cnt <= wait_cnt - 1'b1;
                else begin
                    state <= S_IDLE;
                    ready <= 1'b1;
                end
            end

            // ===== GENERIC WAIT (after refresh) =====
            S_WAIT: begin
                if (wait_cnt > 0) wait_cnt <= wait_cnt - 1'b1;
                else begin
                    state <= S_IDLE;
                    ready <= 1'b1;
                end
            end

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule

// File: mdio_init.v
// Mo ta: MDIO controller don gian — chi can ghi 1 register duy nhat
//        de bat RGMII RX/TX timing delay tren 88E1111 PHY
//        Register 20 (0x14): Bit 7 = RX delay, Bit 1 = TX delay
// Board: DE2i-150, Marvell 88E1111
// Ngay: 16/05/2026

module mdio_init #(
    parameter PHY_ADDR   = 5'h00,       // 88E1111 default PHY address (0 or 1)
    parameter CLK_DIV    = 8'd100       // MDC divider: 125MHz/100 = 1.25MHz MDC (~800ns period)
)(
    input  wire clk,                     // 125MHz system clock
    input  wire rst_n,
    output reg  mdc,
    inout  wire mdio,
    output reg  init_done                // 1 khi da cau hinh xong
);

    // ===== MDIO frame format (IEEE 802.3 clause 22) =====
    // Preamble (32x 1) + ST(01) + OP(01=write) + PHYAD(5) + REGAD(5) + TA(10) + DATA(16)
    // Total: 64 bits

    // Register 20 (0x14) write data:
    // Bit 7 = 1 (RX delay ON)
    // Bit 1 = 1 (TX delay ON)
    // Other bits = keep default (0x0082)
    localparam REG_ADDR  = 5'h14;       // Register 20
    localparam REG_DATA  = 16'h0082;    // Bit7=1 (RX delay) + Bit1=1 (TX delay)

    // MDIO write frame (64 bits)
    // [63:32] = 32'hFFFFFFFF (preamble)
    // [31:30] = 2'b01 (start)
    // [29:28] = 2'b01 (write opcode)
    // [27:23] = PHY_ADDR
    // [22:18] = REG_ADDR
    // [17:16] = 2'b10 (turnaround)
    // [15:0]  = REG_DATA
    wire [63:0] mdio_frame = {
        32'hFFFFFFFF,                    // preamble
        2'b01,                           // start of frame
        2'b01,                           // opcode: write
        PHY_ADDR,                        // PHY address
        REG_ADDR,                        // register address
        2'b10,                           // turnaround
        REG_DATA                         // data to write
    };

    // State machine
    localparam S_IDLE    = 3'd0;
    localparam S_WAIT    = 3'd1;        // Wait 10ms after reset for PHY ready
    localparam S_SEND    = 3'd2;        // Transmit MDIO frame
    localparam S_DONE    = 3'd3;

    reg [2:0]  state;
    reg [23:0] wait_cnt;                // Max 2^24 = ~134ms @ 125MHz
    reg [7:0]  clk_cnt;                 // MDC divider counter
    reg [6:0]  bit_cnt;                 // 0..63 bit position
    reg        mdc_int;
    reg        mdio_out;
    reg        mdio_oe;                 // 1 = drive MDIO

    assign mdio = mdio_oe ? mdio_out : 1'bz;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            wait_cnt  <= 0;
            clk_cnt   <= 0;
            bit_cnt   <= 0;
            mdc       <= 1'b0;
            mdc_int   <= 1'b0;
            mdio_out  <= 1'b1;
            mdio_oe   <= 1'b0;
            init_done <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    wait_cnt <= 0;
                    state    <= S_WAIT;
                end

                // Doi 10ms sau reset de PHY san sang (~1.25M cycles @ 125MHz)
                S_WAIT: begin
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt >= 24'd1_250_000) begin
                        state    <= S_SEND;
                        bit_cnt  <= 7'd63;   // MSB first
                        clk_cnt  <= 0;
                        mdio_oe  <= 1'b1;    // Drive MDIO
                    end
                end

                // Gui tung bit cua MDIO frame
                S_SEND: begin
                    clk_cnt <= clk_cnt + 1'b1;

                    if (clk_cnt == 0) begin
                        // Setup data truoc rising edge
                        mdio_out <= mdio_frame[bit_cnt];
                        mdc      <= 1'b0;
                    end else if (clk_cnt == (CLK_DIV >> 1)) begin
                        // Rising edge MDC — PHY latches data
                        mdc <= 1'b1;
                    end else if (clk_cnt >= CLK_DIV - 1) begin
                        clk_cnt <= 0;
                        if (bit_cnt == 0) begin
                            // Frame hoan tat
                            state   <= S_DONE;
                            mdio_oe <= 1'b0;
                            mdc     <= 1'b0;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end
                end

                S_DONE: begin
                    init_done <= 1'b1;
                    mdc       <= 1'b0;
                    mdio_oe   <= 1'b0;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

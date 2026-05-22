`timescale 1ns / 1ps

module tb_eth_loopback;

    // Clocks
    reg gtx_clk = 0;
    reg gtx_clk90 = 0;
    reg logic_clk = 0;
    
    always #4 gtx_clk = ~gtx_clk;     // 125 MHz
    always #4 logic_clk = ~logic_clk; // 125 MHz
    
    initial begin
        #6 gtx_clk90 = 1;             // Lag 90 degrees (lagging 1/4 of 8ns period)
        forever #4 gtx_clk90 = ~gtx_clk90;
    end

    // Resets
    reg gtx_rst = 1;
    reg logic_rst = 1;

    // AXI TX
    reg [7:0] tx_axis_tdata = 0;
    reg tx_axis_tvalid = 0;
    wire tx_axis_tready;
    reg tx_axis_tlast = 0;
    reg tx_axis_tuser = 0;

    // AXI RX
    wire [7:0] rx_axis_tdata;
    wire rx_axis_tvalid;
    reg rx_axis_tready = 1;
    wire rx_axis_tlast;
    wire rx_axis_tuser;

    // RGMII Loopback connections with 1ns physical cable delay
    wire rgmii_tx_clk;
    wire [3:0] rgmii_txd;
    wire rgmii_tx_ctl;

    wire rgmii_rx_clk;
    assign #1 rgmii_rx_clk = rgmii_tx_clk;

    wire [3:0] rgmii_rxd;
    assign #1 rgmii_rxd = rgmii_txd;

    wire rgmii_rx_ctl;
    assign #1 rgmii_rx_ctl = rgmii_tx_ctl;

    // Status
    wire [1:0] speed;

    eth_mac_1g_rgmii_fifo #(
        .TARGET("ALTERA"),
        .AXIS_DATA_WIDTH(8),
        .ENABLE_PADDING(1),
        .MIN_FRAME_LENGTH(64)
    ) mac_inst (
        .gtx_clk(gtx_clk),
        .gtx_clk90(gtx_clk90),
        .gtx_rst(gtx_rst),
        .logic_clk(logic_clk),
        .logic_rst(logic_rst),

        .tx_axis_tdata(tx_axis_tdata),
        .tx_axis_tvalid(tx_axis_tvalid),
        .tx_axis_tready(tx_axis_tready),
        .tx_axis_tlast(tx_axis_tlast),
        .tx_axis_tuser(tx_axis_tuser),

        .rx_axis_tdata(rx_axis_tdata),
        .rx_axis_tvalid(rx_axis_tvalid),
        .rx_axis_tready(rx_axis_tready),
        .rx_axis_tlast(rx_axis_tlast),
        .rx_axis_tuser(rx_axis_tuser),

        .rgmii_rx_clk(rgmii_rx_clk),
        .rgmii_rxd(rgmii_rxd),
        .rgmii_rx_ctl(rgmii_rx_ctl),
        .rgmii_tx_clk(rgmii_tx_clk),
        .rgmii_txd(rgmii_txd),
        .rgmii_tx_ctl(rgmii_tx_ctl),

        .cfg_ifg(8'd12),
        .cfg_tx_enable(1'b1),
        .cfg_rx_enable(1'b1),
        
        .speed(speed)
    );

    // Task to send a byte into AXI Stream TX
    task send_byte(input [7:0] data, input last);
        begin
            tx_axis_tdata = data;
            tx_axis_tvalid = 1;
            tx_axis_tlast = last;
            wait(tx_axis_tready);
            @(posedge logic_clk);
            tx_axis_tvalid = 0;
            tx_axis_tlast = 0;
        end
    endtask

    // Test sequence
    initial begin
        $display("=== BẮT ĐẦU ETHERNET RGMII LOOPBACK TEST ===");
        
        // Assert resets
        gtx_rst = 1;
        logic_rst = 1;
        #100;
        
        // Deassert resets
        gtx_rst = 0;
        logic_rst = 0;
        #200;
        
        $display("[%0t ns] Đã nhả Reset. Bắt đầu bơm gói tin vào TX FIFO...", $time);
        
        // Wait a few cycles
        repeat(10) @(posedge logic_clk);
        
        // Send a dummy Ethernet frame (Destination MAC, Source MAC, Type/Length, Payload)
        // Dest MAC: 00:11:22:33:44:55
        send_byte(8'h00, 0); send_byte(8'h11, 0); send_byte(8'h22, 0); send_byte(8'h33, 0); send_byte(8'h44, 0); send_byte(8'h55, 0);
        // Src MAC: 66:77:88:99:AA:BB
        send_byte(8'h66, 0); send_byte(8'h77, 0); send_byte(8'h88, 0); send_byte(8'h99, 0); send_byte(8'hAA, 0); send_byte(8'hBB, 0);
        // EtherType: 0x0800 (IPv4)
        send_byte(8'h08, 0); send_byte(8'h00, 0);
        
        // Payload (10 bytes of data for simplicity)
        send_byte(8'hD0, 0); send_byte(8'hD1, 0); send_byte(8'hD2, 0); send_byte(8'hD3, 0); send_byte(8'hD4, 0);
        send_byte(8'hD5, 0); send_byte(8'hD6, 0); send_byte(8'hD7, 0); send_byte(8'hD8, 0); send_byte(8'hD9, 1);
        
        $display("[%0t ns] Đã bơm xong gói tin vào TX FIFO. Đang chờ dữ liệu chạy vòng qua RGMII về RX...", $time);
        
    // Wait enough time for packet to propagate through FIFOs, MAC, RGMII TX, RGMII RX, RX MAC, and RX FIFO
        #900000;  // Wait 900µs for full loopback: FIFO→MAC TX→RGMII TX→loopback delay→RGMII RX→MAC RX→FIFO→AXI out
        
        $display("=== KẾT THÚC TEST MẪU ===");
        $stop;
    end
    
    // Monitor received data on AXI Stream RX
    always @(posedge logic_clk) begin
        if (rx_axis_tvalid && rx_axis_tready) begin
            $display("[%0t ns] THÀNH CÔNG NHẬN ĐƯỢC DATA BÊN RX: %02h | Tín hiệu kết thúc gói (Last): %b", $time, rx_axis_tdata, rx_axis_tlast);
        end
    end

    // MAC Error Monitoring
    always @(posedge logic_clk) begin
        if (mac_inst.tx_error_underflow) $display("[%0t ns] LỖI MAC: TX Underflow!", $time);
        if (mac_inst.rx_error_bad_frame) $display("[%0t ns] LỖI MAC: RX Bad Frame!", $time);
        if (mac_inst.rx_error_bad_fcs)   $display("[%0t ns] LỖI MAC: RX Bad FCS (Sai Checksum)!", $time);
    end

    // Physical RGMII TX Monitoring
    always @(rgmii_tx_ctl) begin
        $display("[%0t ns] TÍN HIỆU VẬT LÝ: rgmii_tx_ctl chuyển sang mức %b", $time, rgmii_tx_ctl);
    end

    // Internal GMII RX Monitoring
    always @(posedge mac_inst.eth_mac_1g_rgmii_inst.rx_clk) begin
        if (mac_inst.eth_mac_1g_rgmii_inst.mac_gmii_rx_dv) begin
            $display("[%0t ns] RAW GMII RX: %02h", $time, mac_inst.eth_mac_1g_rgmii_inst.mac_gmii_rxd);
        end
    end

endmodule

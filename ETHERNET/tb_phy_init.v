`timescale 1ns/1ps

module tb_phy_init();
    reg clk = 0;
    always #10 clk = ~clk; // 50MHz

    reg rst_n = 0;
    wire phy_rst_n, mdc, mdio;
    wire configured;
    wire [3:0] debug_fsm;
    wire [4:0] debug_addr;

    pullup(mdio); // MDIO is open-drain/pullup

    phy_init_88e1111 #(
        .CLK_MHZ(50),
        .CLK_DIV(10) // Speed up for simulation
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .phy_rst_n(phy_rst_n), .mdc(mdc), .mdio(mdio),
        .configured(configured),
        .debug_fsm(debug_fsm),
        .debug_addr(debug_addr)
    );

    // Dummy PHY responding on MDIO
    reg [15:0] phy_reg2 = 16'h0141; // Marvell OUI
    reg [15:0] phy_reg20 = 16'h0000;
    reg [15:0] phy_reg0 = 16'h0000;

    reg mdio_phy_out = 1'bZ;
    assign mdio = mdio_phy_out;

    integer i;
    reg [15:0] recv_data;
    reg [4:0]  recv_reg;
    reg [4:0]  recv_phy;
    reg [1:0]  recv_op;

    initial begin
        $display("Starting simulation...");
        #100 rst_n = 1;

        // Monitor FSM state
        forever begin
            @(posedge clk);
            if(dut.fsm == 10 && dut.configured) begin
                $display("Time %t: FSM Reached F_DONE. PHY Initialization completed.", $time);
                $finish;
            end
        end
    end

    // MDIO Slave monitor
    always begin
        // Wait for start bits (01)
        wait(mdio === 0 && mdc === 1);
        @(negedge mdc);
        wait(mdio === 1 && mdc === 1);
        @(negedge mdc);
        
        // OP Code
        recv_op[1] = mdio; @(negedge mdc);
        recv_op[0] = mdio; @(negedge mdc);
        
        // PHY Addr
        for(i=4; i>=0; i=i-1) begin recv_phy[i] = mdio; @(negedge mdc); end
        
        // Reg Addr
        for(i=4; i>=0; i=i-1) begin recv_reg[i] = mdio; @(negedge mdc); end
        
        // TA
        @(negedge mdc);
        if(recv_op == 2'b10) begin
            // Read
            mdio_phy_out = 0; @(negedge mdc);
            if(recv_reg == 2) recv_data = phy_reg2;
            else recv_data = 16'hFFFF;
            for(i=15; i>=0; i=i-1) begin
                mdio_phy_out = recv_data[i]; @(negedge mdc);
            end
            mdio_phy_out = 1'bZ;
        end else if(recv_op == 2'b01) begin
            // Write
            @(negedge mdc); // TA bit 2
            for(i=15; i>=0; i=i-1) begin
                recv_data[i] = mdio; @(negedge mdc);
            end
            $display("Time %t: PHY Write Addr=%d Reg=%d Data=%h", $time, recv_phy, recv_reg, recv_data);
        end
    end
endmodule

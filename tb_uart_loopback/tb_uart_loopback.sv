`timescale 1ns / 1ps

module tb_uart_loopback;

    // Use a 10 MHz clock and 1 Mbps baud rate (10 clock cycles per bit)
    // so full UART frames complete quickly in behavioral simulation
    localparam int CLK_FREQ  = 10_000_000;
    localparam int BAUD_RATE = 1_000_000;
    localparam int CLK_PER   = 1_000_000_000 / CLK_FREQ; // 100 ns

    logic       clk;
    logic       rst;

    // AXI4-Stream Slave signals driving uart_tx
    logic [7:0] s_axis_data;
    logic       s_axis_valid;
    logic       s_axis_ready;

    // Serial loopback signals between uart_tx and uart_rx
    logic       loopback_line;
    logic       glitch_force_low;
    logic       rx_mux;

    // AXI4-Stream Master signals driven by uart_rx
    logic [7:0] m_axis_data;
    logic       m_axis_valid;
    logic       m_axis_ready;

    // Expected byte queue and self-checking counters
    byte        exp_queue[$];
    int         pass_count = 0;
    int         fail_count = 0;

    // Clean mux: force line low only during explicit glitch injection
    assign rx_mux = glitch_force_low ? 1'b0 : loopback_line;

    // Instantiate UART Transmitter
    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tx (
        .clk         (clk),
        .rst         (rst),
        .s_axis_data (s_axis_data),
        .s_axis_valid(s_axis_valid),
        .s_axis_ready(s_axis_ready),
        .tx          (loopback_line)
    );

    // Instantiate UART Receiver
    uart_rx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_rx (
        .clk         (clk),
        .rst         (rst),
        .rx          (rx_mux),
        .m_axis_data (m_axis_data),
        .m_axis_valid(m_axis_valid),
        .m_axis_ready(m_axis_ready)
    );

    // Generate system clock
    initial begin
        clk = 1'b0;
        forever #(CLK_PER / 2) clk = ~clk;
    end

    // Task to transmit one byte into uart_tx using AXI4-Stream handshake
    task automatic send_byte(input byte data_in);
        byte exp_val;
        exp_val = data_in;

        @(posedge clk);
        while (!s_axis_ready) begin
            @(posedge clk);
        end

        s_axis_data  <= exp_val;
        s_axis_valid <= 1'b1;
        exp_queue.push_back(exp_val);

        @(posedge clk);
        while (!(s_axis_valid && s_axis_ready)) begin
            @(posedge clk);
        end

        @(posedge clk);
        s_axis_valid <= 1'b0;
        s_axis_data  <= '0;
    endtask

    // Bounded wait task with timeout to prevent indefinite simulation hangs
    task automatic wait_queue_empty(input int max_cycles, input string phase_name);
        int cycles;
        cycles = 0;
        while ((exp_queue.size() > 0) && (cycles < max_cycles)) begin
            @(posedge clk);
            cycles++;
        end

        if (exp_queue.size() > 0) begin
            $display("[FAIL] Timeout during %s: %0d byte(s) remaining at t=%0t",
                     phase_name, exp_queue.size(), $time);
            fail_count += exp_queue.size();
            while (exp_queue.size() > 0) begin
                void'(exp_queue.pop_front());
            end
        end
    endtask

    // Self-checking monitor on uart_rx AXI4-Stream Master output
    always @(posedge clk) begin
        if (!rst && m_axis_valid && m_axis_ready) begin
            if (exp_queue.size() == 0) begin
                $display("[FAIL] Unexpected byte 8'h%02h received with empty queue at t=%0t",
                         m_axis_data, $time);
                fail_count++;
            end else begin
                byte expected_b;
                expected_b = exp_queue.pop_front();
                if (m_axis_data === expected_b) begin
                    $display("[PASS] Loopback matched byte 8'h%02h at t=%0t", m_axis_data, $time);
                    pass_count++;
                end else begin
                    $display("[FAIL] Mismatch at t=%0t: expected 8'h%02h, got 8'h%02h",
                             $time, expected_b, m_axis_data);
                    fail_count++;
                end
            end
        end
    end

    // Main test sequence
    initial begin
        rst              <= 1'b1;
        s_axis_data      <= '0;
        s_axis_valid     <= 1'b0;
        m_axis_ready     <= 1'b1;
        glitch_force_low <= 1'b0;

        repeat (5) @(posedge clk);
        rst <= 1'b0;
        repeat (5) @(posedge clk);

        // 1. Corner-case bytes
        send_byte(8'h55);
        send_byte(8'hA3);
        send_byte(8'h00);
        send_byte(8'hFF);

        wait_queue_empty(2500, "corner-case bytes");
        repeat (30) @(posedge clk);

        // 2. Backpressure test: hold m_axis_ready low while sending a byte
        @(posedge clk);
        m_axis_ready <= 1'b0;
        send_byte(8'h3C);
        repeat (200) @(posedge clk); // Full 10-bit frame takes ~100 clocks at 10x oversampling
        @(posedge clk);
        m_axis_ready <= 1'b1;

        wait_queue_empty(2000, "backpressure release");
        repeat (30) @(posedge clk);

        // 3. Random burst bytes
        for (int i = 0; i < 6; i++) begin
            byte rand_b;
            rand_b = $urandom_range(0, 255);
            send_byte(rand_b);
            repeat ($urandom_range(120, 180)) @(posedge clk);
        end

        wait_queue_empty(4000, "random burst");
        repeat (50) @(posedge clk);

        // 4. Short glitch test (2 clock cycles < half-bit threshold of 5 cycles)
        @(posedge clk);
        glitch_force_low <= 1'b1;
        repeat (2) @(posedge clk);
        glitch_force_low <= 1'b0;
        repeat (40) @(posedge clk);

        // Summary report
        $display("--------------------------------------------------");
        $display("Loopback Test Summary: PASS=%0d, FAIL=%0d", pass_count, fail_count);
        $display("--------------------------------------------------");

        if (fail_count == 0 && pass_count > 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("SOME TESTS FAILED!");
        end

        $finish;
    end

endmodule

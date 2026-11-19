`timescale 1ns / 1ps

module uart_rx #(
    parameter int CLK_FREQ  = 100_000_000, // System clock frequency in Hz
    parameter int BAUD_RATE = 115_200      // UART baud rate in bits per second
)(
    input  logic       clk,
    input  logic       rst,

    // Serial UART input
    input  logic       rx,

    // AXI4-Stream Master interface (downstream FIFO / accelerator)
    output logic [7:0] m_axis_data,
    output logic       m_axis_valid,
    input  logic       m_axis_ready
);

    // Clock cycles per UART bit and mid-bit sampling threshold
    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam int HALF_BIT     = CLKS_PER_BIT / 2;
    localparam int CNT_WIDTH    = $clog2(CLKS_PER_BIT);

    typedef enum logic [1:0] {
        S_IDLE      = 2'b00,
        S_START_BIT = 2'b01,
        S_DATA_BITS = 2'b10,
        S_STOP_BIT  = 2'b11
    } state_t;

    state_t current_state, next_state;

    logic [CNT_WIDTH-1:0] clk_count;
    logic [2:0]           bit_index;
    logic [7:0]           data_reg;
    logic                 byte_ready_pulse;

    // 2-stage flip-flop synchronizer for metastability immunity
    logic rx_sync_1, rx_sync;

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_sync_1 <= 1'b1;
            rx_sync   <= 1'b1;
        end else begin
            rx_sync_1 <= rx;
            rx_sync   <= rx_sync_1;
        end
    end

    // Sequential FSM and bit/clock counters
    always_ff @(posedge clk) begin
        if (rst) begin
            current_state    <= S_IDLE;
            clk_count        <= '0;
            bit_index        <= '0;
            data_reg         <= '0;
            byte_ready_pulse <= 1'b0;
        end else begin
            current_state    <= next_state;
            byte_ready_pulse <= 1'b0;

            case (current_state)
                S_IDLE: begin
                    clk_count <= '0;
                    bit_index <= '0;
                end

                S_START_BIT: begin
                    if (clk_count < HALF_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= '0;
                    end
                end

                S_DATA_BITS: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count           <= '0;
                        data_reg[bit_index] <= rx_sync; // Sample at mid-bit

                        if (bit_index < 3'd7) begin
                            bit_index <= bit_index + 1'b1;
                        end else begin
                            bit_index <= '0;
                        end
                    end
                end

                S_STOP_BIT: begin
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= '0;
                        // Valid framing requires stop bit high
                        if (rx_sync == 1'b1) begin
                            byte_ready_pulse <= 1'b1;
                        end
                    end
                end

                default: begin
                    current_state <= S_IDLE;
                end
            endcase
        end
    end

    // AXI4-Stream Master output stage: holds valid data until handshake occurs
    always_ff @(posedge clk) begin
        if (rst) begin
            m_axis_valid <= 1'b0;
            m_axis_data  <= '0;
        end else begin
            if (m_axis_valid && m_axis_ready) begin
                // Current beat accepted; load new byte if available, else deassert valid
                if (byte_ready_pulse) begin
                    m_axis_data  <= data_reg;
                    m_axis_valid <= 1'b1;
                end else begin
                    m_axis_valid <= 1'b0;
                end
            end else if (!m_axis_valid && byte_ready_pulse) begin
                // Output register is free; latch newly received byte
                m_axis_data  <= data_reg;
                m_axis_valid <= 1'b1;
            end
        end
    end

    // Next-state combinational logic
    always_comb begin
        next_state = current_state;

        case (current_state)
            S_IDLE: begin
                if (rx_sync == 1'b0) begin
                    next_state = S_START_BIT;
                end
            end

            S_START_BIT: begin
                if (clk_count == HALF_BIT - 1) begin
                    if (rx_sync == 1'b0) begin
                        next_state = S_DATA_BITS;
                    end else begin
                        next_state = S_IDLE;
                    end
                end
            end

            S_DATA_BITS: begin
                if ((clk_count == CLKS_PER_BIT - 1) && (bit_index == 3'd7)) begin
                    next_state = S_STOP_BIT;
                end
            end

            S_STOP_BIT: begin
                if (clk_count == CLKS_PER_BIT - 1) begin
                    next_state = S_IDLE;
                end
            end

            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

endmodule

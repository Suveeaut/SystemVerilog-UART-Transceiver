module uart_tx #(
    parameter CLK_FREQ   = 100000000, 
    parameter BAUD_RATE  = 115200     
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       s_axis_valid, 
    input  logic [7:0] s_axis_data,  
    output logic       tx,           
    output logic       s_axis_ready  
);

    localparam int CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    typedef enum logic [2:0] {
        S_IDLE      = 3'b000,
        S_START_BIT = 3'b001,
        S_DATA_BITS = 3'b010,
        S_STOP_BIT  = 3'b011
    } state_t;

    state_t current_state, next_state;

    logic [$clog2(CLKS_PER_BIT)-1:0] clk_count;
    logic [2:0] bit_index;
    logic [7:0] data_reg;

    assign s_axis_ready = (current_state == S_IDLE);

    always_ff @(posedge clk) begin
        if (rst) begin
            current_state <= S_IDLE;
            clk_count     <= 0;
            bit_index     <= 0;
            data_reg      <= 0;
            tx            <= 1'b1; 
        end else begin
            current_state <= next_state;

            case (current_state)
                S_IDLE: begin
                    tx        <= 1'b1;
                    clk_count <= 0;
                    bit_index <= 0;
                    if (s_axis_valid) begin
                        data_reg <= s_axis_data; 
                    end
                end

                S_START_BIT: begin
                    tx <= 1'b0; // ส่ง Start Bit เป็น 0
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                    end
                end

                S_DATA_BITS: begin
                    tx <= data_reg[bit_index]; // ทยอยส่งข้อมูลทีละบิตจาก LSB
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1;
                        end else begin
                            bit_index <= 0;
                        end
                    end
                end

                S_STOP_BIT: begin
                    tx <= 1'b1; // ส่ง Stop Bit เป็น 1
                    if (clk_count < CLKS_PER_BIT - 1) begin
                        clk_count <= clk_count + 1;
                    end else begin
                        clk_count <= 0;
                    end
                end

                default: begin
                    tx <= 1'b1;
                end
            endcase
        end
    end

    // 2. Combinational Logic: สมองกลตัดสินใจเปลี่ยนสถานะ FSM
    always_comb begin
        next_state = current_state;

        case (current_state)
            S_IDLE: begin
                if (s_axis_valid) begin
                    next_state = S_START_BIT;
                end
            end

            S_START_BIT: begin
                if (clk_count == CLKS_PER_BIT - 1) begin
                    next_state = S_DATA_BITS;
                end
            end

            S_DATA_BITS: begin
                if (clk_count == CLKS_PER_BIT - 1 && bit_index == 7) begin
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

`timescale 1ns / 1ps

module uart_tx_tb;

    // 1. ประกาศ Signals สำหรับเชื่อมต่อกับ DUT (Device Under Test)
    logic       clk;
    logic       rst;
    logic       s_axis_valid;
    logic [7:0] s_axis_data;
    logic       tx;
    logic       s_axis_ready;

    // 2. Instantiate โมดูล uart_tx (กำหนดความถี่จำลองให้ต่ำลงหน่อยเพื่อให้จำลองใน Simulator ได้ไวขึ้น)
    uart_tx #(
        .CLK_FREQ  (1000000), // ใช้ Clock 1 MHz เพื่อให้จำลองง่าย
        .BAUD_RATE (9600)     // ใช้ Baud Rate 9600
    ) uut (
        .clk          (clk),
        .rst          (rst),
        .s_axis_valid (s_axis_valid),
        .s_axis_data  (s_axis_data),
        .tx           (tx),
        .s_axis_ready (s_axis_ready)
    );

    // 3. สร้างสัญญาณนาฬิกา (Clock Generation: 1 MHz -> Period = 1000 ns, ครึ่งรอบ = 500 ns)
    always #500 clk = ~clk;

    // 4. Test Stimulus (กระบวนการจำลองการส่งข้อมูล)
    initial begin
        // เริ่มต้นค่าสัญญาณทั้งหมด
        clk          = 0;
        rst          = 1;
        s_axis_valid = 0;
        s_axis_data  = 8'h00;

        // ปล่อยรีเซ็ตหลังจากผ่านไป 2000 ns
        #2000;
        rst = 0;
        #2000;

        // จำลองส่งข้อมูลตัวที่ 1: ส่งตัวอักษร 'A' (รหัส ASCII = 8'h41 หรือ binary 01000001)
        wait (s_axis_ready); // รอจนกว่าโมดูลจะพร้อมรับข้อมูล
        @(posedge clk);
        s_axis_data  = 8'h41; 
        s_axis_valid = 1;     // ยกธงบอกว่ามีข้อมูลพร้อมส่ง
        @(posedge clk);
        s_axis_valid = 0;     // ปล่อยให้ valid เป็น 0 หลังจากส่งสัญญาณแล้ว

        // รอจนกระทั่งส่งข้อมูลชุดนี้เสร็จสิ้น (สังเกตจาก s_axis_ready กลับมาเป็น 1 อีกครั้ง)
        @(posedge s_axis_ready);
        #5000;

        // จำลองส่งข้อมูลตัวที่ 2: ส่งตัวอักษร 'K' (รหัส ASCII = 8'h4B)
        wait (s_axis_ready);
        @(posedge clk);
        s_axis_data  = 8'h4B;
        s_axis_valid = 1;
        @(posedge clk);
        s_axis_valid = 0;

        // รอให้ส่งเสร็จแล้วจบการจำลอง
        @(posedge s_axis_ready);
        #10000;
        $finish;
    end

endmodule
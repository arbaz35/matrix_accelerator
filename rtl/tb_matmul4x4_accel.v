// =============================================================
// tb_matmul4x4_accel.v
// Self-checking testbench for matmul4x4_accel (Config F)
//
// NOTE: `#` delays and `initial` blocks are used freely here.
// This is a SIMULATION-ONLY testbench, not synthesizable RTL.
//
// Reference model uses the EXACT same arithmetic as the RTL:
//   4-bit unsigned x 4-bit unsigned products, summed over 4 terms
//   (max 900), then saturated to 8 bits if the sum exceeds 255.
//
// NOTE ON SATURATION FREQUENCY: with 4-bit operands (0..15) and
// an 8-bit output (max 255), saturation is common, not rare --
// mean 4-term dot product for uniform random operands is well
// above 255. Random tests below WILL frequently hit 0xFF on both
// DUT and reference; that is correct, expected behavior for this
// configuration, not a test weakness.
// =============================================================
`timescale 1ns/1ps

module tb_matmul4x4_accel;

    reg        clk;
    reg        rst_n;
    reg        start;
    reg        wr_en;
    reg [3:0]  wr_data;
    wire       ready;
    wire       done;
    reg        rd_en;
    wire [7:0] c_data;

    integer error_count;
    integer test_count;

    // -----------------------------------------------------------
    // DUT
    // -----------------------------------------------------------
    matmul4x4_accel dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (start),
        .wr_en   (wr_en),
        .wr_data (wr_data),
        .ready   (ready),
        .done    (done),
        .rd_en   (rd_en),
        .c_data  (c_data)
    );

    // -----------------------------------------------------------
    // Clock: 10 ns period (100 MHz), matches planned SDC target
    // -----------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk <= ~clk;

    // -----------------------------------------------------------
    // Test matrices (module-level, 0..3 x 0..3, 4-bit elements)
    // -----------------------------------------------------------
    reg [3:0] A [0:3][0:3];
    reg [3:0] B [0:3][0:3];
    integer   C_exp [0:3][0:3];   // reference (before saturation, up to 900)
    reg [7:0] C_sat [0:3][0:3];   // reference (after saturation, width-matched to c_data)
    reg [7:0] C_got [0:3][0:3];   // captured from DUT

    integer r, c, kk;

    // -----------------------------------------------------------
    // Reference model: exact same arithmetic as the RTL
    // -----------------------------------------------------------
    task compute_reference;
        integer sum;
        begin
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    sum = 0;
                    for (kk = 0; kk < 4; kk = kk + 1) begin
                        sum = sum + (A[r][kk] * B[kk][c]); // 4b*4b, max 225
                    end
                    C_exp[r][c] = sum;
                    if (sum > 255)
                        C_sat[r][c] = 8'hFF; // saturation
                    else
                        C_sat[r][c] = sum[7:0];
                end
            end
        end
    endtask

    // -----------------------------------------------------------
    // Drive one full operation: (re-)enter LOAD if needed, load
    // A then B (32 pulses, row-major), wait for ready, start,
    // wait for done, read back 16 elements, compare.
    // -----------------------------------------------------------
    task run_test;
        input string test_name;
        integer timeout;
        begin : run_test_body
            test_count = test_count + 1;

            // If DUT is currently DONE from a previous test, pulse
            // start to return it to the LOAD phase first.
            if (done) begin
                @(posedge clk);
                start = 1'b1;
                @(posedge clk);
                start = 1'b0;
                @(posedge clk);
            end

            // Load A then B, row-major, 32 total wr_en pulses
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    @(posedge clk);
                    wr_en   = 1'b1;
                    wr_data = A[r][c];
                end
            end
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    @(posedge clk);
                    wr_en   = 1'b1;
                    wr_data = B[r][c];
                end
            end
            @(posedge clk);
            wr_en = 1'b0;

            // Wait for ready (bounded)
            timeout = 0;
            while (!ready && timeout < 50) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!ready) begin
                $display("[%0t] FAIL (%s): ready never asserted after load", $time, test_name);
                error_count = error_count + 1;
                disable run_test_body;
            end

            // Pulse start
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            // Wait for done (bounded; expected ~96 cycles, generous margin)
            timeout = 0;
            while (!done && timeout < 500) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (!done) begin
                $display("[%0t] FAIL (%s): done never asserted (timeout)", $time, test_name);
                error_count = error_count + 1;
                disable run_test_body;
            end

            // Read back 16 elements, row-major
            @(posedge clk); // let read_addr settle at 0
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    C_got[r][c] = c_data;
                    @(posedge clk);
                    rd_en = 1'b1;
                    @(posedge clk);
                    rd_en = 1'b0;
                end
            end

            // Compute reference and compare
            compute_reference;
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    if (C_got[r][c] !== C_sat[r][c]) begin
                        $display("[%0t] FAIL (%s): C[%0d][%0d] = %0d, expected %0d (raw sum=%0d)",
                                  $time, test_name, r, c, C_got[r][c], C_sat[r][c], C_exp[r][c]);
                        error_count = error_count + 1;
                    end
                end
            end
            $display("[%0t] test '%s' complete (%0d checks so far, %0d errors so far)",
                       $time, test_name, test_count, error_count);
        end
    endtask

    // -----------------------------------------------------------
    // Random test helper -- values in [0,15] (4-bit range)
    // -----------------------------------------------------------
    task fill_random;
        /* verilator lint_off UNUSEDSIGNAL */
        reg [31:0] rand_val; // only rand_val[3:0] is used intentionally
        /* verilator lint_on UNUSEDSIGNAL */
        begin
            for (r = 0; r < 4; r = r + 1) begin
                for (c = 0; c < 4; c = c + 1) begin
                    rand_val = $random();
                    A[r][c] = rand_val[3:0];
                    rand_val = $random();
                    B[r][c] = rand_val[3:0];
                end
            end
        end
    endtask

    // -----------------------------------------------------------
    // Main stimulus
    // -----------------------------------------------------------
    initial begin
        error_count = 0;
        test_count  = 0;
        rst_n   = 1'b0;
        start   = 1'b0;
        wr_en   = 1'b0;
        wr_data = 4'd0;
        rd_en   = 1'b0;

        // ---- Reset test ----
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        if (ready !== 1'b0 || done !== 1'b0) begin
            $display("[%0t] FAIL (reset): ready=%0b done=%0b, expected both 0", $time, ready, done);
            error_count = error_count + 1;
        end else begin
            $display("[%0t] PASS (reset): ready/done correctly low after reset", $time);
        end

        // ---- All-zero matrices ----
        for (r = 0; r < 4; r = r + 1)
            for (c = 0; c < 4; c = c + 1) begin
                A[r][c] = 4'd0;
                B[r][c] = 4'd0;
            end
        run_test("zero_matrices");

        // ---- Identity: A = I, B = simple known values (0..15 range) ----
        for (r = 0; r < 4; r = r + 1)
            for (c = 0; c < 4; c = c + 1)
                A[r][c] = (r == c) ? 4'd1 : 4'd0;
        B[0][0]=4'd1; B[0][1]=4'd2;  B[0][2]=4'd3;  B[0][3]=4'd4;
        B[1][0]=4'd5; B[1][1]=4'd6;  B[1][2]=4'd7;  B[1][3]=4'd8;
        B[2][0]=4'd9; B[2][1]=4'd10; B[2][2]=4'd11; B[2][3]=4'd12;
        B[3][0]=4'd13;B[3][1]=4'd14; B[3][2]=4'd15; B[3][3]=4'd0;
        run_test("identity_A");

        // ---- Simple hand-calculable matrices ----
        // A = [[1,2,3,4],[5,6,7,8],[9,10,11,12],[13,14,15,0]]
        // B = identity -> C should equal A exactly (easy hand check,
        // and stays within the 8-bit output range without saturating)
        A[0][0]=4'd1; A[0][1]=4'd2;  A[0][2]=4'd3;  A[0][3]=4'd4;
        A[1][0]=4'd5; A[1][1]=4'd6;  A[1][2]=4'd7;  A[1][3]=4'd8;
        A[2][0]=4'd9; A[2][1]=4'd10; A[2][2]=4'd11; A[2][3]=4'd12;
        A[3][0]=4'd13;A[3][1]=4'd14; A[3][2]=4'd15; A[3][3]=4'd0;
        for (r = 0; r < 4; r = r + 1)
            for (c = 0; c < 4; c = c + 1)
                B[r][c] = (r == c) ? 4'd1 : 4'd0;
        run_test("hand_calc_A_times_I");

        // ---- Maximum-value test (forces saturation on every element) ----
        // 15*15*4 = 900 per element, well above the 255 output ceiling
        for (r = 0; r < 4; r = r + 1)
            for (c = 0; c < 4; c = c + 1) begin
                A[r][c] = 4'd15;
                B[r][c] = 4'd15;
            end
        run_test("max_value_saturation");

        // ---- Random tests (0..15 range; many will legitimately saturate) ----
        fill_random; run_test("random_1");
        fill_random; run_test("random_2");
        fill_random; run_test("random_3");
        fill_random; run_test("random_4");
        fill_random; run_test("random_5");

        // ---- Summary ----
        if (error_count == 0) begin
            $display("\n=====================================");
            $display("  ALL %0d TESTS PASSED", test_count);
            $display("=====================================\n");
        end else begin
            $display("\n=====================================");
            $display("  %0d ERROR(S) ACROSS %0d TESTS -- FAIL", error_count, test_count);
            $display("=====================================\n");
        end

        $finish;
    end

    // Safety timeout in case something hangs completely
    initial begin
        #200000;
        $display("[%0t] GLOBAL TIMEOUT - simulation did not finish in time", $time);
        $finish;
    end

endmodule

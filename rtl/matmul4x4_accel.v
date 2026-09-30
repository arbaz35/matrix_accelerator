`timescale 1ns/1ps


// =============================================================
// matmul4x4_accel.v
// 4x4 x 4x4 unsigned matrix multiplier accelerator
// Config F: single shared 4x4 multiplier, sequential MAC reuse
// Target: SKY130HD (sky130_fd_sc_hd), Yosys synthesizable
//
// REVISION HISTORY
//   Config C (8-bit operands) synthesized to 1,393 cells /
//   23,473.7632 um^2 against sky130_fd_sc_hd -- REJECTED, over
//   both the 900-1,000 cell and 10,000-12,000 um^2 budget.
//   Root cause: 512 flip-flops from A(128b)+B(128b)+C(256b)
//   storage, ~16,175.5 um^2 of that alone.
//
//   Config F narrows operands from 8-bit to 4-bit to roughly
//   halve total storage (256 bits vs 512 bits: A=64b, B=64b,
//   C=128b) and shrink the multiplier from 8x8 to 4x4. This is
//   a real architectural change, not a guess -- the resulting
//   cell count/area must still be measured by actual synthesis.
//   NO AREA/CELL NUMBER IS CLAIMED HERE.
// =============================================================
//
// FUNCTIONAL SUMMARY
//   Computes C = A * B for two 4x4 matrices of 4-bit unsigned
//   operands, using ONE shared 4x4 unsigned multiplier and ONE
//   shared 10-bit accumulator, reused sequentially across all
//   16 output elements and all 4 k-terms of each dot product.
//
// ARITHMETIC (must match testbench reference model exactly)
//   - Operand width   : 4-bit unsigned  (0..15)
//   - Product width    : 8-bit unsigned (max 15*15 = 225)
//   - Accumulator width : 10-bit unsigned
//         max 4-term sum = 4 * 225 = 900
//         900 < 1024 (2^10) -> accumulator itself NEVER overflows
//   - Output width      : 8-bit, SATURATING conversion:
//         if acc > 8'hFF (255) -> C = 8'hFF
//         else                  -> C = acc[7:0]
//     IMPORTANT: unlike Config C, saturation now triggers for a
//     LARGE fraction of realistic inputs, not just extreme ones --
//     any dot-product sum above 255 saturates, and for uniformly
//     random 4-bit operands the mean 4-term sum is already in the
//     ~200-300 range. This is inherent to keeping C storage at
//     8 bits/element (128 bits total for the 4x4 output) as
//     specified. Flagging this because it changes how much of the
//     random-test coverage will legitimately land on the saturated
//     branch -- this is expected behavior, not a bug, but it means
//     "several random matrices passing" will very often mean
//     "several random matrices correctly saturating to 0xFF".
//
// INTERFACE / PROTOCOL -- UNCHANGED from Config C
//   clk      : system clock
//   rst_n    : synchronous, active-low reset
//   start    : pulse to begin an operation
//                - while `ready`=1 -> begins computation
//                - while `done`=1  -> discards old result, returns
//                  to LOAD phase to accept a fresh A/B pair
//   wr_en    : pulse with wr_data to load one element. ONE unified
//              load port for BOTH matrix A and matrix B.
//              wr_data is now 4 bits wide (was 8 bits in Config C).
//   wr_data  : 4-bit element value, valid when wr_en asserted
//   ready    : high once all 32 elements (A then B) are loaded
//   done     : high once C is fully computed and stable
//   rd_en    : pulse to advance the C readout pointer by one
//   c_data   : 8-bit combinational readout of C[read_addr]
//              (was 16 bits in Config C). Meaningful only while
//              `done` is high.
//
// LOADING ORDER (unified load port, 32 pulses total) -- unchanged
//   pulses  0..15 -> matrix A, row-major
//   pulses 16..31 -> matrix B, row-major
//   `ready` asserts the cycle after the 32nd pulse.
//
// READOUT ORDER -- unchanged
//   C read out row-major, 16 rd_en pulses. Read pointer auto-resets
//   to 0 whenever DONE state is entered.
//
// LATENCY -- unchanged FSM structure
//   Per output element : 1 (init) + 4 (k=0..3 MAC) + 1 (writeback)
//                         = 6 cycles
//   16 output elements  : 96 cycles from `start` to `done` asserting
//
// STORAGE (for reference against the Config C failure analysis)
//   A_mem : 16 x 4-bit = 64 bits   (was 128 bits)
//   B_mem : 16 x 4-bit = 64 bits   (was 128 bits)
//   C_mem : 16 x 8-bit = 128 bits  (was 256 bits)
//   Total : 256 bits              (was 512 bits)
//
// DELIBERATE SIMPLIFICATIONS (unchanged rationale from Config C)
//   - A_mem / B_mem / C_mem are NOT reset on rst_n. Only control
//     state, counters, the accumulator, and status outputs are
//     reset. Safe because compute logic never reads an element
//     before the LOAD phase has written it.
//   - A_mem/B_mem/C_mem are flat 16-entry register files addressed
//     by simple 4-bit concatenation of 2-bit row/col indices (no
//     multiplier needed for addressing). Expect these to map to
//     individual DFFs via Yosys's generic memory_map pass, not a
//     SKY130 SRAM macro.
//
// NOT ADDRESSED HERE (explicitly out of scope per current direction)
//   - The previously discussed "two clock" requirement is NOT
//     implemented in this revision. Single clock domain only.
//     No CDC logic added. This is a deliberate scope decision, to
//     be revisited only after the area/cell budget is met.
// =============================================================

module matmul4x4_accel (
    input  wire       clk,
    input  wire       rst_n,      // synchronous, active-low

    input  wire       start,
    input  wire       wr_en,
    input  wire [3:0] wr_data,

    output reg        ready,
    output reg        done,
    input  wire       rd_en,
    output wire [7:0] c_data
);

    // -----------------------------------------------------------
    // FSM state encoding (explicit, plain localparams - no enum)
    // -----------------------------------------------------------
    localparam [2:0] ST_LOAD  = 3'd0;
    localparam [2:0] ST_READY = 3'd1;
    localparam [2:0] ST_INIT  = 3'd2;
    localparam [2:0] ST_MAC   = 3'd3;
    localparam [2:0] ST_WB    = 3'd4;
    localparam [2:0] ST_DONE  = 3'd5;

    reg [2:0] state;

    // -----------------------------------------------------------
    // Storage: flattened 4x4 register files
    //   index = {row[1:0], col[1:0]}  (row-major, no multiply)
    // -----------------------------------------------------------
    reg [3:0] A_mem [0:15];
    reg [3:0] B_mem [0:15];
    reg [7:0] C_mem [0:15];

    // -----------------------------------------------------------
    // Loading counter (0..31): unified A-then-B load pointer
    // -----------------------------------------------------------
    reg [4:0] word_cnt;
    wire       load_sel_b = word_cnt[4];      // 0 = A, 1 = B
    wire [3:0] load_index = word_cnt[3:0];    // index within matrix

    // -----------------------------------------------------------
    // Compute indices
    // -----------------------------------------------------------
    reg [1:0] i, j, k;

    wire [3:0] a_idx = {i, k};   // A[i][k]
    wire [3:0] b_idx = {k, j};   // B[k][j]
    wire [3:0] c_idx = {i, j};   // C[i][j]

    // -----------------------------------------------------------
    // Datapath: single shared multiplier + accumulator
    // -----------------------------------------------------------
    wire [7:0] mult_result = A_mem[a_idx] * B_mem[b_idx];

    reg [9:0] acc;

    wire       acc_overflow = |acc[9:8];
    wire [7:0] c_sat        = acc_overflow ? 8'hFF : acc[7:0];

    // -----------------------------------------------------------
    // Readout pointer
    // -----------------------------------------------------------
    reg [3:0] read_addr;

    assign c_data = done ? C_mem[read_addr] : 8'h00;

    // -----------------------------------------------------------
    // Main synchronous FSM + datapath (single clocked process,
    // no combinational always blocks -> no latch inference risk)
    // -----------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= ST_LOAD;
            word_cnt  <= 5'd0;
            ready     <= 1'b0;
            done      <= 1'b0;
            i         <= 2'd0;
            j         <= 2'd0;
            k         <= 2'd0;
            acc       <= 10'd0;
            read_addr <= 4'd0;
        end else begin
            case (state)

                // ---------------------------------------------
                ST_LOAD: begin
                    ready <= 1'b0;
                    if (wr_en) begin
                        if (load_sel_b)
                            B_mem[load_index] <= wr_data;
                        else
                            A_mem[load_index] <= wr_data;

                        if (word_cnt == 5'd31) begin
                            word_cnt <= 5'd0;
                            state    <= ST_READY;
                        end else begin
                            word_cnt <= word_cnt + 5'd1;
                        end
                    end
                end

                // ---------------------------------------------
                ST_READY: begin
                    ready <= 1'b1;
                    if (start) begin
                        ready <= 1'b0;
                        i     <= 2'd0;
                        j     <= 2'd0;
                        state <= ST_INIT;
                    end
                end

                // ---------------------------------------------
                ST_INIT: begin
                    acc   <= 10'd0;
                    k     <= 2'd0;
                    state <= ST_MAC;
                end

                // ---------------------------------------------
                ST_MAC: begin
                    acc <= acc + {2'd0, mult_result};
                    if (k == 2'd3) begin
                        state <= ST_WB;
                    end else begin
                        k <= k + 2'd1;
                    end
                end

                // ---------------------------------------------
                ST_WB: begin
                    C_mem[c_idx] <= c_sat;
                    if (j == 2'd3) begin
                        if (i == 2'd3) begin
                            done      <= 1'b1;
                            read_addr <= 4'd0;
                            state     <= ST_DONE;
                        end else begin
                            i     <= i + 2'd1;
                            j     <= 2'd0;
                            state <= ST_INIT;
                        end
                    end else begin
                        j     <= j + 2'd1;
                        state <= ST_INIT;
                    end
                end

                // ---------------------------------------------
                ST_DONE: begin
                    if (rd_en && read_addr != 4'd15)
                        read_addr <= read_addr + 4'd1;

                    if (start) begin
                        done     <= 1'b0;
                        word_cnt <= 5'd0;
                        state    <= ST_LOAD;
                    end
                end

                // ---------------------------------------------
                default: begin
                    state <= ST_LOAD;
                end

            endcase
        end
    end

endmodule

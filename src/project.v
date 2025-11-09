/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

//======================================================
// Parameterized Mod-N Counter (Async Active-Low Reset)
// Author: ChatGPT (GPT-5)
// Description: Counts from 0 to N-1, then wraps to 0.
//======================================================
module modN_counter #(
    parameter N = 10,               // modulus (max count)
    parameter WIDTH = $clog2(N)     // bit width for count
)(
    input  wire clk,                // clock input
    input  wire reset_n,            // asynchronous active-low reset
    input  wire enable,             // count enable
    output reg  [WIDTH-1:0] count,  // current count
    output wire tc                  // terminal count (high for 1 clk at N-1)
);

    // Terminal count signal
    assign tc = (count == N-1);

    // Asynchronous, active-low reset
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            count <= 0;
        else if (enable) begin
            if (tc)
                count <= 0;
            else
                count <= count + 1;
        end
    end
endmodule

//======================================================
// Exact Clock Divider from 32.768 kHz
// Author: ChatGPT (GPT-5)
// Description:
//   Generates precise 100 Hz, 1 Hz, and 1/60 Hz outputs
//   from a 32.768 kHz reference clock.
//
// Division chain:
//   32_768 Hz --> 100 Hz   (÷ 327)
//   32_768 Hz --> 1 Hz     (÷ 32_768)
//   1 Hz      --> 1/60 Hz  (÷ 60)
//======================================================
module clock_divider_32768Hz_exact (
    input  wire clk_32768Hz,   // 32.768 kHz input clock
    input  wire reset_n,       // asynchronous active-low reset
    output wire clk_100Hz,     // 100 Hz output
    output wire clk_1Hz,       // 1 Hz output
    output wire clk_1div60Hz   // 1/60 Hz output (1 pulse per minute)
);

    //--------------------------------------------------
    // 1) 32.768 kHz → 100 Hz (divide by 327)
    //     32768 / 327 = 100.21 Hz (0.21% error)
    // If you need *exactly* 100.000 Hz, use a PLL instead.
    //--------------------------------------------------
    wire [8:0] count_100;
    wire tc_100;
    modN_counter #(
        .N(327)
    ) div_100 (
        .clk(clk_32768Hz),
        .reset_n(reset_n),
        .enable(1'b1),
        .count(count_100),
        .tc(tc_100)
    );
    assign clk_100Hz = tc_100;

    //--------------------------------------------------
    // 2) 32.768 kHz → 1 Hz (exact divide by 32768)
    //--------------------------------------------------
    wire [15:0] count_1;
    wire tc_1;
    modN_counter #(
        .N(32768)
    ) div_1 (
        .clk(clk_32768Hz),
        .reset_n(reset_n),
        .enable(1'b1),
        .count(count_1),
        .tc(tc_1)
    );
    assign clk_1Hz = tc_1;

    //--------------------------------------------------
    // 3) 1 Hz → 1/60 Hz (exact divide by 60)
    //--------------------------------------------------
    wire [5:0] count_1div60;
    wire tc_1div60;
    modN_counter #(
        .N(60)
    ) div_1div60 (
        .clk(clk_1Hz),
        .reset_n(reset_n),
        .enable(1'b1),
        .count(count_1div60),
        .tc(tc_1div60)
    );
    assign clk_1div60Hz = tc_1div60;

endmodule

//======================================================
// 24-Hour Time Counter (HH:MM in BCD)
// Author: ChatGPT (GPT-5)
// Description:
//   Uses a 1-minute input pulse to increment time in
//   24-hour format. Outputs are four BCD digits:
//     H_tens, H_ones, M_tens, M_ones
//   e.g. 14:29 → 0001 0100 0010 1001
//======================================================
module time_24hr (
    input  wire clk_1min,   // 1-minute clock pulse (one rising edge per minute)
    input  wire reset_n,    // asynchronous active-low reset
    output wire [3:0] H_tens, // Hours tens digit (0–2)
    output wire [3:0] H_ones, // Hours ones digit (0–9 or 0–3 if 20–23)
    output wire [3:0] M_tens, // Minutes tens digit (0–5)
    output wire [3:0] M_ones  // Minutes ones digit (0–9)
);

    //--------------------------------------------------
    // Minute Ones (0–9)
    //--------------------------------------------------
    wire [3:0] count_m_ones;
    wire tc_m_ones;
    modN_counter #(
        .N(10)
    ) min_ones (
        .clk(clk_1min),
        .reset_n(reset_n),
        .enable(1'b1),
        .count(count_m_ones),
        .tc(tc_m_ones)
    );
    assign M_ones = count_m_ones;

    //--------------------------------------------------
    // Minute Tens (0–5)
    //--------------------------------------------------
    wire [2:0] count_m_tens;
    wire tc_m_tens;
    modN_counter #(
        .N(6)
    ) min_tens (
        .clk(clk_1min),
        .reset_n(reset_n),
        .enable(tc_m_ones), // increment every 10 minutes
        .count(count_m_tens),
        .tc(tc_m_tens)
    );
    assign M_tens = {1'b0, count_m_tens}; // pad to 4 bits

    //--------------------------------------------------
    // Hour Ones (0–9 normally, but 0–3 when hour tens = 2)
    // We'll gate rollover with hour tens logic.
    //--------------------------------------------------
    reg [3:0] count_h_ones;
    reg [1:0] count_h_tens;

    wire hour_increment = tc_m_ones && tc_m_tens; // every 60 minutes

    always @(posedge clk_1min or negedge reset_n) begin
        if (!reset_n) begin
            count_h_ones <= 0;
            count_h_tens <= 0;
        end else if (hour_increment) begin
            // increment hours
            if (count_h_tens == 2 && count_h_ones == 3) begin
                // roll over at 23 → 00
                count_h_ones <= 0;
                count_h_tens <= 0;
            end else if (count_h_ones == 9) begin
                // carry to hour tens
                count_h_ones <= 0;
                count_h_tens <= count_h_tens + 1;
            end else begin
                count_h_ones <= count_h_ones + 1;
            end
        end
    end

    assign H_ones = count_h_ones;
    assign H_tens = {2'b00, count_h_tens}; // pad to 4 bits

endmodule

//======================================================
// Switch Debouncer using Shift Register
// Author: ChatGPT (GPT-5)
// Description:
//   Samples a noisy mechanical switch each clock edge.
//   Output is the AND of all shift register bits —
//   goes high only when all samples are high.
//
//   Parameterizable number of samples for filtering.
//======================================================
module switch_debouncer #(
    parameter integer N = 8  // number of samples in shift register
)(
    input  wire clk,        // sampling clock
    input  wire reset_n,    // asynchronous active-low reset
    input  wire sw_in,      // raw (bouncy) switch input
    output wire sw_out      // debounced output
);

    // Shift register for sampling
    reg [N-1:0] shift_reg;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            shift_reg <= {N{1'b0}};
        else
            shift_reg <= {shift_reg[N-2:0], sw_in};
    end

    // Output is AND of all shift register bits
    assign sw_out = &shift_reg;

endmodule



module tt_um_digital_alarm_clock (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
  assign uo_out  = ui_in - uio_in;  // Example: ou_out is the sum of ui_in and uio_in
  assign uio_out = 0;
  assign uio_oe  = 8'hFF;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, clk, rst_n, 1'b0};

endmodule

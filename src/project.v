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
    input  wire clk,
    input  wire inc_min,   // pulse to increment minutes    
    input  wire inc_hour,    // pulse to increment hours manually
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
        .clk(inc_min),
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
    input  wire enable,
    input  wire sw_in,      // raw (bouncy) switch input
    output wire sw_out      // debounced output
);

    // Shift register for sampling
    reg [N-1:0] shift_reg;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            shift_reg <= {N{1'b0}};
        else
            if (enable) begin
                shift_reg <= {shift_reg[N-2:0], sw_in};
            end
    end

    // Output is AND of all shift register bits
    assign sw_out = &shift_reg;

endmodule

//======================================================
// 4-Digit 7-Segment Display Driver (Dual Input + PWM Dim)
// Author: ChatGPT (GPT-5)
// Description:
//   - Displays one of two HH:MM inputs, selected by `sel`.
//   - Multiplexes four digits on each clock edge.
//   - Adds PWM-based brightness control using the upper
//     bits of an 8-bit digit selector counter.
//
//   Common-anode display (active-low segments/anodes).
//======================================================
module sevenseg_driver_dual_pwm (
    input  wire        clk,          // system clock
    input  wire        reset_n,      // async active-low reset
    input  wire        sel,          // 0 = time A, 1 = time B
    input  wire        brightness_up,// increments brightness preset
    // time input set A
    input  wire [3:0]  H_tens_A,
    input  wire [3:0]  H_ones_A,
    input  wire [3:0]  M_tens_A,
    input  wire [3:0]  M_ones_A,
    // time input set B
    input  wire [3:0]  H_tens_B,
    input  wire [3:0]  H_ones_B,
    input  wire [3:0]  M_tens_B,
    input  wire [3:0]  M_ones_B,
    // display outputs
    output reg  [6:0]  seg,          // segments a–g (active-high)
    output reg  [3:0]  an            // anodes (active-high)
);

    //--------------------------------------------------
    // 1) 8-bit digit selector
    //     [1:0] → select which digit (0–3)
    //     [7:2] → PWM brightness phase
    //--------------------------------------------------
    reg [7:0] digit_sel;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            digit_sel <= 8'd0;
        else
            digit_sel <= digit_sel + 1'b1;
    end

    //--------------------------------------------------
    // 2) Brightness presets (8 levels)
    //     Compare upper bits [7:2] against threshold
    //--------------------------------------------------
    reg [2:0] brightness_level; // 0–7
    reg [5:0] brightness_thresh;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            brightness_level <= 3'd4; // default mid brightness
        else if (brightness_up)
            brightness_level <= brightness_level + 1'b1;
    end

    // Map brightness preset → threshold (out of 64)
    always @(*) begin
        case (brightness_level)
            3'd0: brightness_thresh = 6'd0;   // ~6% duty
            3'd1: brightness_thresh = 6'd1;   // ~12%
            3'd2: brightness_thresh = 6'd4;  // ~25%
            3'd3: brightness_thresh = 6'd10;  // ~37%
            3'd4: brightness_thresh = 6'd19;  // ~50%
            3'd5: brightness_thresh = 6'd31;  // ~62%
            3'd6: brightness_thresh = 6'd46;  // ~81%
            3'd7: brightness_thresh = 6'd64;  // ~98%
            default: brightness_thresh = 6'd19;
        endcase
    end

    //--------------------------------------------------
    // 3) Select active time input set
    //--------------------------------------------------
    wire [3:0] H_tens = (sel) ? H_tens_B : H_tens_A;
    wire [3:0] H_ones = (sel) ? H_ones_B : H_ones_A;
    wire [3:0] M_tens = (sel) ? M_tens_B : M_tens_A;
    wire [3:0] M_ones = (sel) ? M_ones_B : M_ones_A;

    //--------------------------------------------------
    // 4) Select which BCD digit to display
    //--------------------------------------------------
    reg [3:0] current_bcd;
    always @(*) begin
        case (digit_sel[1:0])
            2'd0: current_bcd = M_ones;
            2'd1: current_bcd = M_tens;
            2'd2: current_bcd = H_ones;
            2'd3: current_bcd = H_tens;
            default: current_bcd = 4'd0;
        endcase
    end

    //--------------------------------------------------
    // 5) Decode current BCD digit to 7 segments
    //--------------------------------------------------
    wire [6:0] seg_raw;
    bcd_to_7seg seg_decoder (
        .bcd(current_bcd),
        .seg(seg_raw)
    );

    //--------------------------------------------------
    // 6) Generate segment and anode outputs with PWM
    //--------------------------------------------------
    wire pwm_enable = (digit_sel[7:2] < brightness_thresh);

    always @(*) begin
        // Base anode select pattern (active-high)
        case (digit_sel[1:0])
            2'd0: an = 4'b0001;
            2'd1: an = 4'b0010;
            2'd2: an = 4'b0100;
            2'd3: an = 4'b1000;
            default: an = 4'b0000;
        endcase

        // Apply PWM dimming (blank display when off)
        if (!pwm_enable)
            an = 4'b0000;
    end

endmodule

//======================================================
// Alarm FSM
// Author: ChatGPT (GPT-5)
// Description:
//   3-state FSM controlling alarm behavior
//   States: READY → ALARMING → STANDBY
//======================================================
module alarm_fsm (
    input  wire        clk,         // system clock
    input  wire        reset_n,     // asynchronous active-low reset
    input  wire        alarm_en,    // enable alarm comparison
    input  wire [3:0]  H_tens_time, // current time HH:MM
    input  wire [3:0]  H_ones_time,
    input  wire [3:0]  M_tens_time,
    input  wire [3:0]  M_ones_time,
    input  wire [3:0]  H_tens_alarm, // alarm time HH:MM
    input  wire [3:0]  H_ones_alarm,
    input  wire [3:0]  M_tens_alarm,
    input  wire [3:0]  M_ones_alarm,
    input  wire [4:0]  btn,         // 5 buttons
    output reg         alarm_sig    // true only in ALARMING state
);

    //--------------------------------------------------
    // 1) State encoding
    //--------------------------------------------------
    typedef enum reg [1:0] {
        READY    = 2'd0,
        ALARMING = 2'd1,
        STANDBY  = 2'd2
    } state_t;

    state_t state, next_state;

    //--------------------------------------------------
    // 2) Time equality detection
    //--------------------------------------------------
    wire times_equal = (H_tens_time  == H_tens_alarm) &&
                       (H_ones_time  == H_ones_alarm) &&
                       (M_tens_time  == M_tens_alarm) &&
                       (M_ones_time  == M_ones_alarm);

    wire any_button = |btn;

    //--------------------------------------------------
    // 3) State transition logic
    //--------------------------------------------------
    always @(*) begin
        next_state = state; // default hold

        case (state)
            READY: begin
                if (alarm_en && times_equal)
                    next_state = ALARMING;
            end

            ALARMING: begin
                if (any_button)
                    next_state = STANDBY;
                else if (!times_equal)
                    next_state = READY;
            end

            STANDBY: begin
                if (!times_equal)
                    next_state = READY;
            end

            default: next_state = READY;
        endcase
    end

    //--------------------------------------------------
    // 4) State register (async reset)
    //--------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            state <= READY;
        else
            state <= next_state;
    end

    //--------------------------------------------------
    // 5) Output logic
    //--------------------------------------------------
    always @(*) begin
        alarm_sig = (state == ALARMING);
    end

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

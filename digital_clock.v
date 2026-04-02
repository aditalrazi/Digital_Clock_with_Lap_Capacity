`timescale 1ns/1ps
`default_nettype none

// SW0: Stopwatch | SW1: Set Time | SW2: 12/24h | SW3: Alarm Set | SW4: Alarm Kill

module digital_clock (
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,
    input  wire [15:0] SW,
    input  wire        BTU, BTL, BTC, BTD, BTR,
    output wire [7:0]  AN,
    output wire [6:0]  SEG,
    output wire [15:0] LED
);

    // Async assert, sync release reset
    wire rst_async = ~CPU_RESETN;
    wire rst;
    reset_sync rs0 (.clk(CLK100MHZ), .rst_async(rst_async), .rst_sync(rst));

    // Sync slide switches to clk
    reg [15:0] sw_ff0, sw_ff1;
    always @(posedge CLK100MHZ) begin
        if (rst) begin sw_ff0 <= 16'h0000; sw_ff1 <= 16'h0000; end
        else     begin sw_ff0 <= SW;        sw_ff1 <= sw_ff0;   end
    end
    wire [15:0] SW_S = sw_ff1;

    wire alarm_kill = SW_S[4];

    // Tick pulses
    wire t1, t100, t1k;
    clk_divider cd (.clk(CLK100MHZ), .rst(rst), .t1(t1), .t100(t100), .t1k(t1k));

    // Debounced one-shot button pulses (1kHz sample)
    wire b_up, b_left, b_center, b_down, b_right;
    debounce_onepulse db_u (.clk(CLK100MHZ), .rst(rst), .tick_1khz(t1k), .btn_in(BTU), .pulse(b_up));
    debounce_onepulse db_l (.clk(CLK100MHZ), .rst(rst), .tick_1khz(t1k), .btn_in(BTL), .pulse(b_left));
    debounce_onepulse db_c (.clk(CLK100MHZ), .rst(rst), .tick_1khz(t1k), .btn_in(BTC), .pulse(b_center));
    debounce_onepulse db_d (.clk(CLK100MHZ), .rst(rst), .tick_1khz(t1k), .btn_in(BTD), .pulse(b_down));
    debounce_onepulse db_r (.clk(CLK100MHZ), .rst(rst), .tick_1khz(t1k), .btn_in(BTR), .pulse(b_right));

    // Mode priority: Time Set > Alarm Set > Stopwatch > Normal
    wire time_set_mode  = SW_S[1];
    wire alarm_set_mode = SW_S[3] && !SW_S[1];
    wire stopwatch_mode = SW_S[0] && !time_set_mode && !alarm_set_mode;

    // Time logic
    wire [3:0] h1, h0, m1, m0, s1, s0;
    wire [4:0] raw_h;
    wire [5:0] raw_m, raw_s;
    wire pm_ind;

    time_logic tl (
        .clk        (CLK100MHZ),
        .rst        (rst),
        .tick_1hz   (t1),
        .set_mode   (time_set_mode),
        .mode_12_24 (SW_S[2]),
        .btn_h      (time_set_mode ? b_up    : 1'b0),
        .btn_m      (time_set_mode ? b_down  : 1'b0),
        .btn_s      (time_set_mode ? b_right : 1'b0),
        .sw_zones   (SW_S[15:11]),
        .h1(h1), .h0(h0), .m1(m1), .m0(m0), .s1(s1), .s0(s0),
        .is_pm(pm_ind),
        .raw_h(raw_h), .raw_m(raw_m), .raw_s(raw_s)
    );

    // Alarm controller - inhibited during time set, killed by SW4
    wire [4:0] alarm_h_stored;
    wire [5:0] alarm_m_stored;
    wire alarm_ringing;

    alarm_controller ac (
        .clk       (CLK100MHZ),
        .rst       (rst),
        .tick_1hz  (t1),
        .set_mode  (alarm_set_mode),
        .inhibit   (time_set_mode),
        .kill      (alarm_kill),
        .mode_12h  (SW_S[2]),
        .btn_h     (alarm_set_mode ? b_up   : 1'b0),
        .btn_m     (alarm_set_mode ? b_down : 1'b0),
        .btn_ampm  (alarm_set_mode && SW_S[2] ? b_left : 1'b0),
        .snooze_btn(b_center),
        .current_h (raw_h),
        .current_m (raw_m),
        .current_s (raw_s),
        .alarm_active(alarm_ringing),
        .set_h(alarm_h_stored),
        .set_m(alarm_m_stored)
    );

    // Display character codes
    localparam [3:0] CH_A     = 4'hA;
    localparam [3:0] CH_L     = 4'hB;
    localparam [3:0] CH_P     = 4'hC;
    localparam [3:0] CH_DASH  = 4'hF;
    localparam [3:0] CH_BLANK = 4'hE;

    // Alarm display formatting
    wire alarm_pm = (alarm_h_stored >= 12);

    wire [4:0] alarm_h_disp =
        (SW_S[2]) ? (((alarm_h_stored % 12) == 0) ? 5'd12 : (alarm_h_stored % 12))
                  : alarm_h_stored;

    wire [3:0] al_h1   = (SW_S[2] && (alarm_h_disp < 10)) ? CH_BLANK : (alarm_h_disp / 10);
    wire [3:0] al_h0   = (alarm_h_disp % 10);
    wire [3:0] al_m1   = (alarm_m_stored / 10);
    wire [3:0] al_m0   = (alarm_m_stored % 10);
    wire [3:0] al_ampm = alarm_pm ? CH_P : CH_A;

    wire [3:0] al24_h1 = alarm_h_stored / 10;  // Separate wires prevent concat width truncation
    wire [3:0] al24_h0 = alarm_h_stored % 10;

    // Stopwatch
    wire [3:0] sw_h1, sw_h0, sw_m1, sw_m0, sw_s1, sw_s0;

    stopwatch sw_inst (
        .clk(CLK100MHZ), .rst(rst), .tick_1hz(t1),
        .enable   (stopwatch_mode),
        .btn_run  (stopwatch_mode ? b_up    : 1'b0),
        .btn_lap  (stopwatch_mode ? b_left  : 1'b0),
        .btn_reset(stopwatch_mode ? b_right : 1'b0),
        .d5(sw_h1), .d4(sw_h0), .d3(sw_m1), .d2(sw_m0), .d1(sw_s1), .d0(sw_s0)
    );

    // Display data mux
    reg [31:0] display_data;
    always @(*) begin
        if (stopwatch_mode) begin
            display_data = {CH_BLANK, CH_BLANK, sw_h1, sw_h0, sw_m1, sw_m0, sw_s1, sw_s0};
        end else if (alarm_set_mode) begin
            if (SW_S[2])
                display_data = {CH_A, CH_L, al_h1, al_h0, al_m1, al_m0, CH_BLANK, al_ampm};
            else
                display_data = {CH_A, CH_L, al24_h1, al24_h0, al_m1, al_m0, CH_DASH, CH_DASH};
        end else begin
            display_data = {h1, h0, CH_DASH, m1, m0, CH_DASH, s1, s0};
        end
    end

    display_mux dm (
        .clk(CLK100MHZ), .rst(rst), .tick(t1k), .data(display_data),
        .an(AN), .seg(SEG)
    );

    // LEDs
    assign LED[0]    = pm_ind;        // PM indicator (12h mode)
    assign LED[1]    = stopwatch_mode;
    assign LED[2]    = alarm_ringing;
    assign LED[3]    = alarm_set_mode;
    assign LED[4]    = alarm_kill;    // Alarm disabled indicator
    assign LED[15:5] = 11'b0;

endmodule


// ==========================================================
// RESET SYNC - async assert, sync deassert
// ==========================================================
module reset_sync (
    input  wire clk,
    input  wire rst_async,
    output wire rst_sync
);
    (* ASYNC_REG="TRUE" *) reg [1:0] ff;

    always @(posedge clk or posedge rst_async) begin
        if (rst_async) ff <= 2'b11;
        else           ff <= {ff[0], 1'b0};
    end

    assign rst_sync = ff[1];
endmodule


// ==========================================================
// CLOCK DIVIDER - tick pulses, no drift
// ==========================================================
module clk_divider (
    input  wire clk, rst,
    output reg  t1, t100, t1k
);
    reg [26:0] c1;
    reg [19:0] c100;
    reg [16:0] c1k;

    always @(posedge clk) begin
        if (rst) begin
            c1 <= 0; c100 <= 0; c1k <= 0;
            t1 <= 0; t100 <= 0; t1k <= 0;
        end else begin
            t1 <= 1'b0; t100 <= 1'b0; t1k <= 1'b0;

            if (c1  == 27'd99_999_999) begin c1  <= 0; t1  <= 1'b1; end else c1  <= c1  + 1;
            if (c100 == 20'd999_999)   begin c100 <= 0; t100 <= 1'b1; end else c100 <= c100 + 1;
            if (c1k == 17'd99_999)     begin c1k  <= 0; t1k  <= 1'b1; end else c1k  <= c1k  + 1;
        end
    end
endmodule


// ==========================================================
// DEBOUNCE + ONE-PULSE - 1kHz sample, 8 stable samples required
// ==========================================================
module debounce_onepulse (
    input  wire clk, rst,
    input  wire tick_1khz,
    input  wire btn_in,
    output reg  pulse
);
    (* ASYNC_REG="TRUE" *) reg sync0, sync1;
    reg [7:0] hist;
    reg debounced;

    wire [7:0] hist_next = {hist[6:0], sync1};

    always @(posedge clk) begin
        if (rst) begin
            sync0 <= 0; sync1 <= 0;
            hist <= 0; debounced <= 0; pulse <= 0;
        end else begin
            sync0 <= btn_in;
            sync1 <= sync0;
            pulse <= 1'b0;

            if (tick_1khz) begin
                hist <= hist_next;
                if      (&hist_next)  begin if (!debounced) pulse <= 1'b1; debounced <= 1'b1; end
                else if (~|hist_next) begin debounced <= 1'b0; end
            end
        end
    end
endmodule


// ==========================================================
// TIME LOGIC
// Base timezone: Dhaka (UTC+6). Offsets are relative to that.
// ==========================================================
module time_logic (
    input  wire clk, rst, tick_1hz, set_mode, mode_12_24,
    input  wire btn_h, btn_m, btn_s,
    input  wire [4:0] sw_zones,
    output wire [3:0] h1, h0, m1, m0, s1, s0,
    output wire is_pm,
    output wire [4:0] raw_h,
    output wire [5:0] raw_m, raw_s
);
    reg [5:0] s, m;
    reg [4:0] h;

    always @(posedge clk) begin
        if (rst) begin
            h <= 0; m <= 0; s <= 0;
        end else if (set_mode) begin
            if (btn_h) h <= (h == 23) ? 0 : h + 1;
            if (btn_m) m <= (m == 59) ? 0 : m + 1;
            if (btn_s) s <= 0;
        end else if (tick_1hz) begin
            if (s == 59) begin
                s <= 0;
                if (m == 59) begin m <= 0; h <= (h == 23) ? 0 : h + 1; end
                else m <= m + 1;
            end else s <= s + 1;
        end
    end

    reg signed [5:0] offset;
    reg signed [6:0] h_temp;
    reg [4:0] h_adj_u, h_disp;

    always @(*) begin
        // Timezone offsets relative to Dhaka (UTC+6)
        if      (sw_zones[0]) offset = -6'sd16;  // Hawaii  (UTC-10)
        else if (sw_zones[1]) offset = -6'sd6;   // London  (UTC+0)
        else if (sw_zones[2]) offset = -6'sd11;  // New York (UTC-5)
        else if (sw_zones[3]) offset = -6'sd3;   // Moscow  (UTC+3)
        else if (sw_zones[4]) offset =  6'sd3;   // Tokyo   (UTC+9)
        else                  offset =  6'sd0;   // Dhaka   (UTC+6, base)

        h_temp = $signed({2'b00, h}) + offset;

        if      (h_temp < 0)   h_adj_u = h_temp + 7'sd24;
        else if (h_temp >= 24) h_adj_u = h_temp - 7'sd24;
        else                   h_adj_u = h_temp[4:0];

        if (mode_12_24) begin
            if      (h_adj_u == 0)  h_disp = 5'd12;
            else if (h_adj_u < 12)  h_disp = h_adj_u;
            else if (h_adj_u == 12) h_disp = 5'd12;
            else                    h_disp = h_adj_u - 12;
        end else begin
            h_disp = h_adj_u;
        end
    end

    assign is_pm = (h_adj_u >= 12);

    assign h1 = h_disp / 10; assign h0 = h_disp % 10;
    assign m1 = m / 10;      assign m0 = m % 10;
    assign s1 = s / 10;      assign s0 = s % 10;

    assign raw_h = h;
    assign raw_m = m;
    assign raw_s = s;
endmodule


// ==========================================================
// ALARM CONTROLLER
// kill (SW4): disables alarm entirely and stops ringing instantly
// Snooze: 15-second delay before re-ringing
// ==========================================================
module alarm_controller (
    input  wire clk, rst, tick_1hz,
    input  wire set_mode, inhibit, kill,
    input  wire mode_12h,
    input  wire btn_h, btn_m, btn_ampm,
    input  wire snooze_btn,
    input  wire [4:0] current_h,
    input  wire [5:0] current_m, current_s,
    output reg  alarm_active,
    output reg  [4:0] set_h,
    output reg  [5:0] set_m
);
    always @(posedge clk) begin
        if (rst) begin
            set_h <= 0; set_m <= 0;
        end else if (set_mode) begin
            if (btn_h) set_h <= (set_h == 23) ? 0 : set_h + 1;
            if (btn_m) set_m <= (set_m == 59) ? 0 : set_m + 1;
            if (mode_12h && btn_ampm)
                set_h <= (set_h < 12) ? set_h + 12 : set_h - 12;
        end
    end

    localparam [1:0] IDLE = 2'd0, RINGING = 2'd1, SNOOZING = 2'd2;
    localparam [5:0] SNOOZE_SECONDS = 6'd15;

    reg [1:0] state;
    reg [5:0] snooze_counter;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE; alarm_active <= 1'b0; snooze_counter <= 6'd0;
        end else if (kill) begin
            state <= IDLE; alarm_active <= 1'b0; snooze_counter <= 6'd0;
        end else begin
            case (state)
                IDLE: begin
                    alarm_active <= 1'b0;
                    if (!set_mode && !inhibit &&
                        current_h == set_h && current_m == set_m && current_s == 0)
                        state <= RINGING;
                end

                RINGING: begin
                    alarm_active <= 1'b1;
                    if (set_mode || inhibit)         state <= IDLE;
                    else if (current_m != set_m)     state <= IDLE;
                    else if (snooze_btn) begin
                        state <= SNOOZING;
                        snooze_counter <= SNOOZE_SECONDS-1;
                    end
                end

                SNOOZING: begin
                    alarm_active <= 1'b0;
                    if (set_mode || inhibit) begin
                        state <= IDLE; snooze_counter <= 0;
                    end else if (tick_1hz) begin
                        if (snooze_counter == 6'd0) state <= RINGING;
                        else snooze_counter <= snooze_counter - 1;
                    end
                end

                default: begin state <= IDLE; alarm_active <= 1'b0; end
            endcase
        end
    end
endmodule


// ==========================================================
// STOPWATCH - with hours and lap hold
// ==========================================================
module stopwatch (
    input  wire clk, rst, tick_1hz, enable,
    input  wire btn_run, btn_lap, btn_reset,
    output wire [3:0] d5, d4, d3, d2, d1, d0
);
    reg running, lap;
    reg [6:0] s, m, h;
    reg [6:0] ls, lm, lh;

    always @(posedge clk) begin
        if (rst) begin
            running <= 0; lap <= 0;
            h <= 0; m <= 0; s <= 0;
            lh <= 0; lm <= 0; ls <= 0;
        end else if (enable) begin
            if (btn_run)   running <= ~running;
            if (btn_reset) begin
                h <= 0; m <= 0; s <= 0;
                lh <= 0; lm <= 0; ls <= 0; lap <= 0;
                running <= 0;
            end
            if (btn_lap) begin
                lap <= ~lap; lh <= h; lm <= m; ls <= s;
            end

            if (tick_1hz && running) begin
                if (s == 59) begin
                    s <= 0;
                    if (m == 59) begin
                        m <= 0;
                        h <= (h == 99) ? 0 : h + 1;
                    end else m <= m + 1;
                end else s <= s + 1;
            end
        end
    end

    wire [6:0] oh = lap ? lh : h;
    wire [6:0] om = lap ? lm : m;
    wire [6:0] os = lap ? ls : s;

    assign d5 = oh / 10; assign d4 = oh % 10;
    assign d3 = om / 10; assign d2 = om % 10;
    assign d1 = os / 10; assign d0 = os % 10;
endmodule


// ==========================================================
// DISPLAY MUX - 8-digit 7-segment, active-low
// Digit blanking between switches reduces ghosting
// ==========================================================
module display_mux (
    input  wire clk, rst, tick,
    input  wire [31:0] data,
    output reg  [7:0] an,
    output reg  [6:0] seg
);
    reg [2:0] sel;
    reg [3:0] val;

    localparam integer BLANK_CYCLES = 1000; // ~10us @ 100MHz
    reg [15:0] blank_cnt;

    always @(posedge clk) begin
        if (rst) begin sel <= 0; blank_cnt <= 0; end
        else begin
            if (tick) begin sel <= sel + 1'b1; blank_cnt <= BLANK_CYCLES[15:0]; end
            else if (blank_cnt != 0) blank_cnt <= blank_cnt - 1'b1;
        end
    end

    always @(*) begin
        val = 4'h0;
        case (sel)
            3'd0: val = data[3:0];   3'd1: val = data[7:4];
            3'd2: val = data[11:8];  3'd3: val = data[15:12];
            3'd4: val = data[19:16]; 3'd5: val = data[23:20];
            3'd6: val = data[27:24]; 3'd7: val = data[31:28];
        endcase
    end

    always @(*) begin
        an = 8'hFF;
        if (blank_cnt == 0) an[sel] = 1'b0;
    end

    // Segment encoding: {a,b,c,d,e,f,g} active-low
    always @(*) begin
        case (val)
            4'h0: seg = 7'b1000000;
            4'h1: seg = 7'b1111001;
            4'h2: seg = 7'b0100100;
            4'h3: seg = 7'b0110000;
            4'h4: seg = 7'b0011001;
            4'h5: seg = 7'b0010010;
            4'h6: seg = 7'b0000010;
            4'h7: seg = 7'b1111000;
            4'h8: seg = 7'b0000000;
            4'h9: seg = 7'b0010000;
            4'hA: seg = 7'b0001000; // 'A'
            4'hB: seg = 7'b1000111; // 'L'
            4'hC: seg = 7'b0001100; // 'P'
            4'hF: seg = 7'b0111111; // '-'
            4'hE: seg = 7'b1111111; // ' '
            default: seg = 7'b1111111;
        endcase
    end
endmodule

`default_nettype wire
# Digital Clock — Nexys A7 FPGA

A fully-featured digital clock implemented in Verilog, targeting the **Digilent Nexys A7-100T** board. The design runs on the onboard 100 MHz clock and drives the 8-digit 7-segment display with four operating modes: normal timekeeping, time-set, alarm, and stopwatch.

---

## Features

- **Real-time clock** — hours, minutes, seconds with automatic rollover
- **12 / 24-hour mode** — toggled via a slide switch; PM indicator on LED
- **Timezone display** — six selectable offsets relative to Dhaka (UTC+6), including half-hour zones: Hawaii, London, New York (UTC−5:30), Moscow, Tokyo, and Chatham Islands (UTC+12:30)
- **Alarm** — settable hour/minute with 12h AM/PM or 24h entry; 15-second snooze; instant kill switch; startup-safe (will not fire on power-up)
- **Stopwatch** — start/stop, lap hold, and reset; counts up to 99h 59m 59s
- **Debounced buttons** — 8-sample majority filter at 1 kHz prevents false triggers
- **Async-assert / sync-release reset** — glitch-free reset synchroniser

---

## Repository Structure

```
.
├── digital_clock.v   # Complete RTL source (all modules in one file)
└── constr.xdc        # Vivado pin/IO-standard constraints for Nexys A7-100T
```

---

## Module Hierarchy

```
digital_clock          (top)
├── reset_sync         Async-assert, sync-deassert reset synchroniser
├── clk_divider        Generates 1 Hz, 100 Hz, and 1 kHz tick pulses
├── debounce_onepulse  One-shot debouncer (×5, one per button)
├── time_logic         HH:MM:SS counter + half-hour timezone offsets + 12/24h formatting
├── alarm_controller   Alarm set, ring, snooze, and kill FSM (with startup-arm guard)
├── stopwatch          HH:MM:SS stopwatch with lap display
└── display_mux        8-digit multiplexed 7-segment driver with blanking
```

---

## Hardware Requirements

| Item | Detail |
|------|--------|
| Board | Digilent Nexys A7-100T (or -50T with pin re-check) |
| FPGA | Xilinx Artix-7 XC7A100T |
| Tool | Vivado 2020.1 or later |
| Clock | 100 MHz onboard oscillator (E3) |

---

## I/O Reference

### Slide Switches

| Switch | Function |
|--------|----------|
| SW0 | Stopwatch mode |
| SW1 | Time-set mode |
| SW2 | 12h (ON) / 24h (OFF) display |
| SW3 | Alarm-set mode (ignored while SW1 is ON) |
| SW4 | Alarm kill — disables alarm and stops ringing immediately |
| SW10–SW15 | Timezone select (see table below) |

### Timezone Selection (SW10–SW15)

| Switch | Timezone | UTC Offset |
|--------|----------|------------|
| SW10 | Chatham Islands | UTC+12:30 |
| SW11 | Hawaii | UTC−10 |
| SW12 | London | UTC+0 |
| SW13 | New York | UTC−5:30 |
| SW14 | Moscow | UTC+3 |
| SW15 | Tokyo | UTC+9 |
| None | Dhaka (base) | UTC+6 |

> Only one timezone switch should be ON at a time. Priority is SW10 < SW11 < ... < SW15 (higher switch number wins if multiple are ON).

> **Half-hour zones:** New York (UTC−5:30) and Chatham Islands (UTC+12:30) apply a ±30-minute offset to the displayed minutes in addition to the hour offset. Alarm comparison always uses raw Dhaka time internally.

### Pushbuttons

| Button | Time-set mode | Alarm-set mode | Stopwatch mode | Alarm ringing |
|--------|--------------|----------------|----------------|---------------|
| BTU (Up) | +1 Hour | +1 Hour | Start / Stop | — |
| BTD (Down) | +1 Minute | +1 Minute | — | — |
| BTR (Right) | Reset seconds to 0 | — | Reset | — |
| BTL (Left) | — | Toggle AM/PM (12h only) | Lap / Unlap | — |
| BTC (Center) | — | — | — | Snooze (15 s) |

### LEDs

| LED | Meaning |
|-----|---------|
| LED0 | PM indicator (12h mode only) |
| LED1 | Stopwatch mode active |
| LED2 | Alarm currently ringing |
| LED3 | Alarm-set mode active |
| LED4 | Alarm killed (SW4 ON) |
| LED5–15 | Unused (driven low) |

### 7-Segment Display

The 8-digit display shows different content depending on the active mode:

| Mode | Display Format |
|------|---------------|
| Normal / Time-set | `HH - MM - SS` |
| Alarm-set (24h) | `AL HH MM - -` |
| Alarm-set (12h) | `AL HH MM _ A/P` |
| Stopwatch | `_ _ HH MM SS` |

---

## Getting Started

### 1. Clone / copy the files

```bash
git clone https://github.com/aditalrazi/Digital_Clock_with_Lap_Capacity.git
cd Digital_Clock_with_Lap_Capacity
```

### 2. Open in Vivado

1. Create a new **RTL project** targeting `xc7a100tcsg324-1`.
2. Add `digital_clock.v` as a design source.
3. Add `constr.xdc` as a constraint source.
4. Run **Synthesis → Implementation → Generate Bitstream**.

### 3. Program the board

Connect the Nexys A7 via USB-JTAG and use **Open Hardware Manager → Program Device** to load the bitstream.

### 4. Set the time

1. Flip **SW1** ON to enter time-set mode.
2. Press **BTU** to increment hours, **BTD** to increment minutes, **BTR** to zero seconds.
3. Flip **SW1** OFF — the clock starts ticking from the set time.

---

## Design Notes

- **Clock divider** uses independent counters for each tick rate (1 Hz / 100 Hz / 1 kHz), ensuring no accumulated drift.
- **Half-hour timezone support** — `time_logic` computes a separate minute offset (0 or +30) and propagates any carry into the hour calculation, keeping all arithmetic signed and properly wrapped to 0–23h / 0–59m.
- **Alarm arm guard** — an `armed` flip-flop in `alarm_controller` is set after the first 1 Hz tick post-reset. This prevents the alarm from firing spuriously at power-up if the stored alarm time happens to match the initial counter values (all zeros).
- **Display multiplexer** inserts a ~10 µs all-anodes-off blank between digit switches to eliminate ghosting.
- **Reset synchroniser** uses the `ASYNC_REG` attribute to instruct Vivado to place both flip-flops in the same slice and suppress timing-arc warnings.
- **Alarm snooze duration** is configurable via the `SNOOZE_SECONDS` localparam in `alarm_controller` (default: 15 seconds).
- **Mode priority** is: Time-set > Alarm-set > Stopwatch > Normal.

---

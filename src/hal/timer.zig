//! SysTick-based millisecond timer

const SYSTICK_BASE = 0xE000_E010;
const STK_CTRL = @as(*volatile u32, @ptrFromInt(SYSTICK_BASE + 0x00));
const STK_LOAD = @as(*volatile u32, @ptrFromInt(SYSTICK_BASE + 0x04));
const STK_VAL = @as(*volatile u32, @ptrFromInt(SYSTICK_BASE + 0x08));

const CTRL_ENABLE: u32 = 1 << 0;
const CTRL_TICKINT: u32 = 1 << 1;
const CTRL_CLKSOURCE: u32 = 1 << 2;

const DEMCR = @as(*volatile u32, @ptrFromInt(0xE000_EDFC));
const DWT_CTRL = @as(*volatile u32, @ptrFromInt(0xE000_1000));
const DWT_CYCCNT = @as(*volatile u32, @ptrFromInt(0xE000_1004));

const DEMCR_TRCENA: u32 = 1 << 24;
const DWT_CYCCNTENA: u32 = 1 << 0;

var ticks: u32 = 0;
var cycles_per_us: u32 = 1;

pub fn init(cpu_freq_hz: u32) void {
    @atomicStore(u32, &ticks, 0, .monotonic);

    STK_CTRL.* = 0;
    STK_LOAD.* = (cpu_freq_hz / 1000) - 1;
    STK_VAL.* = 0;
    STK_CTRL.* = CTRL_ENABLE | CTRL_TICKINT | CTRL_CLKSOURCE;

    cycles_per_us = cpu_freq_hz / 1_000_000;
    DEMCR.* |= DEMCR_TRCENA;
    DWT_CYCCNT.* = 0;
    DWT_CTRL.* |= DWT_CYCCNTENA;
}

pub fn millis() u32 {
    return @atomicLoad(u32, &ticks, .monotonic);
}

pub fn delayMs(ms: u32) void {
    const start = millis();
    while (millis() -% start < ms) {
        asm volatile ("wfi");
    }
}

/// Raw DWT cycle count, for timing relative to a fixed point with `waitSinceUs`
pub fn cycleCount() u32 {
    return DWT_CYCCNT.*;
}

/// Busy-waits until `us` microseconds have passed since `start` (from `cycleCount`)
pub fn waitSinceUs(start: u32, us: u32) void {
    const target = us * cycles_per_us;
    while (DWT_CYCCNT.* -% start < target) {}
}

/// Busy-waits on the DWT cycle counter, safe to call with interrupts disabled
pub fn delayUs(us: u32) void {
    const start = DWT_CYCCNT.*;
    const cycles = us * cycles_per_us;
    while (DWT_CYCCNT.* -% start < cycles) {}
}

export fn SysTick_Handler() void {
    @atomicStore(u32, &ticks, ticks +% 1, .monotonic);
}

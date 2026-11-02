const gpio = @import("gpio.zig");
const rcc = @import("rcc.zig");

const base = 0x4000_0000;

const cr1: *volatile u32 = @ptrFromInt(base + 0x00);
const egr: *volatile u32 = @ptrFromInt(base + 0x14);
const ccmr1: *volatile u32 = @ptrFromInt(base + 0x18);
const ccer: *volatile u32 = @ptrFromInt(base + 0x20);
const psc: *volatile u32 = @ptrFromInt(base + 0x28);
const arr: *volatile u32 = @ptrFromInt(base + 0x2C);
const ccr1: *volatile u32 = @ptrFromInt(base + 0x34);

const APB1ENR_TIM2EN: u32 = 1 << 0;
const CR1_CEN: u32 = 1 << 0;
const CR1_ARPE: u32 = 1 << 7;
const EGR_UG: u32 = 1 << 0;
const CCMR1_OC1PE: u32 = 1 << 3;
const CCMR1_OC1M_PWM1: u32 = 0b110 << 4;
const CCER_CC1E: u32 = 1 << 0;

const TICK_HZ = 1_000_000;

pub const MAX: u16 = 1000;

pub fn init(timer_clk_hz: u32, freq_hz: u32) void {
    gpio.enable(.a);
    gpio.alternate(.a, 5, 1); // AF1 = TIM2_CH1

    rcc.apb1enr.* |= APB1ENR_TIM2EN;

    cr1.* = 0;
    psc.* = timer_clk_hz / TICK_HZ - 1;
    arr.* = TICK_HZ / freq_hz - 1;
    ccr1.* = 0;
    ccmr1.* = (ccmr1.* & ~@as(u32, 0xFF)) | CCMR1_OC1M_PWM1 | CCMR1_OC1PE;
    ccer.* |= CCER_CC1E;
    // Latch PSC/ARR/CCR1 before starting
    egr.* = EGR_UG;
    cr1.* = CR1_ARPE | CR1_CEN;
}

pub fn setDuty(duty: u16) void {
    const d = @min(duty, MAX);
    const period = arr.* + 1;
    ccr1.* = period * d / MAX;
}

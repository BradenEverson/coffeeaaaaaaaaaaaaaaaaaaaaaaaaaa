const gpio = @import("gpio.zig");
const rcc = @import("rcc.zig");

pub const Channel = enum { ch1, ch2 };

const base = 0x4000_7400;

const cr: *volatile u32 = @ptrFromInt(base + 0x00);
const dhr12r1: *volatile u32 = @ptrFromInt(base + 0x08);
const dhr12r2: *volatile u32 = @ptrFromInt(base + 0x14);

const APB1ENR_DACEN: u32 = 1 << 29;

pub const MAX: u12 = 0xFFF;

fn pinFor(channel: Channel) u4 {
    return switch (channel) {
        .ch1 => 4,
        .ch2 => 5,
    };
}

pub fn init(channel: Channel) void {
    gpio.enable(.a);
    gpio.analog(.a, pinFor(channel));

    rcc.apb1enr.* |= APB1ENR_DACEN;

    const shift: u5 = switch (channel) {
        .ch1 => 0,
        .ch2 => 16,
    };
    cr.* = (cr.* & ~(@as(u32, 0xFFFF) << shift)) | (@as(u32, 1) << shift);
}

pub fn write(channel: Channel, value: u12) void {
    const r = switch (channel) {
        .ch1 => dhr12r1,
        .ch2 => dhr12r2,
    };
    r.* = value;
}

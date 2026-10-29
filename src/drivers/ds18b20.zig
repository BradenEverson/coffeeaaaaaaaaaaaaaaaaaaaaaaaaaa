const std = @import("std");
const hal = @import("../hal.zig");

const CMD_SKIP_ROM: u8 = 0xCC;
const CMD_CONVERT_T: u8 = 0x44;
const CMD_WRITE_SCRATCHPAD: u8 = 0x4E;
const CMD_READ_SCRATCHPAD: u8 = 0xBE;

const SCRATCHPAD_LEN = 9;
const CONFIG_RESERVED_BITS: u8 = 0x1F;

pub const Ds18b20Error = error{ NoPresence, BusStuck, BadCrc, ConfigMismatch };

pub const Resolution = enum(u2) {
    bits9,
    bits10,
    bits11,
    bits12,

    fn conversionMs(self: Resolution) u32 {
        return @as(u32, 94) << @intFromEnum(self);
    }
};

pub const Ds18b20 = struct {
    pin: hal.gpio.Pin,
    resolution: Resolution,

    pub fn init(pin: hal.gpio.Pin, resolution: Resolution) Ds18b20Error!Ds18b20 {
        hal.gpio.enable(pin.port);
        hal.gpio.set(pin.port, pin.num);
        hal.gpio.openDrain(pin.port, pin.num);
        hal.gpio.pullUp(pin.port, pin.num);
        hal.gpio.output(pin.port, pin.num);

        const self: Ds18b20 = .{ .pin = pin, .resolution = resolution };
        const cfg: u8 = (@as(u8, @intFromEnum(resolution)) << 5) | CONFIG_RESERVED_BITS;

        try self.command(CMD_WRITE_SCRATCHPAD);
        self.writeByte(0);
        self.writeByte(0);
        self.writeByte(cfg);

        const sp = try self.readScratchpad();
        if (sp[4] != cfg) return error.ConfigMismatch;

        return self;
    }

    pub fn readTemperatureC(self: *const Ds18b20) Ds18b20Error!f32 {
        try self.command(CMD_CONVERT_T);
        hal.timer.delayMs(self.resolution.conversionMs());

        const sp = try self.readScratchpad();
        var raw: i16 = @bitCast(std.mem.readInt(u16, sp[0..2], .little));

        const undefined_bits: u4 = 3 - @as(u4, @intFromEnum(self.resolution));
        raw &= ~((@as(i16, 1) << undefined_bits) - 1);

        return @as(f32, @floatFromInt(raw)) / 16.0;
    }

    pub fn readTemperatureF(self: *const Ds18b20) Ds18b20Error!f32 {
        return try self.readTemperatureC() * 9.0 / 5.0 + 32.0;
    }

    fn readScratchpad(self: *const Ds18b20) Ds18b20Error![SCRATCHPAD_LEN]u8 {
        try self.command(CMD_READ_SCRATCHPAD);

        var sp: [SCRATCHPAD_LEN]u8 = undefined;
        for (&sp) |*b| b.* = self.readByte();

        if (crc8(sp[0 .. SCRATCHPAD_LEN - 1]) != sp[SCRATCHPAD_LEN - 1]) return error.BadCrc;
        return sp;
    }

    fn command(self: *const Ds18b20, cmd: u8) Ds18b20Error!void {
        try self.reset();
        self.writeByte(CMD_SKIP_ROM);
        self.writeByte(cmd);
    }

    fn reset(self: *const Ds18b20) Ds18b20Error!void {
        if (!self.sample()) return error.BusStuck;

        self.drive();
        hal.timer.delayUs(480);

        disableIrq();
        self.release();
        hal.timer.delayUs(70);
        const present = !self.sample();
        enableIrq();

        hal.timer.delayUs(410);
        if (!present) return error.NoPresence;
    }

    fn writeByte(self: *const Ds18b20, byte: u8) void {
        var b = byte;
        for (0..8) |_| {
            self.writeBit(b & 1 != 0);
            b >>= 1;
        }
    }

    fn readByte(self: *const Ds18b20) u8 {
        var b: u8 = 0;
        for (0..8) |i| {
            if (self.readBit()) b |= @as(u8, 1) << @intCast(i);
        }
        return b;
    }

    fn writeBit(self: *const Ds18b20, bit: bool) void {
        disableIrq();
        defer enableIrq();

        self.drive();
        if (bit) {
            hal.timer.delayUs(6);
            self.release();
            hal.timer.delayUs(64);
        } else {
            hal.timer.delayUs(60);
            self.release();
            hal.timer.delayUs(10);
        }
    }

    fn readBit(self: *const Ds18b20) bool {
        disableIrq();
        defer enableIrq();

        const start = hal.timer.cycleCount();
        self.drive();
        self.release();
        hal.timer.waitSinceUs(start, 12);
        const bit = self.sample();
        hal.timer.waitSinceUs(start, 65);
        return bit;
    }

    fn drive(self: *const Ds18b20) void {
        hal.gpio.reset(self.pin.port, self.pin.num);
    }

    fn release(self: *const Ds18b20) void {
        hal.gpio.set(self.pin.port, self.pin.num);
    }

    fn sample(self: *const Ds18b20) bool {
        return hal.gpio.read(self.pin.port, self.pin.num);
    }
};

fn crc8(data: []const u8) u8 {
    var crc: u8 = 0;
    for (data) |byte| {
        var b = byte;
        for (0..8) |_| {
            const mix = (crc ^ b) & 1;
            crc >>= 1;
            if (mix != 0) crc ^= 0x8C;
            b >>= 1;
        }
    }
    return crc;
}

inline fn disableIrq() void {
    asm volatile ("cpsid i" ::: .{ .memory = true });
}

inline fn enableIrq() void {
    asm volatile ("cpsie i" ::: .{ .memory = true });
}

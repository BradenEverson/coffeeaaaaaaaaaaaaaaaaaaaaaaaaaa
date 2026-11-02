const hal = @import("hal.zig");
const ds18b20 = @import("drivers/ds18b20.zig");

const debug: hal.uart.Uart = .usart2;
const BAUD_RATE = 115200;
const SAMPLE_PERIOD_MS: u32 = 1000;

const CPACR: *volatile u32 = @ptrFromInt(0xE000_ED88);

const TONGUE_GOOD_TEMP: f32 = 136.0;
const FULL_SCREAM_DELTA: f32 = 20.0;

const CPU_FREQ_HZ: u32 = 16_000_000;
const BUZZ_PULSE_HZ: u32 = 4;
const MIN_DUTY: u16 = 50;

export fn run() void {
    CPACR.* |= 0xF << 20;
    asm volatile ("dsb\n isb");
    @call(.never_inline, app, .{});
}

fn app() void {
    hal.uart.init(debug, .{
        .baud = BAUD_RATE,
        .tx = .{ .port = .a, .num = 2 },
        .rx = .{ .port = .a, .num = 3 },
    });

    hal.pwm.init(CPU_FREQ_HZ, BUZZ_PULSE_HZ);

    hal.timer.init(CPU_FREQ_HZ);

    const sensor = ds18b20.Ds18b20.init(.{ .port = .a, .num = 0 }, .bits12) catch |e| {
        hal.uart.print(debug, "DS18B20 init failed: {s}\r\n", .{@errorName(e)});
        while (true) {}
    };

    hal.uart.writeStr(debug, "DS18B20 ready\r\n");

    while (true) {
        if (sensor.readTemperatureF()) |t| {
            const centi: i32 = @intFromFloat(t * 100.0);
            const sign = if (centi < 0) "-" else "";
            const abs = @abs(centi);
            hal.uart.print(debug, "temp: {s}{}.{:0>2} F\r\n", .{ sign, abs / 100, abs % 100 });
            hal.pwm.setDuty(loudness(t));
        } else |e| {
            hal.uart.print(debug, ":( {any}\r\n", .{e});
        }
        hal.timer.delayMs(SAMPLE_PERIOD_MS);
    }
}

fn loudness(t: f32) u16 {
    if (t < TONGUE_GOOD_TEMP) return 0;
    const frac = (t - TONGUE_GOOD_TEMP) / FULL_SCREAM_DELTA;
    if (frac >= 1.0) return hal.pwm.MAX;
    return MIN_DUTY + @as(u16, @intFromFloat(frac * @as(f32, hal.pwm.MAX - MIN_DUTY)));
}

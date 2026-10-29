const hal = @import("hal.zig");
const ds18b20 = @import("drivers/ds18b20.zig");

const debug: hal.uart.Uart = .usart2;
const BAUD_RATE = 115200;
const SAMPLE_PERIOD_MS: u32 = 1000;

const CPACR: *volatile u32 = @ptrFromInt(0xE000_ED88);

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

    hal.timer.init(16_000_000);

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
        } else |e| {
            hal.uart.print(debug, "read failed: {s}\r\n", .{@errorName(e)});
        }
        hal.timer.delayMs(SAMPLE_PERIOD_MS);
    }
}

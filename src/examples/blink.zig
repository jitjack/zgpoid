const std = @import("std");
const zgpiod = @import("zgpiod");

const LED_GPIO: c_uint = 17;
const BTN_GPIO: c_uint = 27;
pub fn main() !void {
    var chip = try zgpiod.Chip.init("/dev/gpiochip0");
    defer chip.deinit();

    // LED
    var led_line_settings = try zgpiod.LineSettings.init();
    defer led_line_settings.deinit();

    _ = led_line_settings.setDirection(.Output);
    _ = led_line_settings.setLineValue(.Inactive);

    var led_line_config = try zgpiod.LineConfig.init();
    defer led_line_config.deinit();

    var led_offsets = zgpiod.Offsets.init();
    defer led_offsets.deinit();
    try led_offsets.addOffset(LED_GPIO);
    _ = led_line_config.addLineSettings(&led_offsets, 1, led_line_settings);
    var led_request_config = try zgpiod.RequestConfig.init();
    defer led_request_config.deinit();

    led_request_config.setConsumer("LED Light");

    var led_line = try chip.getLineRequest(led_request_config, led_line_config);
    defer led_line.deinit();

    // Button
    var btn_line_settings = try zgpiod.LineSettings.init();
    defer btn_line_settings.deinit();

    _ = btn_line_settings.setDirection(.Input);
    _ = btn_line_settings.setBias(.PullUp);
    _ = btn_line_settings.setDebouncePeriodMicrosecs(1000);

    var btn_line_config = try zgpiod.LineConfig.init();
    defer btn_line_config.deinit();

    var btn_offsets = zgpiod.Offsets.init();
    defer btn_offsets.deinit();
    try btn_offsets.addOffset(BTN_GPIO);
    _ = btn_line_config.addLineSettings(&btn_offsets, 1, btn_line_settings);
    var btn_request_config = try zgpiod.RequestConfig.init();
    defer btn_request_config.deinit();

    btn_request_config.setConsumer("Toggle");

    var btn_line = try chip.getLineRequest(btn_request_config, btn_line_config);
    defer btn_line.deinit();

    const stdin = std.io.getStdIn().reader();
    var input_buf: [1]u8 = undefined;

    var btn_value: zgpiod.LineValue = .Inactive;
    std.debug.print("press \"q\" to quit\n", .{});
    while (true) {
        const read_in = try stdin.readAll(&input_buf);

        if (read_in > 0) {
            if (input_buf[0] == 'q') {
                break;
            }
        }

        btn_value = btn_line.getValue(BTN_GPIO);
        if (btn_value == .Active) {
            const led_value = led_line.getValue(LED_GPIO);
            switch (led_value) {
                .Inactive => {
                    _ = led_line.setValue(LED_GPIO, .Active);
                },
                .Active => {
                    _ = led_line.setValue(LED_GPIO, .Inactive);
                },
                else => {
                    std.debug.print("failed to get led value\n", .{});
                },
            }
        }
    }
}

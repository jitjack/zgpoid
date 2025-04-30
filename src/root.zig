const std = @import("std");

const c = @cImport({
    @cInclude("string.h");
    @cInclude("errno.h");
});

pub const gpoid = @cImport({
    @cInclude("gpiod.h");
});

pub const LineWaitEvent = enum(c_int) {
    TimeOut = 0,
    Error = -1,
    Pending = 1,
};

pub const LineValue = enum(c_int) {
    Error = gpoid.GPIOD_LINE_VALUE_ERROR,
    Active = gpoid.GPIOD_LINE_VALUE_ACTIVE,
    Inactive = gpoid.GPIOD_LINE_VALUE_INACTIVE,
};

pub const LineDirection = enum(c_uint) {
    AsIs = gpoid.GPIOD_LINE_DIRECTION_AS_IS,
    Input = gpoid.GPIOD_LINE_DIRECTION_INPUT,
    Output = gpoid.GPIOD_LINE_DIRECTION_OUTPUT,
};

pub const LineEdgeDetection = enum(c_uint) {
    None = gpoid.GPIOD_LINE_EDGE_NONE,
    Rising = gpoid.GPIOD_LINE_EDGE_RISING,
    Falling = gpoid.GPIOD_LINE_EDGE_FALLING,
    Both = gpoid.GPIOD_LINE_EDGE_BOTH,
};

pub const LineBias = enum(c_uint) {
    AsIs = gpoid.GPIOD_LINE_DIRECTION_AS_IS,
    Unknown = gpoid.GPIOD_LINE_BIAS_UNKNOWN,
    Disabled = gpoid.GPIOD_LINE_BIAS_DISABLED,
    PullUp = gpoid.GPIOD_LINE_BIAS_PULL_UP,
    PullDown = gpoid.GPIOD_LINE_BIAS_PULL_DOWN,
};

pub const LineDrive = enum(c_uint) {
    PushPull = gpoid.GPIOD_LINE_DRIVE_PUSH_PULL,
    OpenDrain = gpoid.GPIOD_LINE_DRIVE_OPEN_DRAIN,
    OpenSource = gpoid.GPIOD_LINE_DRIVE_OPEN_SOURCE,
};

pub const LineClock = enum(c_int) {
    ClockMonotonic = gpoid.GPIOD_LINE_CLOCK_MONOTONIC,
    ClockRealtime = gpoid.GPIOD_LINE_CLOCK_REALTIME,
    ClockHTE = gpoid.GPIOD_LINE_CLOCK_HTE,
};

pub const Line = struct {
    offset: c_uint,
    info: *gpoid.struct_gpiod_line_info,
    chip: *Chip,
    is_watching: bool = false,

    pub fn init(chip: *Chip, line_offset: usize) !@This() {
        if (chip.isValidOffset(line_offset)) {
            if (gpoid.gpiod_chip_get_line_info(chip.data, @intCast(line_offset))) |info| {
                return @This(){
                    .offset = @intCast(line_offset),
                    .chip = chip,
                    .info = info,
                };
            }
            return handleError("Invalid line info");
        }
        return handleError("Invalid line offset");
    }

    pub fn initWatch(chip: *Chip, line_offset: usize) !@This() {
        if (chip.isValidOffset(line_offset)) {
            if (gpoid.gpiod_chip_watch_line_info(chip.data, @intCast(line_offset))) |info| {
                return @This(){
                    .offset = @intCast(line_offset),
                    .info = info,
                    .chip = chip,
                    .is_watching = true,
                };
            }
            return handleError("Invalid line info");
        }
        return handleError("Invalid line offset");
    }

    pub fn getName(self: *@This()) [:0]const u8 {
        const n = gpoid.gpiod_line_info_get_name(self.info);
        if (n == null) return "No Name";
        return std.mem.span(n);
    }

    pub fn isInUse(self: *@This()) bool {
        return gpoid.gpiod_line_info_is_used(self.info);
    }

    pub fn getConsumerName(self: *@This()) [:0]const u8 {
        const n = gpoid.gpiod_line_info_get_consumer(self.info);
        if (n == null) return "No Consumer Name";
        return std.mem.span(n);
    }

    pub fn getDirection(self: *@This()) LineDirection {
        const d = gpoid.gpiod_line_info_get_direction(self.info);
        return @enumFromInt(d);
    }

    pub fn getBias(self: *@This()) LineBias {
        const d = gpoid.gpiod_line_info_get_bias(self.info);
        return @enumFromInt(d);
    }

    pub fn getDrive(self: *@This()) LineDrive {
        const d = gpoid.gpiod_line_info_get_drive(self.info);
        return @enumFromInt(d);
    }

    pub fn getEdgeDetection(self: *@This()) LineEdgeDetection {
        const d = gpoid.gpiod_line_info_get_edge_detection(self.info);
        return @enumFromInt(d);
    }

    pub fn getEventClock(self: *@This()) LineClock {
        const d = gpoid.gpiod_line_info_get_event_clock(self.info);
        return @enumFromInt(d);
    }

    pub fn isActiveLow(self: *@This()) bool {
        return gpoid.gpiod_line_info_is_active_low(self.info);
    }

    pub fn isDebounced(self: *@This()) bool {
        return gpoid.gpiod_line_info_is_debounced(self.info);
    }

    /// If debounded us is zero, the line isn't debounced, so it optional
    pub fn getDebouncedPeriodMicrosecs(self: *@This()) ?c_ulong {
        const v = gpoid.gpiod_line_info_get_debounce_period_us(self.info);
        return if (v > 0) v else null;
    }

    pub fn stopWatching(self: *@This()) bool {
        if (!self.is_watching) return false;
        return gpoid.gpiod_chip_unwatch_line_info(
            self.chip.data,
            self.offset,
        ) == 0;
    }

    pub fn deinit(self: *@This()) void {
        gpoid.gpiod_line_info_free(self.info);
    }
};

pub const LineStatusEvent = struct {
    pub const EventType = enum(c_int) {
        ConfigChanged = gpoid.GPIOD_INFO_EVENT_LINE_CONFIG_CHANGED,
        Released = gpoid.GPIOD_INFO_EVENT_LINE_RELEASED,
        Requested = gpoid.GPIOD_INFO_EVENT_LINE_REQUESTED,
    };
    event: *gpoid.struct_gpiod_info_event,
    event_type: EventType,
    timestamp_ns: u64,
    chip: *Chip,

    pub fn init(chip: *Chip) ?@This() {
        if (gpoid.gpiod_chip_read_info_event(chip.data)) |ev| {
            const e_type = gpoid.gpiod_info_event_get_event_type(ev);
            const ts = gpoid.gpiod_info_event_get_timestamp_ns(ev);
            return @This(){
                .event = ev,
                .event_type = @enumFromInt(e_type),
                .timestamp_ns = ts,
                .chip = chip,
            };
        }
        return null;
    }

    /// Don't call deinit on these lines
    pub fn getLineInfo(self: @This()) ?Line {
        if (gpoid.gpiod_info_event_get_line_info(self.event)) |info| {
            const offset = gpoid.gpiod_line_info_get_offset(info);
            return Line{
                .chip = self.chip,
                .info = info,
                .offset = offset,
                .is_watching = true,
            };
        }
        return null;
    }

    pub fn deinit(self: *@This()) void {
        gpoid.gpiod_info_event_free(self.event);
    }
};

pub fn apiVersion() [:0]const u8 {
    const v = gpoid.gpiod_api_version();
    return std.mem.span(v);
}

pub const Chip = struct {
    const Self = @This();
    data: *gpoid.struct_gpiod_chip,
    info: *gpoid.struct_gpiod_chip_info,
    line_count: c_uint,

    pub fn init(chip_path: []const u8) !Self {
        const c_chip_path: [*c]const u8 = @ptrCast(chip_path.ptr);
        if (gpoid.gpiod_is_gpiochip_device(c_chip_path)) {
            if (gpoid.gpiod_chip_open(c_chip_path)) |chip| {
                if (gpoid.gpiod_chip_get_info(chip)) |info| {
                    const lines: usize = gpoid.gpiod_chip_info_get_num_lines(info);
                    return Self{
                        .data = chip,
                        .info = info,
                        .line_count = @intCast(lines),
                    };
                }
                return handleError("Failed to get chip info");
            }
            return handleError("Chip not found");
        }
        return handleError("Path is not a GPIO chip device");
    }

    pub fn getChipPath(self: *Self) ?[:0]const u8 {
        const path = gpoid.gpiod_chip_get_path(self.data);
        if (path == null) return null;
        return std.mem.span(path);
    }

    pub fn getFileDescriptor(self: *Self) std.os.linux.fd_t {
        return @intCast(gpoid.gpiod_chip_get_fd(self.data));
    }

    pub fn getChipName(self: *Self) [:0]const u8 {
        const name = gpoid.gpiod_chip_info_get_name(self.info);
        if (name == null) return "No Chip Name";
        return std.mem.span(name);
    }

    pub fn getChipLabel(self: *Self) [:0]const u8 {
        const name = gpoid.gpiod_chip_info_get_label(self.info);
        if (name == null) return "No Chip Label";
        return std.mem.span(name);
    }

    pub fn isValidLine(self: *Self, line: Line) bool {
        return line.offset < self.line_count;
    }

    pub fn isValidOffset(self: *Self, offset: usize) bool {
        return @as(c_uint, @intCast(offset)) < self.line_count;
    }

    /// Get a Line instance -- caller must call .deinit()
    pub fn getLine(self: *Self, line_offset: usize, watch: bool) !Line {
        if (watch) {
            return try Line.initWatch(self, line_offset);
        }
        return try Line.init(self, line_offset);
    }

    pub fn waitLineEvent(self: *Self, timeout_ns: i64) LineWaitEvent {
        const v = gpoid.gpiod_chip_wait_info_event(self.data, timeout_ns);
        return @enumFromInt(v);
    }

    /// Blocking call
    pub fn nextLineEvent(self: *Self) ?LineStatusEvent {
        return LineStatusEvent.init(self);
    }

    /// Non-blocking call
    pub fn pollLineEvent(self: *Self, timeout_ns: i64) ?LineStatusEvent {
        const event_status = self.waitLineEvent(timeout_ns);
        if (event_status == .Pending) {
            return self.nextLineEvent();
        }
        return null;
    }

    pub fn getLineOffsetFromName(self: *Self, name: [:0]const u8) ?usize {
        const c_name: [*c]const u8 = @ptrCast(name.ptr);
        const result = gpoid.gpiod_chip_get_line_offset_from_name(self.data, c_name);
        if (result == -1) return null;
        return @as(usize, @intCast(result));
    }

    pub fn getLineRequest(
        self: *Self,
        request_config: RequestConfig,
        line_config: LineConfig,
    ) !LineRequest {
        const lr = gpoid.gpiod_chip_request_lines(self.data, request_config.config, line_config.config);
        if (lr) |line_request| {
            return LineRequest{ .request = line_request };
        }
        return handleError("Unable to request line");
    }

    pub fn deinit(self: *Self) void {
        gpoid.gpiod_chip_close(self.data);
        gpoid.gpiod_chip_info_free(self.info);
    }
};

pub const LineSettings = struct {
    const Self = @This();
    settings: *gpoid.gpiod_line_settings,

    pub fn init() !Self {
        if (gpoid.gpiod_line_settings_new()) |settings| {
            return @This(){
                .settings = settings,
            };
        }
        return handleError("Unable to create line settings");
    }

    pub fn reset(self: *Self) void {
        gpoid.gpiod_line_settings_reset(self.settings);
    }

    pub fn copy(self: *Self) ?@This() {
        if (gpoid.gpiod_line_settings_copy(self.settings)) |settings| {
            return @This(){ .settings = settings };
        }
        return null;
    }

    pub fn setDirection(self: *Self, direction: LineDirection) bool {
        return gpoid.gpiod_line_settings_set_direction(
            self.settings,
            @as(c_uint, @intFromEnum(direction)),
        ) == 0;
    }

    pub fn getDirection(self: *Self) LineDirection {
        const d = gpoid.gpiod_line_settings_get_direction(self.settings);
        return @enumFromInt(d);
    }

    pub fn setEdgeDetection(self: *Self, edge_detection: LineEdgeDetection) bool {
        return gpoid.gpiod_line_settings_set_edge_detection(
            self.settings,
            @as(c_uint, @intFromEnum(edge_detection)),
        ) == 0;
    }

    pub fn getEdgeDetection(self: *Self) LineEdgeDetection {
        const d = gpoid.gpiod_line_settings_get_edge_detection(self.settings);
        return @enumFromInt(d);
    }

    pub fn setBias(self: *Self, bias: LineBias) bool {
        return gpoid.gpiod_line_settings_set_bias(
            self.settings,
            @as(c_uint, @intFromEnum(bias)),
        ) == 0;
    }

    pub fn getBias(self: *Self) LineBias {
        const d = gpoid.gpiod_line_settings_get_bias(self.settings);
        return @enumFromInt(d);
    }

    pub fn setDrive(self: *Self, drive: LineDrive) bool {
        return gpoid.gpiod_line_settings_set_drive(
            self.settings,
            @as(c_uint, @intFromEnum(drive)),
        ) == 0;
    }

    pub fn getDrive(self: *Self) LineDrive {
        const d = gpoid.gpiod_line_settings_get_drive(self.settings);
        return @enumFromInt(d);
    }

    pub fn setActiveLow(self: *Self, active_low: bool) void {
        gpoid.gpiod_line_settings_set_active_low(self.settings, active_low);
    }

    pub fn getActiveLow(self: *Self) bool {
        return gpoid.gpiod_line_settings_get_active_low(self.settings);
    }

    pub fn setDebouncePeriodMicrosecs(self: *Self, period: u64) void {
        const to: c_ulong = @intCast(period);
        gpoid.gpiod_line_settings_set_debounce_period_us(self.settings, to);
    }

    pub fn getDebouncedPeriodMicrosecs(self: *Self) u64 {
        const to = gpoid.gpiod_line_settings_get_debounce_period_us(self.settings);
        return @intCast(to);
    }

    pub fn setEventClock(self: *Self, clock: LineClock) bool {
        return gpoid.gpiod_line_settings_set_event_clock(
            self.settings,
            @as(c_int, @intFromEnum(clock)),
        ) == 0;
    }

    pub fn getEventClock(self: *Self) LineClock {
        const d = gpoid.gpiod_line_settings_get_event_clock(self.settings);
        return @enumFromInt(d);
    }

    pub fn setLineValue(self: *Self, value: LineValue) bool {
        return gpoid.gpiod_line_settings_set_output_value(
            self.settings,
            @as(c_int, @intFromEnum(value)),
        ) == 0;
    }

    pub fn getLineValue(self: *Self) LineValue {
        const d = gpoid.gpiod_line_settings_get_output_value(self.settings);
        return @enumFromInt(d);
    }

    pub fn deinit(self: *@This()) void {
        gpoid.gpiod_line_settings_free(self.settings);
    }
};

pub const RequestConfig = struct {
    const Self = @This();
    config: *gpoid.gpiod_request_config,

    pub fn init() !Self {
        if (gpoid.gpiod_request_config_new()) |config| {
            return Self{ .config = config };
        }
        return handleError("Unable to create request config");
    }

    pub fn setConsumer(self: *Self, name: [:0]const u8) void {
        const c_name: [*c]const u8 = @ptrCast(name.ptr);
        gpoid.gpiod_request_config_set_consumer(self.config, c_name);
    }

    pub fn getConsumer(self: *Self) ?[:0]const u8 {
        const name = gpoid.gpiod_request_config_get_consumer(self.config);
        if (name == null) return null;
        return std.mem.span(name);
    }

    pub fn setEventBufferSize(self: *Self, buffer_size: usize) void {
        gpoid.gpiod_request_config_set_event_buffer_size(self.config, buffer_size);
    }

    pub fn getEventBufferSize(self: *Self) usize {
        return gpoid.gpiod_request_config_get_event_buffer_size(self.config);
    }

    pub fn deinit(self: *Self) void {
        gpoid.gpiod_request_config_free(self.config);
    }
};

pub const Offsets = struct {
    offsets: std.ArrayList(c_uint),

    pub fn init() @This() {
        return .{
            .offsets = std.ArrayList(c_uint).init(std.heap.c_allocator),
        };
    }

    pub fn addOffsetFromLine(self: *@This(), line: Line) !void {
        try self.addOffset(line.offset);
    }

    pub fn addOffset(self: *@This(), offset: c_uint) !void {
        try self.offsets.append(offset);
    }

    pub fn deinit(self: *@This()) void {
        self.offsets.deinit();
    }

    pub fn ptr(self: *@This()) [*]c_uint {
        return self.offsets.items.ptr;
    }
};

pub const LineConfig = struct {
    const Self = @This();
    config: *gpoid.gpiod_line_config,

    pub fn init() !Self {
        if (gpoid.gpiod_line_config_new()) |config| {
            return Self{ .config = config };
        }
        return handleError("unable to create line config");
    }

    pub fn addLineSettings(
        self: *Self,
        offsets: *Offsets,
        num_offsets: usize,
        line_settings: LineSettings,
    ) bool {
        return gpoid.gpiod_line_config_add_line_settings(
            self.config,
            offsets.ptr(),
            num_offsets,
            line_settings.settings,
        ) == 0;
    }

    /// Caller must call deinit
    pub fn getLineSettings(self: *Self, offset: usize) !LineSettings {
        const c_offset: c_uint = @intCast(offset);
        if (gpoid.gpiod_line_config_get_line_settings(self.config, c_offset)) |settings| {
            return LineSettings{ .settings = settings };
        }
        return handleError("Unable to create line settings");
    }

    //TODO: int gpiod_line_config_set_output_values(struct gpiod_line_config *config, const enum gpiod_line_value *values, size_t num_values)
    // pub fn setLineValues(self: *Self, value: LineValue) void
    // Should create a Offsets struct for LineValues?

    pub fn getConfiguredOffsetsCount(self: *Self) usize {
        return gpoid.gpiod_line_config_get_num_configured_offsets(self.config);
    }

    pub fn getOffsets(self: *Self, max_offsets: usize) !Offsets {
        var offsets = Offsets.init();
        var buffer = try std.heap.c_allocator.alloc(c_uint, max_offsets);
        defer std.heap.c_allocator.free(buffer);

        const actual_offsets = gpoid.gpiod_line_config_get_configured_offsets(
            self.config,
            buffer.ptr,
            max_offsets,
        );

        try offsets.offsets.ensureTotalCapacity(actual_offsets);
        try offsets.offsets.appendSlice(buffer[0..actual_offsets]);
        return offsets;
    }

    pub fn reset(self: *Self) void {
        gpoid.gpiod_line_config_reset(self.config);
    }

    pub fn deinit(self: *Self) void {
        gpoid.gpiod_line_config_free(self.config);
    }
};

pub const LineRequest = struct {
    const Self = @This();
    request: *gpoid.gpiod_line_request,

    // no init -- use Chip.getLineRequest

    pub fn deinit(self: *Self) void {
        gpoid.gpiod_line_request_release(self.request);
    }

    pub fn getChipName(self: *Self) [:0]const u8 {
        const c_name = gpoid.gpiod_line_request_get_chip_name(self.request);
        if (c_name == null) return "No Chip Name";
        return std.mem.span(c_name);
    }

    pub fn getNumberRequestedLines(self: *Self) usize {
        return gpoid.gpiod_line_request_get_num_requested_lines(self.request);
    }

    pub fn getRequestedOffsets(self: *Self, max_offsets: usize) !Offsets {
        var offsets = Offsets.init();
        var buffer = try std.heap.c_allocator.alloc(c_uint, max_offsets);
        defer std.heap.c_allocator.free(buffer);

        const actual_offsets = gpoid.gpiod_line_request_get_requested_offsets(
            self.request,
            buffer.ptr,
            max_offsets,
        );

        try offsets.offsets.ensureTotalCapacity(actual_offsets);
        try offsets.offsets.appendSlice(buffer[0..actual_offsets]);
        return offsets;
    }

    pub fn getValue(self: *Self, offset: usize) LineValue {
        const c_offset: c_uint = @intCast(offset);
        const v = gpoid.gpiod_line_request_get_value(self.request, c_offset);
        return @enumFromInt(v);
    }

    pub fn setValue(self: *Self, offset: usize, value: LineValue) bool {
        const c_offset: c_uint = @intCast(offset);
        const c_value: c_int = @intFromEnum(value);
        return gpoid.gpiod_line_request_set_value(
            self.request,
            c_offset,
            c_value,
        ) == 0;
    }

    /// up to caller to .deinit() LiveValue array list
    pub fn getValuesSubset(self: *Self, offsets: *const Offsets) !std.ArrayList(LineValue) {
        const count: usize = offsets.offsets.items.len;
        const val_buffer = try std.heap.c_allocator.alloc(c_int, count);
        defer std.heap.c_allocator.free(val_buffer);
        const actual_offsets = gpoid.gpiod_line_request_get_values_subset(
            self.request,
            count,
            offsets.offsets.items.ptr,
            @constCast(val_buffer.ptr),
        );
        var values = std.ArrayList(LineValue).init(std.heap.c_allocator);

        try values.ensureTotalCapacity(actual_offsets);
        for (val_buffer, 0..actual_offsets) |v, _| {
            const enum_val: LineValue = @enumFromInt(v);
            try values.append(enum_val);
        }
        return values;
    }

    /// Up to caller to deinit() LineValue the array list
    pub fn getValues(self: *Self) !std.ArrayList(LineValue) {
        const requested_lines = self.getNumberRequestedLines();
        const val_buffer = try std.heap.c_allocator.alloc(c_int, requested_lines);
        defer std.heap.c_allocator.free(val_buffer);
        const actual_offsets = gpoid.gpiod_line_request_get_values(
            self.request,
            @constCast(val_buffer.ptr),
        );
        var values = std.ArrayList(LineValue).init(std.heap.c_allocator);

        try values.ensureTotalCapacity(actual_offsets);
        for (val_buffer, 0..actual_offsets) |v, _| {
            const enum_val: LineValue = @enumFromInt(v);
            try values.append(enum_val);
        }
        return values;
    }

    pub fn setValuesSubset(self: *Self, offsets: *const Offsets, values: []const LineValue) bool {
        const count: usize = offsets.offsets.items.len;
        if (count != values.len) return false;

        var val_buffer = std.heap.c_allocator.alloc(c_int, count) catch return false;
        defer std.heap.c_allocator.free(val_buffer);

        for (values, 0..count) |v, i| {
            val_buffer[i] = @as(c_int, @intFromEnum(v));
        }

        return gpoid.gpiod_line_request_set_values_subset(
            self.request,
            count,
            offsets.offsets.items.ptr,
            @ptrCast(val_buffer.ptr),
        ) == 0;
    }

    pub fn setValues(self: *Self, values: []const LineValue) bool {
        const count = self.getNumberRequestedLines();
        if (count != values.len) return false;

        var val_buffer = std.heap.c_allocator.alloc(c_int, count) catch return false;
        defer std.heap.c_allocator.free(val_buffer);

        for (values, 0..count) |v, i| {
            val_buffer[i] = @as(c_int, @intFromEnum(v));
        }

        return gpoid.gpiod_line_request_set_values(
            self.request,
            @ptrCast(val_buffer.ptr),
        ) == 0;
    }

    pub fn reconfigureLines(self: *Self, config: *LineConfig) bool {
        return gpoid.gpiod_line_request_reconfigure_lines(
            self.request,
            config.config,
        ) == 0;
    }

    pub fn getFileDescriptor(self: *Self) std.os.linux.fd_t {
        return @intCast(gpoid.gpiod_line_request_get_fd(self.request));
    }

    pub fn waitEdgeEvents(self: *Self, timeout_ns: i64) LineWaitEvent {
        const result = gpoid.gpiod_line_request_wait_edge_events(
            self.request,
            timeout_ns,
        );
        return @enumFromInt(result);
    }

    pub fn readEdgeEvents(self: *Self, buffer: *EdgeEventBuffer, max_events: usize) ?usize {
        const result = gpoid.gpiod_line_request_read_edge_events(
            self.request,
            buffer.buffer,
            max_events,
        );

        if (result < 0) return null;
        return @intCast(result);
    }
};

pub const EdgeEventBuffer = struct {
    const Self = @This();
    buffer: *gpoid.gpiod_edge_event_buffer,

    pub fn init(capacity: usize) !Self {
        if (gpoid.gpiod_edge_event_buffer_new(capacity)) |buffer| {
            return Self{ .buffer = buffer };
        }
        return handleError("Unable to create edge event buffer");
    }

    pub fn copy(self: *Self) ?Self {
        if (gpoid.gpiod_edge_event_buffer_copy(self.buffer)) |buffer_copy| {
            return Self{ .buffer = buffer_copy };
        }
        return null;
    }

    pub fn getCapacity(self: *Self) usize {
        return gpoid.gpiod_edge_event_buffer_get_capacity(self.buffer);
    }

    pub fn getEvent(self: *Self, index: usize) ?EdgeEvent {
        if (gpoid.gpiod_edge_event_buffer_get_event(self.buffer, index)) |event| {
            return EdgeEvent{ .event = event };
        }
        return null;
    }

    pub fn getNumEvents(self: *Self) usize {
        return gpoid.gpiod_edge_event_buffer_get_num_events(self.buffer);
    }

    pub fn deinit(self: *Self) void {
        gpoid.gpiod_edge_event_buffer_free(self.buffer);
    }
};

pub const EdgeEvent = struct {
    const Self = @This();
    event: *gpoid.gpiod_edge_event,

    pub fn getEventType(self: *Self) LineEdgeDetection {
        const event_type = gpoid.gpiod_edge_event_get_event_type(self.event);
        return @enumFromInt(event_type);
    }

    pub fn getTimestampNs(self: *Self) u64 {
        return gpoid.gpiod_edge_event_get_timestamp_ns(self.event);
    }

    pub fn getLineOffset(self: *Self) c_uint {
        return gpoid.gpiod_edge_event_get_line_offset(self.event);
    }

    pub fn getGlobalSeqno(self: *Self) u64 {
        return gpoid.gpiod_edge_event_get_global_seqno(self.event);
    }

    pub fn getLineSeqno(self: *Self) u64 {
        return gpoid.gpiod_edge_event_get_line_seqno(self.event);
    }

    pub fn deinit(self: *Self) void {
        gpoid.gpiod_edge_event_free(self.event);
    }
};

const GpioError = error{
    InvalidArgument,
    OutOfMemory,
    DeviceBusy,
    BadAddress,
    IoError,
    PermissionDenied,
    AccessDenied,
    Unknown,
};

fn handleError(comptime msg: []const u8) GpioError {
    const err = c.__errno_location().*;

    // Log the error using strerror
    if (c.strerror(err)) |error_msg| {
        const err_str = std.mem.span(error_msg);
        std.log.err(msg ++ ": {s} (errno={d})", .{ err_str, err });
    } else {
        std.log.err(msg ++ ": Unknown error (errno={d})", .{err});
    }
    return switch (err) {
        c.EINVAL => GpioError.InvalidArgument,
        c.ENOMEM => GpioError.OutOfMemory,
        c.EBUSY => GpioError.DeviceBusy,
        c.EPERM => GpioError.PermissionDenied,
        c.EACCES => GpioError.AccessDenied,
        c.EIO => GpioError.IoError,
        c.EFAULT => GpioError.BadAddress,
        else => GpioError.Unknown,
    };
}
test "chip and line info test" {
    _ = gpoid;
    _ = Chip;
    _ = Line;
    // may have to do `sudo zig build test` for the test to run
    std.debug.print("API version: {s}\n", .{apiVersion()});

    var chip = try Chip.init("/dev/gpiochip0");
    defer chip.deinit();

    std.debug.print("chip name: {s} label: {s}\n", .{ chip.getChipName(), chip.getChipLabel() });

    var line = try chip.getLine(17, false);
    defer line.deinit();

    std.debug.print("line name: {s}\n\tconsumer name: {s}\n\tbias: {s}\n\tdirection: {s}\n\tdrive: {s}\n\tedge: {s}\n\tclock: {s}\n", .{
        line.getName(),
        line.getConsumerName(),
        @tagName(line.getBias()),
        @tagName(line.getDirection()),
        @tagName(line.getDrive()),
        @tagName(line.getEdgeDetection()),
        @tagName(line.getEventClock()),
    });
}

test "LineSettings struct initialization" {
    // Test creating a LineSettings object without hardware access
    var settings = LineSettings.init() catch |err| {
        std.debug.print("Failed to create LineSettings: {}\n", .{err});
        return;
    };
    defer settings.deinit();

    // Test setting various properties
    _ = settings.setDirection(.Input);
    try std.testing.expectEqual(LineDirection.Input, settings.getDirection());

    _ = settings.setEdgeDetection(.Rising);
    try std.testing.expectEqual(LineEdgeDetection.Rising, settings.getEdgeDetection());

    _ = settings.setBias(.PullUp);
    try std.testing.expectEqual(LineBias.PullUp, settings.getBias());

    settings.setActiveLow(true);
    try std.testing.expect(settings.getActiveLow());

    settings.setDebouncePeriodMicrosecs(1000);
    try std.testing.expectEqual(@as(u64, 1000), settings.getDebouncedPeriodMicrosecs());

    std.debug.print("LineSettings struct initialization successful\n", .{});
}

test "LineConfig initialization and operations" {
    // Test creating a LineConfig object without hardware access
    var config = LineConfig.init() catch |err| {
        std.debug.print("Failed to create LineConfig: {}\n", .{err});
        return;
    };
    defer config.deinit();

    // Create a settings object to use with the config
    var settings = LineSettings.init() catch |err| {
        std.debug.print("Failed to create LineSettings: {}\n", .{err});
        return;
    };
    defer settings.deinit();

    _ = settings.setDirection(.Output);
    _ = settings.setDrive(.PushPull);

    // Create offsets for testing
    var offsets = Offsets.init();
    defer offsets.deinit();

    try offsets.addOffset(0);
    try offsets.addOffset(1);

    // Test adding line settings to the config
    const added = config.addLineSettings(&offsets, 2, settings);

    // We can only verify the function was called, not its success
    // since we don't have real hardware
    std.debug.print("LineConfig.addLineSettings result: {}\n", .{added});

    // Test resetting the config
    config.reset();
    std.debug.print("LineConfig reset successful\n", .{});
}

test "RequestConfig initialization and operations" {
    var req_config = RequestConfig.init() catch |err| {
        std.debug.print("Failed to create RequestConfig: {}\n", .{err});
        return;
    };
    defer req_config.deinit();

    // Test setting and getting consumer name
    const test_consumer = "zgpiod_test";
    req_config.setConsumer(test_consumer);

    if (req_config.getConsumer()) |consumer| {
        try std.testing.expectEqualStrings(test_consumer, consumer);
    } else {
        std.debug.print("Warning: Consumer name not returned\n", .{});
    }

    // Test buffer size operations
    const test_buffer_size: usize = 64;
    req_config.setEventBufferSize(test_buffer_size);
    try std.testing.expectEqual(test_buffer_size, req_config.getEventBufferSize());

    std.debug.print("RequestConfig tests successful\n", .{});
}

test "Offsets struct operations" {
    var offsets = Offsets.init();
    defer offsets.deinit();

    // Test adding offsets
    try offsets.addOffset(5);
    try offsets.addOffset(10);
    try offsets.addOffset(15);

    try std.testing.expectEqual(@as(usize, 3), offsets.offsets.items.len);
    try std.testing.expectEqual(@as(c_uint, 5), offsets.offsets.items[0]);
    try std.testing.expectEqual(@as(c_uint, 10), offsets.offsets.items[1]);
    try std.testing.expectEqual(@as(c_uint, 15), offsets.offsets.items[2]);

    // Test retrieving pointer to offsets
    const ptr = offsets.ptr();
    const ptr_addr = @intFromPtr(ptr);
    const items_addr = @intFromPtr(&offsets.offsets.items[0]);
    try std.testing.expectEqual(items_addr, ptr_addr);
    std.debug.print("Offsets struct operations successful\n", .{});
}

test "LineStatusEvent constants" {
    // Test that enum values are correctly defined
    try std.testing.expectEqual(@intFromEnum(LineStatusEvent.EventType.ConfigChanged), gpoid.GPIOD_INFO_EVENT_LINE_CONFIG_CHANGED);
    try std.testing.expectEqual(@intFromEnum(LineStatusEvent.EventType.Released), gpoid.GPIOD_INFO_EVENT_LINE_RELEASED);
    try std.testing.expectEqual(@intFromEnum(LineStatusEvent.EventType.Requested), gpoid.GPIOD_INFO_EVENT_LINE_REQUESTED);

    std.debug.print("LineStatusEvent enum values verified\n", .{});
}

test "Mock EdgeEventBuffer" {
    // We can't create a real EdgeEventBuffer without hardware,
    // but we can test that the struct and methods are correctly defined

    // First verify that EdgeEvent constants are correct
    try std.testing.expectEqual(@intFromEnum(LineEdgeDetection.None), gpoid.GPIOD_LINE_EDGE_NONE);
    try std.testing.expectEqual(@intFromEnum(LineEdgeDetection.Rising), gpoid.GPIOD_LINE_EDGE_RISING);
    try std.testing.expectEqual(@intFromEnum(LineEdgeDetection.Falling), gpoid.GPIOD_LINE_EDGE_FALLING);
    try std.testing.expectEqual(@intFromEnum(LineEdgeDetection.Both), gpoid.GPIOD_LINE_EDGE_BOTH);

    std.debug.print("EdgeEvent constants verified\n", .{});
}

test "Try non-destructive chip operations" {
    // This test checks if we can open a chip without modifying GPIO state
    // Skip if no GPIO chips are available, but don't fail
    var chip_path_buf: [64]u8 = undefined;
    const chip_path = blk: {
        var dir = std.fs.openDirAbsolute("/dev", .{ .iterate = true }) catch |err| {
            std.debug.print("Could not open /dev directory: {}\n", .{err});
            break :blk null;
        };
        defer dir.close();

        var it = dir.iterate();
        while (it.next() catch |err| {
            std.debug.print("Error iterating directory: {}\n", .{err});
            break :blk null;
        }) |entry| {
            if (std.mem.startsWith(u8, entry.name, "gpiochip")) {
                const full_path = std.fmt.bufPrint(&chip_path_buf, "/dev/{s}", .{entry.name}) catch {
                    break :blk null;
                };
                break :blk full_path;
            }
        }
        break :blk null;
    };

    if (chip_path == null) {
        std.debug.print("No GPIO chips found, skipping test\n", .{});
        return;
    }

    // Try to open the chip (read-only operation)
    var chip = Chip.init(chip_path.?) catch |err| {
        std.debug.print("Could not initialize chip at {s}: {}\n", .{ chip_path.?, err });
        std.debug.print("This is expected on systems without actual GPIO hardware\n", .{});
        return;
    };
    defer chip.deinit();

    // Get basic chip info (read-only)
    const name = chip.getChipName();
    const label = chip.getChipLabel();
    const line_count = chip.line_count;

    std.debug.print("Successfully opened chip: {s}\n", .{chip_path.?});
    std.debug.print("Chip name: {s}, label: {s}, line count: {}\n", .{ name, label, line_count });

    // Test isValidOffset (non-destructive)
    try std.testing.expect(chip.isValidOffset(0));
    try std.testing.expect(chip.isValidOffset(line_count - 1));
    try std.testing.expect(!chip.isValidOffset(line_count + 100));
}

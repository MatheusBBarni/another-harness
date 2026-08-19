const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Period = enum { weekly, monthly, unknown };

pub const Snapshot = struct {
    plan: []u8,
    percent: u8,
    period: Period,
    reset_at: ?[]u8 = null,
    prepaid_cents: ?i64 = null,

    pub fn deinit(self: *Snapshot, alloc: Allocator) void {
        alloc.free(self.plan);
        if (self.reset_at) |value| alloc.free(value);
        self.* = undefined;
    }
};

fn parseBilling(alloc: Allocator, json: []const u8) !Snapshot {
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidGrokBilling;
    const root = parsed.value.object;
    const config_value = root.get("config") orelse return error.InvalidGrokBilling;
    if (config_value != .object) return error.InvalidGrokBilling;
    const config = config_value.object;

    const plan = try parsePlan(alloc, root);
    errdefer alloc.free(plan);
    const percent = try parsePercent(config);
    const period = parsePeriod(config);
    const reset_at = try parseResetAt(alloc, config);
    errdefer if (reset_at) |value| alloc.free(value);
    return .{
        .plan = plan,
        .percent = percent,
        .period = period,
        .reset_at = reset_at,
        .prepaid_cents = parsePrepaidCents(config),
    };
}

fn parsePlan(alloc: Allocator, root: std.json.ObjectMap) ![]u8 {
    if (root.get("subscription_tier")) |value| {
        if (value == .string and value.string.len > 0) return alloc.dupe(u8, value.string);
    }
    if (root.get("subscriptionTier")) |value| {
        if (value == .string and value.string.len > 0) return alloc.dupe(u8, value.string);
    }
    return alloc.dupe(u8, "SuperGrok");
}

fn parsePercent(config: std.json.ObjectMap) !u8 {
    const raw = config.get("creditUsagePercent") orelse config.get("credit_usage_percent") orelse
        return error.InvalidGrokBilling;
    if (raw != .float and raw != .integer) return error.InvalidGrokBilling;
    const value: f64 = if (raw == .float) raw.float else @floatFromInt(raw.integer);
    if (!std.math.isFinite(value) or value < 0 or value > 100.5) return error.InvalidGrokBilling;
    return @intFromFloat(@round(@min(100.0, @max(0.0, value))));
}

fn parsePeriod(config: std.json.ObjectMap) Period {
    const current = config.get("currentPeriod") orelse config.get("current_period") orelse return .unknown;
    if (current != .object) return .unknown;
    const type_value = current.object.get("type") orelse return .unknown;
    if (type_value != .string) return .unknown;
    if (std.mem.endsWith(u8, type_value.string, "WEEKLY")) return .weekly;
    if (std.mem.endsWith(u8, type_value.string, "MONTHLY")) return .monthly;
    return .unknown;
}

fn parseResetAt(alloc: Allocator, config: std.json.ObjectMap) !?[]u8 {
    const current = config.get("currentPeriod") orelse config.get("current_period") orelse return null;
    if (current != .object) return null;
    const end = current.object.get("end") orelse return null;
    if (end != .string) return error.InvalidGrokBilling;
    return try normalizeResetAt(alloc, end.string);
}

fn normalizeResetAt(alloc: Allocator, text: []const u8) ![]u8 {
    if (text.len < 19 or text[10] != 'T') return error.InvalidGrokBilling;
    var millis = [_]u8{ '0', '0', '0' };
    if (text.len > 20 and text[19] == '.') {
        var i: usize = 20;
        while (i < text.len and std.ascii.isDigit(text[i])) i += 1;
        const digits = text[20..i];
        const count = @min(digits.len, 3);
        @memcpy(millis[0..count], digits[0..count]);
    }
    return std.fmt.allocPrint(alloc, "{s}.{s}Z", .{ text[0..19], millis });
}

fn parsePrepaidCents(config: std.json.ObjectMap) ?i64 {
    const prepaid = config.get("prepaidBalance") orelse config.get("prepaid_balance") orelse return null;
    if (prepaid != .object) return null;
    const val = prepaid.object.get("val") orelse return 0;
    return switch (val) {
        .integer => |n| n,
        .string => |text| std.fmt.parseInt(i64, std.mem.trim(u8, text, " \t"), 10) catch null,
        else => null,
    };
}

test "billing json becomes a super grok usage snapshot" {
    const json =
        \\{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-08-24T17:33:48.278812+00:00"},"creditUsagePercent":12.4,"prepaidBalance":{"val":250}},"subscription_tier":"SuperGrok"}
    ;
    var snapshot = try parseBilling(std.testing.allocator, json);
    defer snapshot.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("SuperGrok", snapshot.plan);
    try std.testing.expectEqual(@as(u8, 12), snapshot.percent);
    try std.testing.expectEqual(Period.weekly, snapshot.period);
    try std.testing.expectEqualStrings("2026-08-24T17:33:48.278Z", snapshot.reset_at.?);
    try std.testing.expectEqual(@as(i64, 250), snapshot.prepaid_cents.?);
}

test "credits and xai-usage render snapshot; 401 asks for relogin without leaking the token" {
    const json =
        \\{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","end":"2026-08-24T17:33:48.278812+00:00"},"creditUsagePercent":12.4,"prepaidBalance":{"val":250}},"subscription_tier":"SuperGrok"}
    ;
    var snapshot = try parseBilling(std.testing.allocator, json);
    defer snapshot.deinit(std.testing.allocator);

    const credits = try renderCreditsText(std.testing.allocator, snapshot);
    defer std.testing.allocator.free(credits);
    try std.testing.expect(std.mem.indexOf(u8, credits, "SuperGrok") != null);
    try std.testing.expect(std.mem.indexOf(u8, credits, "12% weekly") != null);
    try std.testing.expect(std.mem.indexOf(u8, credits, "$2.50") != null);

    const usage = try renderXaiUsageText(std.testing.allocator, snapshot, null);
    defer std.testing.allocator.free(usage);
    try std.testing.expectEqualStrings(
        "SuperGrok 12% weekly · resets 2026-08-24T17:33:48.278Z · prepaid $2.50",
        usage,
    );

    const leaked = "sk-secret-token-value";
    const err401 = try renderBillingHttpError(std.testing.allocator, 401, leaked);
    defer std.testing.allocator.free(err401);
    try std.testing.expect(std.mem.indexOf(u8, err401, "fx login grok") != null);
    try std.testing.expect(std.mem.indexOf(u8, err401, leaked) == null);

    const err403 = try renderBillingHttpError(std.testing.allocator, 403, leaked);
    defer std.testing.allocator.free(err403);
    try std.testing.expect(std.mem.indexOf(u8, err403, "fx login grok") != null);
    try std.testing.expect(std.mem.indexOf(u8, err403, leaked) == null);
}

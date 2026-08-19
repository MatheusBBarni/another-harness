const std = @import("std");

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

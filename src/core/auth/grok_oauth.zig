const std = @import("std");
const oauth = @import("oauth.zig");
const oauth_transport = @import("oauth_transport.zig");

const Allocator = std.mem.Allocator;

test "grok device authorization posts client id, grok scopes, and another-harness referrer" {
    var probe = TransportProbe{
        .expected_method = .post_form,
        .expected_url = "https://auth.x.ai/oauth2/device/code",
        .expected_payload = "client_id=b1a00492-073a-47ea-816f-4c329264a828&scope=openid%20profile%20email%20offline_access%20grok-cli%3Aaccess%20api%3Aaccess&referrer=another-harness",
        .response_body = "{\"device_code\":\"device\",\"user_code\":\"CODE\",\"verification_uri\":\"https://auth.x.ai/oauth/device\",\"expires_in\":600,\"interval\":5}",
    };

    var device = try requestDeviceAuthorization(std.testing.allocator, probe.provider());
    defer device.deinit(std.testing.allocator);

    try std.testing.expect(probe.matched);
    try std.testing.expectEqualStrings("device", device.device_code);
    try std.testing.expectEqualStrings("CODE", device.user_code);
    try std.testing.expectEqualStrings("https://auth.x.ai/oauth/device", device.verification_uri);
}

const TransportProbe = struct {
    expected_method: oauth_transport.Method,
    expected_url: []const u8,
    expected_payload: ?[]const u8 = null,
    response_disposition: oauth_transport.Disposition = .accepted,
    response_body: []const u8,
    matched: bool = false,

    fn provider(self: *TransportProbe) oauth_transport.Provider {
        return .{
            .context = self,
            .execute_fn = execute,
        };
    }

    fn execute(
        raw: ?*anyopaque,
        alloc: Allocator,
        request: oauth_transport.Request,
    ) !oauth_transport.Response {
        const self: *TransportProbe = @ptrCast(@alignCast(raw.?));
        self.matched = request.method == self.expected_method and
            std.mem.eql(u8, request.url, self.expected_url) and
            optionalBytesEqual(request.payload, self.expected_payload);
        return .{
            .disposition = self.response_disposition,
            .body = try alloc.dupe(u8, self.response_body),
        };
    }
};

fn optionalBytesEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

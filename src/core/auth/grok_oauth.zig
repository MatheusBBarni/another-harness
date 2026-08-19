const std = @import("std");
const oauth = @import("oauth.zig");
const oauth_transport = @import("oauth_transport.zig");
const secret = @import("secret.zig");

const Allocator = std.mem.Allocator;

test {
    _ = @import("grok_session.zig");
}

pub const client_id = "b1a00492-073a-47ea-816f-4c329264a828";
pub const scope = "openid profile email offline_access grok-cli:access api:access";
pub const referrer = "another-harness";
pub const issuer = "https://auth.x.ai";
const device_code_url = "https://auth.x.ai/oauth2/device/code";
const token_url = "https://auth.x.ai/oauth2/token";

fn requestDeviceAuthorization(
    alloc: Allocator,
    transport: oauth_transport.Provider,
) !oauth.DeviceAuthorization {
    var form: FormBody = .{};
    var writer: std.Io.Writer.Allocating = .init(alloc);
    defer writer.deinit();
    try form.append(&writer.writer, "client_id", client_id);
    try form.append(&writer.writer, "scope", scope);
    try form.append(&writer.writer, "referrer", referrer);

    var response = try transport.execute(alloc, .{
        .method = .post_form,
        .payload = writer.written(),
        .url = device_code_url,
    });
    defer response.deinit(alloc);
    if (response.disposition != .accepted) return oauth.OAuthError.OAuthRequestFailed;
    const bytes = response.takeBody();
    defer secret.zeroAndFree(alloc, bytes);
    return oauth.parseDeviceAuthorization(alloc, bytes);
}

fn refreshAccessToken(
    alloc: Allocator,
    transport: oauth_transport.Provider,
    refresh_token: []const u8,
) !oauth.TokenSet {
    var form: FormBody = .{};
    var writer: std.Io.Writer.Allocating = .init(alloc);
    defer writer.deinit();
    try form.append(&writer.writer, "client_id", client_id);
    try form.append(&writer.writer, "grant_type", "refresh_token");
    try form.append(&writer.writer, "refresh_token", refresh_token);

    var response = try transport.execute(alloc, .{
        .method = .post_form,
        .payload = writer.written(),
        .url = token_url,
    });
    defer response.deinit(alloc);
    if (response.disposition != .accepted) return oauth.OAuthError.OAuthRequestFailed;
    const bytes = response.takeBody();
    defer secret.zeroAndFree(alloc, bytes);
    return oauth.parseTokenSet(alloc, bytes);
}

const FormBody = struct {
    first: bool = true,

    fn append(self: *FormBody, writer: *std.Io.Writer, key: []const u8, value: []const u8) !void {
        if (!self.first) try writer.writeAll("&");
        self.first = false;
        try percentEncode(writer, key);
        try writer.writeAll("=");
        try percentEncode(writer, value);
    }
};

fn percentEncode(writer: *std.Io.Writer, value: []const u8) !void {
    const hex = "0123456789ABCDEF";
    for (value) |byte| {
        const safe = std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.' or byte == '~';
        if (safe) {
            try writer.writeByte(byte);
        } else {
            try writer.writeByte('%');
            try writer.writeByte(hex[byte >> 4]);
            try writer.writeByte(hex[byte & 0x0f]);
        }
    }
}

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

test "grok refresh posts refresh_token grant to auth.x.ai" {
    var probe = TransportProbe{
        .expected_method = .post_form,
        .expected_url = "https://auth.x.ai/oauth2/token",
        .expected_payload = "client_id=b1a00492-073a-47ea-816f-4c329264a828&grant_type=refresh_token&refresh_token=old-refresh",
        .response_body = "{\"access_token\":\"new-access\",\"refresh_token\":\"new-refresh\",\"expires_in\":3600,\"scope\":\"openid offline_access\",\"token_type\":\"Bearer\"}",
    };

    var tokens = try refreshAccessToken(std.testing.allocator, probe.provider(), "old-refresh");
    defer tokens.deinit(std.testing.allocator);

    try std.testing.expect(probe.matched);
    try std.testing.expectEqualStrings("new-access", tokens.access_token);
    try std.testing.expectEqualStrings("new-refresh", tokens.refresh_token.?);
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

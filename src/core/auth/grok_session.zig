const std = @import("std");
const grok_oauth = @import("grok_oauth.zig");
const oauth = @import("oauth.zig");
const oauth_session = @import("oauth_session.zig");
const secret = @import("secret.zig");

const Allocator = std.mem.Allocator;

const schema_version: i64 = 1;

pub const Session = struct {
    issuer: []u8,
    client_id: []u8,
    access_token: []u8,
    refresh_token: []u8,
    expires_at_ms: i64,
    scope: []u8,
    token_type: []u8,

    pub fn deinit(self: *Session, alloc: Allocator) void {
        alloc.free(self.issuer);
        alloc.free(self.client_id);
        secret.zeroAndFree(alloc, self.access_token);
        secret.zeroAndFree(alloc, self.refresh_token);
        alloc.free(self.scope);
        alloc.free(self.token_type);
        self.* = undefined;
    }
};

fn takeLoginSession(alloc: Allocator, token: *oauth.TokenSet, now_ms: i64) !Session {
    const refresh_token = token.refresh_token orelse return error.NoRefreshToken;
    const expires_at_ms = try oauth.expiry_timestamp_ms(now_ms, token.expires_in);
    const owned_issuer = try alloc.dupe(u8, grok_oauth.issuer);
    errdefer alloc.free(owned_issuer);
    const owned_client_id = try alloc.dupe(u8, grok_oauth.client_id);
    errdefer alloc.free(owned_client_id);

    const session = Session{
        .issuer = owned_issuer,
        .client_id = owned_client_id,
        .access_token = token.access_token,
        .refresh_token = refresh_token,
        .expires_at_ms = expires_at_ms,
        .scope = token.scope,
        .token_type = token.token_type,
    };
    token.access_token = &.{};
    token.refresh_token = null;
    token.scope = &.{};
    token.token_type = &.{};
    return session;
}

fn stringify(alloc: Allocator, session: Session) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    const writer = &out.writer;
    try writer.writeAll("{\"version\":1");
    try writeField(writer, "issuer", session.issuer);
    try writeField(writer, "client_id", session.client_id);
    try writeField(writer, "access_token", session.access_token);
    try writeField(writer, "refresh_token", session.refresh_token);
    try writer.print(",\"expires_at_ms\":{d}", .{session.expires_at_ms});
    try writeField(writer, "scope", session.scope);
    try writeField(writer, "token_type", session.token_type);
    try writer.writeAll("}\n");
    return out.toOwnedSlice();
}

fn parse(alloc: Allocator, bytes: []const u8) !Session {
    var parsed = try std.json.parseFromSlice(std.json.Value, alloc, bytes, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidAuthSession;
    const object = parsed.value.object;
    const version = object.get("version") orelse return error.InvalidAuthSession;
    if (version != .integer or version.integer != schema_version) return error.InvalidAuthSession;
    const saved_issuer = try requiredString(object, "issuer");
    if (!std.mem.eql(u8, saved_issuer, grok_oauth.issuer)) return error.InvalidAuthSession;

    const expires_at_ms = try requiredInteger(object, "expires_at_ms");
    const owned_issuer = try alloc.dupe(u8, saved_issuer);
    errdefer alloc.free(owned_issuer);
    const client_id = try dupeRequiredString(alloc, object, "client_id");
    errdefer alloc.free(client_id);
    const access_token = try dupeRequiredString(alloc, object, "access_token");
    errdefer secret.zeroAndFree(alloc, access_token);
    const refresh_token = try dupeRequiredString(alloc, object, "refresh_token");
    errdefer secret.zeroAndFree(alloc, refresh_token);
    const scope = try dupeRequiredString(alloc, object, "scope");
    errdefer alloc.free(scope);
    const token_type = try dupeRequiredString(alloc, object, "token_type");
    errdefer alloc.free(token_type);

    return .{
        .issuer = owned_issuer,
        .client_id = client_id,
        .access_token = access_token,
        .refresh_token = refresh_token,
        .expires_at_ms = expires_at_ms,
        .scope = scope,
        .token_type = token_type,
    };
}

fn writeField(writer: *std.Io.Writer, name: []const u8, value: []const u8) !void {
    try writer.writeAll(",");
    try std.json.Stringify.value(name, .{}, writer);
    try writer.writeAll(":");
    try std.json.Stringify.value(value, .{}, writer);
}

fn dupeRequiredString(alloc: Allocator, object: std.json.ObjectMap, key: []const u8) ![]u8 {
    return alloc.dupe(u8, try requiredString(object, key));
}

fn requiredString(object: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = object.get(key) orelse return error.InvalidAuthSession;
    if (value != .string or value.string.len == 0) return error.InvalidAuthSession;
    return value.string;
}

fn requiredInteger(object: std.json.ObjectMap, key: []const u8) !i64 {
    const value = object.get(key) orelse return error.InvalidAuthSession;
    if (value != .integer) return error.InvalidAuthSession;
    return value.integer;
}

test "grok token response becomes a session with auth.x.ai issuer" {
    var token = try oauth.parseTokenSet(
        std.testing.allocator,
        "{\"access_token\":\"access\",\"refresh_token\":\"refresh\",\"expires_in\":3600,\"scope\":\"openid profile email offline_access grok-cli:access api:access\",\"token_type\":\"Bearer\"}",
    );
    defer token.deinit(std.testing.allocator);

    var session = try takeLoginSession(std.testing.allocator, &token, 1_000);
    defer session.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), token.access_token.len);
    try std.testing.expect(token.refresh_token == null);

    const text = try stringify(std.testing.allocator, session);
    defer secret.zeroAndFree(std.testing.allocator, text);

    try std.testing.expectError(error.InvalidAuthSession, oauth_session.parse(std.testing.allocator, text));

    var parsed = try parse(std.testing.allocator, text);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("https://auth.x.ai", parsed.issuer);
    try std.testing.expectEqualStrings("b1a00492-073a-47ea-816f-4c329264a828", parsed.client_id);
    try std.testing.expectEqualStrings("access", parsed.access_token);
    try std.testing.expectEqualStrings("refresh", parsed.refresh_token);
    try std.testing.expectEqual(@as(i64, 3_601_000), parsed.expires_at_ms);
    try std.testing.expectEqualStrings("openid profile email offline_access grok-cli:access api:access", parsed.scope);
    try std.testing.expectEqualStrings("Bearer", parsed.token_type);
}

test "logout deletes both session files even when one is missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const io = std.testing.io;

    var both = try tmp.dir.makeOpenPath(io, "both", .{});
    defer both.close(io);
    {
        var file = try both.createFile(io, "auth.json", .{});
        file.close(io);
    }
    {
        var file = try both.createFile(io, "grok-auth.json", .{});
        file.close(io);
    }
    try deleteSessionFiles(&both);
    try std.testing.expectError(error.FileNotFound, both.statFile(io, "auth.json", .{}));
    try std.testing.expectError(error.FileNotFound, both.statFile(io, "grok-auth.json", .{}));

    var only_grok = try tmp.dir.makeOpenPath(io, "only-grok", .{});
    defer only_grok.close(io);
    {
        var file = try only_grok.createFile(io, "grok-auth.json", .{});
        file.close(io);
    }
    try deleteSessionFiles(&only_grok);
    try std.testing.expectError(error.FileNotFound, only_grok.statFile(io, "grok-auth.json", .{}));

    var neither = try tmp.dir.makeOpenPath(io, "neither", .{});
    defer neither.close(io);
    try deleteSessionFiles(&neither);
}

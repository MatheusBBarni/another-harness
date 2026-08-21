const std = @import("std");

pub const Id = enum {
    vercel,
    codex,

    pub fn slug(self: Id) []const u8 {
        return switch (self) {
            .vercel => "vercel",
            .codex => "codex",
        };
    }
};

pub const Entry = struct {
    id: Id,
    name: []const u8,
    description: []const u8,
    subscription: bool,
};

pub const entries = [_]Entry{
    .{
        .id = .vercel,
        .name = "Vercel AI Gateway",
        .description = "Vercel account or AI Gateway billing",
        .subscription = false,
    },
    .{
        .id = .codex,
        .name = "Codex",
        .description = "ChatGPT Plus, Pro, Business, Enterprise, or Edu subscription",
        .subscription = true,
    },
};

pub fn parse(value: []const u8) ?Id {
    if (std.ascii.eqlIgnoreCase(value, "vercel") or
        std.ascii.eqlIgnoreCase(value, "ai-gateway")) return .vercel;
    if (std.ascii.eqlIgnoreCase(value, "codex")) return .codex;
    return null;
}

pub fn find(id: Id) *const Entry {
    for (&entries) |*entry| if (entry.id == id) return entry;
    unreachable;
}

test "auth provider catalog exposes codex without unreleased aliases" {
    try std.testing.expectEqual(Id.vercel, parse("vercel").?);
    try std.testing.expectEqual(Id.codex, parse("codex").?);
    try std.testing.expect(parse("openai-codex") == null);
    try std.testing.expect(parse("chatgpt") == null);
    try std.testing.expect(parse("unknown") == null);
    try std.testing.expect(find(.codex).subscription);
}

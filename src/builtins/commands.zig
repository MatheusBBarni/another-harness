const std = @import("std");
const builtin = @import("builtin");
const stream_provider = @import("../core/agent/stream_provider.zig");
const adapter_registry = @import("../core/gateway/adapter_registry.zig");
const command_specs = @import("../core/slash_commands/command_specs.zig");

const Allocator = std.mem.Allocator;

pub const TopLevelKind = command_specs.TopLevelKind;
pub const TopLevelSpec = command_specs.TopLevelSpec;
pub const TopLevelHelpEntry = command_specs.TopLevelHelpEntry;
pub const TopLevelHelpGroup = command_specs.TopLevelHelpGroup;
pub const TopLevelFlag = command_specs.TopLevelFlag;
pub const TopLevelExample = command_specs.TopLevelExample;
pub const TopLevelResource = command_specs.TopLevelResource;
pub const TopLevelRegistry = command_specs.TopLevelRegistry;
pub const HelpStyle = command_specs.HelpStyle;
pub const SlashKind = command_specs.SlashKind;
pub const SlashPresentationCategory = command_specs.SlashPresentationCategory;
pub const SlashSpec = command_specs.SlashSpec;
pub const SlashRegistry = command_specs.SlashRegistry;

const json_option = command_specs.OptionDoc{ .flag = "--json", .description = "Emit machine-readable JSON instead of text" };

const top_level_blueprint = [_]TopLevelSpec{
    .{
        .kind = .help,
        .token = "help",
        .aliases = &.{ "--help", "-h" },
        .usage = "help",
        .summary = "Show this help",
    },
    .{
        .kind = .ask,
        .token = "ask",
        .usage = "ask [--auto|--yolo] [--image PATH] [--json] [--no-save] [--no-color] [--resume <last|id>|--resume-id <id>] [--continue-recovery] [--] <prompt>",
        .summary = "Run one noninteractive request",
        .options = &.{
            .{ .flag = "--auto", .description = "Automatically review unresolved permission requests" },
            .{ .flag = "--yolo", .description = "Disable permission checks and command sandboxing" },
            .{ .flag = "--image PATH", .description = "Attach an image file; repeat for multiple images" },
            json_option,
            .{ .flag = "--no-save", .description = "Do not save the session; incompatible with --resume and --resume-id" },
            .{ .flag = "--no-color", .description = "Render TTY output without colors or hyperlinks" },
            .{ .flag = "--resume <last|id>", .description = "Continue the last session or a session by id" },
            .{ .flag = "--resume-id <id>", .description = "Continue a session by exact id" },
            .{ .flag = "--continue-recovery", .description = "Resume the paused model response in the selected session" },
            .{ .flag = "--", .description = "Treat every following argument as prompt text" },
        },
        .details = &.{
            "The prompt may be passed as arguments or piped on stdin when no prompt args are given.",
            "TTY stdout uses the Minimal transcript presentation; redirected stdout emits raw assistant Markdown.",
            "Operational progress and diagnostics are written to stderr. JSON output keeps raw Markdown in `output`.",
        },
    },
    .{
        .kind = .acp,
        .token = "acp",
        .usage = "acp [--model <id>] [--log-file <path>]",
        .summary = "Start an ACP server over stdio",
        .options = &.{
            .{ .flag = "--model <id>", .description = "Override the default model" },
            .{ .flag = "--log-file <path>", .description = "Write ACP logs to a file" },
        },
    },
    .{
        .kind = .pr,
        .token = "pr",
        .usage = "pr [--auto] [--create] [context]",
        .summary = "Draft or publish a pull request",
        .options = &.{
            .{ .flag = "--auto", .description = "Automatically review unresolved permission requests" },
            .{ .flag = "--create", .description = "Publish the drafted pull request via the GitHub CLI" },
        },
        .details = &.{
            "Must run inside a git repository. Without --create, the drafted PR is printed only.",
        },
    },
    .{
        .kind = .issue,
        .token = "issue",
        .usage = "issue [--auto] [--create] [context]",
        .summary = "Draft or publish a GitHub issue",
        .options = &.{
            .{ .flag = "--auto", .description = "Automatically review unresolved permission requests" },
            .{ .flag = "--create", .description = "Publish the drafted issue via the GitHub CLI" },
        },
    },
    .{
        .kind = .login,
        .token = "login",
        .usage = "login",
        .summary = "",
    },
    .{
        .kind = .logout,
        .token = "logout",
        .usage = "logout",
        .summary = "",
    },
    .{
        .kind = .setup,
        .token = "setup",
        .usage = "setup",
        .summary = "Configure an AI Gateway API key",
    },
    .{
        .kind = .status,
        .token = "status",
        .usage = "status [--json]",
        .summary = "Show configuration and runtime information",
        .options = &.{json_option},
    },
    .{
        .kind = .permissions,
        .token = "permissions",
        .usage = "permissions [--json]",
        .summary = "Show the permission mode and rules",
        .options = &.{json_option},
        .details = &.{
            "Modes:",
            "  ask    Prompt before sensitive tool calls",
            "  auto   Apply rules, then review unresolved sensitive tool calls (default)",
            "  yolo   Disable fx permissions and sandboxing",
            "",
            "Change the mode from the interactive shell with `/permissions [ask|auto|yolo|reset]`,",
            "and manage persistent allow rules with `/allowlist`.",
        },
    },
    .{
        .kind = .models,
        .token = "models",
        .usage = "models [--json]",
        .summary = "List available models",
        .options = &.{json_option},
    },
    .{
        .kind = .doctor,
        .token = "doctor",
        .usage = "doctor [--json]",
        .summary = "Run local health and preflight checks",
        .options = &.{json_option},
    },
    .{
        .kind = .background,
        .token = "background",
        .usage = "background [last|<id>] [--json]",
        .summary = "List or inspect background commands",
        .options = &.{
            .{ .flag = "last", .description = "Inspect the most recent background command" },
            .{ .flag = "<id>", .description = "Inspect a background command by id" },
            json_option,
        },
        .details = &.{
            "With no target, lists the persisted background command history.",
        },
    },
    .{
        .kind = .teams,
        .token = "teams",
        .usage = "teams",
        .summary = "",
    },
    .{
        .kind = .session,
        .token = "session",
        .usage = "session <last|id>|--id <id> [--json] | session migrate <id>|--id <id> [--allow-large] [--json] | session recover <id>|--id <id> [--json]",
        .summary = "Inspect one saved session",
        .options = &.{
            .{ .flag = "last", .description = "Inspect the current workspace session" },
            .{ .flag = "--id <id>", .description = "Inspect a saved session by exact id" },
            .{ .flag = "migrate <id>", .description = "Migrate a saved session to the current format" },
            .{ .flag = "recover <id>", .description = "Copy a recoverable corrupt session into a new session" },
            .{ .flag = "--allow-large", .description = "Permit migrating an oversized session" },
            json_option,
        },
    },
    .{
        .kind = .sessions,
        .token = "sessions",
        .usage = "sessions [--all] [--limit <1-100>] [--cursor <cursor>] [--json]",
        .summary = "List saved sessions for the current workspace",
        .options = &.{
            .{ .flag = "--all", .description = "List saved sessions across every workspace in this profile" },
            .{ .flag = "--limit <1-100>", .description = "Set the maximum sessions returned per page" },
            .{ .flag = "--cursor <cursor>", .description = "Continue from a prior sessions result" },
            json_option,
        },
    },
    .{
        .kind = .@"resume",
        .token = "resume",
        .aliases = &.{ "--resume", "--resume-last", "--continue", "-c", "-r" },
        .hidden_from_top_level_help = true,
        .usage = "--resume [last|<id>] [--record] | resume [last|<id>] [--record] | resume --id <id> [--record] | --resume-last | --continue | -c | -r | --resume-<id>",
        .summary = "Continue a saved interactive session",
        .options = &.{
            .{ .flag = "-r", .description = "Choose the session to resume from a picker" },
            .{ .flag = "last", .description = "Resume the most recent session" },
            .{ .flag = "<id>", .description = "Resume a session by id" },
            .{ .flag = "--id <id>", .description = "Resume a session by exact id" },
            .{ .flag = "--record", .description = "Capture visible terminal content while running" },
        },
    },
    .{
        .kind = .credits,
        .token = "credits",
        .aliases = &.{"balance"},
        .usage = "credits [--json]",
        .summary = "Show the AI Gateway credit balance",
        .options = &.{json_option},
    },
    .{
        .kind = .usage,
        .token = "usage",
        .usage = "usage [--period <24h|7d|30d>] [--json]",
        .summary = "Show local fx token usage and spend",
        .options = &.{
            .{ .flag = "--period <24h|7d|30d>", .description = "Select a rolling window (default: 30d)" },
            json_option,
        },
        .details = &.{
            "Reports only usage recorded by fx on this machine.",
            "This command reads local state and does not query account-wide Gateway reports.",
        },
    },
    .{
        .kind = .upgrade,
        .token = "upgrade",
        .usage = "upgrade [--channel <stable|dev>] [--json]",
        .summary = "Upgrade 𝒇x on the selected release channel",
        .options = &.{
            .{ .flag = "--channel <stable|dev>", .description = "Select and remember the release channel" },
            json_option,
        },
    },
    .{
        .kind = .replay,
        .token = "replay",
        .usage = "replay <tape> [--frames] [--json] [--golden <path>] [--frames-dir <path>]",
        .summary = "Replay a recorded terminal session",
        .options = &.{
            .{ .flag = "--frames", .description = "Render each captured frame" },
            .{ .flag = "--golden <path>", .description = "Write the final rendered grid to a file" },
            .{ .flag = "--frames-dir <path>", .description = "Write rendered frames to a directory" },
            json_option,
        },
    },
    .{
        .kind = .workspace,
        .token = "workspace",
        .usage = "workspace [list|add PATH|remove PATH|clear] [--json]",
        .summary = "Manage additional workspace directories",
        .options = &.{
            .{ .flag = "list", .description = "List the primary and additional directories (default)" },
            .{ .flag = "add PATH", .description = "Persist an existing additional directory" },
            .{ .flag = "remove PATH", .description = "Remove an additional directory" },
            .{ .flag = "clear", .description = "Remove all additional directories" },
            json_option,
        },
        .details = &.{
            "Additional directories are stored for the current primary workspace.",
        },
    },
};

pub const top_level_help_default_width = command_specs.top_level_help_default_width;
pub const top_level_help_fast_buffer_bytes: usize = 32 * 1024;

pub const top_level_help_groups = [_]TopLevelHelpGroup{
    .{ .entries = &.{
        .{ .kind = .ask, .usage = "ask <prompt>" },
    } },
    .{ .entries = &.{
        .{ .kind = .pr, .usage = "pr [context]" },
        .{ .kind = .issue, .usage = "issue [context]" },
        .{ .kind = .background, .usage = "background [last|<id>]" },
    } },
    .{ .entries = &.{
        .{ .kind = .sessions, .usage = "sessions" },
        .{ .kind = .session, .usage = "session <last|id>" },
        .{ .usage = "session migrate <id>", .summary = "Migrate a saved session to the current format" },
        .{ .usage = "session recover <id>", .summary = "Copy a recoverable corrupt session" },
        .{ .kind = .replay, .usage = "replay <tape>" },
    } },
    .{ .entries = &.{
        .{ .kind = .login, .usage = "login" },
        .{ .kind = .logout, .usage = "logout" },
        .{ .kind = .setup, .usage = "setup" },
        .{ .kind = .teams, .usage = "teams" },
        .{ .kind = .credits, .usage = "credits|balance" },
        .{ .kind = .usage, .usage = "usage [--period <24h|7d|30d>]" },
    } },
    .{ .entries = &.{
        .{ .kind = .status, .usage = "status" },
        .{ .kind = .doctor, .usage = "doctor" },
        .{ .kind = .models, .usage = "models" },
        .{ .kind = .permissions, .usage = "permissions" },
        .{ .kind = .workspace, .usage = "workspace" },
        .{ .kind = .upgrade, .usage = "upgrade" },
        .{ .kind = .acp, .usage = "acp" },
        .{ .kind = .help, .usage = "help" },
    } },
};

pub const top_level_flags = [_]TopLevelFlag{
    .{
        .usage = "--record",
        .description = "Record terminal output",
    },
    .{
        .usage = "--context-limit <spec>",
        .description = "Set name=bytes|off; repeatable",
    },
    .{
        .usage = "--add-dir <path>",
        .description = "Add a workspace directory; repeatable",
    },
    .{
        .usage = "--no-additional-dirs",
        .description = "Ignore saved additional directories",
    },
    .{
        .usage = "-c, --continue",
        .description = "Resume the latest workspace session",
    },
    .{
        .usage = "-r",
        .description = "Open the saved-session picker",
    },
    .{
        .usage = "--resume [last|<id>]",
        .description = "Resume the latest workspace session or an exact ID",
    },
    .{
        .usage = "--resume-last",
        .description = "Resume the latest workspace session",
    },
    .{
        .usage = "--resume-<id>",
        .description = "Resume a session by exact ID",
    },
    .{
        .usage = "-h, --help",
        .description = "Display this help and exit",
    },
    .{
        .usage = "-v, --version",
        .description = "Print the 𝒇x version and exit",
    },
};

pub const top_level_examples = [_]TopLevelExample{
    .{ .command = "fx", .description = "Start a fresh interactive session" },
    .{ .command = "fx ask \"Explain the changes in this repository\"", .description = "Run one request and exit" },
    .{ .command = "fx --resume last", .description = "Continue the latest session for this workspace" },
    .{ .command = "fx status --json", .description = "Inspect the current configuration as JSON" },
};

pub const top_level_notes = [_][]const u8{
    "Run `fx <command> --help` for command-specific options and examples.",
    "Run `/help` inside an interactive session for slash commands.",
};

pub const top_level_resources = [_]TopLevelResource{
    .{ .label = "Learn more about 𝒇x:", .value = "https://fx.sh/docs", .link = true },
    .{ .label = "Report a problem:", .value = "run `/feedback` inside 𝒇x" },
};

const slash_blueprint = [_]SlashSpec{
    .{ .kind = .help, .command = "/help", .help_entry = "/help", .completion_description = "show available slash commands", .presentation_category = .general, .show_in_welcome = true },
    .{ .kind = .clear_screen, .command = "/clear", .help_entry = "/clear", .completion_description = "start a fresh session and keep background processes", .presentation_category = .general, .show_in_welcome = true },
    .{ .kind = .new_session, .command = "/new", .help_entry = "/new", .completion_description = "start a fresh session", .presentation_category = .session, .show_in_welcome = true },
    .{ .kind = .reset_session, .command = "/reset", .help_entry = "/reset", .completion_description = "reset the current session context", .presentation_category = .session },
    .{ .kind = .resume_session, .command = "/resume", .help_entry = "/resume", .completion_description = "resume a saved session", .presentation_category = .session },
    .{ .kind = .continue_recovery, .command = "/continue", .help_entry = "/continue", .completion_description = "continue a paused model response", .presentation_category = .session, .requires_prompt_credential = true },
    .{ .kind = .rename_session, .command = "/rename", .help_entry = "/rename <title>", .completion_description = "rename the current session", .presentation_category = .session, .has_args = true, .accepts_payload = true },
    .{ .kind = .login, .command = "/login", .help_entry = "/login", .completion_description = null, .presentation_category = .account },
    .{ .kind = .logout, .command = "/logout", .help_entry = "/logout", .completion_description = "sign out of fx login", .presentation_category = .account },
    .{ .kind = .setup, .command = "/setup", .help_entry = "/setup", .completion_description = "set up AI Gateway access", .presentation_category = .account },
    .{ .kind = .stats, .command = "/stats", .help_entry = "/stats", .completion_description = "show token and turn statistics", .presentation_category = .account },
    .{ .kind = .usage, .command = "/usage", .aliases = &.{"/cost"}, .help_entry = "/usage (/cost)", .completion_description = "show local fx tokens, models, and spend", .presentation_category = .account },
    .{ .kind = .status, .command = "/status", .help_entry = "/status", .completion_description = "show runtime configuration", .presentation_category = .general, .show_in_welcome = true },
    .{ .kind = .background, .command = "/background", .help_entry = "/background [open|logs|stop <id|last>]", .completion_description = "inspect background command history", .presentation_category = .agents, .show_in_welcome = true, .has_args = true },
    .{ .kind = .background_stop, .command = "/background stop", .accepts_payload = true },
    .{ .kind = .background_open, .command = "/background open", .accepts_payload = true },
    .{ .kind = .background_logs, .command = "/background logs", .accepts_payload = true },
    .{ .kind = .image, .command = "/image", .aliases = &.{"/img"}, .help_entry = "/image <path> (/img)", .completion_description = "attach an image by path", .presentation_category = .media, .has_args = true, .accepts_payload = true },
    .{ .kind = .images, .command = "/images", .help_entry = "/images [clear]", .completion_description = "manage pending image attachments", .presentation_category = .media, .has_args = true, .accepts_payload = true },
    .{ .kind = .model, .command = "/model", .help_entry = "/model <id-or-query>", .completion_description = "choose what model and reasoning effort to use", .presentation_category = .model, .has_args = true, .accepts_payload = true, .requires_prompt_credential = true },
    .{ .kind = .models, .command = "/models", .help_entry = "/models", .completion_description = "browse available models", .presentation_category = .model },
    .{ .kind = .permissions, .command = "/permissions", .help_entry = "/permissions [ask|auto|yolo|reset]", .completion_description = "choose what fx is allowed to do", .presentation_category = .security, .show_in_welcome = true, .has_args = true, .accepts_payload = true },
    .{ .kind = .allowlist, .command = "/allowlist", .help_entry = "/allowlist [view [effective|local|user]|[local|user] add|remove|reset ...]", .completion_description = "manage trusted commands, tools, and URLs", .presentation_category = .security, .show_in_welcome = true, .has_args = true, .accepts_payload = true },
    .{ .kind = .undo, .command = "/undo", .help_entry = "/undo", .completion_description = "undo the latest tracked file operation", .presentation_category = .session },
    .{ .kind = .mcp, .command = "/mcp", .help_entry = "/mcp [list|resource|prompt|add|remove|path|reload|auth|logout]", .completion_description = "manage MCP servers, resources, and prompts", .presentation_category = .extensions, .has_args = true, .accepts_payload = true },
    .{ .kind = .skills, .command = "/skills", .help_entry = "/skills [list|add|install|show|create|remove|path] [name|url|path] ($ opens skill search)", .completion_description = "browse and manage skills", .presentation_category = .extensions, .has_args = true, .accepts_payload = true },
    .{ .kind = .copy, .command = "/copy", .help_entry = "/copy", .completion_description = "copy the last assistant response", .presentation_category = .session },
    .{ .kind = .feedback, .command = "/feedback", .help_entry = "/feedback", .completion_description = "open the fx feedback form", .presentation_category = .product, .show_in_welcome = true },
    .{ .kind = .trace, .command = "/trace", .help_entry = "/trace", .completion_description = "copy a private diagnostic trace", .presentation_category = .product },
    .{ .kind = .compact, .command = "/compact", .help_entry = "/compact", .completion_description = "compact older conversation turns", .presentation_category = .session },
    .{ .kind = .settings, .command = "/settings", .help_entry = "/settings [startup-scrollback [on|off]]", .completion_description = "browse and update settings", .presentation_category = .appearance, .has_args = true, .accepts_payload = true },
    .{ .kind = .alias, .command = "/alias", .aliases = &.{}, .help_entry = "/alias [name] [command]", .completion_description = "show alias availability", .presentation_category = .extensions, .has_args = true, .accepts_payload = true },
    .{ .kind = .credits, .command = "/credits", .aliases = &.{"/balance"}, .help_entry = "/credits (/balance)", .completion_description = "show gateway credits balance", .presentation_category = .account, .requires_prompt_credential = true },
    .{ .kind = .paste, .command = "/paste", .help_entry = "/paste", .completion_description = "attach an image from the clipboard when supported", .presentation_category = .media },
    .{ .kind = .fast, .command = "/fast", .help_entry = "/fast", .completion_description = "toggle Fast mode when supported", .presentation_category = .model },
    .{ .kind = .appearance, .command = "/appearance", .aliases = &.{ "/input", "/maxxing" }, .show_aliases_in_completion = false, .help_entry = "/appearance [input lines|tint|presentation normal|minimal]", .completion_description = "choose input and transcript presentation", .presentation_category = .appearance, .has_args = true, .accepts_payload = true },
    .{ .kind = .sandbox, .command = "/sandbox", .help_entry = "/sandbox [os|none]", .completion_description = "choose command sandbox behavior", .presentation_category = .security, .has_args = true, .accepts_payload = true },
    .{ .kind = .statusline, .command = "/statusline", .help_entry = "/statusline [sandbox|context|session]", .completion_description = "toggle status line segments", .presentation_category = .appearance, .has_args = true, .accepts_payload = true },
    .{ .kind = .notifications, .command = "/sound", .help_entry = "/sound [on|off|max]", .completion_description = "toggle notification sounds", .presentation_category = .appearance, .has_args = true, .accepts_payload = true },
    .{ .kind = .workspace, .command = "/workspace", .help_entry = "/workspace [list|add PATH|remove PATH|clear]", .completion_description = "manage additional workspace directories", .presentation_category = .workspace, .show_in_welcome = true, .has_args = true, .accepts_payload = true },
    .{ .kind = .version, .command = "/version", .help_entry = "/version", .completion_description = "show the fx version", .presentation_category = .general },
    .{ .kind = .quit, .command = "/quit", .aliases = &.{"/exit"}, .help_entry = "/quit", .completion_description = "exit the interactive shell", .presentation_category = .general, .show_in_welcome = true },
};

pub const Catalog = struct {
    auth_service: @import("../core/gateway/adapter_auth.zig").AuthServicePresentation,
    login_summary: []u8,
    logout_summary: []u8,
    teams_summary: []u8,
    login_completion: []u8,
    top_level_specs: []TopLevelSpec,
    slash_specs: []SlashSpec,
    top_level: TopLevelRegistry,
    slash: SlashRegistry,

    pub fn init(
        alloc: Allocator,
        adapters: adapter_registry.AdapterRegistry,
        adapter_kind: []const u8,
    ) !Catalog {
        const adapter = try adapters.resolve(adapter_kind);
        const auth = adapter.auth orelse return error.MissingAuthCapability;
        var auth_service = try auth.authServicePresentation(alloc);
        errdefer auth_service.deinit(alloc);

        const login_summary = try std.fmt.allocPrint(alloc, "Sign in with {s}", .{auth_service.service_label});
        errdefer alloc.free(login_summary);
        const logout_summary = try std.fmt.allocPrint(alloc, "Sign out of the current {s} session", .{auth_service.service_label});
        errdefer alloc.free(logout_summary);
        const teams_summary = try std.fmt.allocPrint(alloc, "Choose the {s} team used by AI Gateway", .{auth_service.service_label});
        errdefer alloc.free(teams_summary);
        const login_completion = try std.fmt.allocPrint(alloc, "sign in with {s}", .{auth_service.service_label});
        errdefer alloc.free(login_completion);

        const owned_top_level = try alloc.dupe(TopLevelSpec, &top_level_blueprint);
        errdefer alloc.free(owned_top_level);
        const owned_slash = try alloc.dupe(SlashSpec, &slash_blueprint);
        errdefer alloc.free(owned_slash);

        for (owned_top_level) |*spec| switch (spec.kind) {
            .login => spec.summary = login_summary,
            .logout => spec.summary = logout_summary,
            .teams => spec.summary = teams_summary,
            else => {},
        };
        for (owned_slash) |*spec| switch (spec.kind) {
            .login => spec.completion_description = login_completion,
            else => {},
        };

        return .{
            .auth_service = auth_service,
            .login_summary = login_summary,
            .logout_summary = logout_summary,
            .teams_summary = teams_summary,
            .login_completion = login_completion,
            .top_level_specs = owned_top_level,
            .slash_specs = owned_slash,
            .top_level = .{
                .specs = owned_top_level,
                .description = "Fast, native coding agent for the terminal.",
                .interactive_hint = "𝒇x starts an interactive session by default. Use `fx ask` to run one noninteractive request.",
                .help_groups = top_level_help_groups[0..],
                .flags = top_level_flags[0..],
                .examples = top_level_examples[0..],
                .notes = top_level_notes[0..],
                .resources = top_level_resources[0..],
            },
            .slash = .{ .commands = owned_slash },
        };
    }

    pub fn deinit(self: *Catalog, alloc: Allocator) void {
        alloc.free(self.top_level_specs);
        alloc.free(self.slash_specs);
        alloc.free(self.login_summary);
        alloc.free(self.logout_summary);
        alloc.free(self.teams_summary);
        alloc.free(self.login_completion);
        self.auth_service.deinit(alloc);
        self.* = undefined;
    }

    pub fn topLevelSummary(self: *const Catalog, kind: TopLevelKind) []const u8 {
        for (self.top_level_specs) |spec| if (spec.kind == kind) return spec.summary;
        unreachable;
    }
};

pub fn testTopLevelRegistry() TopLevelRegistry {
    if (!builtin.is_test) @compileError("test catalog is test-only");
    return .{
        .specs = test_top_level_blueprint[0..],
        .description = "Fast, native coding agent for the terminal.",
        .interactive_hint = "𝒇x starts an interactive session by default. Use `fx ask` to run one noninteractive request.",
        .help_groups = top_level_help_groups[0..],
        .flags = top_level_flags[0..],
        .examples = top_level_examples[0..],
        .notes = top_level_notes[0..],
        .resources = top_level_resources[0..],
    };
}

pub fn testSlashRegistry() SlashRegistry {
    if (!builtin.is_test) @compileError("test catalog is test-only");
    return .{ .commands = test_slash_blueprint[0..] };
}

const test_top_level_blueprint = blk: {
    var specs = top_level_blueprint;
    for (&specs) |*spec| switch (spec.kind) {
        .login => spec.summary = "Sign in with test service",
        .logout => spec.summary = "Sign out of the current test service session",
        .teams => spec.summary = "Choose the test service team used by AI Gateway",
        else => {},
    };
    break :blk specs;
};

const test_slash_blueprint = blk: {
    var specs = slash_blueprint;
    for (&specs) |*spec| switch (spec.kind) {
        .login => spec.completion_description = "sign in with test service",
        else => {},
    };
    break :blk specs;
};

pub const argCompletionAnchor = command_specs.argCompletionAnchor;
pub const argCompletionIndexForLabel = command_specs.argCompletionIndexForLabel;
pub const allowlistArgCompletionPrefix = command_specs.allowlistArgCompletionPrefix;
pub const appearanceArgCompletionPrefix = command_specs.appearanceArgCompletionPrefix;
pub const inputArgCompletionPrefix = command_specs.inputArgCompletionPrefix;
pub const maxxingArgCompletionPrefix = command_specs.maxxingArgCompletionPrefix;
pub const sandboxArgCompletionPrefix = command_specs.sandboxArgCompletionPrefix;
pub const statuslineArgCompletionPrefix = command_specs.statuslineArgCompletionPrefix;
pub const notificationsArgCompletionPrefix = command_specs.notificationsArgCompletionPrefix;
pub const permissionsArgCompletionPrefix = command_specs.permissionsArgCompletionPrefix;

test "built-in slash commands register exact active order" {
    const expected_commands = [_][]const u8{
        "/help",
        "/clear",
        "/new",
        "/reset",
        "/resume",
        "/continue",
        "/rename",
        "/login",
        "/logout",
        "/setup",
        "/stats",
        "/usage",
        "/status",
        "/background",
        "/background stop",
        "/background open",
        "/background logs",
        "/image",
        "/images",
        "/model",
        "/models",
        "/permissions",
        "/allowlist",
        "/undo",
        "/mcp",
        "/skills",
        "/copy",
        "/feedback",
        "/trace",
        "/compact",
        "/settings",
        "/alias",
        "/credits",
        "/paste",
        "/fast",
        "/appearance",
        "/sandbox",
        "/statusline",
        "/sound",
        "/workspace",
        "/version",
        "/quit",
    };

    try std.testing.expectEqual(expected_commands.len, slash_blueprint.len);
    for (expected_commands, slash_blueprint) |expected, spec| {
        try std.testing.expectEqualStrings(expected, spec.command);
    }
}

test "built-in slash registry resolves primary commands and aliases" {
    const slash_registry = testSlashRegistry();
    const image = slash_registry.lookup("/img") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(SlashKind.image, image.kind);

    const usage = slash_registry.lookup("/usage") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(SlashKind.usage, usage.kind);

    const quit = slash_registry.matchExact("/exit\t") orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(SlashKind.quit, quit.command.kind);
    try std.testing.expectEqualStrings("/exit", quit.token);

    const model = command_specs.matchedSlashPrefix(slash_registry, "/model\tmodel-id", .model) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("/model", model);

    for ([_][]const u8{ "/model", "/credits" }) |command| {
        const credential_backed = slash_registry.lookup(command) orelse return error.TestExpectedEqual;
        try std.testing.expect(credential_backed.requires_prompt_credential);
    }

    const models = slash_registry.lookup("/models") orelse return error.TestExpectedEqual;
    try std.testing.expect(!models.requires_prompt_credential);

    try std.testing.expect(command_specs.matchedSlashPrefix(slash_registry, "/model\nmodel-id", .model) == null);
}

test "exact slash command matching includes hidden completion aliases" {
    const slash_registry = testSlashRegistry();
    try std.testing.expect(slash_registry.matchExact("/appearance") != null);
    try std.testing.expect(slash_registry.matchExact("/input") != null);
    try std.testing.expect(slash_registry.matchExact("/maxxing\t") != null);
    try std.testing.expect(slash_registry.matchExact("/input lines") == null);
    try std.testing.expect(slash_registry.matchExact("/unknown") == null);
}

test "built-in paste completion describes clipboard image attachment" {
    const slash_registry = testSlashRegistry();
    const completion = command_specs.nthSlashCompletion(slash_registry, "/pas", 0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("/paste", completion);

    const description = command_specs.nthSlashCompletionDescription(slash_registry, "/pas", 0) orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("attach an image from the clipboard when supported", description);
}

test "owned catalog materializes the same four templates for a test peer" {
    const adapters = [_]stream_provider.ProviderAdapter{.{
        .kind = "peer",
        .supported_protocol = "peer",
        .auth = .{ .kind = "peer", .auth_service_label = "Example Cloud" },
        .stream_fn = stream_provider.unavailable_adapter.stream_fn,
    }};
    const registry = try adapter_registry.AdapterRegistry.init(&adapters);
    var catalog = try Catalog.init(std.testing.allocator, registry, "peer");
    defer catalog.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("Sign in with Example Cloud", catalog.topLevelSummary(.login));
    try std.testing.expectEqualStrings("Sign out of the current Example Cloud session", catalog.topLevelSummary(.logout));
    try std.testing.expectEqualStrings("Choose the Example Cloud team used by AI Gateway", catalog.topLevelSummary(.teams));
    try std.testing.expectEqualStrings("sign in with Example Cloud", catalog.slash.lookup("/login").?.completion_description.?);
}

test "owned command catalog cleans every label and specification allocation failure" {
    const adapters = [_]stream_provider.ProviderAdapter{.{
        .kind = "peer",
        .supported_protocol = "peer",
        .auth = .{ .kind = "peer", .auth_service_label = "Example Cloud" },
        .stream_fn = stream_provider.unavailable_adapter.stream_fn,
    }};
    const registry = try adapter_registry.AdapterRegistry.init(&adapters);
    const backing = std.testing.allocator;
    var probe = std.testing.FailingAllocator.init(backing, .{});
    var complete = try Catalog.init(probe.allocator(), registry, "peer");
    complete.deinit(probe.allocator());
    try std.testing.expectEqual(probe.allocated_bytes, probe.freed_bytes);

    for (0..probe.alloc_index) |fail_index| {
        var failing = std.testing.FailingAllocator.init(
            backing,
            .{ .fail_index = fail_index },
        );
        if (Catalog.init(failing.allocator(), registry, "peer")) |catalog_value| {
            var catalog = catalog_value;
            catalog.deinit(failing.allocator());
        } else |err| try std.testing.expectEqual(error.OutOfMemory, err);
        try std.testing.expect(failing.has_induced_failure);
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
}

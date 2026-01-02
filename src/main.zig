const std = @import("std");
const mrubyOnZap = @import("mrubyOnZap");
const c = mrubyOnZap.c;
const zap = @import("zap");

const Allocator = std.mem.Allocator;

// The global Application Context
const MContext = struct {
    mrb: ?*c.mrb_state,

    pub fn init() MContext {
        return .{
            .mrb = null,
        };
    }
};

// A very simple endpoint handling only GET requests
const SimpleEndpoint = struct {

    // zap.App.Endpoint Interface part
    path: []const u8,
    error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

    // data specific for this endpoint
    some_data: []const u8,

    pub fn init(path: []const u8, data: []const u8) SimpleEndpoint {
        return .{
            .path = path,
            .some_data = data,
        };
    }

    // handle GET requests
    pub fn get(e: *SimpleEndpoint, arena: Allocator, context: *MContext, r: zap.Request) !void {
        const thread_id = std.Thread.getCurrentId();

        r.setStatus(.ok);

        if (context.mrb) |m| {
            if (r.path) |path| {
                const env = c.mrb_hash_new(m);
                _ = c.mrb_hash_set(m, env, zigStringToRuby(m, "PATH_INFO"),
                                           zigStringToRuby(m, path));
                _ = c.mrb_hash_set(m, env, zigStringToRuby(m, "REQUEST_METHOD"),
                                           zigStringToRuby(m, "get"));

                const app = c.mrb_module_get(m, "App");
                const mrb_result = c.mrb_funcall(m, c.mrb_obj_value(app), "entry_point", 1, env);

                const body = c.mrb_ary_ref(m, mrb_result, 2);
                const cstr: [*:0]const u8 = c.mrb_str_to_cstr(m, body);
                const len: usize = std.mem.len(cstr);
                const out = try arena.alloc(u8, len);
                defer arena.free(out);
                @memcpy(out, cstr[0..len]);

                try r.sendBody(out);
                return;
            }
        }

        // look, we use the arena allocator here -> no need to free the response_text later!
        // and we also just `try` it, not worrying about errors
        const response_text = try std.fmt.allocPrint(
            arena,
            \\Hello!
            \\endpoint.data: {s}
            \\arena: {}
            \\thread_id: {}
            \\
        ,
            .{ e.some_data, arena.ptr, thread_id },
        );

        try r.sendBody(response_text);
        std.Thread.sleep(std.time.ns_per_ms * 300);
    }
};

const StopEndpoint = struct {
    path: []const u8,
    error_strategy: zap.Endpoint.ErrorStrategy = .log_to_response,

    pub fn get(_: *StopEndpoint, _: Allocator, my_context: *MContext, _: zap.Request) !void {
        std.debug.print(
            \\Before I stop, let me dump the app context:
            \\
            \\
        , .{});
        zap.stop();
        if (my_context.mrb) |m| {
            c.mrb_close(m);
            my_context.mrb = null;
        }
    }
};

pub fn main() !void {
    // setup allocations
    var gpa: std.heap.GeneralPurposeAllocator(.{
        // just to be explicit
        .thread_safe = true,
    }) = .{};
    defer std.debug.print("\n\nLeaks detected: {}\n\n", .{gpa.deinit() != .ok});
    const allocator = gpa.allocator();

    // create an app context
    var my_context = MContext.init();

    // run main.rb of mruby first
    const mrb = c.mrb_open();
    if (mrb) |m| {
        _ = c.mrb_load_irep(m, c.rb_main);
        my_context.mrb = m;
        // defer c.mrb_close(m);
    }


    // create an App instance
    const App = zap.App.Create(MContext);
    try App.init(allocator, &my_context, .{});
    defer App.deinit();

    // create the endpoints
    var my_endpoint = SimpleEndpoint.init("/test", "some endpoint specific data");
    var stop_endpoint: StopEndpoint = .{ .path = "/stop" };
    //
    // register the endpoints with the App
    try App.register(&my_endpoint);
    try App.register(&stop_endpoint);

    // listen on the network
    try App.listen(.{
        .interface = "0.0.0.0",
        .port = 3000,
    });
    std.debug.print("Listening on 0.0.0.0:3000\n", .{});

    std.debug.print(
        \\ Try me via:
        \\ curl http://localhost:3000/test
        \\ Stop me via:
        \\ curl http://localhost:3000/stop
        \\
    , .{});

    // start worker threads -- only 1 process!!!
    zap.start(.{
        .threads = 2,
        .workers = 1,
    });
}

fn zigStringToRuby(m: *c.mrb_state, txt:[]const u8) c.mrb_value {
    return c.mrb_str_new(m, txt.ptr, @as(c.mrb_int, @intCast(txt.len)));
}

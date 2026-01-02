# mruby on zap

mruby embedded inside zap web server

## Compile and Run

Steps to create this repository from scratch after `zig init`.

### Fetch Zap as module

Fetch zap as module

```
$ zig fetch --save git+https://github.com/zigzap/zap/
```

Add these to `build.zig`

```
    const zap_mod = b.dependency("zap", .{
        .target = target,
        .optimize = optimize,
    });
```

```
    exe.root_module.addImport("zap", zap_mod.module("zap"));
```

Replace the `src/main.zig` with [app_basic](https://github.com/zigzap/zap/blob/master/examples/app/basic.zig) example from zap and run it via `zig build run`. It should work by connecting to `localhost:3000/test`.

### Add mruby as dependency

Follows [mrubyOnZig](https://github.com/rguiscard/mrubyOnZig). It may take a few efforts to adapt. Here are hints:

- You need to build mruby with rake to generate `libmruby.a` and `mruby.h` under `build/host/` directory.
- Create `mruby_headers.h` and use `zig translate-c` to convert it to a zig file. Replace the `mrb_gc` with `u128` to avoid opaque error.
- Modify `src/root.zig` to include translated mruby headers.
- Automatically generate mruby bytecode from `main.rb`

```
+    // Generate mrb bytecode from src/main.rb
+    const mruby_path = "mruby-3.4.0/build/host/";
+    const mrbc = b.addSystemCommand(&.{
+        mruby_path++"bin/mrbc",
+        "-Brb_main",
+    });
+
+    const mrb_c = mrbc.addPrefixedOutputFileArg("-o", "main.c");
+    mrbc.addFileArg(b.path("src/main.rb"));
```

- Include the genreate bydecode in C into zig executable

```
+    mod.addCSourceFile(.{
+        .file = mrb_c,
+        .flags = &.{},
+    });
+    mod.addIncludePath(b.path(mruby_path++"include/"));
+    mod.addObjectFile(b.path(mruby_path++"lib/libmruby.a"));
```

- Run mruby bytecode in `src/main.zig`

```
+    // run main.rb of mruby first
+    const mrb = c.mrb_open();
+    if (mrb) |m| {
+        _ = c.mrb_load_irep(m, c.rb_main);
+        defer c.mrb_close(m);
+    }
+
```

### Call mruby from zap

On zap side (`src/main.zig`):

Keep `mrb_state` in context of zap:

```
const MContext = struct {
    mrb: ?*c.mrb_state,

    pub fn init() MContext {
        return .{
            .mrb = null,
        };
    }
};
```

Create context in `main` function:

```
    // create an app context
    var my_context = MContext.init();

    // run main.rb of mruby first
    const mrb = c.mrb_open();
    if (mrb) |m| {
        _ = c.mrb_load_irep(m, c.rb_main);
        my_context.mrb = m;
        // defer c.mrb_close(m);
    }
```

Handle get method:

```
    // handle GET requests
    pub fn get(e: *SimpleEndpoint, arena: Allocator, context: *MContext, r: zap.Request) !void {
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
    }
```

On mruby side (`src/main.rb`):

```
module App
  def self.entry_point(env)
    path = env["PATH_INFO"]
    method = env["REQUEST_METHOD"]

    s = "<html><head></head><body><p>Hello from mruby</p><p>#{method}: #{path}</p></body></html>"
    [200, {}, s]
  end
end
```

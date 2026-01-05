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

- You need to build mruby with rake to generate `libmruby.a` and `mruby.h` under `build/host/` directory. Remember to use `zig cc` instead of default C compiler. It will eliminate some errors on C macros.

```
$ CC='zig cc' rake test all
```

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

### mruby-shelf

You can consider to use [mruby-shelf](https://github.com/katzer/mruby-shelf/) as a simple web framework. Here is a working example.

First, add `mruby-shelf` into mruby by adding the following line to `mrbgems/default.gembox` (or your own genbox):

```
  conf.gem :github => "katzer/mruby-shelf"
```

Run `rake test all` and it should show errors on missing `mruby-print`. 
Current version of mruby-shelf does not fully support mruby 0.3.4, therefore, comment out `mruby-print` from your local repository at `build/repos/host/mruby-shelf/mrbgem.rake`

```
#  spec.add_test_dependency 'mruby-print',   core: 'mruby-print'
```

Run `rake test all` again. The test will fail, but the libmruby.a will be correctly built.

On ruby side:

```
module App
  @@app = Shelf::Builder.app do
    run ->(env) { [200, { 'content-type' => 'text/plain' }, ['A barebones shelf app']] }
  end

  def self.entry_point(env)
    return @@app.call(env)
  end
end
```

On zig side

```
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
                // _ = c.mrb_funcall(m, c.mrb_top_self(m), "puts", 1, mrb_result);

                const array_class = c.mrb_class_get(m, "Array");
                const string_class = c.mrb_class_get(m, "String");
                if (c.mrb_obj_is_kind_of(m, mrb_result, array_class)) {
                    const body = c.mrb_ary_ref(m, mrb_result, 2);
                    var cstr: [*:0]const u8 = undefined;
                    if (c.mrb_obj_is_kind_of(m, body, array_class)) {
                        const data = c.mrb_ary_ref(m, body, 0);
                        cstr = c.mrb_str_to_cstr(m, data);
                    } else if (c.mrb_obj_is_kind_of(m, body, string_class)) {
                        cstr = c.mrb_str_to_cstr(m, body);
                    } else {
                        // error: not string or array of strings
                        return;
                    }
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

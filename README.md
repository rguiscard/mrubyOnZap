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


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

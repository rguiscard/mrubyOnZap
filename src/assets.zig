// path, name, to gzipped or not, data from @embedFile
pub const assets = [_]struct { []const u8, []const u8, ?[]const u8, bool } {
    .{ "assets/simple.min.css", "simple_css", "text/css", true },
};

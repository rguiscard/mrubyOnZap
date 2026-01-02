puts "Hello World from mruby"

module App
  def self.entry_point(env)
    path = env["PATH_INFO"]
    method = env["REQUEST_METHOD"]

    s = "<html><head></head><body><p>Hello from mruby</p><p>#{method}: #{path}</p></body></html>"
    [200, {}, s]
  end
end

puts "Hello World from mruby"

module App
  def self.entry_point(path)
    s = "<html><head></head><body><p>Hello from mruby</p><p>#{path}</p></body></html>"
    s
  end
end

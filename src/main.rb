puts "Hello World from mruby"

module App
  @@app = Shelf::Builder.app do
    run ->(env) { [200, { 'content-type' => 'text/plain' }, ['A barebones shelf app']] }
  end

  def self.entry_point(env)
    return @@app.call(env)
  end
end

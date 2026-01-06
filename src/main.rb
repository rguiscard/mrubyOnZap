puts "Hello World from mruby"

module App
  def self.app
    return Shelf::Builder.app do
      map('/test/users/{id}') { run ->(env) { [200, {}, [env['shelf.request.query_hash'][:id]]] } }
      get('/test') do
        run ->(env) { [200, {}, ['test run']] }
      end
    end
  end

  def self.entry_point(env)
    return app.call(env)
  end
end

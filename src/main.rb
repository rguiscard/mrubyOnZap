puts "Hello World from mruby"

module Zap
  class App
    def app
      return Shelf::Builder.app do
        map('/test/users/{id}') { run ->(env) { [200, {}, [env['shelf.request.query_hash'][:id]]] } }
        get('/test') do
          run ->(env) { [200, {}, ['test run']] }
        end
      end
    end

    def entry_point(env)
      return app.call(env)
#      [200, {}, "ok"]
    end
  end
end

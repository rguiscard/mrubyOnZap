puts "Hello World from mruby"

module Zap
  class Controller
    attr_reader :env, :params

    def initialize(env)
      @env = env
      @params = env["router.params"] || {}
    end

    def render(text, status: 200, headers: {})
      headers["Content-Type"] ||= "text/plain"
      [status, headers, [text]]
    end
  end

  class HelloController < Controller
    def world
      render "OK from HelloController#world"
    end
  end

  class Router
    def initialize
#      @routes = []
    end

#    def get(path, to:)
#      controller, action = to.split("#")
#      @routes << {
#        method: "GET",
#        path: path,
#        controller: controller,
#        action: action
#      }
#    end

    def call(env)
      req_method = env["REQUEST_METHOD"]
      path_info  = env["PATH_INFO"]

      if (to=env['shelf.r3.data'][:to]) != nil
        controller, action = to.split("#")
        return dispatch({controller: controller, action: action}, env)
      end

#      route = @routes.find do |r|
#        r[:method] == req_method && r[:path] == path_info
#      end
#
#      if env['controller'] != nil && env['action'] != nil
#        route[:controller] = env['controller']
#        route[:action] = env['action']
#      end

      return not_found unless route

#      dispatch(route, env)
    end

    def dispatch(route, env)
      controller_class = resolve_controller(route[:controller])

      controller = controller_class.new(env)
      controller.send(route[:action])
    end

    def not_found
      [404, { "Content-Type" => "text/plain" }, ["Not Found"]]
    end

    def resolve_controller(path)
      parts = path.split("/")

      const = Object
      parts.each_with_index do |part, i|
        name = camelize(part)

        if i == parts.length - 1
          name += "Controller"
        end

        const = const.const_get(name)
      end

      const
    end

    def camelize(name)
      name.split("_").map(&:capitalize).join
    end
  end

  class App
    def app
      return Shelf::Builder.app do
#        router = Router.new

#        router.get "/test/ok", to: "zap/hello#world"

#        run router
        
#        map('/test/users/{id}') { run ->(env) { [200, {}, [env['shelf.request.query_hash'][:id]]] } }

        # use controller controller#action
        get('/test/ok', {to: "zap/hello#world"}) do
          run ->(env) {
            Router.new.call(env)
          }
        end
      end
    end

    def entry_point(env)
      return app.call(env)
#      [200, {}, "ok"]
    end
  end
end

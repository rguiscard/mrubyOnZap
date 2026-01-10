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

    def say
      render "say #{env['shelf.request.query_hash'][:word]} from HelloController"
    end
  end

  class Router
    def initialize
    end

    def call(env)
      req_method = env["REQUEST_METHOD"]
      path_info  = env["PATH_INFO"]

      if (to=env['shelf.r3.data'][:to]) != nil
        controller, action = to.split("#")
        return dispatch({controller: controller, action: action}, env)
      end

      return not_found unless route
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
#      default_app = lambda { |env| [200, { "Content-Type" => "text/plain" }, ["default app"]] }
      default_app = Router.new
      return Shelf::Builder.app(default_app) do
        # mruby-shelf typical use
        map('/test/users/{id}') { run ->(env) { [200, {}, [env['shelf.request.query_hash'][:id]]] } }

        # use controller controller#action
        get('/test/ok', {to: "zap/hello#world"}) do
          run ->(env) {
            Router.new.call(env)
          }
        end

        # this defaults to default_app above, using Rails-like route pattern
        get '/test/say/{word}', to: "zap/hello#say"

        get '/doc/index', to: "doc#index"
      end
    end

    def entry_point(env)
      return app.call(env)
    end
  end
end

class DocController < Zap::Controller
  def index
    render <<EOF
This is a blog index
EOF
  end
end

puts "Hello World from mruby"

# https://github.com/rbuchberger/objective_elements
# Author: Robert Buchberger <robert@buchberger.cc>
# License: MIT
#
# This module provides a few helpful classes for generating HTML using simple
# Ruby. Its goal is to be lightweight, and more focused than the general-purpose
# nature of nokogiri.
module ObjectiveElements
  # Represents standard HTML attributes, such as class="myclass"
  class HTMLAttributes
    attr_reader :content
    def initialize(new = nil)
      @content = {}
      self << new
    end

    def [](key)
      @content[key.to_sym]
    end

    def to_s
      return_string = ''
      @content.each_pair do |k, v|
        # If an attribute has no values, we need to introduce an empty string to
        # the array in order to get the correct format (alt="", for example):
        v << '' if v.empty?

        return_string << "#{k}=\"#{v.join ' '}\" "
      end

      return_string.strip
    end

    # This is the only way we add new attributes. Flexible about what you give
    # it-- accepts both strings and symbols for the keys, and both strings and
    # arrays for the values.
    def <<(new)
      # Don't break everything if this is passed an empty value:
      return self unless new

      if new.is_a? Hash
        add_hash(new)
      else
        add_string(new)
      end

      self
    end

    def delete(trash)
      # accepts an array or a single element
      [trash].flatten
             .map(&:to_sym)
             .each { |k| @content.delete k }
  
      self
    end

    def replace(new)
      formatted_new = if new.is_a? String
                        hashify_input(new)
                      else
                        new.transform_keys(&:to_sym)
                      end

      delete formatted_new.keys

      add_hash formatted_new

      self
    end

    def empty?
      @content.empty?
    end

    def method_missing(method, arg = nil)
      if method[-1] == '='
        raise 'must supply new value' unless arg
  
        replace(method[0..-2] => arg)
      elsif @content.key? method
        @content[method].join(' ')
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      (method[-1] == '=') ||
        (@content.key? method) ||
        super
    end

    private

    def add_string(new_string)
      add_hash hashify_input new_string
    end

    # Input: Keys are attribute names (either strings or symbols), values are
    # attribute values (either a string or an array of strings)
    def add_hash(new_hash)
      formatted_new = {}

      new_hash.each_pair do |k, v|
        v = v.split(' ') if v.is_a? String

        formatted_new[k.to_sym] = v
      end

      @content.merge!(formatted_new) do |_key, oldval, newval|
        oldval.concat(newval)
      end

      self
    end

    def hashify_input(new_string)
      # looking for something like:
      # 'class="something something-else" id="my-id" alt=""'
      new_hash = {}
      new_string.scan(/ ?([^="]+)="([^"]*)"/).each do |match|
        # Returns something like:
        # [['class','something something-else'],['id','my-id'],['alt', '']]

        key, val = *match

        if new_hash[key]
          new_hash[key] << ' ' + val
        else
          new_hash[key] = val
        end
      end
      new_hash
    end
  end

  # Collection of HTML element tags
  # Describes a basic, self-closing HTML tag.
  class SingleTag
    attr_accessor :element
    attr_reader :attributes

    # element is a string, such as 'div' or 'p'.

    # Attributes are a hash. Keys are symbols, values are arrays. Will render as
    # key="value1 value2 value3"

    def initialize(element, attributes: nil)
      @element = element
      self.attributes = attributes
    end

    def attributes=(new)
      @attributes = HTMLAttributes.new(new)
    end

    # Deletes all current attributes, overwrites them with supplied hash.
    def reset_attributes
      @attributes = HTMLAttributes.new
    end

    # Returns parent, with self added as a child
    def add_parent(parent)
      parent.add_content(self)
    end

    def to_a
      [opening_tag]
    end

    # Renders our HTML.
    def to_s
      opening_tag + "\n"
    end

    # Allows us to work with attributes as methods:
    def method_missing(method, arg = nil)
      if @attributes.respond_to?(method)
        @attributes.send(method, arg)
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      @attributes.respond_to?(method) || super
    end

    private

    def opening_tag
      output =  '<' + @element
      output << ' ' + @attributes.to_s unless @attributes.empty?
      output << '>'
    end
  end

  # Non-Self-Closing tag. Can have content, but doesn't have to.
  class DoubleTag < SingleTag
    attr_accessor :oneline
    attr_reader :content

    # Content represents everything between the opening and closing tags.

    def initialize(element, attributes: nil, content: nil, oneline: false)
      @oneline = oneline
      self.content = content
      super(element, attributes: attributes)
    end

    def content=(new)
      reset_content
      add_content(new)
    end

    def reset_content
      @content = []
    end

    def add_content(addition)
      @content << addition if addition
      @content.flatten!
      self
    end
    alias << add_content

    def to_a
      lines = content.map { |c| build_content_line c }
      lines = lines.flatten.map { |l| l.prepend oneline ? '' : indent }
      lines.unshift(opening_tag).push(closing_tag)
    end

    def to_s
      to_a.join(oneline ? '' : "\n") + "\n"
    end

    private

    def build_content_line(element)
      # Since DoubleTag inherits from SingleTag, it will slurp up those too.
      element.is_a?(SingleTag) ? element.to_a : element.to_s.dup
    end

    def indent
      "\ \ "
    end

    def closing_tag
      "</#{element}>"
    end
  end
end

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
        map('/users/{id}') { run ->(env) { [200, {}, [env['shelf.request.query_hash'][:id]]] } }

        # use controller controller#action
        get('/ok', {to: "zap/hello#world"}) do
          run ->(env) {
            Router.new.call(env)
          }
        end

        # this defaults to default_app above, using Rails-like route pattern
        get '/say/{word}', to: "zap/hello#say"

        get '/doc/index', to: "doc#index"

        get '/__console__', to: "console#index"
        post '/__console__', to: "console#index"
      end
    end

    def entry_point(env)
      return app.call(env)
    end
  end
end

class ConsoleController < Zap::Controller
  def index
    if env["REQUEST_METHOD"] == "POST"
      code = env["PARAMS"]["code"]
      if (code != nil)
        result = eval(code)
        [404, { "Content-Type" => "text/plain" }, ["Not Found / POST / "+result.to_s]]
      end
#      result
    else
      render html
    end
  end

#  def result
#    [404, { "Content-Type" => "text/plain" }, ["Not Found / POST"]]
#  end

  def html
    html = ObjectiveElements::DoubleTag.new 'html'
    head = ObjectiveElements::DoubleTag.new 'head'
    head << ObjectiveElements::SingleTag.new(
      'link',
      attributes: { rel: 'stylesheet', href: 'assets/simple.min.css' },
    )
    html << head

    body = ObjectiveElements::DoubleTag.new 'body'
    body.add_content ObjectiveElements::DoubleTag.new(
      'h1',
      content: 'Web Console',
    )

    form = ObjectiveElements::DoubleTag.new(
      'form',
      attributes: {method: 'POST'}
    )
    textarea = ObjectiveElements::DoubleTag.new(
      'textarea',
      attributes: {name: 'code', rows: '10', cols: '80'}
    )
    input = ObjectiveElements::SingleTag.new(
      'input',
      attributes: {type: 'submit', value: 'eval'}
    )
    form << textarea
    form << input
    body << form

    body.add_content ObjectiveElements::DoubleTag.new(
      'pre',
      attributes: { id: 'result' }
    )

    html << body
    html.to_s
  end
end

class DocController < Zap::Controller
  def index
    html = ObjectiveElements::DoubleTag.new 'html'
    head = ObjectiveElements::DoubleTag.new 'head'
    head << ObjectiveElements::SingleTag.new(
      'link',
      attributes: { rel: 'stylesheet', href: 'assets/simple.min.css' },
    )
    html << head
    body = ObjectiveElements::DoubleTag.new 'body'
    body.add_content ObjectiveElements::DoubleTag.new(
      'h1',
      content: 'mruby on zap',
    )
    body.add_content ObjectiveElements::DoubleTag.new(
      'p',
      content: <<EOF
This zig program embeds mruby virtual machine inside zap web server to provide all contents in a single executable, allowing it to be deployed by copying the single file
EOF
    )

    html << body
    render html.to_s
  end
end

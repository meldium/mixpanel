require "open-uri"
require 'base64'
require 'json'
require 'thread'

require 'action_view/helpers/javascript_helper'

module Mixpanel
  class Tracker
    require 'mixpanel/async'
    require 'mixpanel/event'
    require 'mixpanel/person'

    extend Mixpanel::Async
    include Mixpanel::Event
    include Mixpanel::Person

    include ActionView::Helpers::JavaScriptHelper

    def initialize(token, options={})
      @token = token
      @async = !!options.fetch(:async, false)
      @persist = !!options.fetch(:persist, false)
      @env = options.fetch :env, {}
      @api_key = options.fetch :api_key, nil

      # Make sure queue object is instantiated to an array.  If not persisted, set queue object to empty array.
      if @persist
        @env['rack.session'] ||= {}
        @env['rack.session']['mixpanel_events'] ||= []
      else
        @env['mixpanel_events'] = []
      end
    end

    def queue
      @persist ? @env['rack.session']['mixpanel_events'] : @env['mixpanel_events']
    end

    def append(type, *args)
      js_args = args.collect do |arg|
        escape_object_for_js(arg).to_json
      end
      queue << [type, js_args]
    end

    protected

    def ip
        (@env['HTTP_X_FORWARDED_FOR'] || @env['REMOTE_ADDR'] || '').split(',').last
    end

    # Walk through each property and see if it is in the special_properties.  If so, change the key to have a $ in front of it.
    def properties_hash(properties, special_properties)
      properties.inject({}) do |props, (key, value)|
        key = "$#{key}" if special_properties.include?(key.to_s)
        props[key.to_sym] = value
        props
      end
    end

    def encoded_data(parameters)
      Base64.encode64(JSON.generate(parameters)).gsub(/\n/,'')
    end

    def request(url, async)
      async ? send_async(url) : open(url).read
    end

    def parse_response(response)
      response.to_i == 1
    end

    def send_async(url)
      w = Mixpanel::Tracker.worker
      begin
        url << "\n"
        w.write url
        1
      rescue Errno::EPIPE => e
        Mixpanel::Tracker.dispose_worker w
        0
      end
    end

    private

    # Recursively escape anything in a primitive, array, or hash, in
    # preparation for jsonifying it
    def escape_object_for_js(object, i = 0)
      if object.kind_of? Hash
        Hash.new.tap do |h|
          object.each do |k, v|
            h[escape_object_for_js(k, i + 1)] = escape_object_for_js(v, i + 1)
          end
        end

      elsif object.kind_of? Enumerable
        object.map do |elt|
          escape_object_for_js(elt, i + 1)
        end

      elsif object.respond_to? :iso8601
        object.iso8601

      elsif object.kind_of?(Numeric)
        object

      elsif [true, false, nil].member?(object)
        object

      else
        # From ActiveSupport
        escape_javascript(object.to_s)

      end
    end
  end
end

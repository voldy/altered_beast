# This file is copied to ~/spec when you run 'ruby script/generate rspec'
# from the project root directory.
ENV["RAILS_ENV"] = "test"
require File.expand_path(File.dirname(__FILE__) + "/../config/environment")
require 'spec'
require 'spec/rails'
require 'model_stubbing'
require File.dirname(__FILE__) + "/model_stubs"
require 'ruby-debug'
Debugger.start

Spec::Runner.configure do |config|
  config.use_transactional_fixtures = true
  config.use_instantiated_fixtures  = false
  config.fixture_path = RAILS_ROOT + '/spec/fixtures/'

  # Sets the current user in the session from the user fixtures.
  def login_as(user)
    @request.session[:user] = user ? users(user).id : nil
  end

  def authorize_as(user)
    @request.env["HTTP_AUTHORIZATION"] = user ? "Basic #{Base64.encode64("#{users(user).login}:test")}" : nil
  end
  
  def acting(&block)
    act!
    block.call(response) if block
    response
  end

  def assert_collection_value(collection, key, expected)
    case expected
      when nil
        collection[key].should be_nil
      when :not_nil
        collection[key].should_not be_nil
      when :undefined
        collection.should_not include(key)
      else
        collection[key].should == expected
    end
  end
  
  def act!
    instance_eval &self.class.acting_block
  end
end

class ActionController::TestSession
  def include?(key)
    data.include?(key)
  end
end

module Spec::Example::ExampleGroupMethods
  def acting_block
    @acting_block
  end

  def act!(&block)
    @acting_block = block
  end

  def create_example(description, &implementation) #:nodoc:
    Spec::Example::AwesomeExample.new(description, self, &implementation)
  end
end

class Spec::Example::AwesomeExample < Spec::Example::Example
  def initialize(defined_description=nil, example_group=nil, &implementation)
    super(defined_description, &implementation)
    @example_group = example_group
  end
  
  # Checks that the action redirected:
  #
  #   it.redirects_to { foo_path(@foo) }
  # 
  # Provide a better hint than Proc#inspect
  #
  #   it.redirects_to("foo_path(@foo)") { foo_path(@foo) }
  #
  def redirects_to(hint = nil, &route)
    @defined_description = "redirects to #{(hint || route).inspect}"
    @implementation = lambda do
      acting.should redirect_to(instance_eval(&route))
    end
  end

  # Check that an instance variable was set to the instance variable of the same name 
  # in the Spec Example:
  #
  #   it.assigns :foo # => assigns[:foo].should == @foo
  #
  # Check multiple instance variables
  # 
  #   it.assigns :foo, :bar
  #
  # Check the instance variable was set to something more specific
  #
  #   it.assigns :foo => 'bar'
  #
  # Check the instance variable is not nil:
  #
  #   it.assigns :foo => :not_nil # assigns[:foo].should_not be_nil
  #
  # Check the instance variable is nil
  #
  #   it.assigns :foo => nil # => assigns[:foo].should be_nil
  #
  # Check the instance variable was not set at all
  #
  #   it.assigns :foo => :undefined # => controller.send(:instance_variables).should_not include("@foo")
  #
  def assigns(*names)
    if names.size == 1
      if names.first.is_a?(Hash)
        names.first.each do |key, value|
          if @defined_description
            desc, imp = assigns_example_values(key, value)
            create_sub_example desc, &imp if @example_group
          else
            @defined_description, @implementation = assigns_example_values(key, value)
          end
        end
      else
        @defined_description, @implementation = assigns_example_values(names.first, names.first)
      end
    else
      assigns(names.pop) # go forth and recurse!
      names.each do |name|
        desc, imp = assigns_example_values(name, name)
        create_sub_example desc, &imp
      end if @example_group
    end
  end
  
  # See protected #render_blank, #render_template, and #render_xml for details.
  #
  #   it.renders :blank
  #   it.renders :template, :new
  #   it.renders :xml, :foo
  #
  def renders(render_method, *args, &block)
    send("render_#{render_method}", *args, &block)
  end
  
  # Check that the flash variable(s) were assigned
  #
  #   it.assigns_flash :notice => 'foo',
  #     :this_is_nil => nil,
  #     :this_is_undefined => :undefined,
  #     :this_is_set => :not_nil
  #
  def assigns_flash(flash)
    flash.each do |key, value|
      if @defined_description
        desc, imp = assigns_flash_values(key, value)
        create_sub_example desc, &imp
      else
        @defined_description, @implementation = assigns_flash_values(key, value)
      end
    end
  end

  # Check that the session variable(s) were assigned
  #
  #   it.assigns_session :notice => 'foo',
  #     :this_is_nil => nil,
  #     :this_is_undefined => :undefined,
  #     :this_is_set => :not_nil
  #
  def assigns_session(session)
    session.each do |key, value|
      if @defined_description
        desc, imp = assigns_session_values(key, value)
        create_sub_example desc, &imp
      else
        @defined_description, @implementation = assigns_session_values(key, value)
      end
    end
  end

  # Check that the HTTP header(s) were assigned
  #
  #   it.assigns_headers :Location => 'foo',
  #     :this_is_nil => nil,
  #     :this_is_undefined => :undefined,
  #     :this_is_set => :not_nil
  #
  def assigns_headers(headers)
    headers.each do |key, value|
      if @defined_description
        desc, imp = assigns_header_values(key, value)
        create_sub_example desc, &imp
      else
        @defined_description, @implementation = assigns_header_values(key, value)
      end
    end
  end
  
protected
  # Creates 2 examples:  One to check that the body is blank,
  # and the other to check the status.  It looks for one option:
  # :status.  If unset, it checks that that the response was a success.
  # Otherwise it takes an integer or a symbol and matches the status code.
  #
  #   it.renders :blank
  #   it.renders :blank, :status => :not_found
  #
  def render_blank(options = {})
    @defined_description = "renders a blank response"
    @implementation = lambda do
      acting do |response|
        response.body.strip.should be_blank
      end
    end
    assert_status options[:status] if @example_group
  end

  # Creates 3 examples: One to check that the given template was rendered.
  # It looks for two options: :status and :format.
  #
  #   it.renders :template, :index
  #   it.renders :template, :index, :status => :not_found
  #   it.renders :template, :index, :format => :xml
  #
  # If :status is unset, it checks that that the response was a success.
  # Otherwise it takes an integer or a symbol and matches the status code.
  #
  # If :format is unset, it checks that the action is Mime:HTML.  Otherwise
  # it attempts to match the mime type using Mime::Type.lookup_by_extension.
  #
  def render_template(template_name, options = {})
    @defined_description = "renders #{template_name}"
    @implementation = lambda do
      acting.should render_template(template_name.to_s)
    end
    if @example_group
      assert_status options[:status]
      assert_content_type options[:format]
    end
  end

  # Creates 3 examples: One to check that the given XML was returned.
  # It looks for two options: :status and :format.
  #
  # Checks that the xml matches a given string
  #
  #   it.renders :xml, "<foo />"
  #
  # Checks that the xml matches @foo.to_xml
  #
  #   it.renders :xml, :foo
  #
  # Checks that the xml matches @foo.errors.to_xml
  #
  #   it.renders :xml, "foo.errors".intern
  #
  #   it.renders :xml, :index, :status => :not_found
  #   it.renders :xml, :index, :format => :xml
  #
  # If :status is unset, it checks that that the response was a success.
  # Otherwise it takes an integer or a symbol and matches the status code.
  #
  # If :format is unset, it checks that the action is Mime:HTML.  Otherwise
  # it attempts to match the mime type using Mime::Type.lookup_by_extension.
  #
  def render_xml(string = nil, options = {}, &string_proc)
    if string.is_a?(Hash)
      options = string
      string  = nil
    end
    @defined_description = "renders xml"
    @implementation = lambda do
      if string_proc || string.is_a?(Symbol)
        string_proc ||= lambda { |record| record.to_xml }
        pieces = string.to_s.split(".")
        string = pieces.shift
        record = instance_variable_get("@#{string}")
        until pieces.empty?
          record = record.send(pieces.shift)
        end
        acting.should have_text(string_proc.call(record))
      else
        acting.should have_text(string)
      end
    end
    if @example_group
      assert_status options[:status]
      assert_content_type options[:format] || :xml
    end
  end

  def assigns_example_values(name, value)
    ["assigns @#{name}", lambda do
      act!
      value = 
        case value
        when :not_nil
          assigns[name].should_not be_nnil
        when :undefined
          controller.send(:instance_variables).should_not include("@#{name}")
        when Symbol
          assigns[name].should == instance_variable_get("@#{value}")
        end
      
    end]
  end
  
  def assigns_header_values(key, value)
    ["assigns #{key.inspect} header", lambda do
      acting do |resp|
        value = instance_eval(&value) if value.respond_to?(:call)
        assert_collection_value resp.headers, key.to_s, value
      end
    end]
  end
  
  def assigns_flash_values(key, value)
    ["assigns flash[#{key.inspect}]", lambda do
      acting do |resp|
        value = instance_eval(&value) if value.respond_to?(:call)
        assert_collection_value resp.flash, key, value
      end
    end]
  end
  
  def assigns_session_values(key, value)
    ["assigns session[#{key.inspect}]", lambda do
      acting do |resp|
        value = instance_eval(&value) if value.respond_to?(:call)
        assert_collection_value resp.session, key, value
      end
    end]
  end

  def assert_content_type(type = nil)
    mime = Mime::Type.lookup_by_extension((type ||= :html).to_s)
    create_sub_example "renders with Content-Type of #{mime}" do
      acting.content_type.should == mime
    end
  end
  
  def assert_status(status)
    case status
    when String, Fixnum
      code = ActionController::StatusCodes::STATUS_CODES[status.to_i]
      create_sub_example "renders with status of #{code.inspect}" do
        acting.code.should == status.to_s
      end
    when Symbol
      code_value = ActionController::StatusCodes::SYMBOL_TO_STATUS_CODE[status]
      code       = ActionController::StatusCodes::STATUS_CODES[code_value]
      create_sub_example "renders with status of #{code.inspect}" do
        acting.code.should == code_value.to_s
      end
    else
      create_sub_example "is successful" do
        acting.should be_success
      end
    end
  end
  
  def create_sub_example(desc, &imp)
    @example_group.send(:example_objects) << Spec::Example::AwesomeExample.new(desc, @example_group, &imp)
  end
end
require 'active_support'
require 'active_record'
require 'sham'
 
module Machinist
  def self.with_save_nerfed
    begin
      @@nerfed = true
      yield
    ensure
      @@nerfed = false
    end
  end
  
  @@nerfed = false
  def self.nerfed?
    @@nerfed
  end

  module ObjectExtensions
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def blueprint(&blueprint)
        @blueprint = blueprint
      end

      def make_unsaved(attributes = {})
        returning(Machinist.with_save_nerfed { make_it(attributes) }) do |object|
          yield object if block_given?
        end
      end

      def make_it(attributes = {})
        raise "No blueprint for class #{self}" if @blueprint.nil?
        lathe = Lathe.new(self, attributes)
        lathe.instance_eval(&@blueprint)
        returning(lathe.object) do |object|
          yield object if block_given?
        end
      end
    end
  end

  module ActiveRecordExtensions
    def self.included(base)
      base.extend(ClassMethods)
    end
    
    module ClassMethods
      def make(attributes = {})
        returning(make_it(attributes) do |object|
          unless Machinist.nerfed?
            object.save!
            object.reload
          end
        end) do |obj|
          yield obj if block_given?
        end
      end
    end
  end
  
  class Lathe
    def initialize(klass, attributes={})
      @object = klass.new
      @assigned_attributes = attributes.keys.map(&:to_sym)
      attributes.each_pair {|method_name, value| @object.send("#{method_name}=", value)}
    end

    attr_reader :object

    def method_missing(symbol, *args, &block)
      if @assigned_attributes.include?(symbol)
        @object.send(symbol)
      else
        value = if block
          block.call
        elsif args.first.is_a?(Hash) || args.empty?
          symbol.to_s.camelize.constantize.make_it(args.first || {})
        else
          args.first
        end
        @object.send("#{symbol}=", value)
        @assigned_attributes << symbol
      end
    end
  end
end

class Object
  include Machinist::ObjectExtensions
end

class ActiveRecord::Base
  include Machinist::ActiveRecordExtensions
end

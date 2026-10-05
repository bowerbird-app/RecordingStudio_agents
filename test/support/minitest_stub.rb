# frozen_string_literal: true

# Minitest 6 dropped Object#stub. Keep the old call shape for this suite.
module MinitestStub
  def stub(name, val_or_callable, *block_args)
    name = name.to_sym
    backup_name = :"__minitest_stub__#{name}"
    metaclass = singleton_class

    MinitestStub.ensure_method!(metaclass, name)
    metaclass.alias_method backup_name, name
    metaclass.define_method(name) do |*args, **kwargs, &blk|
      MinitestStub.call_stub(val_or_callable, args, kwargs, block_args, blk)
    end

    yield self
  ensure
    MinitestStub.restore!(metaclass, name, backup_name)
  end

  module_function

  def defined_on?(metaclass, name)
    metaclass.method_defined?(name) || metaclass.private_method_defined?(name)
  end

  def ensure_method!(metaclass, name)
    return if defined_on?(metaclass, name)

    metaclass.define_method(name) do |*args, **kwargs, &blk|
      super(*args, **kwargs, &blk)
    end
  end

  def call_stub(val_or_callable, args, kwargs, block_args, blk)
    return val_or_callable unless val_or_callable.respond_to?(:call)

    if kwargs.empty?
      val_or_callable.call(*args, *block_args, &blk)
    else
      val_or_callable.call(*args, *block_args, **kwargs, &blk)
    end
  end

  def restore!(metaclass, name, backup_name)
    return unless defined_on?(metaclass, backup_name)

    metaclass.alias_method name, backup_name
    metaclass.remove_method backup_name
  end
end

Object.include MinitestStub unless Object.method_defined?(:stub)

# frozen_string_literal: true

module McpJsonSchema
  module_function

  def error(schema, value)
    schema = stringify(schema)
    value = json(value)
    return one_of_error(schema, value) if schema["oneOf"]

    check_type(schema, value)
  end

  def stringify(value)
    JSON.parse(JSON.generate(value))
  end

  def json(value)
    stringify(value)
  rescue JSON::GeneratorError, TypeError
    value
  end

  def one_of_error(schema, value)
    return if schema["oneOf"].any? { |branch| error(branch, value).nil? }

    "value did not match oneOf"
  end

  def check_type(schema, value)
    type = schema["type"]
    return union_error(type, schema, value) if type.is_a?(Array)

    send(:"#{type}_error", schema, value)
  end

  def union_error(types, schema, value)
    return if types.any? { |entry| check_type(schema.merge("type" => entry), value).nil? }

    "expected #{types.join(' or ')}"
  end

  def null_error(_schema, value)
    value.nil? ? nil : "expected null"
  end

  def string_error(_schema, value)
    value.is_a?(String) ? nil : "expected string"
  end

  def boolean_error(_schema, value)
    [true, false].include?(value) ? nil : "expected boolean"
  end

  def integer_error(_schema, value)
    value.is_a?(Integer) ? nil : "expected integer"
  end

  def number_error(_schema, value)
    value.is_a?(Numeric) ? nil : "expected number"
  end

  def array_error(schema, value)
    return "expected array" unless value.is_a?(Array)
    return unless schema["items"]

    value.each do |entry|
      message = error(schema["items"], entry)
      return message if message
    end
    nil
  end

  def object_error(schema, value)
    return "expected object" unless value.is_a?(Hash)

    keys = value.keys
    missing = Array(schema["required"]) - keys
    return "missing #{missing.first}" if missing.any?
    return "unexpected #{(keys - properties(schema).keys).first}" if extra?(schema, keys)

    properties(schema).each do |name, child|
      next unless value.key?(name)

      message = error(child, value[name])
      return "#{name}: #{message}" if message
    end
    nil
  end

  def properties(schema)
    schema["properties"] || {}
  end

  def extra?(schema, keys)
    schema["additionalProperties"] == false && (keys - properties(schema).keys).any?
  end
end

# frozen_string_literal: true

module RecordingStudioAgents
  module ExtensionInstaller
    def apply_model_extensions(target)
      apply_extensions(target, extensions_for(:model, extension_keys_for(target)))
    end

    def apply_controller_extensions(target)
      apply_extensions(target, extensions_for(:controller, extension_keys_for(target)))
    end

    private

    def extensions_for(kind, names)
      hooks = RecordingStudioAgents.configuration.hooks
      Array(names).flat_map do |name|
        if kind == :model
          hooks.model_extensions_for(name)
        else
          hooks.controller_extensions_for(name)
        end
      end
    end

    def apply_extensions(target, extensions)
      return unless target

      applied = target.instance_variable_get(:@recording_studio_agents_applied_extensions) || identity_hash

      extensions.flatten.compact.each do |extension|
        next if applied[extension]

        target.class_eval(&extension)
        applied[extension] = true
      end

      target.instance_variable_set(:@recording_studio_agents_applied_extensions, applied)
    end

    def extension_keys_for(target)
      names = [target.name, target.name&.demodulize].compact.uniq
      names.map(&:to_sym)
    end

    def identity_hash
      {}.compare_by_identity
    end
  end
end

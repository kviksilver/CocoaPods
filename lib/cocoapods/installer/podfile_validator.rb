module Pod
  class Installer
    # Validate the podfile before installing to catch errors and
    # problems
    #
    class PodfileValidator
      # @return [Podfile] The podfile being validated
      #
      attr_reader :podfile

      # @return [Array<String>] any errors that have occured during the validation
      #
      attr_reader :errors

      # @return [Array<String>] any warnings that have occured during the validation
      #
      attr_reader :warnings


      # Initialize a new instance
      # @param [Podfile] podfile
      #        The podfile to validate
      #
      def initialize(podfile)
        @podfile = podfile
        @errors = []
        @warnings = []
        @validated = false
      end

      # Validate the podfile
      # Errors are added to the errors array
      #
      def validate
        validate_pod_directives
        validate_no_abstract_only_pods!
        validate_dependencies_are_present!

        @validated = true
      end

      # Wether the podfile is valid is not
      # NOTE: Will execute `validate` if the podfile
      # has not yet been validated
      #
      def valid?
        validate unless @validated

        @validated && errors.empty?
      end

      # A message describing any errors in the
      # validation
      #
      def message
        errors.join("\n")
      end

      private

      def add_error(error)
        errors << error
      end

      def add_warning(warning)
        warnings << warning
      end

      def validate_pod_directives
        dependencies = podfile.target_definitions.flat_map do |_, target|
          target.dependencies
        end.uniq

        dependencies.each do |dependency|
          validate_conflicting_external_sources!(dependency)
        end
      end

      def validate_conflicting_external_sources!(dependency)
        external_source = dependency.external_source
        return false if external_source.nil?

        available_downloaders = Downloader.downloader_class_by_key.keys
        specified_downloaders = external_source.select { |key| available_downloaders.include?(key) }
        if specified_downloaders.size > 1
          add_error "The dependency `#{dependency.name}` specifies more than one download strategy(#{specified_downloaders.keys.join(',')})." \
            'Only one is allowed'
        end

        pod_spec_or_path = external_source[:podspec].present? || external_source[:path].present?
        if pod_spec_or_path && specified_downloaders.size > 0
          add_error "The dependency `#{dependency.name}` specifies `podspec` or `path` in combination with other" \
            ' download strategies. This is not allowed'
        end
      end

      # Warns the user if the podfile is empty.
      #
      # @note   The workspace is created in any case and all the user projects
      #         are added to it, however the projects are not integrated as
      #         there is no way to discern between target definitions which are
      #         empty and target definitions which just serve the purpose to
      #         wrap other ones. This is not an issue because empty target
      #         definitions generate empty libraries.
      #
      # @return [void]
      #
      def validate_dependencies_are_present!
        if podfile.target_definitions.values.all?(&:empty?)
          add_warning 'The Podfile does not contain any dependencies.'
        end
      end

      def validate_no_abstract_only_pods!
        abstract_pods = ->(target_definition) do
          if !target_definition.abstract? || !target_definition.children.empty?
            target_definition.children.flat_map do |td|
              abstract_pods[td]
            end
          else
            target_definition.dependencies
          end
        end
        pods = podfile.root_target_definitions.flat_map(&abstract_pods).uniq
        pods.each do |pod|
          add_error "The dependency `#{pod}` is not used in any concrete target."
        end
      end
    end
  end
end

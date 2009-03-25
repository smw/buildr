require 'buildr/core/build'
require 'buildr/core/compile'
require 'buildr/java/bdd'
require 'buildr/scala/tests'

module Buildr::Scala
  
  # Specs is a Scala based BDD framework.
  # To use in your project:
  #
  #   test.using :specs
  # 
  # This framework will search in your project for:
  #   src/spec/scala/**/*.scala
  class Specs < Buildr::TestFramework::JavaBDD
    @lang = :scala
    @bdd_dir = :spec

    VERSION = '1.4.3'
    
    class << self
      def version
        Buildr.settings.build['scala.specs'] || VERSION
      end
      
      def dependencies
        ["org.specs:specs:jar:#{version}"] + Check.dependencies + 
          JMock.dependencies + JUnit.dependencies
      end
      
      def applies_to?(project)  #:nodoc:
        !Dir[project.path_to(:source, bdd_dir, lang, '**/*.scala')].empty?
      end

    private
      def const_missing(const)
        return super unless const == :REQUIRES # TODO: remove in 1.5
        Buildr.application.deprecated "Please use Scala::Specs.dependencies/.version instead of ScalaSpecs::REQUIRES/VERSION"
        dependencies
      end
    end

    def initialize(task, options) #:nodoc:
      super
      
      specs = task.project.path_to(:source, :spec, :scala)
      task.compile.from specs if File.directory?(specs)
      
      resources = task.project.path_to(:source, :spec, :resources)
      task.resources.from resources if File.directory?(resources)
    end
    
    def tests(dependencies)
      dependencies += [task.compile.target.to_s]
      filter_classes(dependencies, :interfaces => ['org.specs.Specification'])
    end
    
    def run(specs, dependencies)  #:nodoc:
      dependencies += [task.compile.target.to_s] + Scalac.dependencies
      
      cmd_options = { :properties => options[:properties],
                      :java_args => options[:java_args],
                      :classpath => dependencies}
      
      specs.inject [] do |passed, spec|
        begin
          Java.load
          Java::Commands.java(spec, cmd_options)
        rescue => e
          passed
        else
          passed << spec
        end
      end
    end
  end
end

# Backwards compatibility stuff.  Remove in 1.5.
module Buildr
  ScalaSpecs = Scala::Specs
end

Buildr::TestFramework << Buildr::Scala::Specs

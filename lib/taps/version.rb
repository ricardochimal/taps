require "yaml"

module Taps
  def self.version_yml
    @@version_yml ||= YAML.load(File.read(File.dirname(__FILE__) + '/../../VERSION.yml'))
  end

  def self.version
    version = "#{version_yml[:major]}.#{version_yml[:minor]}.#{version_yml[:patch]}"
    version += ".#{version_yml[:build]}" if version_yml[:build]
    version
  end

  def self.compatible_version
    "#{version_yml[:major]}.#{version_yml[:minor]}"
  end
end


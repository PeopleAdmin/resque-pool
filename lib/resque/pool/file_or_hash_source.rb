class FileOrHashSource
  def initialize(filename_or_hash=nil)
    case filename_or_hash
    when String, nil
      @filename = filename_or_hash
    when Hash
      @static_config = filename_or_hash.dup
    else
      raise "#{self.class} cannot be initialized with #{filename_or_hash.inspect}"
    end
  end

  def retrieve_config(environment)
    @config ||= load_config_from_file(environment)
  end

  def reset!
    @config = nil
  end

  private

  def load_config_from_file(environment)
    if @static_config
      new_config = @static_config
    else
      filename = @filename || choose_config_file
      if filename
        new_config = YAML.load(ERB.new(IO.read(filename)).result)
      else
        new_config = {}
      end
    end
    environment and new_config[environment] and new_config.merge!(new_config[environment])
    new_config.delete_if {|key, value| value.is_a? Hash }
  end

  CONFIG_FILES = ["resque-pool.yml", "config/resque-pool.yml"]
  def choose_config_file
    if ENV["RESQUE_POOL_CONFIG"]
      ENV["RESQUE_POOL_CONFIG"]
    else
      CONFIG_FILES.detect { |f| File.exist?(f) }
    end
  end
end

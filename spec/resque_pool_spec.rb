require 'spec_helper'

RSpec.configure do |config|
  config.after {
    Object.send(:remove_const, :RAILS_ENV) if defined? RAILS_ENV
    ENV.delete 'RACK_ENV'
    ENV.delete 'RAILS_ENV'
    ENV.delete 'RESQUE_ENV'
  }
end

describe Resque::Pool, "when loading a simple pool configuration" do
  let(:config) do
    { 'foo' => 1, 'bar' => 2, 'foo,bar' => 3, 'bar,foo' => 4, }
  end
  subject { Resque::Pool.new(config) }

  context "when ENV['RACK_ENV'] is set" do
    before { ENV['RACK_ENV'] = 'development' }

    it "should load the values from the Hash" do
      subject.config["foo"].should == 1
      subject.config["bar"].should == 2
      subject.config["foo,bar"].should == 3
      subject.config["bar,foo"].should == 4
    end
  end

end

describe Resque::Pool, "when loading the pool configuration from a Hash" do

  let(:config) do
    {
      'foo' => 8,
      'test'        => { 'bar' => 10, 'foo,bar' => 12 },
      'development' => { 'baz' => 14, 'foo,bar' => 16 },
    }
  end

  subject { Resque::Pool.new(config) }

  context "when RAILS_ENV is set" do
    before { RAILS_ENV = "test" }

    it "should load the default values from the Hash" do
      subject.config["foo"].should == 8
    end

    it "should merge the values for the correct RAILS_ENV" do
      subject.config["bar"].should == 10
      subject.config["foo,bar"].should == 12
    end

    it "should not load the values for the other environments" do
      subject.config["foo,bar"].should == 12
      subject.config["baz"].should be_nil
    end

  end

  context "when Rails.env is set" do
    before(:each) do
      module Rails; end
      Rails.stub(:env).and_return('test')
    end

    it "should load the default values from the Hash" do
      subject.config["foo"].should == 8
    end

    it "should merge the values for the correct RAILS_ENV" do
      subject.config["bar"].should == 10
      subject.config["foo,bar"].should == 12
    end

    it "should not load the values for the other environments" do
      subject.config["foo,bar"].should == 12
      subject.config["baz"].should be_nil
    end

    after(:all) { Object.send(:remove_const, :Rails) }
  end


  context "when ENV['RESQUE_ENV'] is set" do
    before { ENV['RESQUE_ENV'] = 'development' }
    it "should load the config for that environment" do
      subject.config["foo"].should == 8
      subject.config["foo,bar"].should == 16
      subject.config["baz"].should == 14
      subject.config["bar"].should be_nil
    end
  end

  context "when there is no environment" do
    it "should load the default values only" do
      subject.config["foo"].should == 8
      subject.config["bar"].should be_nil
      subject.config["foo,bar"].should be_nil
      subject.config["baz"].should be_nil
    end
  end

end

describe Resque::Pool, "given no configuration" do
  subject { Resque::Pool.new(nil) }
  it "should have no worker types" do
    subject.config.should == {}
  end
end

describe Resque::Pool, "when loading the pool configuration from a file" do

  subject { Resque::Pool.new("spec/resque-pool.yml") }

  context "when RAILS_ENV is set" do
    before { RAILS_ENV = "test" }

    it "should load the default YAML" do
      subject.config["foo"].should == 1
    end

    it "should merge the YAML for the correct RAILS_ENV" do
      subject.config["bar"].should == 5
      subject.config["foo,bar"].should == 3
    end

    it "should not load the YAML for the other environments" do
      subject.config["foo"].should == 1
      subject.config["bar"].should == 5
      subject.config["foo,bar"].should == 3
      subject.config["baz"].should be_nil
    end

  end

  context "when ENV['RACK_ENV'] is set" do
    before { ENV['RACK_ENV'] = 'development' }
    it "should load the config for that environment" do
      subject.config["foo"].should == 1
      subject.config["foo,bar"].should == 4
      subject.config["baz"].should == 23
      subject.config["bar"].should be_nil
    end
  end

  context "when there is no environment" do
    it "should load the default values only" do
      subject.config["foo"].should == 1
      subject.config["bar"].should be_nil
      subject.config["foo,bar"].should be_nil
      subject.config["baz"].should be_nil
    end
  end

  context "when a custom file is specified" do
    before { ENV["RESQUE_POOL_CONFIG"] = 'spec/resque-pool-custom.yml.erb' }
    subject { Resque::Pool.new }
    it "should find the right file, and parse the ERB" do
      subject.config["foo"].should == 2
    end
  end

  context "when the file changes" do
    require 'tempfile'

    let(:config_file_path) {
      config_file = Tempfile.new("resque-pool-test")
      config_file.write "orig: 1"
      config_file.close
      config_file.path
    }

    subject {
      Resque::Pool.new(config_file_path).tap{|p| p.stub(:spawn_worker!) {} }
    }

    it "should not automatically load the changes" do
      subject.config.keys.should == ["orig"]

      File.open(config_file_path, "w"){|f| f.write "changed: 1"}
      subject.config.keys.should == ["orig"]
    end

    it "should reload the changes on HUP signal" do
      subject.config.keys.should == ["orig"]

      File.open(config_file_path, "w"){|f| f.write "changed: 1"}
      subject.config.keys.should == ["orig"]

      simulate_signal :HUP

      subject.config.keys.should == ["changed"]
    end

    def simulate_signal(signal)
      subject.sig_queue.clear
      subject.sig_queue.push signal
      subject.handle_sig_queue!
    end
  end

end

describe Resque::Pool, "when loading the pool configuration from a custom source" do
  it "should retrieve the config based on the environment" do
    custom_source = double(retrieve_config: Hash.new)
    RAILS_ENV = "env"

    Resque::Pool.new(custom_source)

    custom_source.should have_received(:retrieve_config).with("env")
  end

  it "should reset the config source on HUP" do
    custom_source = double(retrieve_config: Hash.new)

    pool = Resque::Pool.new(custom_source)
    custom_source.should have_received(:retrieve_config).once

    pool.sig_queue.push :HUP
    pool.handle_sig_queue!
    custom_source.should have_received(:retrieve_config).twice
  end

end

describe "the class-level .config_source attribute" do
  context "when not provided" do
    subject { Resque::Pool.create_configured }

    it "created pools use config file and hash loading logic" do
      subject.config_source.should be_instance_of FileOrHashSource
    end
  end

  context "when provided with a custom config source" do
    let(:custom_config_source) {
      double(retrieve_config: Hash.new, refresh!: true)
    }
    before(:each) { Resque::Pool.config_source = custom_config_source }
    after(:each) { Resque::Pool.config_source = nil }
    subject { Resque::Pool.create_configured }

    it "created pools use the specified config source" do
      subject.config_source.should == custom_config_source
    end
  end

end

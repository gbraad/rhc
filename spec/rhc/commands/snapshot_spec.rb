require 'spec_helper'
require 'rest_spec_helper'
require 'rhc/commands/snapshot'
require 'rhc/config'
require 'rhc/tar_gz'

describe RHC::Commands::Snapshot do

  APP_NAME = 'mockapp'

  let!(:rest_client) { MockRestClient.new }
  before do
    user_config
    @app = rest_client.add_domain("mockdomain").add_application APP_NAME, 'mock-1.0'
    @ssh_uri = URI.parse @app.ssh_url
    @targz_filename = APP_NAME + '.tar.gz'
    FileUtils.cp(File.expand_path('../../assets/targz_sample.tar.gz', __FILE__), @targz_filename)
    File.chmod 0644, @targz_filename unless File.executable? @targz_filename
  end

  after do
    File.delete @targz_filename if File.exist? @targz_filename
  end

  describe 'snapshot without an action' do
    let(:arguments) {['snapshot', '--trace', '--noprompt']}
    it('should raise') { expect{ run }.to raise_error(ArgumentError, /Please specify an action to take/) }
  end

  describe 'snapshot save' do
    let(:arguments) {['snapshot', 'save', '--noprompt', '--config', 'test.conf', '-l', 'test@test.foo', '-p', 'password', '--app', 'mockapp']}

    context 'when saving a snapshot' do
      before(:each) do
        `(exit 0)`
        Kernel.should_receive(:`).with("ssh #{@ssh_uri.user}@#{@ssh_uri.host} 'snapshot' > #{@app.name}.tar.gz")
      end
      it { expect { run }.to exit_with_code(0) }
    end

    context 'when failing to save a snapshot' do
      before(:each) do
        `(exit 1)`
        Kernel.should_receive(:`).with("ssh #{@ssh_uri.user}@#{@ssh_uri.host} 'snapshot' > #{@app.name}.tar.gz")
      end
      it { expect { run }.to exit_with_code(130) }
    end

    context 'when saving a snapshot on windows' do
      before(:each) do
        RHC::Helpers.stub(:windows?) do ; true; end
        RHC::Helpers.stub(:jruby?) do ; false ; end
        RHC::Helpers.stub(:linux?) do ; false ; end
        ssh = double(Net::SSH)
        Net::SSH.should_receive(:start).with(@ssh_uri.host, @ssh_uri.user).and_yield(ssh)
        ssh.should_receive(:exec!).with("snapshot").and_yield(nil, :stdout, 'foo').and_yield(nil, :stderr, 'foo')
      end
      it { expect { run }.to exit_with_code(0) }
      it { run_output.should match("Success") }
    end

    context 'when timing out on windows' do
      before(:each) do
        RHC::Helpers.stub(:windows?) do ; true; end
        RHC::Helpers.stub(:jruby?) do ; false ; end
        RHC::Helpers.stub(:linux?) do ; false ; end
        ssh = double(Net::SSH)
        Net::SSH.should_receive(:start).with(@ssh_uri.host, @ssh_uri.user).and_raise(Timeout::Error)
      end
      it { expect { run }.to exit_with_code(130) }
    end

  end

  describe 'snapshot save with invalid ssh executable' do
    let(:arguments) {['snapshot', 'save', '--trace', '--noprompt', '-l', 'test@test.foo', '-p', 'password', '--app', 'mockapp', '--ssh', 'path_to_ssh']}
    it('should raise') { expect{ run }.to raise_error(RHC::InvalidSSHExecutableException, /SSH executable 'path_to_ssh' does not exist./) }
  end

  describe 'snapshot save when ssh is not executable' do
    let(:arguments) {['snapshot', 'save', '--trace', '--noprompt', '-l', 'test@test.foo', '-p', 'password', '--app', 'mockapp', '--ssh', @targz_filename]}
    it('should raise') { expect{ run }.to raise_error(RHC::InvalidSSHExecutableException, /SSH executable '#{@targz_filename}' is not executable./) }
  end

  describe 'snapshot restore' do
    let(:arguments) {['snapshot', 'restore', '--noprompt', '-l', 'test@test.foo', '-p', 'password', '--app', 'mockapp']}

    context 'when restoring a snapshot' do
      before(:each) do
        File.stub(:exists?).and_return(true)
        RHC::TarGz.stub(:contains).and_return(true)
        `(exit 0)`
        Kernel.should_receive(:`).with("cat '#{@app.name}.tar.gz' | ssh #{@ssh_uri.user}@#{@ssh_uri.host} 'restore INCLUDE_GIT'")
      end
      it { expect { run }.to exit_with_code(0) }
    end

    context 'when restoring a snapshot and failing to ssh' do
      before(:each) do
        File.stub(:exists?).and_return(true)
        RHC::TarGz.stub(:contains).and_return(true)
        Kernel.should_receive(:`).with("cat '#{@app.name}.tar.gz' | ssh #{@ssh_uri.user}@#{@ssh_uri.host} 'restore INCLUDE_GIT'")
        $?.stub(:exitstatus) { 1 }
      end
      it { expect { run }.to exit_with_code(130) }
    end

    context 'when restoring a snapshot on windows' do
      before(:each) do
        RHC::Helpers.stub(:windows?) do ; true; end
        RHC::Helpers.stub(:jruby?) do ; false ; end
        RHC::Helpers.stub(:linux?) do ; false ; end
        ssh = double(Net::SSH)
        session = double(Net::SSH::Connection::Session)
        channel = double(Net::SSH::Connection::Channel)
        Net::SSH.should_receive(:start).with(@ssh_uri.host, @ssh_uri.user).and_return(session)
        session.should_receive(:open_channel).and_yield(channel)
        channel.should_receive(:exec).with("restore INCLUDE_GIT").and_yield(nil, nil)
        channel.should_receive(:on_data).and_yield(nil, 'foo')
        channel.should_receive(:on_extended_data).and_yield(nil, nil, 'foo')
        channel.should_receive(:on_close).and_yield(nil)
        lines = ''
        File.open(File.expand_path('../../assets/targz_sample.tar.gz', __FILE__), 'rb') do |file|
          file.chunk(1024) do |chunk|
            lines << chunk
          end
        end
        channel.should_receive(:send_data).with(lines)
        channel.should_receive(:eof!)
        session.should_receive(:loop)
      end
      it { expect { run }.to exit_with_code(0) }
    end

    context 'when timing out on windows' do
      before(:each) do
        RHC::Helpers.stub(:windows?) do ; true; end
        RHC::Helpers.stub(:jruby?) do ; false ; end
        RHC::Helpers.stub(:linux?) do ; false ; end
        ssh = double(Net::SSH)
        Net::SSH.should_receive(:start).with(@ssh_uri.host, @ssh_uri.user).and_raise(Timeout::Error)
      end
      it { expect { run }.to exit_with_code(130) }
    end

  end

  describe 'snapshot restore file not found' do
    let(:arguments) {['snapshot', 'restore', '--noprompt', '-l', 'test@test.foo', '-p', 'password', '--app', 'mockapp', '-f', 'foo.tar.gz']}
    context 'when restoring a snapshot' do
      it { expect { run }.to exit_with_code(130) }
    end
  end

  describe 'snapshot restore with invalid ssh executable' do
    let(:arguments) {['snapshot', 'restore', '--trace', '--noprompt', '-l', 'test@test.foo', '-p', 'password', '--app', 'mockapp', '--ssh', 'path_to_ssh']}
    it('should raise') { expect{ run }.to raise_error(RHC::InvalidSSHExecutableException, /SSH executable 'path_to_ssh' does not exist./) }
  end

  describe 'snapshot save when ssh is not executable' do
    let(:arguments) {['snapshot', 'restore', '--trace', '--noprompt', '-l', 'test@test.foo', '-p', 'password', '--app', 'mockapp', '--ssh', @targz_filename]}
    it('should raise') { expect{ run }.to raise_error(RHC::InvalidSSHExecutableException, /SSH executable '#{@targz_filename}' is not executable./) }
  end
end


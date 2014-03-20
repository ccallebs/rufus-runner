dir = File.expand_path(File.join(__FILE__, '../..'))
$:.unshift(dir) unless $:.include?(dir)

require 'rufus-runner'
require 'support'

module ScheduleHelper
  TEST_SCHEDULE = Pathname.new('tmp/schedule.rb').expand_path
  CHILD_OUTPUT  = Pathname.new('tmp/stdout').expand_path

  def create_schedule(string)
    TEST_SCHEDULE.open('w') do |io|
      io.puts %{
        dir = File.expand_path(File.join(__FILE__, '../..'))
        $:.unshift(dir) unless $:.include?(dir)
        require "spec/support"
      }
      io.write string
    end
  end

  def remove_schedule
    TEST_SCHEDULE.delete_if_exist
  end

  def run_schedule
    raise 'already started' if @schedule_pid
    CHILD_OUTPUT.delete_if_exist

    @schedule_pid = fork do
      STDOUT.reopen CHILD_OUTPUT.open('a')
      STDERR.reopen CHILD_OUTPUT.open('a')

      if TEST_SCHEDULE.exist?
        exec "bin/rufus-runner #{TEST_SCHEDULE}"
      else
        exec "bin/rufus-runner"
      end
    end
  end

  def signal_schedule(signal)
    raise 'not started' unless @schedule_pid
    Process.kill(signal, @schedule_pid)
  end

  def wait_schedule
    raise 'not started' unless @schedule_pid
    status = Process.waitpid2(@schedule_pid).last
    @schedule_pid = nil
    status.exitstatus
  end

  def end_schedule
    return unless @schedule_pid
    # dont send KILL, otherwise the child processes will survive
    Process.kill('TERM', @schedule_pid)
    Process.wait(@schedule_pid)
    @schedule_pid = nil
  end

  def scheduler_output
    CHILD_OUTPUT.read
  end
end


module FileExpectationsHelper
  def wait_for_file(pathname)
    1.upto(500) do
      return true if pathname.exist?
      Kernel.sleep(20e-3)
    end
    return false
  end

  def expect_new_file(pathname)
    pathname = Pathname.new(pathname) if pathname.kind_of?(String)
    pathname.delete if pathname.exist?
    yield
    wait_for_file(pathname) and return
    raise 'file did not appear'
  end
end

module ProcessHelper
  class CrossProcessReturn
    def initialize
      @reader, @writer = IO.pipe
    end

    def capture
      yield(self)
      @writer.close
      result = Marshal.load(@reader.read) rescue nil
      @reader.close
      result
    end

    def return(value)
      @writer.print(Marshal.dump(value)) rescue nil
      @writer.close
    end
  end

  def get_from_other_process(&block)
    CrossProcessReturn.new.capture(&block)
  end

  def process_running?(pid)
    status = Process.getpgid(pid)
    true
  rescue Errno::ESRCH
    false
  end

  def wait_for_child_processes
    loop do
      Process.wait(-1) # wait for any child
    end
  rescue Errno::ECHILD
  end
end


RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  # config.order = 'random'

  config.include ScheduleHelper
  config.include FileExpectationsHelper
  config.include ProcessHelper

  config.after(:each) { end_schedule }
  config.after(:each) { remove_schedule }
end

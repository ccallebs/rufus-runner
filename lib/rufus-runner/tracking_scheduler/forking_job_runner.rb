require 'rufus-runner/tracking_scheduler/job_runner'

class Rufus::TrackingScheduler::ForkingJobRunner < Rufus::TrackingScheduler::JobRunner

  class UnexpectedExitStatus < StandardError; end

  def run_block
    @pid = fork do
      $PROGRAM_NAME = "rufus: #{@name}"
      @block.call
      exit 0
    end
    status = Process.wait2(@pid)[1]
    unless status.success?
      raise UnexpectedExitStatus.new(status.exitstatus)
    end
  rescue Rufus::Scheduler::TimeoutError
    log("timed out, killing")
    kill
    raise
  end

  def shutdown
    kill
  end


  private

  def kill
    Process.kill("KILL", @pid)
    Process.wait(@pid)
  rescue Errno::ESRCH, Errno::ECHILD
    # process already dead, which is fine
  end

end

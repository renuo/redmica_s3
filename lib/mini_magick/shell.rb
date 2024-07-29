require "mini_magick"
require "timeout"

MiniMagick::Shell.prepend Module.new {
  def run(command, options = {})
    stdout, stderr, status = execute(command, stdin: options[:stdin], timeout: options[:timeout])

    if status != 0 && options.fetch(:whiny, MiniMagick.whiny)
      fail MiniMagick::Error, "`#{command.join(" ")}` failed with status: #{status.inspect} and error:\n#{stderr}"
    end

    $stderr.print(stderr) unless options[:stderr] == false || stderr.strip == %(WARNING: The convert command is deprecated in IMv7, use "magick")

    [stdout, stderr, status]
  end

  private

  def execute_open3(command, options = {})
    require "open3"

    # We would ideally use Open3.capture3, but it wouldn't allow us to
    # terminate the command after timing out.
    Open3.popen3(*command) do |in_w, out_r, err_r, thread|
      [in_w, out_r, err_r].each(&:binmode)
      stdout_reader = Thread.new { out_r.read }
      stderr_reader = Thread.new { err_r.read }
      begin
        in_w.write options[:stdin].to_s
      rescue Errno::EPIPE
      end
      in_w.close

      timeout = options[:timeout] || MiniMagick.timeout
      unless thread.join(timeout)
        Process.kill("TERM", thread.pid) rescue nil
        Process.waitpid(thread.pid)      rescue nil
        raise Timeout::Error, "MiniMagick command timed out: #{command}"
      end

      [stdout_reader.value, stderr_reader.value, thread.value]
    end
  end

  def execute_posix_spawn(command, options = {})
    require "posix-spawn"
    timeout = options[:timeout] || MiniMagick.timeout
    child = POSIX::Spawn::Child.new(*command, input: options[:stdin].to_s, timeout: timeout)
    [child.out, child.err, child.status]
  rescue POSIX::Spawn::TimeoutExceeded
    raise Timeout::Error, "MiniMagick command timed out: #{command}"
  end
}

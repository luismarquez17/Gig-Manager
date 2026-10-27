ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.

# Clean up stale tmp/pids/server.pid if the process is no longer alive
pid_file = File.expand_path("../tmp/pids/server.pid", __dir__)
if File.file?(pid_file)
  begin
    pid = File.read(pid_file).to_i
    Process.kill(0, pid) if pid.positive?
  rescue Errno::ESRCH
    File.delete(pid_file)
  rescue Errno::EPERM
    # Process exists but owned by someone else
  end
end

# Waiters, as the gem's: command_executed polls get_command_invocation
# until a success, a failure or too many attempts, retries while the
# invocation does not exist, stops at an unexpected error, and calls
# before_attempt and before_wait.
require "aws-sdk-ssm"

ssm = Aws::SSM::Client.new(stub_responses: true)
params = { command_id: "c1", instance_id: "i-1" }

puts "waiter_names: #{ssm.waiter_names.inspect}"

ssm.stub_responses(:get_command_invocation, [{ status: "Pending" }, { status: "InProgress" }, { status: "Success" }])
attempts = []
waits = []
options = {
  delay: 0,
  before_attempt: ->(n) { attempts << n },
  before_wait: ->(n, resp) { waits << "#{n}:#{resp.data.status}" }
}
resp = ssm.wait_until(:command_executed, params, options)
puts "success: #{resp.status} attempts=#{attempts.inspect} waits=#{waits.inspect}"

ssm.stub_responses(:get_command_invocation, [{ status: "Pending" }, { status: "Failed" }])
begin
  ssm.wait_until(:command_executed, params, { delay: 0 })
rescue Aws::Waiters::Errors::FailureStateError => e
  puts "failure: #{e.class} #{e.message} #{e.response.status} #{e.is_a?(Aws::Waiters::Errors::WaiterFailed)}"
end

ssm.stub_responses(:get_command_invocation, ["InvocationDoesNotExist", { status: "Success" }])
puts "retry on error: #{ssm.wait_until(:command_executed, params, { delay: 0 }).status}"

ssm.stub_responses(:get_command_invocation, "InvalidCommandId")
begin
  ssm.wait_until(:command_executed, params, { delay: 0 })
rescue Aws::Waiters::Errors::UnexpectedError => e
  puts "unexpected: #{e.class} #{e.message} #{e.error.class} #{e.error.code}"
end

ssm.stub_responses(:get_command_invocation, { status: "Pending" })
begin
  ssm.wait_until(:command_executed, params, { delay: 0, max_attempts: 3 })
rescue Aws::Waiters::Errors::TooManyAttemptsError => e
  puts "too many: #{e.class} #{e.message} #{e.attempts}"
end

begin
  ssm.wait_until(:instance_running, params)
rescue Aws::Waiters::Errors::NoSuchWaiterError => e
  puts "no such waiter: #{e.class} #{e.message} #{e.is_a?(ArgumentError)}"
end

ssm.stub_responses(:get_command_invocation, [{ status: "Delayed" }, { status: "Success" }])
waiter = Aws::SSM::Waiters::CommandExecuted.new(client: ssm, max_attempts: 5, delay: 0)
puts "waiter class: #{waiter.waiter.max_attempts} #{waiter.waiter.delay} #{waiter.wait(params).status}"

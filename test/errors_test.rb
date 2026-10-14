# An error's data, as the gem parses it: the modeled error's members when
# the operation lists that error, its readers on the error, and an empty
# structure for a code the operation does not list, an unmodeled code and
# a body that is not JSON.
require "aws-sdk-ssm"

ssm = Aws::SSM::Client.new(stub_responses: true)

def show(label)
  yield
rescue Aws::SSM::Errors::ServiceError => e
  puts "#{label}: #{e.class} #{e.code} #{e.message.inspect}"
  puts "#{label} data: #{e.data.class} #{e.data.to_h}"
  e
end

ssm.stub_responses(:get_parameter, "ParameterNotFound")
e = show("stubbed code") { ssm.get_parameter(name: "/a") }
puts "stubbed code message member: #{e.data.message.inspect}"

def raw(ssm, operation, status, body)
  ssm.stub_responses(operation, { status_code: status, headers: {}, body: body })
end

raw(ssm, :create_resource_data_sync, 400, '{"__type":"com.amazonaws.ssm#ResourceDataSyncAlreadyExistsException","SyncName":"s1"}')
show("sync exists") { ssm.create_resource_data_sync(sync_name: "s1") }
begin
  ssm.create_resource_data_sync(sync_name: "s1")
rescue Aws::SSM::Errors::ResourceDataSyncAlreadyExistsException => e
  puts "sync exists reader: #{e.sync_name} #{e.data.sync_name}"
end

raw(ssm, :create_ops_item, 400, '{"__type":"OpsItemLimitExceededException","Message":"too many","ResourceTypes":["a","b"],"Limit":5,"LimitType":"OpsItem"}')
show("limit") { ssm.create_ops_item(description: "d", source: "s", title: "t") }
begin
  ssm.create_ops_item(description: "d", source: "s", title: "t")
rescue Aws::SSM::Errors::OpsItemLimitExceededException => e
  puts "limit readers: #{e.resource_types.inspect} #{e.limit} #{e.limit_type}"
end

raw(ssm, :delete_resource_data_sync, 400, '{"__type":"ResourceDataSyncNotFoundException","SyncName":"s2","SyncType":"SyncToDestination","Message":"gone"}')
show("not found") { ssm.delete_resource_data_sync(sync_name: "s2") }
begin
  ssm.delete_resource_data_sync(sync_name: "s2")
rescue Aws::SSM::Errors::ResourceDataSyncNotFoundException => e
  puts "not found readers: #{e.sync_name} #{e.sync_type}"
end

raw(ssm, :get_parameter, 400, '{"__type":"ResourceDataSyncAlreadyExistsException","SyncName":"s3"}')
show("not the operation's") { ssm.get_parameter(name: "/a") }

raw(ssm, :get_parameter, 400, '{"__type":"ParameterNotFound"}')
show("no message") { ssm.get_parameter(name: "/a") }

# Http500Error is a class the gem creates at run time; only its code and
# data are compared.
raw(ssm, :get_parameter, 500, "<html>oops</html>")
begin
  ssm.get_parameter(name: "/a")
rescue Aws::SSM::Errors::ServiceError => e
  puts "not json: #{e.code} data: #{e.data.class} #{e.data.to_h}"
end

ssm.stub_responses(:get_access_token, "ThrottlingException")
show("stubbed throttling") { ssm.get_access_token(access_request_id: "r") }
begin
  ssm.get_access_token(access_request_id: "r")
rescue Aws::SSM::Errors::ThrottlingException => e
  puts "stubbed throttling readers: #{e.quota_code.inspect} #{e.service_code.inspect}"
end

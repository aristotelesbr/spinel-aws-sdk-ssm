# Aws::SSM::Client with stub_responses: each operation's default data, data
# from a Hash, a sequence, an error code, a raw HTTP response (success and
# error JSON), and the request body each call serializes.
require "aws-sdk-ssm"

ssm = Aws::SSM::Client.new(stub_responses: true)

resp = ssm.get_parameter(name: "/app/TOKEN")
param = resp.parameter
puts "get_parameter: #{param.name} #{param.type} #{param.value} #{param.version} #{param.last_modified_date.class} #{param.data_type}"
puts "data: #{resp.data.class} #{resp.successful?} #{resp.error.inspect}"

put = ssm.put_parameter(name: "/app/TOKEN", value: "s3cr3t")
puts "put_parameter: #{put.version} #{put.tier}"

many = ssm.get_parameters(names: ["/a", "/b"])
puts "get_parameters: #{many.parameters.inspect} #{many.invalid_parameters.inspect}"

by_path = ssm.get_parameters_by_path(path: "/app")
puts "get_parameters_by_path: #{by_path.parameters.inspect} #{by_path.next_token}"

deleted = ssm.delete_parameter(name: "/app/TOKEN")
puts "delete_parameter: #{deleted.data.class} #{deleted.data.to_h}"

deleted = ssm.delete_parameters(names: ["/a", "/b"])
puts "delete_parameters: #{deleted.deleted_parameters.inspect} #{deleted.invalid_parameters.inspect}"

described = ssm.describe_parameters
puts "describe_parameters: #{described.parameters.inspect} #{described.next_token}"

ssm.stub_responses(:get_parameter, { parameter: { name: "/app/TOKEN", value: "s3cr3t", version: 3 } })
param = ssm.get_parameter(name: "/app/TOKEN").parameter
puts "hash: #{param.name} #{param.value} #{param.version} #{param.type.inspect}"
puts "to_h: #{param.to_h}"

ssm.stub_responses(:get_parameters, { parameters: [{ name: "/a", value: "1" }, { name: "/b", value: "2" }], invalid_parameters: ["/c"] })
many = ssm.get_parameters(names: ["/a", "/b", "/c"])
puts "hash list: #{many.parameters.map(&:value).join(",")} #{many.invalid_parameters.join(",")}"

ssm.stub_responses(:put_parameter, { version: 1 }, { version: 2 })
puts "sequence: #{ssm.put_parameter(name: "/a", value: "v").version} #{ssm.put_parameter(name: "/a", value: "v").version} #{ssm.put_parameter(name: "/a", value: "v").version}"

ssm.stub_responses(:get_parameter, "ParameterNotFound")
begin
  ssm.get_parameter(name: "/missing")
rescue Aws::SSM::Errors::ServiceError => e
  puts "error: #{e.class} #{e.code} #{e.message}"
end

ok = '{"Parameter":{"ARN":"arn:aws:ssm:us-east-1:123456789012:parameter/app/TOKEN","DataType":"text",' \
     '"LastModifiedDate":1.700000000123E9,"Name":"/app/TOKEN","Type":"SecureString",' \
     '"Value":"são \"x\"","Version":7}}'
ssm.stub_responses(:get_parameter, { status_code: 200, headers: {}, body: ok })
param = ssm.get_parameter(name: "/app/TOKEN").parameter
puts "raw: #{param.name} #{param.type} #{param.value} #{param.version} #{param.arn} #{param.data_type}"
puts "raw time: #{param.last_modified_date.to_i} #{param.last_modified_date.utc.strftime("%Y-%m-%dT%H:%M:%S.%L")}"
puts "raw missing: #{param.selector.inspect} #{param.source_result.inspect}"

ssm.stub_responses(:get_parameter, { status_code: 200, headers: {}, body: "" })
puts "empty body: #{ssm.get_parameter(name: "/a").parameter.inspect}"

# A code the model does not list gets a class the gem creates at run time
# (its message is that class's name); only the code is compared for those.
[
  [400, '{"__type":"com.amazonaws.ssm#ParameterNotFound","message":"no such parameter"}', true],
  [400, '{"__type":"ParameterVersionNotFound","Message":"capital M"}', true],
  [400, '{"code":"ThrottlingException:extra","message":"slow down"}', true],
  [400, '{"__type":"SomethingNew","message":"not in the model"}', false],
  [500, '{}', false],
  [503, "<html>Service Unavailable</html>", false],
  [500, "", false]
].each do |status, body, modeled|
  ssm.stub_responses(:get_parameter, { status_code: status, headers: {}, body: body })
  begin
    ssm.get_parameter(name: "/a")
  rescue Aws::SSM::Errors::ServiceError => e
    detail = modeled ? "#{e.class} #{e.message.inspect}" : "(unmodeled)"
    puts "raw error #{status}: #{e.code.inspect} #{detail}"
  end
end

def body(label, resp)
  puts "body #{label}: #{resp.context.http_request.body.read}"
end

ssm = Aws::SSM::Client.new(stub_responses: true)
body "get_parameter", ssm.get_parameter(name: "/app/TOKEN", with_decryption: true)
body "get_parameter", ssm.get_parameter(with_decryption: false, name: "/app/TOKEN")
body "get_parameters", ssm.get_parameters(names: ["/a", "/b"], with_decryption: true)
body "get_parameters_by_path", ssm.get_parameters_by_path(
  path: "/app", recursive: true, max_results: 10,
  parameter_filters: [{ key: "Type", option: "Equals", values: ["SecureString"] }]
)
body "put_parameter", ssm.put_parameter(
  name: "/app/TOKEN", value: "s3cr3t", type: "SecureString", overwrite: true,
  tags: [{ key: "team", value: "core" }], description: nil
)
body "put_parameter", ssm.put_parameter(overwrite: false, type: "String", value: "v", name: "/b")
body "delete_parameter", ssm.delete_parameter(name: "/app/TOKEN")
body "delete_parameters", ssm.delete_parameters(names: ["/a", "/b"])
body "describe_parameters", ssm.describe_parameters
body "describe_parameters", ssm.describe_parameters(max_results: 5, next_token: "t", shared: true)

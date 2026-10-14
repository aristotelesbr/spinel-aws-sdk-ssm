# Aws::SSM::Client over HTTP against a local server: the JSON-protocol
# request (headers, X-Amz-Target, signature, body), the responses it reads,
# error codes from the body and from the x-amzn-errortype header, and
# retries of a throttled call in the legacy and standard modes. Sleeping is
# intercepted, and the standard mode's random factor is fixed at 0.5.
require "socket"
require "openssl"
require "aws-sdk-ssm"

$sleeps = []
module Kernel
  def self.sleep(seconds)
    $sleeps << seconds
    0
  end

  def self.rand(*_args)
    0.5
  end
end

# The package waits through Aws::Runtime.sleep; the gem calls Kernel.sleep.
module Aws
  module Runtime
    def self.sleep(seconds)
      $sleeps << seconds
      0
    end
  end
end

ENV["AWS_CONFIG_FILE"] = __dir__ + "/fixtures/no-such-config"
ENV["AWS_SHARED_CREDENTIALS_FILE"] = __dir__ + "/fixtures/no-such-credentials"
%w[AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE AWS_REGION
   AMAZON_REGION AWS_DEFAULT_REGION AWS_RETRY_MODE AWS_MAX_ATTEMPTS].each { |name| ENV.delete(name) }

PUT = '{"Tier":"Standard","Version":1}'
PARAM = '{"Parameter":{"ARN":"arn:aws:ssm:sa-east-1:123456789012:parameter/app/TOKEN",' \
        '"DataType":"text","LastModifiedDate":1700000000,"Name":"/app/TOKEN",' \
        '"Type":"SecureString","Value":"s3cr3t","Version":1}}'
NOT_FOUND = '{"__type":"com.amazonaws.ssm#ParameterNotFound","message":"Parameter /missing not found."}'
THROTTLED = '{"__type":"ThrottlingException","message":"Rate exceeded"}'
UNMODELED = '{"__type":"com.amazonaws.ssm#SomethingNew","message":"new"}'

# [status, body, extra header]
replies = [
  [200, PUT, nil],
  [200, PARAM, nil],
  [400, NOT_FOUND, nil],
  [400, "{}", "x-amzn-ErrorType: ParameterNotFound:http://internal.amazon.com/coral/com.amazonaws.ssm/"],
  [400, UNMODELED, nil],
  [400, THROTTLED, nil],
  [200, PARAM, nil],
  [400, THROTTLED, nil],
  [500, "", nil],
  [200, PARAM, nil]
]

server = TCPServer.new("127.0.0.1", 0)
port = server.addr[1]
requests = []
thread = Thread.new do
  replies.each do |status, reply, extra|
    conn = server.accept
    line = conn.gets.strip
    headers = {}
    while (h = conn.gets) && h != "\r\n"
      name, value = h.split(":", 2)
      headers[name.downcase] = value.strip
    end
    body = conn.read(headers["content-length"].to_i)
    requests << [line, headers, body]
    reason = { 200 => "OK", 400 => "Bad Request", 500 => "Internal Server Error" }[status]
    head = "HTTP/1.1 #{status} #{reason}\r\nContent-Type: application/x-amz-json-1.1\r\n"
    head += "#{extra}\r\n" if extra
    conn.write("#{head}Content-Length: #{reply.bytesize}\r\nConnection: close\r\n\r\n#{reply}")
    conn.close
  end
end

def describe(label, request)
  line, headers, body = request
  puts "#{label}: #{line}"
  # user-agent names the SDK build; connection is how each transport keeps
  # (or closes) the socket. Neither is part of the request the service reads.
  puts "  headers: #{(headers.keys - ["user-agent", "connection"]).sort.join(" ")}"
  puts "  content-type: #{headers["content-type"]}"
  puts "  x-amz-target: #{headers["x-amz-target"]}"
  puts "  authorization: #{headers["authorization"].sub(/\d{8}/, "DATE").sub(/Signature=\h{64}/, "Signature=SIG")}"
  puts "  body: #{body}"
end

def signature_valid?(request, port)
  _line, headers, body = request
  signed = headers.reject { |name, _| %w[authorization user-agent accept-encoding accept content-length connection].include?(name) }
  signer = Aws::Sigv4::Signer.new(service: "ssm", region: "sa-east-1", access_key_id: "AKID", secret_access_key: "SECRET")
  signer.sign_request(http_method: "POST", url: "http://127.0.0.1:#{port}/", headers: signed,
                      body: body).headers["authorization"] == headers["authorization"]
end

def failure(label, ssm, modeled = true)
  ssm.get_parameter(name: "/missing")
rescue Aws::SSM::Errors::ServiceError => e
  # A code the model does not list gets a class the gem creates at run time.
  detail = modeled ? "#{e.class} #{e.message}" : "(unmodeled) #{e.message}"
  puts "#{label}: #{e.code} #{detail} data: #{e.data.class} #{e.data.to_h}"
end

endpoint = "http://127.0.0.1:#{port}"
credentials = Aws::Credentials.new("AKID", "SECRET")
ssm = Aws::SSM::Client.new(region: "sa-east-1", endpoint: endpoint, credentials: credentials)

put = ssm.put_parameter(name: "/app/TOKEN", value: "s3cr3t", type: "SecureString", overwrite: true)
puts "put: #{put.version} #{put.tier}"
param = ssm.get_parameter(name: "/app/TOKEN", with_decryption: true).parameter
puts "get: #{param.name} #{param.value} #{param.version} #{param.last_modified_date.to_i} #{param.arn}"
failure("not found", ssm)
failure("header code", ssm)
failure("unmodeled", ssm, false)

resp = ssm.get_parameter(name: "/app/TOKEN")
puts "legacy retry: #{resp.parameter.value} retries=#{resp.context.retries} sleeps=#{$sleeps.inspect}"

$sleeps.clear
standard = Aws::SSM::Client.new(region: "sa-east-1", endpoint: endpoint, credentials: credentials,
                                retry_mode: "standard")
resp = standard.get_parameter(name: "/app/TOKEN")
puts "standard retry: #{resp.parameter.value} retries=#{resp.context.retries} sleeps=#{$sleeps.inspect}"
thread.join

describe("put", requests[0])
puts "  signature valid: #{signature_valid?(requests[0], port)}"
describe("get", requests[1])
puts "  signature valid: #{signature_valid?(requests[1], port)}"
puts "retried: #{requests[5][1]["x-amz-target"]} #{requests[6][2]}"
puts "standard attempts: #{requests[7..9].map { |r| r[1]["amz-sdk-request"] }.join(" | ")}"

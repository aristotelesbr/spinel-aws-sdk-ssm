# Paging, as the gem's PageableResponse and Pager: each_page over stubbed
# pages, the request each next page sends (the caller's params, the token
# last), next_page with params, the last page (no token, an empty token,
# the token the request sent) and an operation without a paginator.
require "aws-sdk-ssm"

ssm = Aws::SSM::Client.new(stub_responses: true)

def body(resp)
  resp.context.http_request.body.read
end

first = ssm.get_parameters_by_path(path: "/app")
puts "default: #{first.last_page?} #{first.next_page?} #{first.next_token.inspect}"
begin
  first.next_page
rescue Aws::PageableResponse::LastPageError => e
  puts "default next_page: #{e.class} #{e.message} #{e.response.equal?(first)}"
end

ssm.stub_responses(:get_parameters_by_path, [
  { parameters: [{ name: "/app/a" }], next_token: "t1" },
  { parameters: [{ name: "/app/b" }, { name: "/app/c" }], next_token: "t2" },
  { parameters: [{ name: "/app/d" }] }
])
resp = ssm.get_parameters_by_path(path: "/app", recursive: true)
pages = 0
result = resp.each_page do |page|
  pages += 1
  names = page.parameters.map(&:name).join(",")
  puts "page #{pages}: #{names} #{page.next_token.inspect} #{page.last_page?} #{body(page)}"
end
puts "each_page returns: #{result.inspect}"

ssm.stub_responses(:get_parameters_by_path, [{ parameters: [], next_token: "t1" }, { parameters: [] }])
resp = ssm.get_parameters_by_path(next_token: "t0", path: "/app", max_results: 2)
puts "next_page with params: #{body(resp.next_page(max_results: 5, with_decryption: true))}"

ssm.stub_responses(:describe_parameters, { parameters: [], next_token: "" })
puts "empty token: #{ssm.describe_parameters.last_page?}"
ssm.stub_responses(:describe_parameters, { parameters: [], next_token: "same" })
puts "same token: #{ssm.describe_parameters(next_token: "same").last_page?}"
puts "new token: #{ssm.describe_parameters(next_token: "other").last_page?}"

single = ssm.get_parameter(name: "/a")
count = 0
single.each_page { |page| count += 1 }
puts "no paginator: #{single.last_page?} #{single.next_page?} #{count}"

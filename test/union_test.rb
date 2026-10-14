# Unions (NodeType, ExecutionPreview, CloudConnectorConfiguration and its
# ConfigurationTargets, ExecutionInputs): the member subclass a default
# stub, a stubbed Hash and a parsed response give, member and value, to_h,
# a key the model does not list, and a union in a request body.
require "aws-sdk-ssm"

ssm = Aws::SSM::Client.new(stub_responses: true)

def show(label, union)
  puts "#{label}: #{union.class} #{union.member.inspect} #{union.value.class} #{union.is_a?(union.class.superclass)}"
end

preview = ssm.get_execution_preview(execution_preview_id: "x").execution_preview
show "default execution_preview", preview
puts "default automation: #{preview.automation.total_accounts} #{preview.automation.regions.inspect} #{preview.unknown.inspect}"

connector = ssm.get_cloud_connector(cloud_connector_id: "id").configuration
show "default configuration", connector
puts "default azure: #{connector.azure_configuration.tenant_id}"
show "default targets", connector.azure_configuration.targets
puts "default subscriptions: #{connector.azure_configuration.targets.subscriptions.inspect}"

puts "list_nodes: #{ssm.list_nodes.nodes.inspect}"

ssm.stub_responses(:list_nodes, { nodes: [{ id: "n1", node_type: { instance: { agent_type: "x", ip_address: "10.0.0.1" } } }] })
node = ssm.list_nodes.nodes[0]
show "hash node_type", node.node_type
puts "hash instance: #{node.node_type.instance.agent_type} #{node.node_type.value.ip_address}"
puts "hash to_h: #{node.node_type.to_h}"

nodes = '{"Nodes":[{"Id":"n2","NodeType":{"Instance":{"AgentType":"y"}}},' \
        '{"Id":"n3","NodeType":{"Future":{"a":1},"__type":"t"}},' \
        '{"Id":"n4","NodeType":{"Instance":null,"Later":"z"}}]}'
ssm.stub_responses(:list_nodes, { status_code: 200, headers: {}, body: nodes })
ssm.list_nodes.nodes.each do |n|
  show "json #{n.id}", n.node_type
  puts "json #{n.id} instance: #{n.node_type.instance.nil? ? "nil" : n.node_type.instance.agent_type}"
  puts "json #{n.id} unknown: name=#{n.node_type.unknown && n.node_type.unknown["name"]}"
end

ssm.stub_responses(:start_execution_preview, { execution_preview_id: "p" })
resp = ssm.start_execution_preview(document_name: "d", execution_inputs: { automation: { parameters: { "a" => ["b"] }, target_parameter_name: "t" } })
puts "body start_execution_preview: #{resp.context.http_request.body.read}"
resp = ssm.create_cloud_connector(
  display_name: "c", role_arn: "r", config_connector_arn: "cc",
  configuration: { azure_configuration: { tenant_id: "t", application_id: "a", targets: { subscriptions: [{ id: "s1", display_name: "one" }, { id: "s2" }] } } }
)
puts "body create_cloud_connector: #{resp.context.http_request.body.read}"

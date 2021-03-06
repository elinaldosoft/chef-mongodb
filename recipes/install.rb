if node['mongodb']['install_method'] == "10gen" or node.run_list.recipes.include?("mongodb::10gen_repo") then
    include_recipe "mongodb::10gen_repo"
end

# prevent-install defaults, but don't overwrite
file node['mongodb']['sysconfig_file'] do
    content "ENABLE_MONGODB=no"
    group node['mongodb']['root_group']
    owner "root"
    mode 0644
    action :create_if_missing
end

if node['mongodb']['replicaset_name'].nil? && node.recipe?('mongodb::shard') && node.recipe?('mongodb::replicaset')
  node.default['mongodb']['config']['replSet'] = "rs_#{node['mongodb']['shard_name']}"
end

if node.recipe?("mongodb::mongos")
  node.default['mongodb']['config']['configdb'] = search(
    :node,
    "mongodb_cluster_name:#{node['mongodb']['cluster_name']} AND \
     recipes:mongodb\\:\\:configserver AND \
     chef_environment:#{node.chef_environment}"
  ).collect{|n| "#{(n['mongodb']['configserver_url'] || n['fqdn'])}:#{n['mongodb']['port']}" }.sort.join(",")
  %w(dbpath nojournal rest smallfiles oplogSize replSet).each { |k| node.default['mongodb']['config'].delete(k) }
end

# just-in-case config file drop
template node['mongodb']['dbconfig_file'] do
    cookbook node['mongodb']['template_cookbook']
    source node['mongodb']['dbconfig_file_template']
    group node['mongodb']['root_group']
    owner "root"
    mode 0644
    action :create_if_missing
end

# and we install our own init file
if node['mongodb']['apt_repo'] == "ubuntu-upstart" then
    init_file = File.join(node['mongodb']['init_dir'], "#{node['mongodb']['default_init_name']}.conf")
else
    init_file = File.join(node['mongodb']['init_dir'], "#{node['mongodb']['default_init_name']}")
end
template init_file do
    cookbook node['mongodb']['template_cookbook']
    source node['mongodb']['init_script_template']
    group node['mongodb']['root_group']
    owner "root"
    mode "0755"
    variables({
        :provides => "mongod"
    })
    action :create_if_missing
end

packager_opts = ""
case node['platform_family']
when "debian"
    # this options lets us bypass complaint of pre-existing init file
    # necessary until upstream fixes ENABLE_MONGOD/DB flag
    packager_opts = '-o Dpkg::Options::="--force-confold"'
end

# install
package node[:mongodb][:package_name] do
    options packager_opts
    action :install
    version node[:mongodb][:package_version]
end

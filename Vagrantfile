# -*- mode: ruby -*-
# vi: set ft=ruby :

VAGRANTFILE_API_VERSION = "2"
domain = "prestashop.lan"
ip_address = "192.168.100.5"
machine_name = "PrestaShop"
Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = "debian/buster64"
  config.vm.provider :virtualbox do |vb|
      vb.name = machine_name
  end
  config.vm.synced_folder "./sites", "/var/www",
    owner: "vagrant",
    group: "www-data",
    mount_options: ["dmode=775,fmode=664"],
    create: true
  config.hostmanager.enabled = true
  config.hostmanager.manage_host = true
  config.vm.define domain do |node|
    node.vm.hostname = domain
    node.vm.network :private_network, ip: ip_address
    node.hostmanager.aliases = %w(prestashop www.prestashop.lan) 
  end
  config.vm.provision :hostmanager
  config.vm.provision :shell, :path => "bootstrap.sh", :args => [domain,] 
end

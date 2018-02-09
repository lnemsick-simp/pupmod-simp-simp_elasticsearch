require 'spec_helper_acceptance'
require 'json'

test_name 'simp_elasticsearch class'

describe 'simp_elasticsearch class' do

  elasticsearch_servers = hosts_with_role(hosts, 'elasticsearch_server')

  ssh_allow = <<-EOM
    include '::tcpwrappers'
    include '::iptables'

    tcpwrappers::allow { 'sshd':
      pattern => 'ALL'
    }

    iptables::listen::tcp_stateful { 'ssh_access':
      order        => 8,
      trusted_nets => ['10.0.0.0/16','127.0.0.0/2'],
      dports       => 22
    }
  EOM
 
  let(:manifest) { <<-EOM
include '::simp_elasticsearch'

#{ssh_allow}
  EOM
  }

  let(:hieradata) {
    <<-EOS
---
simp_elasticsearch::cluster_name : 'test_cluster'
simp_elasticsearch::bind_host : '#IPADDRESS#'
simp_elasticsearch::unicast_hosts :
  - #{hosts.map{|x| '"' + x.to_s + '.%{::domain}' + ':9300"'}.join("\n  - ")}

simp_elasticsearch::http_method_acl :
  limits :
    hosts :
      #{hosts.map{|x| '"' + x.to_s + '.%{::domain}" : defaults'}.join("\n      ")}

simp_apache::rsync_web_root : false
simp_options::rsync::server : "%{::fqdn}"

simp_options::pki : true
simp_options::pki::source : '/etc/pki/simp-testing/pki'

simp_options::firewall : true
   EOS
  }

  elasticsearch_servers.each do |host|
    context 'on the servers' do
      it 'should work with no errors' do
        # Need to get the secondary interface
        interfaces = fact_on(host, 'interfaces').split(',')
        interfaces.delete('lo')
        # net_hash = JSON.load(fact_on(host, %(networking)))
        # ipaddr = net_hash['interfaces'][interfaces.sort.last]['ip']
        ipaddr = fact_on(host, %(ipaddress_#{interfaces.sort.last}))

        hdata = hieradata.dup
        hdata.gsub!(/#IPADDRESS#/m, ipaddr)

        if host.name == 'el6-server'
          # need newer JAVA version 
           hdata += "\njava::package : 'java-1.8.0-openjdk-devel'\n"
        end

        set_hieradata_on(host, hdata)
        apply_manifest_on(host, manifest, :catch_failures => true)
        on(host, 'rpm -q elasticsearch')
      end

      it 'should be idempotent' do
        apply_manifest_on(host, manifest, :catch_changes => true)
      end

      it 'should be running elasticsearch' do
        on(host, %(ps -ef | grep "[e]lasticsearch"))
      end
    end
  end

  context 'cluster validation' do
    let(:host) { elasticsearch_servers.first }

    it 'should be running a healthy cluster' do
      # Give it a few seconds for the cluster to come to terms with itself
      sleep(30)

      result = on(host, %(curl -XGET 'http://localhost:9199/_cat/nodes')).stdout
      expect(result.lines.count).to eq elasticsearch_servers.count
    end

    it 'should allow secure ES api access' do
      fqdn = fact_on(host, 'fqdn')
      cert = "/etc/pki/simp_apps/simp_apache/x509/private/#{fqdn}.pem"
      elasticsearch_servers.each do |es_host|
        # -k needed because we are using a self-signing CA
        # --cert needed because SSLVerifyClient is enabled by default in ES apache config
        result = on(host, %(curl -k --cert #{cert} -XGET 'https://#{es_host.name}:9200/_cat/nodes')).stdout
        expect(result.lines.count).to eq elasticsearch_servers.count
      end
    end
  end
end

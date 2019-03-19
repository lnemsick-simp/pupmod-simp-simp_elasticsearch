# This class is just for storing default option hashes/arrays so the
# main classes are cleaner.
#
# Items are called from simp_elasticsearch
#
class simp_elasticsearch::defaults {

  if length($::simp_elasticsearch::unicast_hosts) < 3 {
    $min_master_nodes = 1
  }
  else {
    $min_master_nodes = $::simp_elasticsearch::min_master_nodes
  }

  # The amount of memory that ES should allocate on startup.
  #   Default: 50% of Memory + 2G. If < 10G is present, just 50% of
  #   mem.
  $mem_bytes = to_bytes($::memorysize)

  if $mem_bytes < 10737418240 {
    $es_heap_size = ( $mem_bytes / 2 )
  }
  else {
    $es_heap_size = (( $mem_bytes / 2 ) + 2147483648 )
  }

  # JNA tmp dir must be set, as default is /tmp which won't
  # work with noexec constraints
  $jvm_options_defaults = [
    "-Xms${es_heap_size}",
    "-Xmx${es_heap_size}",
    "-Djna.tmpdir=${::simp_elasticsearch::jna_tmpdir}"
  ]

  $_base_config = {
    'cluster'     => {
      'name'                => $::simp_elasticsearch::cluster_name
    },
    'node.name'   => $::simp_elasticsearch::node_name,
    'network'     => {
      'bind_host'    => $::simp_elasticsearch::bind_host,
      # This must be done due to a bug in the ES configuration processor that
      # does not match the documentation which states that publish_host will be
      # automatically selected from the best address in bind_host.
      # TODO Verify this workaround is still required with ES 5.X
      'publish_host' => $::simp_elasticsearch::bind_host
    },
    'http'        => {
      'bind_host' => $::simp_elasticsearch::http_bind_host,
      'port'      => $::simp_elasticsearch::http_port
    },
    'path.logs'   => '/var/log/elasticsearch',
    'path.data'   => $::simp_elasticsearch::data_dir,
    'discovery'                => {
      'zen'                    => {
        'minimum_master_nodes' => $min_master_nodes,
        'ping'                 => {
          'unicast' => {
            'hosts' => $::simp_elasticsearch::unicast_hosts
          }
        }
      }
    }
  }

  if (versioncmp($facts['os']['release']['major'],'7') < 0) {
    # CentOS 6 does not support SecComp so need to disable that feature
    # See https://github.com/elastic/elasticsearch/issues/22899
    $base_config  = merge($_base_config, { 'bootstrap.system_call_filter' => false })
  }
  else {
    $base_config = $_base_config
  }
}

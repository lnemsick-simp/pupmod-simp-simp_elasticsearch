# This class provides the configuration of Apache for use as a front-end to
# ElasticSearch. The defaults are targeted toward making the interface as
# highly available as possible without regard to system load.
#
# @param manage_httpd Whether or not to manage the httpd daemon/apache
#   itself.
#
#   @note This class assumes that you're using the simp-supplied apache module
#     and calls apache::add_site accordingly. If you're not comfortable doing
#     this, you don't want to use this module.
#
# @param listen The port upon which to listen for HTTP connections.
#
# @param proxy_port The port to proxy HTTP connections to on the local
#   system.
#
# @param cipher_suite OpenSSL cipher suite to use for SSL connections
#
# @param ssl_protocols  SSL protocols allowed
#
# @param apache_user  apache user; used to set configuration file ownership
#
# @param apache_group  apache group; used to set configuration file ownership
#
# @param ssl_verify_client Type of client certificate verification.
#
# @param ssl_verify_depth  Maximum depth of CA certificates in client
#   certificate verifiction.
#
# @param method_acl Users, Groups, and Hosts HTTP operation ACL
#   management. Keys are the relevant entry to allow and values are an Array of
#   operations to allow the key to use.
#
#   @note These are OR'd together (Satisfy any).
#
#   @example ACL Structure
#
#     # If no value is assigned to the associated key then ['GET','POST','PUT']
#     # is assumed.
#
#     # Values will be merged with those in simp_elasticsearch::simp_apache::defaults
#     # if defined.
#
#     {
#       'limits'  => {
#         'hosts'   => {
#           '127.0.0.1' => ['GET','POST','PUT']
#         }
#       }
#     }
#
#   @example Use LDAP with the defaults and only allow localhost
#
#     {
#       'method' => {
#         'ldap' => {
#           'enable' => true
#         }
#       }
#     }
#
#   @example Full example with all options
#
#     {
#       # 'file' (htpasswd), and 'ldap' support are provided. You will need to
#       # set up target files if using 'file'. The SIMP apache module provides
#       # automated support for this if required.
#       'method' => {
#         # Htpasswd only supports 'file' at this time. If you need more, please
#         # use 'ldap'
#         'file' => {
#           # Don't turn this on.
#           'enable'    => false,
#           'user_file' => '/etc/httpd/conf.d/elasticsearch/.htdigest'
#         }
#         'ldap'    => {
#           'enable'      => true,
#           'url'         => lookup('simp_options::ldap::uri'),
#           'security'    => 'STARTTLS',
#           'binddn'      => lookup('simp_options::ldap::bind_dn'),
#           'bindpw'      => lookup('simp_options::ldap::bind_pw'),
#           'search'      => inline_template('ou=People,<%= scope.function_lookup(["simp_options::ldap::base_dn"]) %>'),
#           # Whether or not your LDAP groups are POSIX groups.
#           'posix_group' => true
#         }
#       },
#       'limits' => {
#         # Set the defaults
#         'defaults' => [ 'GET', 'POST', 'PUT' ],
#         # Allow the hosts/subnets below to GET, POST, and PUT to ES.
#         'hosts'  => {
#           '1.2.3.4'     => 'defaults',
#           '3.4.5.6'     => 'defaults',
#           '10.1.2.0/24' => 'defaults'
#         },
#         # You can make a special user 'valid-user' that will translate to
#         # allowing all valid users.
#         'users'  => {
#           # Allow user bob GET, POST, and PUT to ES.
#           'bob'     => 'defaults',
#           # Allow user alice GET, POST, PUT, and DELETE to ES.
#           'alice'   => ['GET','POST','PUT','DELETE']
#         },
#         'ldap_groups' => {
#           # Let the nice users read from ES.
#           "cn=nice_users,ou=Group,${::basedn}" => 'defaults'
#         }
#       }
#     }
#
# @author Trevor Vaughan <tvaughan@onyxpoint.com>
#
class simp_elasticsearch::simp_apache (
  Variant[Boolean,Enum['conf']]    $manage_httpd,
  Simplib::Port                    $listen            = 9200,
  Simplib::Port                    $proxy_port        = 9199,
  Array[String]                    $cipher_suite      = simplib::lookup('simp_options::openssl::cipher_suite', { 'default_value' => ['HIGH'] } ),
  Array[String]                    $ssl_protocols     = ['+TLSv1','+TLSv1.1','+TLSv1.2'],
  String                           $apache_user       = 'root',
  String                           $apache_group      = 'apache',
  Enum['none', 'require',
    'optional', 'optional_no_ca']  $ssl_verify_client = 'require',
  Integer                          $ssl_verify_depth  = 10,
  Hash                             $method_acl        = {},
) {

  if $manage_httpd or $manage_httpd == 'conf' {
    include '::simp_elasticsearch::simp_apache::defaults'
    include '::simp_apache::validate'

    $_method_acl = deep_merge(
      $::simp_elasticsearch::simp_apache::defaults::method_acl,
      $method_acl
    )

    simplib::validate_deep_hash( $::simp_apache::validate::method_acl, $_method_acl)

    # These only work because we guarantee that we have content here.
    validate_absolute_path($_method_acl['method']['file']['user_file'])
    simplib::validate_bool($_method_acl['method']['ldap']['posix_group'])
    simplib::validate_net_list(keys($_method_acl['limits']['hosts']))

    $es_httpd_includes = '/etc/httpd/conf.d/elasticsearch'

    if $manage_httpd == 'conf' {
      include simp_elasticsearch::pki

      $_app_pki_cert   = $::simp_elasticsearch::pki::app_pki_cert
      $_app_pki_key    = $::simp_elasticsearch::pki::app_pki_key
      $_app_pki_ca_dir = $::simp_elasticsearch::pki::app_pki_ca_dir

    } else {

      include ::simp_apache
      include ::simp_apache::ssl

      $_app_pki_cert   = $::simp_apache::ssl::app_pki_cert
      $_app_pki_key    = $::simp_apache::ssl::app_pki_key
      $_app_pki_ca_dir = $::simp_apache::ssl::app_pki_ca_dir

    }

    file { $es_httpd_includes:
      ensure => 'directory',
      owner  => $apache_user,
      group  => $apache_group,
      mode   => '0640',
    }

    file { [
      "${es_httpd_includes}/auth",
      "${es_httpd_includes}/limit",
    ]:
      ensure  => 'directory',
      owner   => $apache_user,
      group   => $apache_group,
      mode    => '0640',
      require => File[$es_httpd_includes]
    }

    $_apache_auth = simp_apache::auth($_method_acl['method'])

    if !empty($_apache_auth) {
      file { "${es_httpd_includes}/auth/auth.conf":
        ensure  => 'file',
        owner   => $apache_user,
        group   => $apache_group,
        mode    => '0640',
        content => "${_apache_auth}\n",
        notify  => Service['httpd'],
        require => File[ "${es_httpd_includes}/auth", "${es_httpd_includes}/limit"]
      }
    }

    $_apache_limits = simp_apache::limits($_method_acl['limits'])
    $_apache_limits_content = $_apache_limits ? {
      # Set some sane defaults.
      ''      => "<Limit GET POST PUT DELETE>
          Order deny,allow
          Deny from all
          Allow from 127.0.0.1
          Allow from ${facts['fqdn']}
        </Limit>",
      default => "${_apache_limits}\n"
    }

    file { "${es_httpd_includes}/limit/limits.conf":
      ensure  => 'file',
      owner   => $apache_user,
      group   => $apache_group,
      mode    => '0640',
      content => $_apache_limits_content,
      require => File[ "${es_httpd_includes}/auth", "${es_httpd_includes}/limit"],
      notify  => Service['httpd']
    }

    simp_apache::site { 'elasticsearch':
      content => template("${module_name}/simp/etc/httpd/conf.d/elasticsearch.conf.erb")
    }

  }
}

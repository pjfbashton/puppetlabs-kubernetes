# Class kubernetes config kubeadm, populates kubeadm config file with params to bootstrap cluster
class kubernetes::config::kubeadm (
  Optional[Array] $apiserver_cert_extra_sans         = $kubernetes::apiserver_cert_extra_sans,
  Integer $api_server_count                          = $kubernetes::api_server_count,
  Optional[Array] $apiserver_extra_arguments         = $kubernetes::apiserver_extra_arguments,
  Optional[Hash] $apiserver_extra_volumes            = $kubernetes::apiserver_extra_volumes,
  String $cgroup_driver                              = $kubernetes::cgroup_driver,
  Optional[String] $cloud_config                     = $kubernetes::cloud_config,
  Optional[String] $cloud_provider                   = $kubernetes::cloud_provider,
  String $cni_pod_cidr                               = $kubernetes::cni_pod_cidr,
  String $config_file                                = $kubernetes::config_file,
  String $container_runtime                          = $kubernetes::container_runtime,
  String $controller_address                         = $kubernetes::controller_address,
  Optional[Array] $controllermanager_extra_arguments = $kubernetes::controllermanager_extra_arguments,
  Optional[Hash] $controllermanager_extra_volumes    = $kubernetes::controllermanager_extra_volumes,
  String $discovery_token_hash                       = $kubernetes::discovery_token_hash,
  Optional[String] $etcd_advertise_client_urls       = $kubernetes::etcd_advertise_client_urls,
  String $etcd_ca_crt                                = $kubernetes::etcd_ca_crt,
  String $etcd_ca_key                                = $kubernetes::etcd_ca_key,
  String $etcdclient_crt                             = $kubernetes::etcdclient_crt,
  String $etcdclient_key                             = $kubernetes::etcdclient_key,
  String $etcd_hostname                              = $kubernetes::etcd_hostname,
  Optional[String] $etcd_initial_advertise_peer_urls = $kubernetes::etcd_initial_advertise_peer_urls,
  String $etcd_initial_cluster                       = $kubernetes::etcd_initial_cluster,
  String $etcd_initial_cluster_state                 = $kubernetes::etcd_initial_cluster_state,
  String $etcd_install_method                        = $kubernetes::etcd_install_method,
  String $etcd_ip                                    = $kubernetes::etcd_ip,
  Optional[String] $etcd_listen_client_urls          = $kubernetes::etcd_listen_client_urls,
  Optional[String] $etcd_listen_peer_urls            = $kubernetes::etcd_listen_peer_urls,
  String $etcdpeer_crt                               = $kubernetes::etcdpeer_crt,
  String $etcdpeer_key                               = $kubernetes::etcdpeer_key,
  Array $etcd_peers                                  = $kubernetes::etcd_peers,
  String $etcdserver_crt                             = $kubernetes::etcdserver_crt,
  String $etcdserver_key                             = $kubernetes::etcdserver_key,
  String $etcd_version                               = $kubernetes::etcd_version,
  String $image_repository                           = $kubernetes::image_repository,
  Optional[Hash] $kubeadm_extra_config               = $kubernetes::kubeadm_extra_config,
  String $kube_api_advertise_address                 = $kubernetes::kube_api_advertise_address,
  Optional[Array] $kubelet_extra_arguments           = $kubernetes::kubelet_extra_arguments,
  Optional[Hash] $kubelet_extra_config               = $kubernetes::kubelet_extra_config,
  String $kubernetes_ca_crt                          = $kubernetes::kubernetes_ca_crt,
  String $kubernetes_ca_key                          = $kubernetes::kubernetes_ca_key,
  String $kubernetes_cluster_name                    = $kubernetes::kubernetes_cluster_name,
  String $kubernetes_version                         = $kubernetes::kubernetes_version,
  Boolean $manage_etcd                               = $kubernetes::manage_etcd,
  String $node_name                                  = $kubernetes::node_name,
  String $proxy_mode                                 = $kubernetes::proxy_mode,
  String $sa_key                                     = $kubernetes::sa_key,
  String $sa_pub                                     = $kubernetes::sa_pub,
  String $service_cidr                               = $kubernetes::service_cidr,
  String $token                                      = $kubernetes::token,
) {

  if !($proxy_mode in ['', 'userspace', 'iptables', 'ipvs', 'kernelspace']) {
    fail('Invalid kube-proxy mode! Must be one of "", userspace, iptables, ipvs, kernelspace.')
  }

  $kube_dirs = ['/etc/kubernetes','/etc/kubernetes/manifests','/etc/kubernetes/pki','/etc/kubernetes/pki/etcd']
  $etcd = ['ca.crt', 'ca.key', 'client.crt', 'client.key','peer.crt', 'peer.key', 'server.crt', 'server.key']
  $pki = ['ca.crt', 'ca.key','sa.pub','sa.key']
  $kube_dirs.each | String $dir |  {
    file  { $dir :
      ensure  => directory,
      mode    => '0600',
      recurse => true,
    }
  }

  if $manage_etcd {

    $real_etcd_listen_client_urls          = pick_default($etcd_listen_client_urls, $etcd_ip)
    $real_etcd_advertise_client_urls       = pick_default($etcd_advertise_client_urls, $etcd_ip)
    $real_etcd_listen_peer_urls            = pick_default($etcd_listen_peer_urls, $etcd_ip)
    $real_etcd_initial_advertise_peer_urls = pick_default($etcd_initial_advertise_peer_urls, $etcd_ip)

    $etcd.each | String $etcd_files | {
      file { "/etc/kubernetes/pki/etcd/${etcd_files}":
        ensure  => present,
        content => template("kubernetes/etcd/${etcd_files}.erb"),
        mode    => '0600',
      }
    }
    if $etcd_install_method == 'wget' {
      file { '/etc/systemd/system/etcd.service':
        ensure  => present,
        content => template('kubernetes/etcd/etcd.service.erb'),
      }
    } else {
      file { '/etc/default/etcd':
        ensure  => present,
        content => template('kubernetes/etcd/etcd.erb'),
      }
    }
  }

  $pki.each | String $pki_files | {
    file {"/etc/kubernetes/pki/${pki_files}":
      ensure  => present,
      content => template("kubernetes/pki/${pki_files}.erb"),
      mode    => '0600',
    }
  }

  # The alpha1 schema puts Kubelet configuration in a different place.
  $kubelet_extra_config_alpha1 = {
    'kubeletConfiguration' => {
      'baseConfig' => $kubelet_extra_config,
    },
  }

  # Need to merge the cloud configuration parameters into extra_arguments
  if $cloud_provider {
    $cloud_args = $cloud_config ? {
      undef   => ["cloud-provider: ${cloud_provider}"],
      default => ["cloud-provider: ${cloud_provider}", "cloud-config: ${cloud_config}"],
    }
    $apiserver_merged_extra_arguments = concat($apiserver_extra_arguments, $cloud_args)
    $controllermanager_merged_extra_arguments = concat($controllermanager_extra_arguments, $cloud_args)

    # could check against Kubernetes 1.10 here, but that uses alpha1 config which doesn't have these options
    if $cloud_config {
      # The cloud config must be mounted into the apiserver and controllermanager containers
      $cloud_volume = {
        'cloud' => {
          hostPath  => $cloud_config,
          mountPath => $cloud_config,
        },
      }
      if has_key($apiserver_extra_volumes, 'cloud') or has_key($controllermanager_extra_volumes, 'cloud') {
        fail('Cannot use "cloud" as volume name')
      }

      $apiserver_merged_extra_volumes = merge($apiserver_extra_volumes, $cloud_volume)
      $controllermanager_merged_extra_volumes = merge($controllermanager_extra_volumes, $cloud_volume)
    }
  } else {
    $apiserver_merged_extra_arguments = $apiserver_extra_arguments
    $controllermanager_merged_extra_arguments = $controllermanager_extra_arguments

    $apiserver_merged_extra_volumes = $apiserver_extra_volumes
      $controllermanager_merged_extra_volumes = $controllermanager_extra_volumes
  }

  # to_yaml emits a complete YAML document, so we must remove the leading '---'
  $kubeadm_extra_config_yaml = regsubst(to_yaml($kubeadm_extra_config), '^---\n', '')
  $kubelet_extra_config_yaml = regsubst(to_yaml($kubelet_extra_config), '^---\n', '')
  $kubelet_extra_config_alpha1_yaml = regsubst(to_yaml($kubelet_extra_config_alpha1), '^---\n', '')

  $config_version = $kubernetes_version ? {
    /1.1(0|1)/ => 'v1alpha1',
    /1.1(3|4)/  => 'v1beta1',
    default    => 'v1alpha3',
  }

  file { $config_file:
    ensure  => present,
    content => template("kubernetes/${config_version}/config_kubeadm.yaml.erb"),
    mode    => '0600',
  }
}

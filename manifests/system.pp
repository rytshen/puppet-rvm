# Install the RVM system
class rvm::system(
  $version=undef,
  $install_from=undef,
  $proxy_url=undef,
  $no_proxy=undef,
  $key_server=undef,
  $home=$::root_home,
  $gnupg_key_id=$rvm::params::gnupg_key_id) inherits rvm::params {

  $actual_version = $version ? {
    undef     => 'latest',
    'present' => 'latest',
    default   => $version,
  }

  # curl needs to be installed
  if ! defined(Package['curl']) {
    case $::kernel {
      'Linux': {
        ensure_packages(['curl'])
        Package['curl'] -> Exec['system-rvm']
      }
      default: { }
    }
  }

  $http_proxy_environment = $proxy_url ? {
    undef   => [],
    default => ["http_proxy=${proxy_url}", "https_proxy=${proxy_url}"]
  }
  $no_proxy_environment = $no_proxy ? {
    undef   => [],
    default => ["no_proxy=${no_proxy}"]
  }
  $proxy_environment = concat($http_proxy_environment, $no_proxy_environment)
  $environment = concat($proxy_environment, ["HOME=${home}"])

  # install the gpg key
  if $gnupg_key_id {
    class { 'rvm::gnupg_key':
      key_server => $key_server,
      key_id     => $gnupg_key_id,
      proxy_url  => $proxy_url,
      before     => Exec['system-rvm'],
    }
  }

  if $install_from {

    file { '/tmp/rvm':
      ensure => directory,
    }

    exec { 'unpack-rvm':
      path    => '/usr/bin:/usr/sbin:/bin:/usr/local/bin',
      command => "tar --strip-components=1 -xzf ${install_from}",
      cwd     => '/tmp/rvm',
    }

    exec { 'system-rvm':
      path        => '/usr/bin:/usr/sbin:/bin:/usr/local/bin',
      command     => './install --auto-dotfiles',
      cwd         => '/tmp/rvm',
      creates     => '/usr/local/rvm/bin/rvm',
      environment => $environment,
    }

  }
  else {
    exec { 'get rvm installer script':
      path        => ['/bin','/usr/bin','/usr/sbin','/usr/local/bin'],
      command     => 'curl -fsSLk https://get.rvm.io -o /tmp/rvm_installer.sh',
      creates     => '/tmp/rvm_installer.sh',
      environment => concat($proxy_environment, ["HOME=${home}"]),
    }

    exec { 'get rvm keys':
      path        => ['/bin','/usr/bin','/usr/sbin','/usr/local/bin'],
      command => 'gpg2 --keyserver hkp://pool.sks-keyservers.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB',
      environment => concat($proxy_environment, ["HOME=${home}"]),
    }

    file { '/tmp/rvm_installer.sh':
      mode    => '0755',
      require => Exec['get rvm installer script'],
    }

    exec { 'system-rvm':
      path        => ['/bin','/usr/bin','/usr/sbin','/usr/local/bin'],
      command     => "/tmp/rvm_installer.sh --version ${actual_version}",
      logoutput   => true,
      creates     => '/usr/local/rvm/bin/rvm',
      environment => concat($proxy_environment, ["HOME=${home}"]),
      require     => File['/tmp/rvm_installer.sh'],
    }
  }

  # the fact won't work until rvm is installed before puppet starts
  if getvar('::rvm_version') and !empty($::rvm_version) {
    if ($version != undef) and ($version != present) and ($version != $::rvm_version) {

      if defined(Class['rvm::gnupg_key']) {
        Class['rvm::gnupg_key'] -> Exec['system-rvm-get']
      }

      # Update the rvm installation to the version specified
      notify { 'rvm-get_version':
        message => "RVM updating from version ${::rvm_version} to ${version}",
      } ->
      exec { 'system-rvm-get':
        path        => '/usr/local/rvm/bin:/usr/bin:/usr/sbin:/bin',
        command     => "rvm get ${version}",
        before      => Exec['system-rvm'], # so it doesn't run after being installed the first time
        environment => $environment,
      }
    }
  }
}

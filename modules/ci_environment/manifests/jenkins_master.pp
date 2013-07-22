# == Class: ci_environment::jenkins_master
#
# Class to install things only on the Jenkins Master
#
# See opsmanual for manual steps:
#
# https://github.gds/pages/gds/opsmanual \
#   /infrastructure/howto/configuring-ci-environment-and-machines.html
#
class ci_environment::jenkins_master (
  $github_enterprise_cert,
  $jenkins_servername,
  $jenkins_serveraliases = [],
  $slave_user = 'slave'
) {
    validate_string($github_enterprise_cert, $jenkins_servername)
    validate_array($jenkins_serveraliases)

    Package <| title == 'jenkins' |> -> Jenkins::Plugin <| |>

    package {'ssl-cert':
        ensure  => latest,
        require => Exec['apt-get-update'],
    }

    class {'nginx::server':
        require => Package['ssl-cert'],
    }

    nginx::vhost::proxy  { 'jenkins-nginx':
        ssl            => true,
        ssl_redirect   => true,
        isdefaultvhost => true,
        servername     => $jenkins_servername,
        serveraliases  => $jenkins_serveraliases,
    }

    # This file resource installs a Jenkins plugin manually. The build we are
    # using is from a Pull Request and has not been merged into mainline. With
    # any luck, when version 0.14 is release, we can just use that.
    # Download URL:
    #   https://buildhive.cloudbees.com/job/jenkinsci/job/github-oauth-plugin
    #          /34/org.jenkins-ci.plugins$github-oauth/
    #
    file {'/var/lib/jenkins/plugins/github-oauth.hpi':
        ensure => 'present',
        owner  => 'jenkins',
        group  => 'nogroup',
        mode   => '0644',
        source => 'puppet:///modules/ci_environment/jenkins-plugin-github-oauth-0.14-b34.hpi',
        notify => Class['jenkins::service'],
    }

    file {'/etc/ssl/certs/github.gds.pem':
        ensure  => 'present',
        content => $github_enterprise_cert,
        notify  => Exec['import-github-cert'],
    }

    exec {'import-github-cert':
        command => '/usr/bin/keytool -import -trustcacerts -alias github.gds \
                    -file /etc/ssl/certs/github.gds.pem \
                    -keystore /etc/ssl/certs/java/cacerts \
                    -storepass changeit -noprompt',
        unless  => '/usr/bin/keytool -list \
                    -keystore /etc/ssl/certs/java/cacerts \
                    -storepass changeit | grep github.gds',
    }

    jenkins::api_user { $slave_user: }

    ufw::allow {'jenkins-slave-to-jenkins-master-on-tcp':
        port  => '39408',
        proto => 'tcp',
        ip    => 'any',
    }
    ufw::allow {'jenkins-slave-to-jenkins-master-on-udp':
        port  => '33848',
        proto => 'udp',
        ip    => 'any',
    }
    ufw::allow {'http-for-redirects-only':
        port  => '80',
        proto => 'tcp',
        ip    => 'any',
    }
    ufw::allow {'internal-http-for-jenkins':
        port  => '8080',
        proto => 'tcp',
        ip    => 'any',
    }
    ufw::allow {'https-connections':
        port  => '443',
        proto => 'tcp',
        ip    => 'any',
    }
}

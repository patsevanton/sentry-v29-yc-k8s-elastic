config:
  localDns: "169.254.20.10"
  dnsServer: "10.96.128.2"
  customConfig: |
    cluster.local:53 {
        errors
        cache {
            success 9984 30
            denial 9984 5
        }
        reload
        loop
        bind 169.254.20.10 10.96.128.2
        forward . 10.96.128.2 {
            force_tcp
        }
        prometheus :9253
        health 169.254.20.10:8080
    }
    in-addr.arpa:53 {
        errors
        cache 30
        reload
        loop
        bind 169.254.20.10 10.96.128.2
        forward . 10.96.128.2 {
            force_tcp
        }
        prometheus :9253
    }
    ip6.arpa:53 {
        errors
        cache 30
        reload
        loop
        bind 169.254.20.10 10.96.128.2
        forward . 10.96.128.2 {
            force_tcp
        }
        prometheus :9253
    }
    .:53 {
        errors
        cache 30
        reload
        loop
        bind 169.254.20.10 10.96.128.2
        hosts {
            ${sentry_ingress_ip} sentry.apatsev.org.ru
            fallthrough
        }
        forward . /etc/resolv.conf
        prometheus :9253
    }

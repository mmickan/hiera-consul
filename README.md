[consul](http://www.consul.io) is an orchestration mechanism with fault-tolerance based on the gossip protocol and a key/value store that is strongly consistent. Hiera-consul is a backend for Hiera using Consul as its data source.

## Configuration

The following hiera.yaml should get you started:

    :backends:
      - consul

    :consul:
      :paths:
        - kv/configuration/%{fqdn}
        - kv/configuration/common

## Extra parameters

The following parameters are also valid and available:

    :consul:
      :host: 127.0.0.1
      :port: 8500
      :protocol: 1
      :failure: consistent
      :ignore_absent: true
      :use_ssl: false
      :ssl_verify: false
      :ssl_cert: /path/to/cert
      :ssl_key: /path/to/key
      :ssl_ca_cert: /path/to/ca/cert

## Query the catalog

You can also query the Consul catalog for values by adding catalog resources
in your paths, the values will be returned as an array so you will need to
parse accordingly.  Note that hiera_hash is not supported with Consul's
catalog endpoint.

    :backends:
      - consul

    :consul:
      :paths:
        - kv/configuration/%{fqdn}
        - kv/configuration/common
        - catalog/service
        - catalog/node

## Thanks

Thanks to @lynxman, @garethr and @crayfishx, as well as @puppetlabs for the projects this draws from:

* [hiera-consul](https://github.com/lynxman/hiera-consul)
* [hiera-etcd](https://github.com/garethr/hiera-etcd)
* [hiera-http](https://github.com/crayfishx/hiera-http)
* [hiera](https://github.com/puppetlabs/hiera)

Thanks also to @mitchellh for writing such wonderful tools and the [API Documentation](http://www.consul.io/docs/agent/http.html)

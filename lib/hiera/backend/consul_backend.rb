class Hiera
  module Backend
    class Consul_backend

      def initialize
        require 'net/http'
        require 'net/https'
        require 'json'
        require 'deep_merge'

        Hiera.debug("Hiera Consul backend starting")

        @config = Config[:consul]

        # default settings
        @config[:host] ||= '127.0.0.1'
        @config[:port] ||= '8500'
        @config[:protocol] ||= 1
        @config[:paths] ||= ['kv/common']

        # initialisation
        @consul = Net::HTTP.new(@config[:host], @config[:port])
        @consul.read_timeout = @config[:http_read_timeout] || 10
        @consul.open_timeout = @config[:http_connect_timeout] || 10

        if @config[:use_ssl]
          @consul.use_ssl = true

          if @config[:ssl_verify] == false
            @consul.verify_mode = OpenSSL::SSL::VERIFY_NONE
          else
            @consul.verify_mode = OpenSSL::SSL::VERIFY_PEER
          end

          if @config[:ssl_cert]
            store = OpenSSL::X509::Store.new
            store.add_cert(OpenSSL::X509::Certificate.new(File.read(@config[:ssl_ca_cert])))
            @consul.cert_store = store

            @consul.key = OpenSSL::PKey::RSA.new(File.read(@config[:ssl_cert]))
            @consul.cert = OpenSSL::X509::Certificate.new(File.read(@config[:ssl_key]))
          end
        else
          @consul.use_ssl = false
        end
      end

      def lookup(key, scope, order_override, resolution_type)
        Hiera.debug("Looking up #{key} in Consul backend")

        answer = nil
        prefix = "/v#{@config[:protocol]}"
        mapped_key = key.gsub('::', '/')

        Backend.datasources(scope, order_override, @config[:paths]) do |source|
          Hiera.debug("Looking under path #{prefix}/#{source}")

          case resolution_type
          when :hash
            # hash type only supports querying the kv store
            if source !~ /^kv\//
              Hiera.debug("hiera_hash only supports Consul KV store, skipping")
              next
            end

            # build hash from structure of tree below the given key
            httpreq = Net::HTTP::Get.new("#{prefix}/#{source}/#{mapped_key}?recurse=1&keys=1")
            result = @consul.request(httpreq)
            unless result.kind_of?(Net::HTTPSuccess)
              if result.code == '404'
                Hiera.debug("Cannot find data at #{prefix}/#{source}/#{mapped_key}, skipping")
              else
                Hiera.debug("Cannot find data at #{prefix}/#{source}/#{mapped_key} (HTTP response code #{result.code}), skipping")
              end
              next
            end

            result_hash = {}
            keys = JSON.parse(result.body)
            # keys don't include the endpoint, so we'll need to remove the
            # endpoint in order to be able to convert the returned key back
            # into something we can use with the known prefix and source
            source_sans_endpoint = source.sub(/^kv\//, '')
            keys.each do |subkey|
              subkey.sub!("#{source_sans_endpoint}/", '')
              httpreq = Net::HTTP::Get.new("#{prefix}/#{source}/#{subkey}?raw=1")
              result = @consul.request(httpreq)
              unless result.kind_of?(Net::HTTPSuccess)
                if result.code == '404'
                  Hiera.debug("Cannot find data at #{prefix}/#{source}/#{subkey}, skipping")
                else
                  Hiera.debug("Cannot find data at #{prefix}/#{source}/#{subkey} (HTTP response code #{result.code}), skipping")
                end
                # fail disgracefully so we don't return inconsistent data
                raise Exception, "HTTP response code #{result.code} retrieving #{prefix}/#{source}/#{subkey}"
              end

              begin
                data = JSON.parse(result.body)
                result_hash.deep_merge!(self.mdh(subkey.split('/'), data))
              rescue
                result_hash.deep_merge!(self.mdh(subkey.split('/'), result.body))
              end
            end

            answer ||= {}
            res = result_hash
            key.split('::').each do |keypart|
              res = res[keypart]
            end
            if res.is_a?(Hash)
              answer = Backend.merge_answer(res, answer)
            else
              Hiera.debug("Hash requested, but #{prefix}/#{source}/#{subkey} is a #{res.class}, skipping")
              next
            end

          else  # when resolution_type != :hash
            if source !~ /(catalog|kv)\//
              if resolution_type == :array
                Hiera.debug("hiera_array only supports Consul kv and catalog endpoints, skipping")
              else
                Hiera.debug("hiera only supports Consul kv and catalog endpoints, skipping")
              end
              next
            end

            httpreq = Net::HTTP::Get.new("#{prefix}/#{source}/#{mapped_key}")
            result = @consul.request(httpreq)
            unless result.kind_of?(Net::HTTPSuccess)
              if result.code == '404'
                Hiera.debug("Cannot find data at #{prefix}/#{source}/#{mapped_key}, skipping")
              else
                Hiera.debug("Cannot find data at #{prefix}/#{source}/#{mapped_key} (HTTP response code #{result.code}), skipping")
              end
              next
            end

            case resolution_type
            when :array
              answer ||= []
              answer << self.parse_result(result.body)
            else
              answer = self.parse_result(result.body)
              break if answer
            end
          end

        end
        answer
      end

      def parse_result(res)
        require 'base64'
        answer = nil
        # Consul always returns an array
        res_array = JSON.parse(res)
        if res_array.length > 0
          if res_array[0].include? 'Value'
            # this is from Consul's KV store endpoint
            answer = Base64.decode64(res_array.first['Value'])
          else
            # this is from Consul's catalog endpoint
            answer = res_array
          end
        end
        return answer
      end

      # construct a multi-dimensional hash from an array of keys and a value
      def mdh(key_array, value)
        count = 0
        mdhash = lambda do |*keys|
          count += 1
          Hash.new(var = keys.shift).update(var => mdhash[*keys] || value) unless keys.empty?
        end
        mdhash.call(*key_array)
      end
    end
  end
end

# frozen_string_literal: true

require 'money'
require 'money/rates_store/rate_removal_support'
require 'open-uri'
require 'faraday'

class Money
  module Bank
    # # Raised when there is an unexpected error in extracting exchange rates
    # # from Oanda
    class OandaCurrencyFetchError < Error; end
    class UnknownCurrency < Error; end

    # VariableExchange bank that handles fetching exchange rates from Oanda
    # and storing them in the in memory rates store.
    class OandaCurrency < Money::Bank::VariableExchange
      SERVICE_HOST = 'web-services.oanda.com'
      SERVICE_PATH = '/rates/api/v2/rates/spot.json'
      DEFAULT_DATA_SET = 'OANDA'

      # @return [Hash] Stores the currently known rates.
      attr_reader :rates

      # @return [String] Access key from Oanda allowing access to API
      attr_accessor :access_key

      class << self
        # @return [Integer] Returns the Time To Live (TTL) in seconds.
        attr_reader :ttl_in_seconds

        # @return [Time] Returns the time when the rates expire.
        attr_reader :rates_expiration

        ##
        # Set the Time To Live (TTL) in seconds.
        #
        # @param [Integer] the seconds between an expiration and another.
        def ttl_in_seconds=(value)
          @ttl_in_seconds = value
          refresh_rates_expiration! if ttl_in_seconds
        end

        ##
        # Set the rates expiration TTL seconds from the current time.
        #
        # @return [Time] The next expiration.
        def refresh_rates_expiration!
          @rates_expiration = Time.now + ttl_in_seconds
        end
      end

      def initialize(st, access_key, white_list_currencies, data_set)
        super(st)
        @store.extend Money::RatesStore::RateRemovalSupport
        @access_key = access_key
        @white_list_currencies = white_list_currencies
        @data_set = data_set
      end

      ##
      # Clears all rates stored in @rates
      #
      # @return [Hash] The empty @rates Hash.
      #
      # @example
      #   @bank = OandaCurrency.new  #=> <Money::Bank::OandaCurrency...>
      #   @bank.get_rate(:USD, :EUR)  #=> 0.776337241
      #   @bank.flush_rates           #=> {}
      def flush_rates
        store.clear_rates
      end

      ##
      # Clears the specified rate stored in @rates.
      #
      # @param [String, Symbol, Currency] from Currency to convert from (used
      #   for key into @rates).
      # @param [String, Symbol, Currency] to Currency to convert to (used for
      #   key into @rates).
      #
      # @return [Float] The flushed rate.
      #
      # @example
      #   @bank = OandaCurrency.new    #=> <Money::Bank::OandaCurrency...>
      #   @bank.get_rate(:USD, :EUR)    #=> 0.776337241
      #   @bank.flush_rate(:USD, :EUR)  #=> 0.776337241
      def flush_rate(from, to)
        store.remove_rate(from, to)
      end

      ##
      # Returns the requested rate.
      #
      # It also flushes all the rates when and if they are expired.
      #
      # @param [String, Symbol, Currency] from Currency to convert from
      # @param [String, Symbol, Currency] to Currency to convert to
      #
      # @return [Float] The requested rate.
      #
      # @example
      #   @bank = OandaCurrency.new  #=> <Money::Bank::OandaCurrency...>
      #   @bank.get_rate(:USD, :EUR)  #=> 0.776337241
      def get_rate(from, to)
        expire_rates

        fetch_rates(from.iso_code, to.iso_code) unless store.get_rate(from.iso_code, to.iso_code)
        begin
          rate = store.get_rate(from.iso_code, to.iso_code)
          raise unless rate

          rate
        rescue StandardError
          raise UnknownRate
        end
      end

      ##
      # Flushes all the rates if they are expired.
      #
      # @return [Boolean]
      def expire_rates
        if self.class.ttl_in_seconds && self.class.rates_expiration <= Time.now
          flush_rates
          self.class.refresh_rates_expiration!
          true
        else
          false
        end
      end

      private

      ##
      # Makes an api call to populate all of the exchange rates in the in
      # memory store.
      #
      # Using Faraday to capture responses with error messages from the api,
      # instead of generic OpenURI::HTTPError 400 Bad Request from [URI::HTTP]#read
      def fetch_rates(base, quote)
        response = Faraday.get(build_uri(base, quote, @data_set).to_s)
        data = raise_or_return(response, base, quote)
        extract_rates(data)
      end

      ##
      # Build a URI for the given arguments.
      #
      # @return [URI::HTTP]
      def build_uri(base, quote, data_set)
        URI::HTTPS.build(
          host: SERVICE_HOST,
          path: SERVICE_PATH,
          query: [
            "base=#{base}",
            "quote=#{quote}",
            "data_set=#{data_set}",
            "api_key=#{access_key}"
          ].join('&')
        )
      end

      ##
      # Takes the response from Oanda and extract the rates and adds them to
      # the rates store.
      #
      # @param [String] data The hash of rates from Oanda to decode.
      def extract_rates(data)
        rates = JSON.parse(data).fetch('quotes')
        rates.each do |rate|
          from_currency = rate.fetch('base_currency')
          to_currency = rate.fetch('quote_currency')

          unless @white_list_currencies.include?(from_currency) &&
                   @white_list_currencies.include?(to_currency)
            next
          end

          store.add_rate(
            from_currency,
            to_currency,
            BigDecimal(rate.fetch('midpoint'))
          )
        end
      rescue StandardError
        raise OandaCurrencyFetchError, 'Error parsing rates or adding rates to store'
      end

      # OANDA API docs: https://developer.oanda.com/exchange-rates-api/#cmp--responses
      def raise_or_return(response, base, quote)
        return response.body if response.status == 200

        rsp_body = JSON.parse(response.body)
        rsp_code = rsp_body.fetch('code')
        rsp_message = rsp_body.fetch('message')

        case response.status
        when 400
          raise OandaCurrencyFetchError, rsp_message unless rsp_code == 1

          # Attempt a second API call with default data set (OANDA)
          # return a JSON response body only if successful, else will fail with OpenURI::HTTPError
          build_uri(base, quote, DEFAULT_DATA_SET).read
        else
          raise OandaCurrencyFetchError, rsp_message
        end
      rescue OpenURI::HTTPError
        raise UnknownCurrency, rsp_message
      end
    end
  end
end

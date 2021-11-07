# frozen_string_literal: true

require 'money'
require 'money/rates_store/rate_removal_support'
require 'open-uri'

class Money
  module Bank
    # # Raised when there is an unexpected error in extracting exchange rates
    # # from fixer.io
    class FixerCurrencyFetchError < Error
    end

    # VariableExchange bank that handles fetching exchange rates from fixer.io
    # and storing them in the in memory rates store.
    class FixerCurrency < Money::Bank::VariableExchange
      SERVICE_HOST = 'web-services.oanda.com'
      SERVICE_PATH = '/rates/api/v2/rates/candle.json'

      # @return [Hash] Stores the currently known rates.
      attr_reader :rates

      # @return [String] Access key from fixer.io allowing access to API
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

      def initialize(st, access_key, white_list_currencies)
        super(st)
        @store.extend Money::RatesStore::RateRemovalSupport
        @access_key = access_key
        @white_list_currencies = white_list_currencies
      end

      ##
      # Clears all rates stored in @rates
      #
      # @return [Hash] The empty @rates Hash.
      #
      # @example
      #   @bank = FixerCurrency.new  #=> <Money::Bank::FixerCurrency...>
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
      #   @bank = FixerCurrency.new    #=> <Money::Bank::FixerCurrency...>
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
      #   @bank = FixerCurrency.new  #=> <Money::Bank::FixerCurrency...>
      #   @bank.get_rate(:USD, :EUR)  #=> 0.776337241
      def get_rate(from, to)
        expire_rates

        fetch_rates(from, to) if !store.get_rate(from.iso_code, 'EUR') || !store.get_rate(to.iso_code, 'EUR')

        begin
          store.get_rate(from.iso_code, 'EUR') / store.get_rate(to.iso_code, 'EUR')
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
      def fetch_rates(base, quote)
        data = build_uri(base, quote).read
        extract_rates(data)
      end

      ##
      # Build a URI for the given arguments.
      #
      # @return [URI::HTTP]
      def build_uri(base, quote)
        URI::HTTP.build(
          host: SERVICE_HOST,
          path: SERVICE_PATH,
          query: [
            "base=#{base}",
            "quote=#{quote}",
            "date_time=#{(Time.now.utc - 86_400).strftime('%Y-%m-%d')}",
            'data_set=MUFG',
            "access_key=#{access_key}"
          ].join('&')
        )
      end

      ##
      # Takes the response from fixer.io and extract the rates and adds them to
      # the rates store.
      #
      # @param [String] data The hash of rates from fixer to decode.
      def extract_rates(data)
        rates = JSON.parse(data).fetch(:quotes)
        rates.each do |rate|
          currency = rate.fetch(:base_currency)
          next unless @white_list_currencies.include?(currency)

          store.add_rate(
            currency,
            'EUR',
            1 / BigDecimal(rate.fetch(:average_midpoint))
          )
        end
      rescue StandardError
        raise FixerCurrencyFetchError
      end
    end
  end
end

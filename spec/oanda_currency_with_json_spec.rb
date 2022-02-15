require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

require 'money'
require 'money/bank/oanda_currency'

describe Money::Bank::OandaCurrency do
  before :each do
    @bank = Money::Bank::OandaCurrency.new(
      Money::RatesStore::Memory.new,
      '123',
      ['EUR', 'CNY', 'USD', 'JPY'],
      'MUFG'
      )
  end

  context 'given ttl_in_seconds' do
    before(:each) do
      Money::Bank::OandaCurrency.ttl_in_seconds = 86_400
    end

    it 'should accept a ttl_in_seconds option' do
      expect(Money::Bank::OandaCurrency.ttl_in_seconds).to eq(86_400)
    end

    describe '.refresh_rates_expiration!' do
      it 'set the #rates_expiration using the TTL and the current time' do
        new_time = Time.now
        Timecop.freeze(new_time)
        Money::Bank::OandaCurrency.refresh_rates_expiration!
        expect(Money::Bank::OandaCurrency.rates_expiration)
          .to eq(new_time + 86_400)
      end
    end
  end

  describe '#get_rate' do
    before(:each) do
      @bank.flush_rates
      @bank.store.add_rate(:EUR, :EUR, 1.0)
    end

    it 'should try to expire the rates' do
      expect(@bank).to receive(:expire_rates).once
      @bank.get_rate(Money::Currency.wrap(:EUR), Money::Currency.wrap(:EUR))
    end

    it 'should return the correct rate' do
      expect(@bank.get_rate(Money::Currency.wrap(:EUR), Money::Currency.wrap(:EUR))).to eq(1.0)
    end

    context 'when rate is unknown' do
      before(:each) do
        @bank.flush_rates
        allow(@bank).to receive(:fetch_rates) do
          @bank.store.add_rate(Money::Currency.wrap(:EUR), Money::Currency.wrap(:EUR), 1.0)
          @bank.store.add_rate(Money::Currency.wrap(:EUR), Money::Currency.wrap(:CNY), 7.77)
          @bank.store.add_rate(Money::Currency.wrap(:CNY), Money::Currency.wrap(:EUR), 7.77)
        end
      end

      it 'should call #fetch_rates' do
        expect(@bank).to receive(:fetch_rates).once
        @bank.get_rate(Money::Currency.wrap(:EUR), Money::Currency.wrap(:CNY))
      end

      it 'should store the rate for faster retreival' do
        @bank.get_rate(Money::Currency.wrap(:EUR), Money::Currency.wrap(:EUR))
        expect(@bank.store.instance_variable_get('@index'))
          .to include('EUR_TO_EUR')
      end

      context 'when exhange rate is not found in store' do
        it 'should raise UnknownRate error' do
          expect { @bank.get_rate(Money::Currency.wrap(:VND), Money::Currency.wrap(:USD)) }
            .to raise_error(Money::Bank::UnknownRate)
        end
      end
    end

    context 'when the currency is not found upstream' do
      before do
        failed_response = instance_double(Faraday::Response,
                                          status: 400,
                                          body: { code: 1, message: 'Dunno why but I still fail after falling back to OANDA' }.to_json)
        allow(Faraday).to receive(:get).and_return(failed_response)
      end

      it 'should fall back to default data set and attempt another API call' do
        allow(@bank).to receive_message_chain(:build_uri, :read).and_return(anything)
        @bank.store.add_rate(:VND, :USD, 0.6)

        @bank.get_rate(Money::Currency.wrap(:VND), Money::Currency.wrap(:USD))
        expect(@bank.store.instance_variable_get('@index'))
          .to include('VND_TO_USD')
      end

      it 'should raise UnknownCurrency error when second call with default data set fails' do
        expect { @bank.get_rate(Money::Currency.wrap(:VND), Money::Currency.wrap(:USD)) }
          .to raise_error(Money::Bank::UnknownCurrency, 'Dunno why but I still fail after falling back to OANDA')
      end
    end

    context 'when there are other errors fetching from OANDA' do
      before do
        failed_response = instance_double(Faraday::Response,
                                          status: 404,
                                          body: { code: 56, message: 'The rates requested have not yet been published' }.to_json)
        allow(Faraday).to receive(:get).and_return(failed_response)
      end

      it 'should raise OandaCurrencyFetchError with an error message' do
        expect { @bank.get_rate(Money::Currency.wrap(:MYR), Money::Currency.wrap(:USD)) }
          .to raise_error(Money::Bank::OandaCurrencyFetchError, 'The rates requested have not yet been published')
      end
    end

    context 'when rate is known' do
      it 'should not use #fetch_rates' do
        expect(@bank).to_not receive(:fetch_rates)
        @bank.get_rate(Money::Currency.wrap(:EUR), Money::Currency.wrap(:EUR))
      end
    end
  end

  describe '#flush_rates' do
    before(:each) do
      @bank.store.add_rate(Money::Currency.wrap(:EUR), Money::Currency.wrap(:EUR), 1.0)
    end

    it 'should empty @rates' do
      @bank.get_rate(Money::Currency.wrap(:EUR), Money::Currency.wrap(:EUR))
      @bank.flush_rates
      expect(@bank.store.instance_variable_get('@index')).to eq({})
    end
  end

  describe '#flush_rate' do
    before(:each) do
      allow(@bank).to(receive(:fetch_rates).once) do
        @bank.store.add_rate(Money::Currency.wrap(:JPY), Money::Currency.wrap(:USD), 107)
        @bank.store.add_rate(Money::Currency.wrap(:USD), Money::Currency.wrap(:JPY), 1.2)
      end
    end

    it 'should remove a specific rate from @rates' do
      @bank.get_rate(Money::Currency.wrap(:JPY), Money::Currency.wrap(:USD))
      @bank.flush_rate(Money::Currency.wrap(:USD), Money::Currency.wrap(:JPY))
      expect(@bank.store.instance_variable_get('@index'))
        .to include('JPY_TO_USD')
      expect(@bank.store.instance_variable_get('@index'))
        .to_not include('USD_TO_JPY')
    end
  end

  describe '#expire_rates' do
    before do
      Money::Bank::OandaCurrency.ttl_in_seconds = 1000
    end

    context 'when the ttl has expired' do
      before do
        new_time = Time.now + 1001
        Timecop.freeze(new_time)
      end

      it 'should flush all rates' do
        expect(@bank).to receive(:flush_rates)
        @bank.expire_rates
      end

      it 'updates the next expiration time' do
        exp_time = Time.now + 1000

        @bank.expire_rates
        expect(Money::Bank::OandaCurrency.rates_expiration).to eq(exp_time)
      end
    end

    context 'when the ttl has not expired' do
      it 'not should flush all rates' do
        expect(@bank).to_not receive(:flush_rates)
        @bank.expire_rates
      end
    end
  end

  describe 'private#build_uri' do
    it 'uses MUFG data set' do
      expect(@bank.send(:build_uri, 'JPY', 'EUR', 'MUFG').query.split('&')).to(
        include('data_set=MUFG'))
    end

    it 'grabs previous day rate info' do
      Timecop.freeze(Time.now.utc)
      expect(@bank.send(:build_uri, 'JPY', 'EUR', 'MUFG').query.split('&')).to(
        include("date_time=#{(Time.now - 86_400).strftime('%Y-%m-%d')}"))
    end
  end
end

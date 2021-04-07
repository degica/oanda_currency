require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

require 'money'
require 'money/bank/fixer_currency'

describe Money::Bank::FixerCurrency do
  before :each do
    @bank = Money::Bank::FixerCurrency.new(Money::RatesStore::Memory.new, '123')
  end

  context 'given ttl_in_seconds' do
    before(:each) do
      Money::Bank::FixerCurrency.ttl_in_seconds = 86_400
    end

    it 'should accept a ttl_in_seconds option' do
      expect(Money::Bank::FixerCurrency.ttl_in_seconds).to eq(86_400)
    end

    describe '.refresh_rates_expiration!' do
      it 'set the #rates_expiration using the TTL and the current time' do
        new_time = Time.now
        Timecop.freeze(new_time)
        Money::Bank::FixerCurrency.refresh_rates_expiration!
        expect(Money::Bank::FixerCurrency.rates_expiration)
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
      @bank.get_rate(:EUR, :EUR)
    end

    it 'should return the correct rate' do
      expect(@bank.get_rate(:EUR, :EUR)).to eq(1.0)
    end

    context 'when rate is unknown' do
      before(:each) do
        @bank.flush_rates
        allow(@bank).to receive(:fetch_rates) do
          @bank.store.add_rate(:EUR, :EUR, 1.0)
          @bank.store.add_rate(:EUR, :CNY, 7.77)
          @bank.store.add_rate(:CNY, :EUR, 7.77)
        end
      end

      it 'should call #fetch_rates' do
        expect(@bank).to receive(:fetch_rates).once
        @bank.get_rate(:EUR, :CNY)
      end

      it 'should store the rate for faster retreival' do
        @bank.get_rate(:EUR, :EUR)
        expect(@bank.store.instance_variable_get('@index'))
          .to include('EUR_TO_EUR')
      end

      context 'when exhange rate is not found' do
        it 'should raise UnknownRate error' do
          expect { @bank.get_rate('VND', :USD) }
            .to raise_error(Money::Bank::UnknownRate)
        end
      end
    end

    context 'when rate is known' do
      it 'should not use #fetch_rates' do
        expect(@bank).to_not receive(:fetch_rates)
        @bank.get_rate(:EUR, :EUR)
      end
    end
  end

  describe '#flush_rates' do
    before(:each) do
      @bank.store.add_rate(:EUR, :EUR, 1.0)
    end

    it 'should empty @rates' do
      @bank.get_rate(:EUR, :EUR)
      @bank.flush_rates
      expect(@bank.store.instance_variable_get('@index')).to eq({})
    end
  end

  describe '#flush_rate' do
    before(:each) do
      allow(@bank).to(receive(:fetch_rates).once) do
        @bank.store.add_rate('JPY', :EUR, 107)
        @bank.store.add_rate(:USD, :EUR, 1.2)
      end
    end

    it 'should remove a specific rate from @rates' do
      @bank.get_rate(:USD, :JPY)
      @bank.flush_rate(:USD, :EUR)
      expect(@bank.store.instance_variable_get('@index'))
        .to include('JPY_TO_EUR')
      expect(@bank.store.instance_variable_get('@index'))
        .to_not include('USD_TO_EUR')
    end
  end

  describe '#expire_rates' do
    before do
      Money::Bank::FixerCurrency.ttl_in_seconds = 1000
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
        expect(Money::Bank::FixerCurrency.rates_expiration).to eq(exp_time)
      end
    end

    context 'when the ttl has not expired' do
      it 'not should flush all rates' do
        expect(@bank).to_not receive(:flush_rates)
        @bank.expire_rates
      end
    end
  end
end

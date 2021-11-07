Oanda Currency
===============
This gem extends Money::Bank::VariableExchange with Money::Bank::OandaCurrency
and gives you access to the current Oanda exchange rates.

This gem was forked from the [Money::Bank::GoogleCurrency](http://rubymoney.github.com/google_currency)
gem.

Installation
-----
If the money gem is not already installed:

```gem install money```

Install the Oanda_currency gem:

```gem install Oanda_currency```

Usage
-----

```ruby

require 'money'
require 'money/bank/oanda_currency'

# (optional)
# set the seconds after than the current rates are automatically expired
# by default, they never expire
Money::Bank::OandaCurrency.ttl_in_seconds = 86400

# set default bank to instance of OandaCurrency with access key parameter
# being your access_key from Oanda
Money.default_bank =
  Money::Bank::OandaCurrency.new(
  	rate_store,
  	'your_access_key',
  	currencies_supported
  )

# create a new money object, and use the standard #exchange_to method
money = Money.new(1_00, "USD") # amount is in cents
money.exchange_to(:EUR)

# or install and use the 'monetize' gem
require 'monetize'
money = 1.to_money(:USD)
money.exchange_to(:EUR)

```

An `UnknownRate` will be thrown if `#exchange_to` is called with a `Currency`
that `Money` knows, but Oanda does not.

An `UnknownCurrency` will be thrown if `#exchange_to` is called with a
`Currency` that `Money` does not know.

A `OandaCurrencyFetchError` will be thrown if there is an unknown issue with
parsing the response including rates from Oanda's API.

Caveats
-------

This gem uses [Oanda](https://www.oanda.com/) under the hood.

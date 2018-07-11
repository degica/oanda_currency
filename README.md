Fixer Currency
===============
This gem extends Money::Bank::VariableExchange with Money::Bank::FixerCurrency
and gives you access to the current fixer.io exchange rates.

This gem was forked from the [Money::Bank::GoogleCurrency](http://rubymoney.github.com/google_currency)
gem.

Installation
-----
If the money gem is not already installed:

```gem install money```

Install the fixer_currency gem:

```gem install fixer_currency```

Usage
-----

```ruby

require 'money'
require 'money/bank/fixer_currency'

# (optional)
# set the seconds after than the current rates are automatically expired
# by default, they never expire
Money::Bank::FixerCurrency.ttl_in_seconds = 86400

# set default bank to instance of FixerCurrency with access key parameter
# being your access_key from fixer.io
Money.default_bank = Money::Bank::FixerCurrency.new('your_access_key')

# create a new money object, and use the standard #exchange_to method
money = Money.new(1_00, "USD") # amount is in cents
money.exchange_to(:EUR)

# or install and use the 'monetize' gem
require 'monetize'
money = 1.to_money(:USD)
money.exchange_to(:EUR)

```

An `UnknownRate` will be thrown if `#exchange_to` is called with a `Currency`
that `Money` knows, but fixer.io does not.

An `UnknownCurrency` will be thrown if `#exchange_to` is called with a
`Currency` that `Money` does not know.

A `FixerCurrencyFetchError` will be thrown if there is an unknown issue with
parsing the response including rates from fixer.io's API.

Caveats
-------

This gem uses [fixer.io](https://fixer.io/) under the hood.

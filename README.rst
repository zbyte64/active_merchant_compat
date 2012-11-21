
Testing
=======

Install the active_merchant_compat gem to your environment::

  gem1.9.1 build activemerchantcompat.gemspec
  gem1.9.1 install activemerchantcompat-0.1.gem


Create a file called gateways.yaml that will contain your test credentials::

    authorize_net_cim_compat:
        login: login
        password: password
        test: true

    orbital_compat:
        login: login
        password: password
        merchant_id: somemerchant
        test: true


Run tox::

  tox

Or run tests with setup.py::

  python setup.py test


The tests will only run for gateways that you have supplied credentials for and the bogus gateway.

# -*- coding: utf-8 -*-
module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    # ==== Customer Information Manager (CIM)
    #
    # The Authorize.Net Customer Information Manager (CIM) is an optional additional service that allows you to store sensitive payment information on
    # Authorize.Net's servers, simplifying payments for returning customers and recurring transactions. It can also help with Payment Card Industry (PCI)
    # Data Security Standard compliance, since customer data is no longer stored locally.
    #
    # To use the AuthorizeNetCimGateway CIM must be enabled for your account.
    #
    # Information about CIM is available on the {Authorize.Net website}[http://www.authorize.net/solutions/merchantsolutions/merchantservices/cim/].
    # Information about the CIM API is available at the {Authorize.Net Integration Center}[http://developer.authorize.net/]
    #
    # ==== Login and Password
    #
    # The login and password are not the username and password you use to
    # login to the Authorize.Net Merchant Interface. Instead, you will
    # use the API Login ID as the login and Transaction Key as the
    # password.
    #
    # ==== How to Get Your API Login ID and Transaction Key
    #
    # 1. Log into the Merchant Interface
    # 2. Select Settings from the Main Menu
    # 3. Click on API Login ID and Transaction Key in the Security section
    # 4. Type in the answer to the secret question configured on setup
    # 5. Click Submit
    class AuthorizeNetCimCompatGateway < AuthorizeNetCimGateway
      def merge_authorization_strings(old_auth, new_auth)
        trans_id, profile_id, payment_profile_id, shipping_address_id = split_authorization(old_auth)
        new_trans_id, new_profile_id, new_payment_profile_id, new_shipping_address_id = split_authorization(new_auth)
        return authorization_string(new_trans_id || trans_id, new_profile_id || profile_id, new_payment_profile_id || payment_profile_id, new_shipping_address_id || shipping_address_id)
      end
      
      def create_transaction(reference, params = {})
        trans_id, profile_id, payment_profile_id, shipping_address_id = split_authorization(reference)
        transaction = {
          :trans_id => trans_id,
          :customer_profile_id => profile_id,
          :customer_payment_profile_id => payment_profile_id,
          :customer_shipping_address_id => shipping_address_id,
        }
        options[:transaction] = transaction.merge(params)
        response = create_customer_profile_transaction(options)
        response.authorization = merge_authorization_strings(creditcard_or_reference, response.authorization)
        return response
      end
      
      def store(creditcard, options = {})
        #TODO check that the responses are successful, if not delete other profiles
        options[:profile] = {
          :email => options[:email] || creditcard.email #TODO verify this
        }
        response = create_customer_profile(options)
        _, profile_id, _, _ = split_authorization(response.authorization)
        options[:customer_profile_id] = profile_id
        options[:payment_profile] = {
          :payment => {
            :credit_card => creditcard
          }
        }
        response = create_customer_payment_profile(options)
        _, _, payment_profile_id, ship_address_id = split_authorization(response.authorization)
        if options[:ship_address]:
          #TODO copy options instead
          options[:address] = options[:ship_address]
          response = create_customer_shipping_address(options)
          _, _, _, ship_address_id = split_authorization(response.authorization)
        response.authorization = authorization_string("", profile_id, payment_profile_id, ship_address_id)
        return response
      end
      
      #TODO verify we have the right trnasaction types
      
      def authorize(money, creditcard_or_reference, options = {})
        #every action must be done through a payment profile, so this will create a profile on CIM!
        if not creditcard_or_reference.is_a?(String)
          response = store(creditcard_or_reference)
          credit_card_or_reference = response.authorization
        end
        
        create_transaction(creditcard_or_reference, {:type => :auth_only, :amount => "%.2f" % money / 100.0})
      end

      # Capture an authorization that has previously been requested
      def capture(money, authorization, options = {})
        create_transaction(creditcard_or_reference, {:type => :prior_auth_capture, :amount => "%.2f" % money / 100.0})
      end

      def purchase(money, creditcard_or_reference, options = {})
        #every action must be done through a payment profile, so this will create a profile on CIM!
        if not creditcard_or_reference.is_a?(String)
          response = store(creditcard_or_reference)
          credit_card_or_reference = response.authorization
        end
        
        create_transaction(creditcard_or_reference, {:type => :capture_only, :amount => "%.2f" % money / 100.0})
      end

      def void(identification, options = {})
        create_transaction(identification, {:type => :void})
      end

      def refund(money, identification, options = {})
        create_transaction(identification, {:type => :refund, :amount => "%.2f" % money / 100.0})
      end

      # Updates a customer subscription/profile
      #TODO
      def update(reference, creditcard, options = {})
        requires!(options, :order_id)
        setup_address_hash(options)
        commit(build_update_subscription_request(reference, creditcard, options), options)
      end

      # Removes a customer subscription/profile
      def unstore(reference, options = {})
        #TODO consider: we may want to recycle the profile id, but remove the payment
        trans_id, profile_id, payment_profile_id, shipping_address_id = split_authorization(reference)
        params = {
          :customer_profile_id => profile_id,
          :customer_payment_profile_id => payment_profile_id,
          :customer_address_id => shipping_address_id
        }
        if shipping_address_id
          delete_customer_shippping_address(params)
        end
        if payment_profile_id
          delete_customer_payment_profile(params)
        end
        delete_customer_profile(params)
      end

      # Retrieves a customer subscription/profile
      #TODO
      def retrieve(reference, options = {})
        requires!(options, :order_id)
        commit(build_retrieve_subscription_request(reference, options), options)
      end
      
      def authorization_string(*args)
        args.compact.join(";")
      end

      def split_authorization(authorization)
        authorization.split(';')
      end

      def commit(action, request)
        url = test? ? test_url : live_url
        xml = ssl_post(url, request, "Content-Type" => "text/xml")

        response_params = parse(action, xml)

        message = response_params['messages']['message']['text']
        test_mode = test? || message =~ /Test Mode/
        success = response_params['messages']['result_code'] == 'Ok'
        response_params['direct_response'] = parse_direct_response(response_params['direct_response']) if response_params['direct_response']
        transaction_id = response_params['direct_response']['transaction_id'] if response_params['direct_response']
        
        #trans_id, profile_id, payment_profile_id, shipping_address_id
        profile_params = response_params['profile'] ? response_params['profile'] : response_params
        authorization = authorization_string(transaction_id || '', profile_params['customer_profile_id'] || '', profile_params['customer_payment_profile_id'] || '', profile_params['customer_address_id'] || '')

        Response.new(success, message, response_params,
          :test => test_mode,
          :authorization => authorization
        )
      end
    end
  end
end

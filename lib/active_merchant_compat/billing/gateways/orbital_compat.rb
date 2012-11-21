module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    # For more information on Orbital, visit the {integration center}[http://download.chasepaymentech.com]
    #
    # ==== Authentication Options
    #
    # The Orbital Gateway supports two methods of authenticating incoming requests:
    # Source IP authentication and Connection Username/Password authentication
    #
    # In addition, these IP addresses/Connection Usernames must be affiliated with the Merchant IDs
    # for which the client should be submitting transactions.
    #
    # This does allow Third Party Hosting service organizations presenting on behalf of other
    # merchants to submit transactions.  However, each time a new customer is added, the
    # merchant or Third-Party hosting organization needs to ensure that the new Merchant IDs
    # or Chain IDs are affiliated with the hosting companies IPs or Connection Usernames.
    #
    # If the merchant expects to have more than one merchant account with the Orbital
    # Gateway, it should have its IP addresses/Connection Usernames affiliated at the Chain
    # level hierarchy within the Orbital Gateway.  Each time a new merchant ID is added, as
    # long as it is placed within the same Chain, it will simply work.  Otherwise, the additional
    # MIDs will need to be affiliated with the merchant IPs or Connection Usernames respectively.
    # For example, we generally affiliate all Salem accounts [BIN 000001] with
    # their Company Number [formerly called MA #] number so all MIDs or Divisions under that
    # Company will automatically be affiliated.

    class OrbitalCompatGateway < OrbitalGateway
      # A – Authorization request
      def authorize(money, creditcard_or_reference, options = {})
        order = build_new_order_xml('A', money, options) do |xml|
          if creditcard_or_reference.is_a?(String)
            _, _, customer_ref_num = split_authorization(creditcard_or_reference)
            options[:customer_ref_num] = customer_ref_num
            options[:profile_txn] = true
            add_customer_data(xml, options)
          else
            add_creditcard(xml, creditcard_or_reference, options[:currency])
          end
          #TODO is this needed if we are doing a profile transaction?
          add_address(xml, creditcard_or_reference, options)
        end
        commit(order, :authorize)
      end

      # AC – Authorization and Capture
      def purchase(money, creditcard_or_reference, options = {})
        order = build_new_order_xml('AC', money, options) do |xml|
          if creditcard_or_reference.is_a?(String)
            _, _, customer_ref_num = split_authorization(creditcard_or_reference)
            options[:customer_ref_num] = customer_ref_num
            options[:profile_txn] = true
            add_customer_data(xml, options)
          else
            add_creditcard(xml, creditcard_or_reference, options[:currency])
          end
          add_address(xml, creditcard_or_reference, options)
        end
        commit(order, :purchase)
      end

      # R – Refund request
      def refund(money, authorization, options = {})
        _, _, customer_ref_num = split_authorization(authorization)
        if customer_ref_num
          options[:customer_ref_num] = customer_ref_num
          options[:profile_txn] = true
        end
        
        order = build_new_order_xml('R', money, options.merge(:authorization => authorization)) do |xml|
          add_refund(xml, options[:currency])
          xml.tag! :CustomerRefNum, options[:customer_ref_num] if options[:profile_txn]
        end
        commit(order, :refund)
      end
      
      def store(creditcard, options = {})
        add_customer_profile(creditcard, options)
      end

      # Updates a customer subscription/profile
      def update(reference, creditcard, options = {})
        _, _, customer_ref_num = split_authorization(reference)
        options[:customer_ref_num] = customer_ref_num
        update_customer_profile(creditcard, options)
      end

      # Removes a customer subscription/profile
      def unstore(reference, options = {})
        _, _, customer_ref_num = split_authorization(reference)
        delete_customer_profile(customer_ref_num)
      end

      # Retrieves a customer subscription/profile
      def retrieve(reference, options = {})
        _, _, customer_ref_num = split_authorization(reference)
        retrieve_customer_profile(customer_ref_num)
      end

      def add_address(xml, creditcard, options)
        if address = options[:billing_address] || options[:address]
          avs_supported = AVS_SUPPORTED_COUNTRIES.include?(address[:country].to_s)

          if avs_supported
            xml.tag! :AVSzip, address[:zip]
            xml.tag! :AVSaddress1, address[:address1]
            xml.tag! :AVSaddress2, address[:address2]
            xml.tag! :AVScity, address[:city]
            xml.tag! :AVSstate, address[:state]
            xml.tag! :AVSphoneNum, address[:phone] ? address[:phone].scan(/\d/).join.to_s : nil
          end
          
          #TODO review this
          if not creditcard.is_a?(String)
            xml.tag! :AVSname, creditcard.name
          end
          xml.tag! :AVScountryCode, avs_supported ? address[:country] : ''
        end
      end

      def commit(order, message_type=nil)
        headers = POST_HEADERS.merge("Content-length" => order.size.to_s)
        request = lambda{|url| parse(ssl_post(url, order, headers))}

        # Failover URL will be attempted in the event of a connection error
        response = begin
          request.call(remote_url)
        rescue ConnectionError
          request.call(remote_url(:secondary))
        end
        
        #TODO validate this
        #we want the string to be transaction, order id, customer number
        authorization = if [:add_customer_profile, :update_customer_profile, :retrieve_customer_profile, :delete_customer_profile].index(message_type) != nil
          authorization_string("", response[:order_id], response[:tx_ref_num])
        else
          authorization_string(response[:tx_ref_num], response[:order_id], "")
        end

        Response.new(success?(response, message_type), message_from(response), response,
          {
             :authorization => authorization,
             :test => self.test?,
             :avs_result => OrbitalGateway::AVSResult.new(response[:avs_resp_code]),
             :cvv_result => response[:cvv2_resp_code]
          }
        )
      end
    end
  end
end

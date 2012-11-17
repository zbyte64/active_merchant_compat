require "rubygems"
require "active_merchant"
require "json"

class PaymentBridge
    def initialize()
        #do nothing
    end
    
    def configure_from_environ()
        payload = ENV['PAYMENT_CONFIGURATION']
        if payload == nil
            configure([])
        else
            config = JSON.parse(payload)
            configure(config)
        end
    end
    
    def configure(config)
        @gateways = {}
        for gateway_config in config:
            klass = get_gateway_class(gateway_config['module'])
            @gateways[gateway_config['name']] = klass.new(*gateway_config['params'])
        end
    end
    
    def get_gateway_class(name)
        case name
        when "bogus"
          return ActiveMerchant::Billing::BogusGateway
        when "paypal"
          return ActiveMerchant::Billing::PaypalGateway
        else
          return nil
        end
    end
    
    def run()
        # read command from standard input:
        #TODO guard against other code printing to STDOUT
        while cmd = STDIN.gets
          #TODO we want to ensure we read one line at a time
          payload = JSON.parse(cmd)
          
          data = payload['data']
          secure_data = payload['secure_data'] || {}
          action = payload['action']
          gateway = @gateways[payload['gateway']]
          
          if gateway == nil
            callback_params = {
                'message' => "Unrecognized gateway",
                'success' => false
            }
          elsif data == nil
            callback_params = {
                'message' => "No Data",
                'success' => false
            }
          elsif secure_data == nil
            callback_params = {
                'message' => "No Secure Data",
                'success' => false
            }
          elsif action == nil
            callback_params = {
                'message' => "No action",
                'success' => false
            }
          else
            expanded_response = process_direct_post(gateway, action, data, secure_data)
            callback_params = construct_callback_params(expanded_response)
          end
          callback_params['gateway'] = payload['gateway']
          callback_params['action'] = action
          callback_params['request_id'] = payload['request_id']
          
          puts JSON.dump(callback_params)
          STDOUT.flush
        end
    end
    
    def construct_callback_params(expanded_response)
        response_params = expanded_response.fetch('passthrough', {})
        
        response = expanded_response['response']
        if response != nil
          response_params = response_params.merge({
            #'action': action,
            #'gateway': decrypted_data['gateway'],
            'success' => response.success?(),
            'test' => response.test?(),
            'fraud_review' => response.fraud_review?(),
            'message' => response.message,
            #'result' => response.result,
            #'card_store_id': response.card_store_id,
            'authorization' => response.authorization #this may also be your card store id
            #'avs' => response.avs_result,
            #'cvv' => response.cvv_result,
          })
        else
          response_params['success'] = false
        end
        
        if expanded_response['message'] != nil
          response_params['message'] = expanded_response['message']
        end
        
        if expanded_response['credit_card'] != nil
            credit_card = expanded_response['credit_card']
            response_params['cc_display'] = credit_card.display_number
            response_params['cc_exp_month'] = credit_card.month
            response_params['cc_exp_year'] = credit_card.year
            response_params['cc_type'] = credit_card.brand
        end
        
        if expanded_response['amount'] != nil
            response_params['amount'] = expanded_response['amount']
        end
        
        if expanded_response['currency_code'] != nil
            response_params['currency_code'] = expanded_response['currency_code']
        end
        
        return response_params
    end
    
    def parse_address_from_post(post_data, prefix='bill')
        address = {}
        value_found = false
        for key in ['first_name', 'last_name', 'address1', 'address2', 'city', 'state', 'country', 'zip', 'email']
            f_key = prefix+"_"+key
            if post_data.has_key?(f_key)
                value_found = true
            end
            address[key] = post_data.fetch(f_key, nil)
        end
        
        if value_found
            return address
        else
            return nil
        end
    end
    
    def process_direct_post(gateway, action, data, secure_data)
        #should return dict containing: response, credit_card, passthrough, amount, currency_code
        case action
        when "authorize"
          return authorize(gateway, data, secure_data)
        when "capture"
          return capture(gateway, data, secure_data)
        when "purchase"
          return purchase(gateway, data, secure_data)
        when "void"
          return void(gateway, data, secure_data)
        when "refund"
          return refund(gateway, data, secure_data)
        when "store"
          return store(gateway, data, secure_data)
        when "retrieve"
          return retrieve(gateway, data, secure_data)
        when "update"
          return update(gateway, data, secure_data)
        when "unstore"
          return unstore(gateway, data, secure_data)
        else
          return invalid_action(gateway, action, data, secure_data)
        end
    end
    
    def build_expanded_response(data, secure_data, options={})
      passthrough_fields = secure_data.fetch('passthrough', [])
      passthrough = {}
      for key in passthrough_fields
        if not key.startswith('cc_') and data.has_key?(key)
          passthrough[key] = post_data[key]
        end
      end
      
      return {'response' => options[:response],
              'credit_card' => options[:credit_card],
              'amount' => options[:amount],
              'currency_code' => options[:currency_code],
              'passthrough' => passthrough}
    end
    
    def build_options(data, secure_data)
      options = secure_data.fetch('options', {})
      #currency_code = secure_data['currency_code']
      
      address = parse_address_from_post(data)
      if address
        options['address'] = address
      end
      
      ship_address = parse_address_from_post(data, prefix='ship')
      if ship_address:
        options['ship_address'] = ship_address
      end
      return options
    end
    
    def build_credit_card(data)
      return ActiveMerchant::Billing::CreditCard.new(
        :number => data['cc_number'],
        :month => data['cc_exp_month'],
        :year => data['cc_exp_year'],
        :first_name => data['bill_first_name'],
        :last_name => data['bill_last_name'],
        :verification_value => data['cc_ccv']
      )
    end
    
    def invalid_action(gateway, action, data, secure_data)
      response = build_expanded_response(data, secure_data)
      response['message'] = "Unreognized Action"
      return response
    end
    
    def authorize(gateway, data, secure_data)
      amount = secure_data['amount']
      credit_card = build_credit_card(data)
      options = build_options(data, secure_data)
      
      response = gateway.authorize(amount, credit_card, options)
      return build_expanded_response(data, secure_data, :response=>response, :credit_card=>credit_card, :amount=>amount)
    end
    
    def capture(gateway, data, secure_data)
      amount = secure_data['amount']
      authorization = secure_data['authorization']
      options = build_options(data, secure_data)
      
      response = gateway.capture(amount, authorization, options)
      return build_expanded_response(data, secure_data, :response=>response, :amount=>amount)
    end
    
    def purchase(gateway, data, secure_data)
      amount = secure_data['amount']
      credit_card = build_credit_card(data)
      options = build_options(data, secure_data)
      
      response = gateway.purchase(amount, credit_card, options)
      return build_expanded_response(data, secure_data, :response=>response, :credit_card=>credit_card, :amount=>amount)
    end
    
    def void(gateway, data, secure_data)
      authorization = secure_data['authorization']
      options = build_options(data, secure_data)
      
      response = gateway.void(authorization, options)
      return build_expanded_response(data, secure_data, :response=>response)
    end
    
    def refund(gateway, data, secure_data)
      amount = secure_data['amount']
      authorization = secure_data['authorization']
      options = build_options(data, secure_data)
      
      respone = gateway.refund(amount, authorization, options)
      return build_expanded_response(data, secure_data, :response=>response, :amount=>amount)
    end
    
    def store(gateway, data, secure_data)
      credit_card = build_credit_card(data)
      options = build_options(data, secure_data)
      
      response = gateway.store(credit_card, options)
      return build_expanded_response(data, secure_data, :response=>response, :credit_card=>credit_card)
    end
    
    def retrieve(gateway, data, secure_data)
      authorization = secure_data['authorization']
      options = build_options(data, secure_data)
      
      response = gateway.retrieve(authorization, options)
      return build_expanded_response(data, secure_data, :response=>response)
    end
    
    def update(gateway, data, secure_data)
      authorization = secure_data['authorization']
      credit_card = build_credit_card(data)
      options = build_options(data, secure_data)
      
      response = gateway.update(authorization, credit_card, options)
      return build_expanded_response(data, secure_data, :response=>response, :credit_card=>credit_card)
    end
    
    def unstore(gateway, data, secure_data)
      authorization = secure_data['authorization']
      options = build_options(data, secure_data)
      
      response = gateway.unstore(authorization, options)
      return build_expanded_response(data, secure_data, :response=>response)
    end
end

bridge = PaymentBridge.new()
bridge.configure_from_environ()
bridge.run()


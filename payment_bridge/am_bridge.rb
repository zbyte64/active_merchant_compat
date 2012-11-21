require "rubygems"
require "active_merchant"
require 'active_merchant_compat/billing'
require "json"
require "stringio"

class PaymentBridge
    #include ActiveMerchant::Billing::Gateway::RequiresParameters
    
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
      for gateway_config in config
        klass = get_gateway_class(gateway_config['module'])
        if klass == nil
          @gateways[gateway_config['name']] = klass
        else
          #convert string params into symbol params
          params = gateway_config['params']
          params = params.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
          @gateways[gateway_config['name']] = klass.new(params)
        end
      end
    end
    
    def get_gateway_class(name)
      begin
        return ActiveMerchant::Billing::Base.gateway(name)
      rescue NameError => error
        return nil
      end
    end
    
    def run()
      setup_data_channel()
      while payload = receive_data
        data = payload['data']
        secure_data = payload['secure_data'] || {}
        action = payload['action']
        gateway = @gateways[payload['gateway']]
        
        if gateway == nil
          callback_params = {
              'message' => "Unrecognized gateway",
              'success' => false
          }
        elsif action == nil
          callback_params = {
              'message' => "No action",
              'success' => false,
              'supported_actions' => get_supported_actions(gateway)
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
        else
          expanded_response = process_direct_post(gateway, action, data, secure_data)
          callback_params = construct_callback_params(expanded_response)
        end
        callback_params['gateway'] = payload['gateway']
        callback_params['action'] = action
        callback_params['request_id'] = payload['request_id']
        
        send_data(callback_params)
      end
    end
    
    def setup_data_channel()
      sio = StringIO.new
      @data_out, $stdout = $stdout, sio
    end
    
    def receive_data()
      input = STDIN.gets()
      if input == nil
        return nil
      end
      return JSON.parse(input)
    end
    
    def send_data(data)
      @data_out.puts(JSON.dump(data))
      @data_out.flush
    end
    
    def construct_callback_params(expanded_response)
        response_params = expanded_response.fetch('passthrough', {})
        
        response = expanded_response['response']
        if response != nil
          response_params = response_params.merge({
            'success' => response.success?(),
            'test' => response.test?(),
            'fraud_review' => response.fraud_review?(),
            'message' => response.message,
            'authorization' => response.authorization #this may also be your card store id
            #'avs' => response.avs_result,
            #'cvv' => response.cvv_result,
          })
        else
          response_params['success'] = false
        end
        
        if expanded_response['message'] != nil
          response_params['message'] = expanded_response['message']
        elsif expanded_response['exception'] != nil
          response_params['message'] = expanded_response['exception']
        end
        
        if expanded_response['bill_address'] != nil
          add_address_with_prefix(response_params, expanded_response['bill_address'], 'bill')
        end
        
        if expanded_response['ship_address'] != nil
          add_address_with_prefix(response_params, expanded_response['ship_address'], 'ship')
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
    
    def add_address_with_prefix(response, address, prefix)
      address.each do |key, value|
        response[prefix+"_"+key] = value
      end
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
        if not get_supported_actions(gateway).index(action)
          return invalid_action(gateway, action, data, secure_data)
        end
        
        begin
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
        rescue ArgumentError => error
          return build_expanded_response(data, secure_data, :exception=>error)
        end
    end
    
    def build_expanded_response(data, secure_data, params={})
      passthrough_fields = secure_data.fetch('passthrough', [])
      passthrough = {}
      for key in passthrough_fields
        if not key.startswith('cc_') and data.has_key?(key)
          passthrough[key] = post_data[key]
        end
      end
      
      bill_address = nil
      ship_address = nil
      
      if params[:options] and params[:options][:address]
        bill_address = params[:options][:address]
      end
      
      if params[:options] and params[:options][:ship_address]
        ship_address = params[:options][:ship_address]
      end
      
      return {'response' => params[:response],
              'credit_card' => params[:credit_card],
              'amount' => params[:amount],
              'currency_code' => params[:currency_code],
              'exception' => params[:exception],
              'passthrough' => passthrough,
              'message' => params[:message],
              'bill_address' => bill_address,
              'ship_address' => ship_address}
    end
    
    def build_options(data, secure_data)
      options = secure_data.fetch('options', {})
      #currency_code = secure_data['currency_code']
      
      address = parse_address_from_post(data)
      if address
        options[:address] = address
      end
      
      ship_address = parse_address_from_post(data, prefix='ship')
      if ship_address
        options[:ship_address] = ship_address
      end
      return options
    end
    
    def build_credit_card(data)
      requires!(data, 'cc_number', 'cc_exp_month', 'cc_exp_year', 'bill_first_name', 'bill_last_name', 'cc_ccv')
      return ActiveMerchant::Billing::CreditCard.new(
        :number => data['cc_number'].gsub(/\s+/, ""), #remove all white spaces
        :month => data['cc_exp_month'],
        :year => data['cc_exp_year'],
        :first_name => data['bill_first_name'],
        :last_name => data['bill_last_name'],
        :verification_value => data['cc_ccv']
      )
    end
    
    def get_supported_actions(gateway)
      actions_seen = []
      for action in ["authorize", "capture", "purchase", "void", "refund", "store", "retrieve", "update", "unstore"]
        if gateway.respond_to?(action)
          actions_seen.push(action)
        end
      end
      return actions_seen
    end
    
    def invalid_action(gateway, action, data, secure_data)
      response = build_expanded_response(data, secure_data)
      response['message'] = "Unrecognized Action"
      return response
    end
    
    def authorize(gateway, data, secure_data)
      requires!(secure_data, 'amount')
      amount = Integer(secure_data['amount'])
      credit_card = build_credit_card(data)
      options = build_options(data, secure_data)
      
      begin
        response = gateway.authorize(amount, credit_card, options)
      rescue ActiveMerchant::Billing::Error => error
        return build_expanded_response(data, secure_data, :options=>options, :credit_card=>credit_card, :amount=>amount, :exception=>error)
      end
      return build_expanded_response(data, secure_data, :response=>response, :options=>options, :credit_card=>credit_card, :amount=>amount)
    end
    
    def capture(gateway, data, secure_data)
      requires!(secure_data, 'amount', 'authorization')
      amount = Integer(secure_data['amount'])
      authorization = secure_data['authorization']
      options = build_options(data, secure_data)
      
      begin
        response = gateway.capture(amount, authorization, options)
      rescue ActiveMerchant::Billing::Error => error
        return build_expanded_response(data, secure_data, :options=>options, :amount=>amount, :exception=>error)
      end
      return build_expanded_response(data, secure_data, :response=>response, :options=>options, :amount=>amount)
    end
    
    def purchase(gateway, data, secure_data)
      requires!(secure_data, 'amount')
      amount = Integer(secure_data['amount'])
      credit_card = build_credit_card(data)
      options = build_options(data, secure_data)
      
      begin
        response = gateway.purchase(amount, credit_card, options)
      rescue ActiveMerchant::Billing::Error => error
        return build_expanded_response(data, secure_data, :options=>options, :credit_card=>credit_card, :amount=>amount, :exception=>error)
      end
      return build_expanded_response(data, secure_data, :response=>response, :options=>options, :credit_card=>credit_card, :amount=>amount)
    end
    
    def void(gateway, data, secure_data)
      requires!(secure_data, 'authorization')
      authorization = secure_data['authorization']
      options = build_options(data, secure_data)
      
      begin
        response = gateway.void(authorization, options)
      rescue ActiveMerchant::Billing::Error => error
        return build_expanded_response(data, secure_data, :options=>options, :exception=>error)
      end
      return build_expanded_response(data, secure_data, :response=>response, :options=>options)
    end
    
    def refund(gateway, data, secure_data)
      requires!(secure_data, 'amount', 'authorization')
      amount = Integer(secure_data['amount'])
      authorization = secure_data['authorization']
      options = build_options(data, secure_data)
      
      begin
        response = gateway.refund(amount, authorization, options)
      rescue ActiveMerchant::Billing::Error => error
        return build_expanded_response(data, secure_data, :options=>options, :amount=>amount, :exception=>error)
      end
      return build_expanded_response(data, secure_data, :response=>response, :options=>options, :amount=>amount)
    end
    
    def store(gateway, data, secure_data)
      credit_card = build_credit_card(data)
      options = build_options(data, secure_data)
      
      begin
        response = gateway.store(credit_card, options)
      rescue ActiveMerchant::Billing::Error => error
        return build_expanded_response(data, secure_data, :options=>options, :credit_card=>credit_card, :exception=>error)
      end
      return build_expanded_response(data, secure_data, :response=>response, :options=>options, :credit_card=>credit_card)
    end
    
    def retrieve(gateway, data, secure_data)
      requires!(secure_data, 'authorization')
      authorization = secure_data['authorization']
      options = build_options(data, secure_data)
      
      begin
        response = gateway.retrieve(authorization, options)
      rescue ActiveMerchant::Billing::Error => error
        return build_expanded_response(data, secure_data, :options=>options, :exception=>error)
      end
      return build_expanded_response(data, secure_data, :response=>response, :options=>options)
    end
    
    def update(gateway, data, secure_data)
      requires!(secure_data, 'authorization')
      authorization = secure_data['authorization']
      credit_card = build_credit_card(data)
      options = build_options(data, secure_data)
      
      begin
        response = gateway.update(authorization, credit_card, options)
      rescue ActiveMerchant::Billing::Error => error
        return build_expanded_response(data, secure_data, :options=>options, :credit_card=>credit_card, :exception=>error)
      end
      return build_expanded_response(data, secure_data, :response=>response, :options=>options, :credit_card=>credit_card)
    end
    
    def unstore(gateway, data, secure_data)
      requires!(secure_data, 'authorization')
      authorization = secure_data['authorization']
      options = build_options(data, secure_data)
      
      begin
        response = gateway.unstore(authorization, options)
      rescue ActiveMerchant::Billing::Error => error
        return build_expanded_response(data, secure_data, :options=>options, :exception=>error)
      end
      return build_expanded_response(data, secure_data, :response=>response, :options=>options)
    end
    
    def requires!(hash, *params)
      params.each do |param|
        if param.is_a?(Array)
          raise ArgumentError.new("Missing required parameter: #{param.first}") unless hash.has_key?(param.first)
 
          valid_options = param[1..-1]
          raise ArgumentError.new("Parameter: #{param.first} must be one of #{valid_options.to_sentence(:connector => 'or')}") unless valid_options.include?(hash[param.first])
        else
          raise ArgumentError.new("Missing required parameter: #{param}") unless hash.has_key?(param)
        end
      end
    end
end

bridge = PaymentBridge.new()
bridge.configure_from_environ()
bridge.run()


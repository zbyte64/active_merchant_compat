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
        #TODO
        if name == "bogus"
            return ActiveMerchant::Billing::BogusGateway
        elsif name == "paypal"
            return ActiveMerchant::Billing::PaypalGateway
        end
        return nil
    end
    
    def run()
        # read command from standard input:
        #TODO guard against other code printing to STDOUT
        while cmd = STDIN.gets
          #TODO we want to ensure we read one line at a time
          payload = JSON.parse(cmd)
          
          post_data = payload['post_data']
          secure_data = payload['secure_data'] || {}
          action = payload['action']
          gateway = @gateways[payload['gateway']]
          
          if gateway == nil
            callback_params = {
                'message' => "Unrecognized gateway",
                'success' => false
            }
          elsif post_data == nil
            callback_params = {
                'message' => "No Post Data",
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
            expanded_response = process_direct_post(gateway, action, post_data, secure_data)
            callback_params = construct_callback_params(expanded_response)
          end
          callback_params['action'] = action
          callback_params['request_id'] = payload['request_id']
          
          puts JSON.dump(callback_params)
          STDOUT.flush
        end
    end
    
    def construct_callback_params(expanded_response)
        response = expanded_response['response']
        response_params = expanded_response.fetch('passthrough', {})
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
        if expanded_response.has_key?('credit_card')
            credit_card = expanded_response['credit_card']
            response_params['cc_display'] = credit_card.display_number
            response_params['cc_exp_month'] = credit_card.month
            response_params['cc_exp_year'] = credit_card.year
            response_params['cc_type'] = credit_card.brand
        end
        
        if expanded_response.has_key?('amount')
            response_params['amount'] = expanded_response['amount']
        end
        
        if expanded_response.has_key?('currency_code')
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
    
    def process_direct_post(gateway, action, post_data, secure_data)
        #should return dict containing: response, credit_card, passthrough, amount, currency_code
        amount = secure_data['amount']
        currency_code = secure_data['currency_code']
        #currency_code = secure_data['currency_code'] #TODO how does active merchant do this?
        credit_card = ActiveMerchant::Billing::CreditCard.new(
          :number => post_data['cc_number'],
          :month => post_data['cc_exp_month'],
          :year => post_data['cc_exp_year'],
          :first_name => post_data['bill_first_name'],
          :last_name => post_data['bill_last_name'],
          :verification_value => post_data['cc_ccv']
        )

        options = secure_data.fetch('options', {})
        
        address = parse_address_from_post(post_data)
        if address
            options['address'] = address
        end
        
        ship_address = parse_address_from_post(post_data, prefix='ship')
        if ship_address:
            options['ship_address'] = ship_address
        end
        
        #TODO support other actions
        if action == "authorize":
            response = gateway.authorize(amount, credit_card, options)
        elsif action == "store":
            response = gateway.store(credit_card, options)
        end
        
        passthrough_fields = secure_data.fetch('passthrough', [])
        passthrough = {}
        for key in passthrough_fields
            if not key.startswith('cc_') and post_data.has_key?(key)
                passthrough[key] = post_data[key]
            end
        end
        
        return {'response' => response,
                'credit_card' => credit_card,
                'amount' => amount,
                'currency_code' => currency_code,
                'passthrough' => passthrough}
    end
end

bridge = PaymentBridge.new()
bridge.configure_from_environ()
bridge.run()


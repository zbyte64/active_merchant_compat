import base64
import json
import unittest
import yaml
import os

from payment_bridge.wsgi import BaseDirectPostApplication

global_config = {}
inpath = os.path.join(os.getcwd(), 'gateways.yaml')
if os.path.exists(inpath):
    infile = open(inpath)
    global_config = yaml.load(infile) or {}
else:
    print "Please create the following file with gateway credentials:", inpath

class BaseTestDirectPostApplication(BaseDirectPostApplication):
    def __init__(self, **kwargs):
        self.gateway = kwargs.pop('gateway')
        super(BaseTestDirectPostApplication, self).__init__(**kwargs)
    
    def load_gateways_config(self):
        return [self.gateway]
    
    def decrypt_data(self, encrypted_data):
        """
        Takes an encoded string and returns a dictionary
        """
        return json.loads(base64.b64decode(encrypted_data))
    
    def encrypt_data(self, params):
        """
        Takes a dictionary and returns a string
        """
        return base64.b64encode(json.dumps(params))

class PaymentData(object):
    cc_info = {
        'cc_number':'4111 1111 1111 1111',
        'cc_exp_year': '2015',
        'cc_exp_month': '11',
        'cc_ccv': '111',
        'bill_first_name':'John',
        'bill_last_name': 'Smith',
    }
    
    bill_address = {
        'bill_first_name':'John',
        'bill_last_name': 'Smith',
        'bill_address1':'5555 Main St',
        'bill_address2':'',
        'bill_city':'San Diego',
        'bill_state':'CA',
        'bill_country':'US',
        'bill_zip':'92101',
        'bill_email':'john@smith.com',
    }
    
    ship_address = {
        'ship_first_name':'John',
        'ship_last_name': 'Smith',
        'ship_address1':'5555 Main St',
        'ship_address2':'',
        'ship_city':'San Diego',
        'ship_state':'CA',
        'ship_country':'US',
        'ship_zip':'92101',
        'ship_email':'john@smith.com',
    }
    
    def get_cc_info(self):
        return dict(self.cc_info)
    
    def get_bill_address(self):
        return dict(self.bill_address)
    
    def get_bill_info(self):
        info = self.get_cc_info()
        info.update(self.bill_address)
        return info
    
    def get_ship_address(self):
        return dict(self.ship_address)
    
    def get_all_info(self):
        info = self.get_bill_info()
        info.update(self.ship_address)
        return info

class BaseGatewayTestCase(unittest.TestCase):
    gateway = {}
    
    def setUp(self):
        self.checkGatewayConfigured()
        gateway = dict(self.gateway)
        gateway['params'] = self.read_gateway_params()
        self.application = BaseTestDirectPostApplication(redirect_to='http://localhost:8080/direct-post/', gateway=gateway)
        self.data_source = PaymentData()
    
    def tearDown(self):
        self.application.shutdown()
    
    def read_gateway_params(self):
        return global_config.get(self.gateway['module'], None)
    
    def get_supported_actions(self):
        if not hasattr(self, '_supported_actions'):
            #calling a gateway with action = None is a request for the supported actions
            response = self.application.call_bridge(data=None, secure_data=None, gateway='test', action=None)
            if response['message'] == 'Unrecognized gateway':
                self.skipTest(response['message'])
            self._supported_actions = response['supported_actions']
        return self._supported_actions
    
    def checkGatewayConfigured(self):
        if self.read_gateway_params() == None:
            self.skipTest("Gateway unconfigured")
    
    def checkGatewaySupport(self, action):
        if not action in self.get_supported_actions():
            self.skipTest("Unsupported action: %s" % action)


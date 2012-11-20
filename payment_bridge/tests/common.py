import base64
import json

from payment_bridge.wsgi import BaseDirectPostApplication


class BaseTestDirectPostApplication(BaseDirectPostApplication):
    gateway = {} #subclasses implement this
    
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

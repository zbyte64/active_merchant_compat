import sys
sys.path.append('/home/jason/Repos/active_merchant_compat/lib')

import unittest

from payment_bridge.tests.common import BaseTestDirectPostApplication, PaymentData


class BogusTestDirectPostApplication(BaseTestDirectPostApplication):
    gateway = {
        'module':'bogus',
        'name':'test',
        'params': {}
    }

class TestBogusGateway(unittest.TestCase):

    def setUp(self):
        self.application = BogusTestDirectPostApplication(redirect_to='http://localhost:8080/direct-post/')
        self.data_source = PaymentData()
    
    def test_store_error(self):
        secure_data = {}
        bill_info = self.data_source.get_all_info() #will fail because we don't have a bogus approved cc
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='store')
        self.assertFalse(response['success'], response['message'])
    
    def test_store_success(self):
        secure_data = {}
        bill_info = self.data_source.get_all_info()
        bill_info['cc_number'] = '1'
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='store')
        self.assertTrue(response['success'], response['message'])
    
    def test_store_failure(self):
        secure_data = {}
        bill_info = self.data_source.get_all_info()
        bill_info['cc_number'] = '2'
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='store')
        self.assertFalse(response['success'], response['message'])
    
    def test_authorize_success(self):
        secure_data = {'amount':'100'}
        bill_info = self.data_source.get_all_info()
        bill_info['cc_number'] = '1'
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='authorize')
        self.assertTrue(response['success'], response['message'])
    
    def test_authorize_failure(self):
        secure_data = {'amount':'100'}
        bill_info = self.data_source.get_all_info()
        bill_info['cc_number'] = '2'
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='authorize')
        self.assertFalse(response['success'], response['message'])
    
    def test_authorize_error(self):
        secure_data = {} #no amount data
        bill_info = self.data_source.get_all_info()
        bill_info['cc_number'] = '1'
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='authorize')
        self.assertFalse(response['success'], response['message'])

if __name__ == '__main__':
    unittest.main()

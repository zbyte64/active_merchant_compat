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
    
    ## Store ##
    
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
    
    ## Authorize ##
    
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
        secure_data = {} #no data
        bill_info = self.data_source.get_all_info()
        bill_info['cc_number'] = '1'
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='authorize')
        self.assertFalse(response['success'], response['message'])
    
    def test_authorize_bad_amount_error(self):
        secure_data = {'amount':'$50'} #bad data
        bill_info = self.data_source.get_all_info()
        bill_info['cc_number'] = '1'
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='authorize')
        self.assertFalse(response['success'], response['message'])
    
    ## Capture ##
    
    def test_capture_success(self):
        secure_data = {'amount':'100',
                       'authorization':'ABCDEF',}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='capture')
        self.assertTrue(response['success'], response['message'])
    
    def test_capture_failure(self):
        return #TODO raise skiptest
        secure_data = {'amount':'100',
                       'authorization':'ABCDEF',}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='capture')
        self.assertFalse(response['success'], response['message'])
    
    def test_capture_error(self):
        secure_data = {} #no data
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='capture')
        self.assertFalse(response['success'], response['message'])
    
    ## Purchase ##
    
    def test_purchase_success(self):
        secure_data = {'amount':'100'}
        bill_info = self.data_source.get_all_info()
        bill_info['cc_number'] = '1'
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='purchase')
        self.assertTrue(response['success'], response['message'])
    
    def test_purchase_failure(self):
        secure_data = {'amount':'100'}
        bill_info = self.data_source.get_all_info()
        bill_info['cc_number'] = '2'
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='purchase')
        self.assertFalse(response['success'], response['message'])
    
    def test_purchase_error(self):
        secure_data = {} #no data
        bill_info = self.data_source.get_all_info()
        bill_info['cc_number'] = '1'
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='purchase')
        self.assertFalse(response['success'], response['message'])
    
    ## Void ##
    
    def test_void_success(self):
        secure_data = {'authorization':'ABCDEF',}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='void')
        self.assertTrue(response['success'], response['message'])
    
    def test_void_failure(self):
        return #TODO raise skiptest
        secure_data = {'authorization':'ABCDEF',}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='void')
        self.assertFalse(response['success'], response['message'])
    
    def test_void_error(self):
        secure_data = {} #no data
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='void')
        self.assertFalse(response['success'], response['message'])
    
    ## Refund ##
    
    def test_refund_success(self):
        secure_data = {'amount':'100',
                       'authorization':'ABCDEF',}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='refund')
        self.assertTrue(response['success'], response['message'])
    
    def test_refund_failure(self):
        return #TODO raise skiptest
        secure_data = {'amount':'100',
                       'authorization':'ABCDEF',}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='refund')
        self.assertFalse(response['success'], response['message'])
    
    def test_refund_error(self):
        secure_data = {} #no data
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='refund')
        self.assertFalse(response['success'], response['message'])

if __name__ == '__main__':
    unittest.main()


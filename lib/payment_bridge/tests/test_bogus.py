# -*- coding: utf-8 -*-
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
    
    def test_authorize_no_credit_card_error(self):
        secure_data = {'amount':'100'}
        bill_info = self.data_source.get_bill_address()
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='authorize')
        self.assertFalse(response['success'], response['message'])
    
    def test_authorize_success_with_unicode(self):
        secure_data = {'amount':'100'}
        bill_info = self.data_source.get_all_info()
        bill_info['cc_number'] = '1'
        bill_info['bill_first_name'] = '안녕하'
        bill_info['bill_last_name'] = '세요'
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='authorize')
        self.assertTrue(response['success'], response['message'])
    
    ## Capture ##
    
    def test_capture_success(self):
        secure_data = {'amount':'100',
                       'authorization':'3',}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='capture')
        self.assertTrue(response['success'], response['message'])
    
    def test_capture_failure(self):
        secure_data = {'amount':'100',
                       'authorization':'2',}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='capture')
        self.assertFalse(response['success'], response['message'])
    
    def test_capture_exception(self):
        secure_data = {'amount':'100',
                       'authorization':'1',}
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
        secure_data = {'authorization':'3',}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='void')
        self.assertTrue(response['success'], response['message'])
    
    def test_void_failure(self):
        secure_data = {'authorization':'2',}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='void')
        self.assertFalse(response['success'], response['message'])
    
    def test_void_exception(self):
        secure_data = {'authorization':'1',} #no data
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='void')
        self.assertFalse(response['success'], response['message'])
    
    ## Refund ##
    
    def test_refund_success(self):
        secure_data = {'amount':'100',
                       'authorization':'3',}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='refund')
        self.assertTrue(response['success'], response['message'])
    
    def test_refund_failure(self):
        secure_data = {'amount':'100',
                       'authorization':'2',}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='refund')
        self.assertFalse(response['success'], response['message'])
    
    def test_refund_exception(self):
        secure_data = {'amount':'100',
                       'authorization':'1',} #no data
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='refund')
        self.assertFalse(response['success'], response['message'])
    
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
    
    ## Retrieve ##
    
    def test_retrieve_error(self):
        secure_data = {} #no data
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='retrieve')
        self.assertFalse(response['success'], response['message'])
    
    def test_retrieve_success(self):
        return #TODO raise skiptest
        secure_data = {'authorization':'ABCDEF'}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='retrieve')
        self.assertTrue(response['success'], response['message'])
    
    def test_retrieve_failure(self):
        return #TODO raise skiptest
        secure_data = {'authorization':'ABCDEF'}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='retrieve')
        self.assertFalse(response['success'], response['message'])
    
    ## Update ##
    
    def test_update_error(self):
        secure_data = {} #no data
        bill_info = self.data_source.get_all_info() #will fail because we don't have a bogus approved cc
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='update')
        self.assertFalse(response['success'], response['message'])
    
    def test_update_success(self):
        return #TODO raise skiptest
        secure_data = {'authorization':'ABCDEF'}
        bill_info = self.data_source.get_all_info()
        bill_info['cc_number'] = '1'
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='update')
        self.assertTrue(response['success'], response['message'])
    
    def test_update_failure(self):
        secure_data = {'authorization':'ABCDEF'}
        bill_info = self.data_source.get_all_info()
        bill_info['cc_number'] = '2'
        response = self.application.call_bridge(data=bill_info, secure_data=secure_data, gateway='test', action='update')
        self.assertFalse(response['success'], response['message'])
    
    ## Unstore ##
    
    def test_unstore_error(self):
        secure_data = {} #no data
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='unstore')
        self.assertFalse(response['success'], response['message'])
    
    def test_unstore_success(self):
        secure_data = {'authorization':'1'}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='unstore')
        self.assertTrue(response['success'], response['message'])
    
    def test_unstore_failure(self):
        secure_data = {'authorization':'2'}
        response = self.application.call_bridge(data={}, secure_data=secure_data, gateway='test', action='unstore')
        self.assertFalse(response['success'], response['message'])

if __name__ == '__main__':
    unittest.main()


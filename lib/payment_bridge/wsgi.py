from subprocess import Popen, PIPE, STDOUT
from threading import Lock
from cgi import parse_qs
from urllib import urlencode
import json
import random


random.seed()


def flatten_dictionary(dictionary):
    new_dict = dict()
    for key, values in dictionary.items():
        new_dict[key] = values[0]
    return new_dict

class Bridge(object):
    def __init__(self, exec_path='ruby', script_path='am_bridge.rb', environ=None):
        self.lock = Lock()
        self.slave = Popen([exec_path, script_path], stdin=PIPE, stdout=PIPE, stderr=STDOUT, env=environ)
    
    def send(self, **kwargs):
        kwargs['request_id'] = random.getrandbits(32)
        in_payload = json.dumps(kwargs)
        self.lock.acquire()
        try:
            self.slave.stdin.write(in_payload+'\n')
            if self.slave.poll() is not None:
                print 'slave has terminated.'
                exit()
            out_payload = self.slave.stdout.readline()
        finally:
            self.lock.release()
        params = json.loads(out_payload)
        
        #ensure we don't have someone else's response
        assert params['request_id'] == kwargs['request_id']
        
        return params

class BaseDirectPostApplication(object):
    encrypted_field = 'payload'
    protected_fields = ['currency', 'amount', 'gateway', 'action', 'passthrough']
    
    def __init__(self, redirect_to):
        self.redirect_to = redirect_to
        self.bridge = self.construct_bridge()
    
    def construct_bridge(self):
        config = self.load_gateways_config()
        return Bridge(environ={'PAYMENT_CONFIGURATION':json.dumps(config)})
    
    def load_gateways_config(self):
        """
        Returns a list of gateways to set up
        Each entry is a dictionary containing:
        * name - string
        * module - string
        * params - dictionary
        """
        raise NotImplementedError
    
    def decrypt_data(self, encrypted_data):
        """
        Takes an encoded string and returns a dictionary
        """
        raise NotImplementedError
    
    def encrypt_data(self, params):
        """
        Takes a dictionary and returns a string
        """
        raise NotImplementedError
    
    def process_direct_post(self, post_data):
        post_data = flatten_dictionary(post_data)
        #encrypted data gives us our necessary sensitive variables: currency, amount, gateway, etc
        encrypted_data = post_data[self.encrypted_field]
        decrypted_data = self.decrypt_data(encrypted_data)
        gateway_key = decrypted_data['gateway']
        action = decrypted_data['action']
        
        response_params = self.bridge.send(post_data=post_data, secure_data=decrypted_data, gateway=gateway_key, action=action)
        return response_params
    
    def render_bad_request(self, environ, start_response, response_body):
        status = '405 METHOD NOT ALLOWED'
        
        response_headers = [('Content-Type', 'text/html'),
                      ('Content-Length', str(len(response_body)))]
        start_response(status, response_headers)
        
        return [response_body]
    
    def __call__(self, environ, start_response):
        if environ['REQUEST_METHOD'].upper() != 'POST':
            return self.render_bad_request(environ, start_response, "Request method must me a post")
        
        # the environment variable CONTENT_LENGTH may be empty or missing
        try:
            request_body_size = int(environ.get('CONTENT_LENGTH', 0))
        except (ValueError):
            request_body_size = 0
        
        # When the method is POST the query string will be sent
        # in the HTTP request body which is passed by the WSGI server
        # in the file like wsgi.input environment variable.
        request_body = environ['wsgi.input'].read(request_body_size)
        #dictionary of arrays:
        post_data = parse_qs(request_body)
        
        response_params = self.process_direct_post(post_data)
        params = {self.encrypted_field: self.encrypt_data(response_params)}
        
        response_body = '%s?%s' % (self.redirect_to, urlencode(params))
        
        status = '303 SEE OTHER'
        
        response_headers = [('Content-Type', 'text/html'),
                      ('Content-Length', str(len(response_body)))]
        start_response(status, response_headers)
        
        return [response_body]

class DjangoDirectPostApplication(BaseDirectPostApplication):
    """
    Uses django's signing mechanism to encrypt and decrypt payloads
    Requires Django 1.4 or later
    """
    salt_namespace = 'merchant_gateways.wsgi'
    settings_name = 'PAYMENT_GATEWAYS'
    
    def load_gateways(self):
        """
        Returns a list of gateways to set up
        """
        from django.conf import settings
        return getattr(settings, self.settings_name, [])
    
    def decrypt_data(self, encrypted_data):
        """
        Takes an encoded string and returns a dictionary
        """
        from django.core.signing import loads
        return loads(encrypted_data, salt=self.salt_namespace)
    
    def encrypt_data(self, params):
        """
        Takes a dictionary and returns a string
        """
        from django.core.signing import dumps
        return dumps(params, salt=self.salt_namespace)

class DirectPostMiddleware(object):
    def __init__(self, main_application, direct_post_application, url_endpoint):
        self.main_application = main_application
        self.direct_post_application = direct_post_application
        self.url_endpoint = url_endpoint
    
    def __call__(self, environ, start_response):
        if environ['PATH_INFO'] == self.url_endpoint:
            return self.direct_post_application(environ, start_response)
        return self.main_application(environ, start_response)

def sanity_test():
    env = {'PAYMENT_CONFIGURATION':json.dumps([
        {'module':'bogus',
         'name':'bogus',
         'params': {}}
    ])}
    bridge = Bridge(environ=env)
    bill_info = {'cc_number':'1', #for success use 1
                 'cc_exp_year': '2015',
                 'cc_exp_month': '11',
                 'cc_ccv': '111',
                 'bill_first_name':'John',
                 'bill_last_name': 'Smith',}
    print bridge.send(test=True, gateway='bogus', action='store', post_data=bill_info)
    
    bill_info = {'cc_number':'2', #for failure use 2
                 'cc_exp_year': '2015',
                 'cc_exp_month': '11',
                 'cc_ccv': '111',
                 'bill_first_name':'John',
                 'bill_last_name': 'Smith',}
    print bridge.send(test=True, gateway='bogus', action='store', post_data=bill_info)

if __name__ == '__main__':
    sanity_test()


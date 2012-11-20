from subprocess import Popen, PIPE, STDOUT
from threading import Lock
from cgi import parse_qs
from urllib import urlencode
import json
import random
import os


random.seed()

JSONP_RESPONSE = '%(callback)s(%(json_data)s);'

def flatten_dictionary(dictionary):
    new_dict = dict()
    for key, values in dictionary.items():
        new_dict[key] = values[0]
    return new_dict

SCRIPT_PATH = os.path.join(os.path.split(os.path.abspath(__file__))[0], 'am_bridge.rb')
RUBY_PATH = 'ruby1.9.1' #specific to ubuntu

class Bridge(object):
    def __init__(self, exec_path=RUBY_PATH, script_path=SCRIPT_PATH, environ=None):
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
        try:
            params = json.loads(out_payload)
        except ValueError as error:
            print error
            print out_payload
            raise
        
        #ensure we don't have someone else's response
        assert params['request_id'] == kwargs['request_id']
        
        return params
    
    def close(self):
        #self.slave.stdin.close()
        outdata, errdata = self.slave.communicate()
        print 'Shutdown bridge result:', outdata, errdata
        #self.slave.terminate()
        #self.slave.kill()

class BaseDirectPostApplication(object):
    encrypted_field = 'payload'
    
    def __init__(self, redirect_to):
        self.redirect_to = redirect_to
        self.bridge = self.construct_bridge()
    
    def construct_bridge(self):
        config = self.load_gateways_config()
        return Bridge(environ={'PAYMENT_CONFIGURATION':json.dumps(config)})
    
    def shutdown(self):
        self.bridge.close()
    
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
    
    def call_bridge(self, data, secure_data, gateway, action):
        return self.bridge.send(data=data, secure_data=secure_data, gateway=gateway, action=action)
    
    def process_direct_post(self, caller_data):
        encrypted_data = caller_data[self.encrypted_field]
        decrypted_data = self.decrypt_data(encrypted_data)
        gateway_key = decrypted_data['gateway']
        action = decrypted_data['action']
        redirect_to = decrypted_data.get('redirect', self.redirect_to)
        
        response_params = self.call_bridge(data=caller_data, secure_data=decrypted_data, gateway=gateway_key, action=action)
        return {'url_params':{self.encrypted_field: self.encrypt_data(response_params)},
                'redirect':redirect_to,}
    
    def render_bad_request(self, environ, start_response, response_body):
        status = '405 METHOD NOT ALLOWED'
        
        response_headers = [('Content-Type', 'text/html'),
                      ('Content-Length', str(len(response_body)))]
        start_response(status, response_headers)
        
        return [response_body]
    
    def __call__(self, environ, start_response):
        if environ['REQUEST_METHOD'].upper() == 'GET':
            
            #read our caller data from GET params
            request_body = environ.get('QUERY_STRING', '')
            caller_data = flatten_dictionary(parse_qs(request_body))
            
            callback = caller_data.get('callback')
            if not callback:
                return self.render_bad_request(environ, start_response, "Invalid JSONP request; Please provide 'callback'.")
            
            params = self.process_direct_post(caller_data)['url_params']
            
            response_body = JSONP_RESPONSE % {'callback':callback, 'json_data': json.dumps(params)}
            
            status = '200 OK'
            content_type = 'text/javascript'
        elif environ['REQUEST_METHOD'].upper() == 'POST':
            # the environment variable CONTENT_LENGTH may be empty or missing
            try:
                request_body_size = int(environ.get('CONTENT_LENGTH', 0))
            except (ValueError):
                request_body_size = 0
            
            # read our caller data from POST params
            request_body = environ['wsgi.input'].read(request_body_size)
            caller_data = flatten_dictionary(parse_qs(request_body))
            
            params = self.process_direct_post(caller_data)
            
            
            response_body = '%s?%s' % (params['redirect'], urlencode(params['url_params']))
            
            status = '303 SEE OTHER'
            content_type = 'text/html'
        else:
            return self.render_bad_request(environ, start_response, "Request method must be a POST or JSONP")
        
        response_headers = [('Content-Type', content_type),
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
    print bridge.send(test=True, gateway='bogus', action='store', data=bill_info)
    
    bill_info = {'cc_number':'2', #for failure use 2
                 'cc_exp_year': '2015',
                 'cc_exp_month': '11',
                 'cc_ccv': '111',
                 'bill_first_name':'John',
                 'bill_last_name': 'Smith',}
    print bridge.send(test=True, gateway='bogus', action='store', data=bill_info)

if __name__ == '__main__':
    sanity_test()


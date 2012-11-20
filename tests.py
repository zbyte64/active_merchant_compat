import unittest

from distutils import log

#TODO replace with nose

class TestSuite(unittest.TestSuite):
    """
    Test Suite configuring Django settings and using
    DjangoTestSuiteRunner as test runner.
    Also runs PEP8 and Coverage checks.
    """
    def __init__(self, *args, **kwargs):
        super(TestSuite, self).__init__(tests=self.build_tests(), \
                *args, **kwargs)

    def build_tests(self):
        """
        Build tests for inclusion in suite from resolved packages.
        """
        tests = []
        for module, klass in [('payment_bridge.tests.test_bogus', 'TestBogusGateway')]:
            try:
                _temp = __import__(module, globals(), locals(), [klass])
                tests.append(getattr(_temp, klass))
            except ImportError, e:
                log.error("Import Error on %s: %s" % (module, e))
        return tests


import importlib.util
from pathlib import Path
spec=importlib.util.spec_from_file_location('checker',Path(__file__).with_name('check-api-catalog.py'));c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
base=dict(id='test',name='Test',category='test',example='https://example.com/data',docs='https://example.com/docs',auth='none',cors='yes',method='GET',use='test')
def check(entry):return c.validate({'meta':{'count':1},'apis':[entry]})
assert not check(base)
assert check({**base,'example':'http://example.com'})
assert check({**base,'example':'https://localhost/a'})
assert check({**base,'example':'https://127.0.0.1/a'})
assert check({**base,'example':'https://user:secret@example.com'})
assert check({**base,'example':'https://example.com?api_key=secret'})
assert check({**base,'method':None})
print('Catalog schema and unsafe-URL fixtures passed.')

import json

with open('/home/hechth/dev/mzSpecLib/examples/SpectraST/fetal_brain_tiny.mzSpecLib.json') as f:
    j = json.load(f)
print('top keys:', list(j.keys()))
sp = j['spectra'][0]
print('spectrum keys:', list(sp.keys()))
print('analytes:', json.dumps(sp['analytes'], indent=1)[:800])
print('interpretations:', json.dumps(sp['interpretations'], indent=1)[:600])
print('attributes[:2]:', json.dumps(sp['attributes'][:2], indent=1))
print('mzs len:', len(sp['mzs']), 'peak_annotations[:3]:', sp['peak_annotations'][:3])
print('spectrum_attribute_sets:', j['spectrum_attribute_sets'])
print('interpretation_attribute_sets:', j['interpretation_attribute_sets'])
print('clusters:', j['clusters'])
print('format_version:', j['format_version'])

# also check the second json example
with open('/home/hechth/dev/mzSpecLib/examples/NIST/IARPA3_best_tissue_add_info.head.mzSpecLib.json') as f:
    j2 = json.load(f)
print()
print('IARPA3 top keys:', list(j2.keys()))
sp2 = j2['spectra'][0]
print('IARPA3 spectrum keys:', list(sp2.keys()))
print('IARPA3 spectrum_attribute_sets:', j2.get('spectrum_attribute_sets'))
print('IARPA3 clusters:', j2.get('clusters'))
print('IARPA3 aggregations?', 'aggregations' in str(j2.keys()))
spk = sp2.get('aggregations') or sp2.get('attributes')
print('IARPA3 aggregation sample:', json.dumps(sp2.get('aggregations'), indent=1)[:400] if sp2.get('aggregations') else None)

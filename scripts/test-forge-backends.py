#!/usr/bin/env python3
"""Regressions for the recording's missing backend and inert bundle transport.
Foundation tests use the production Swift implementations when swiftc exists.
"""
from pathlib import Path
import json
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
service = (root/'HTMLAppV3/AIGenerationService.swift').read_text()
view = (root/'HTMLAppV3/AIGenerationView.swift').read_text()
backend = (root/'HTMLAppV3/HTMLAppBackend.swift').read_text()
native = (root/'HTMLAppV3/NativeAPIBridge.swift').read_text()
assert 'ForgeBackendContract.instructions' in service.split('static func systemPrompt',1)[1].split('static func shortEditSummary',1)[0]
assert 'ForgeBackendContract.instructions' in service.split('static func patchSystemPrompt',1)[1]
qa = service.split('private func verifyAndRepair',1)[1]
assert qa.index('ensureRuntimeBackend') < qa.index('testMode == .skip')
assert 'backend_required' in service and 'runtimeBackendRequired = runtimeBackendRequired || planning.backendRequired' in service
assert view.index('ForgeBackendContract.issues') < view.index('HTMLAppRuntimeBackend.deploy')
assert 'HTMLAppBackendAPI.runtimeStatus(link)' in native
assert 'Repair backend with Forge' in backend and 'connectRuntime()' in backend
assert 'does not declare a supported backend' not in backend
print('PASS: mandatory backend gate, planner contract, save gate, v2 status and repair action')

compiler = shutil.which('swiftc')
if not compiler:
    print('NOT RUN: Foundation backend behavior tests require swiftc.')
    raise SystemExit(0)
source = (root/'HTMLAppV3/HTMLAppRuntimeBackend.swift').read_text().split('@MainActor',1)[0]
resolver = (root/'HTMLAppV3/ForgeCapabilityResolver.swift').read_text()
helper = resolver[resolver.index('    static func requiresBackend'):resolver.index('    static func infer')]
contract = (root/'HTMLAppV3/ForgeBackendContract.swift').read_text()
with tempfile.TemporaryDirectory(prefix='forge-backend-tests-') as directory:
    directory = Path(directory)
    example = root/'backend/runtime-v2/examples'
    bundle = {'source': (example/'server.py').read_text(), 'manifest': json.loads((example/'manifest.json').read_text())}
    tag = '<script id="htmlapp-backend-v2" data-test="yes" type="application/json">' + json.dumps(bundle) + '</script>'
    cases = [
        ('recording-local-fallback', 'make a simple app where I get an api I can use from anywhere to send a message to my phone and it will send a notification, require no key or auth', '<html>Local notification test</html>', False, True),
        ('legacy-managed', 'make an app', '<meta name="htmlapp-backend" content="managed">', False, True),
        ('offline', 'offline only calculator', '<html>calculator</html>', False, False),
        ('public-weather', 'show weather from a public weather API', '<html>weather</html>', False, False),
        ('semantic-required', 'coordinate our shopping', '<html>shopping</html>', True, True),
        ('valid-route', 'cloud encrypted text storage', tag + "<script>HTMLAppNative.backend.request({path:'/items',method:'GET'})</script>", False, False),
        ('missing-route', 'shared chat', tag + "<script>HTMLAppNative.backend.request({path:'/devices/register',method:'POST'})</script>", False, True),
        ('duplicate-bundle', 'backend', tag + tag, False, True),
        ('uppercase-tag', 'backend', tag.upper().replace(json.dumps(bundle).upper(), json.dumps(bundle)) + "<script>HTMLAppNative.backend.request({path:'/items'})</script>", False, False),
    ]
    (directory/'cases.json').write_text(json.dumps(cases))
    (directory/'main.swift').write_text('''import Foundation
struct HTMLAppBackendError: LocalizedError {
 let message: String; var status: Int? = nil
 var errorDescription: String? { message }
}
''' + source + '\nstruct ForgeCapabilityPlan {\n' + helper + '\n}\n' + contract + '''
let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[Any]]
for item in cases {
 let issues = ForgeBackendContract.issues(request: item[1] as! String, html: item[2] as! String, required: item[3] as! Bool)
 precondition(!issues.isEmpty == (item[4] as! Bool), "Failed \\(item[0]): \\(issues)")
}
print("PASS: \\(cases.count) production backend completeness and bundle cases")
''')
    binary=directory/'test'
    subprocess.run([compiler,str(directory/'main.swift'),'-o',str(binary)],check=True)
    subprocess.run([str(binary),str(directory/'cases.json')],check=True)

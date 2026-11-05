#!/usr/bin/env python3
"""Compile the production patch implementation without the iOS UI dependencies."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "HTMLAppV3/AIGenerationService.swift").read_text()
start = source.index("struct HTMLPatchApplication {")
end = source.index("\nenum HTMLQualityChecks {", start)
with tempfile.TemporaryDirectory(prefix="htmlapp-generation-") as directory:
    extracted = Path(directory) / "Patch.swift"
    icon_context = source.index("struct ForgeEditIconContext {")
    extracted.write_text("import Foundation\n" + source[start:end] + "\n" + source[icon_context:])
    binary = Path(directory) / "tests"
    subprocess.run(["swiftc", str(extracted),
                    str(root / "HTMLAppV3/ForgeGenerationResponseGuard.swift"),
                    str(root / "scripts/test-generation-reliability.swift"),
                    "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)

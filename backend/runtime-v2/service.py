"""Local manager entrypoint. Socket permissions are the privilege boundary."""
import os
import threading
from pathlib import Path
from api import API
from manager import Manager


def create_app():
    from push import APNs
    manager = Manager(push=APNs.from_environment())
    manager.recover()
    threading.Thread(target=manager.monitor, daemon=True).start()
    threading.Thread(target=manager.deliver_notifications, daemon=True).start()
    return API(manager, Path("FORGE-CONTRACT.md").read_text())

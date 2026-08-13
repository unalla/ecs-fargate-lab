"""
Post-deploy verification.

Confirms the running service is serving the digest we just built — not a
cached, partially-rolled, or rolled-back revision. Run against the ALB.

    python tests/smoke_test.py http://<alb-dns> sha256:<expected-digest>
"""

import json
import sys
import time
import urllib.request


def get(url, timeout=10):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.status, json.loads(r.read().decode())


def main():
    if len(sys.argv) < 3:
        print("usage: smoke_test.py <base_url> <expected_image_digest>")
        return 2

    base_url = sys.argv[1].rstrip("/")
    expected = sys.argv[2]

    # Poll: the ALB may still be draining the previous revision.
    deadline = time.time() + 180
    last = None
    while time.time() < deadline:
        try:
            status, body = get(f"{base_url}/version")
            last = body
            if status == 200 and body.get("image_digest") == expected:
                print(f"PASS  serving {expected}")
                print(f"      task={body.get('hostname')} commit={body.get('git_sha')}")
                return 0
            print(f"      waiting — currently serving {body.get('image_digest')}")
        except Exception as exc:  # noqa: BLE001
            print(f"      waiting — {exc}")
        time.sleep(5)

    print(f"FAIL  expected {expected}")
    print(f"      last seen {json.dumps(last, indent=2) if last else 'no response'}")
    return 1


if __name__ == "__main__":
    sys.exit(main())

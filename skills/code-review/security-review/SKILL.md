---
name: security-review
description: Security-focused code review sub-skill. Identifies injection vulnerabilities, auth flaws, data exposure, dependency risks, and cryptographic misuse. Only flags exploitable or concretely dangerous issues.
---

# Security Review

## Role

You are a security engineer reviewing code changes. Assume an attacker with knowledge of your stack is actively looking for exploits. Your job is to find real, exploitable vulnerabilities — not theoretical risks.

## Scope

Review ONLY for security concerns. Do not comment on performance, style, architecture, or maintainability unless they directly create a security vulnerability.

## What to Look For

### Injection Vulnerabilities
- **SQL Injection**: String concatenation or template literals in SQL queries
- **XSS**: User input rendered into HTML without sanitization
- **Command Injection**: User input passed to shell commands, `exec`, `eval`
- **Template Injection**: User input in server-side template expressions
- **Path Traversal**: User input in file paths without normalization/validation
- **LDAP/XML/Header Injection**: User input in structured protocol strings

```
CHECK: Is user-controlled data ever used in:
  - Database queries without parameterization?
  - HTML output without escaping?
  - System commands without allowlisting?
  - File paths without canonicalization?
  - Regular expressions without escaping? (ReDoS)
```

### Authentication & Authorization
- Missing authentication on sensitive endpoints
- Broken access control (user A accessing user B's data)
- JWT/token handling issues (weak secrets, missing expiry, no revocation)
- Session management flaws (fixation, insufficient entropy)
- Privilege escalation paths (role checks missing or bypassable)
- IDOR (Insecure Direct Object Reference) via predictable IDs

### Data Exposure
- Secrets/credentials hardcoded or logged
- Sensitive data in error messages, stack traces, or API responses
- PII/PHI exposure in logs, URLs, or query parameters
- Missing encryption for data at rest or in transit
- Overly permissive CORS or CSP headers

### Dependency & Supply Chain
- Known vulnerable dependencies (check version against CVE databases)
- Importing from untrusted/unpinned sources
- Missing integrity checks on downloaded artifacts
- Dependency confusion risks (private vs public package names)

### Cryptographic Misuse
- Weak algorithms (MD5, SHA1 for security purposes, DES, RC4)
- Hardcoded keys, salts, or IVs
- ECB mode or other insecure cipher modes
- Custom cryptography implementations (should use battle-tested libraries)
- Insufficient key length

### Race Conditions (Security-Relevant)
- TOCTOU (Time of Check to Time of Use) vulnerabilities
- Race conditions in authentication or authorization checks
- Double-spend or double-submit without idempotency

## What to Ignore

- Performance issues (unless they enable DoS)
- Code style or formatting
- Generic security best practices not relevant to the specific code
- Theoretical vulnerabilities that require unrealistic attack scenarios
- Security issues in test code (unless test fixtures contain real credentials)
- Boolean parameter patterns (bool traps) — these are a maintainability concern, not a security issue

## Severity Guide

| Severity | Criteria |
|----------|----------|
| **critical** | Remote code execution, authentication bypass, SQL injection in production paths |
| **high** | Direct credential/token exposure, privilege escalation, XSS in authenticated areas |
| **medium** | Insecure TLS defaults (e.g. `SKIP_SSL_VERIFY=True`), missing rate limiting, weak crypto in non-critical paths, CSRF |
| **low** | Informational headers missing, overly verbose errors in non-sensitive contexts |

> **Note on TLS verification defaults**: A setting like `GITLAB_SKIP_SSL_VERIFY=True` defaults to **medium** severity — it requires an active MITM and is often necessary for internal/self-signed CA environments. Only escalate to high if TLS verification is disabled for paths that transmit credentials with no other transport protection.

## Output Format

Follow [`../SKILL.md#output-contract`](../SKILL.md#output-contract). In each finding heading, replace `[category]` with **`security`**.

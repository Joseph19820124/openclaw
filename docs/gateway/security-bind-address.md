# Gateway Bind Address Security

This document explains why binding the Gateway to a specific IP address instead of `0.0.0.0` is important for security.

## The Problem with 0.0.0.0

Binding to `0.0.0.0` means the service listens on **all network interfaces**, including public-facing ones. This creates several security risks:

### 1. "0.0.0.0 Day" Browser Vulnerability (CVE-2024)

An 18-year-old browser vulnerability discovered by Oligo Security allows malicious websites to bypass browser security and access services bound to `0.0.0.0`:

- Browsers block access to `127.0.0.1`, `localhost`, and private IPs
- But they **do not block** access to `0.0.0.0`
- Malicious websites can exploit this to reach local services
- Affects Chrome, Firefox, and Safari on macOS and Linux

**Impact**: Remote code execution on local services from a malicious webpage.

### 2. Clawdbot/Moltbot Security Incidents (January 2026)

Security researchers found hundreds of exposed instances due to default `0.0.0.0` bindings:

| CVE | Severity | Description |
|-----|----------|-------------|
| CVE-2025-6514 | 9.6 Critical | Command injection |
| CVE-2025-52882 | 8.8 High | Arbitrary file access and code execution |

**Consequences**:
- API keys leaked
- Full conversation histories exposed
- Configuration data accessible to attackers

## The Solution: Bind to Specific IP

Instead of binding to `0.0.0.0`, bind to a specific private IP address:

```yaml
# openclaw.json
{
  "gateway": {
    "bind": "custom",
    "customBindHost": "172.31.31.188"
  }
}
```

### Security Architecture with SSH Tunnel

```
Public Internet                    AWS VPC

    Attacker                       ┌─────────────────────┐
        │                          │                     │
        ├──X── :18789 ────────────►│ (port not exposed)  │
        │      (blocked)           │                     │
        │                          │  Gateway listens    │
        └──X── Private IP ────────►│  172.31.31.188:18789│
               (not routable)      │  (private only)     │
                                   └─────────────────────┘
                                            ▲
    Your Mac                                │
        │                                   │
        └───── SSH Tunnel ──────────────────┘
               (encrypted, key-auth)
               via Public IP:443
```

### Comparison

| Aspect | 0.0.0.0 | Private IP + SSH |
|--------|---------|------------------|
| Public access | Yes (dangerous) | No |
| Authentication layers | Token only | SSH key + Token |
| Encrypted transport | Optional | Forced (SSH) |
| Attack surface | Large | Minimal (SSH port only) |
| Browser 0.0.0.0 Day | Vulnerable | Not affected |

## Configuration Steps

1. **Set bind mode to custom**:
   ```bash
   openclaw config set gateway.bind custom
   ```

2. **Set the specific IP**:
   ```bash
   openclaw config set gateway.customBindHost 172.31.31.188
   ```

3. **Restart the Gateway**:
   ```bash
   sudo systemctl restart openclaw-gateway
   ```

4. **Establish SSH tunnel from client**:
   ```bash
   ssh -L 18789:172.31.31.188:18789 your-server
   ```

5. **Connect via localhost**:
   ```bash
   openclaw config set gateway.remote.url ws://localhost:18789
   ```

## References

- [0.0.0.0 Day: Exploiting Localhost APIs From the Browser (Oligo Security)](https://www.oligo.security/blog/0-0-0-0-day-exploiting-localhost-apis-from-the-browser)
- [Clawdbot becomes Moltbot, but can't shed security concerns (The Register)](https://www.theregister.com/2026/01/27/clawdbot_moltbot_security_concerns/)
- [Moltbot Security Alert (Bitdefender)](https://www.bitdefender.com/en-us/blog/hotforsecurity/moltbot-security-alert-exposed-clawdbot-control-panels-risk-credential-leaks-and-account-takeovers)

## Summary

**Never expose the Gateway unauthenticated on 0.0.0.0.**

Prefer:
1. Tailscale Serve (recommended)
2. Private IP binding with SSH tunnel
3. If LAN bind is necessary, use strict IP allowlisting

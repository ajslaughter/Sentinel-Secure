# SentinelField Security Auditor

## Executive Summary

SentinelField is a high-performance, native Windows security auditing and system hardening utility engineered for mission-critical field operations. It serves as a standalone, single-file executable designed to provide immediate security posture assessments and remediation in air-gapped environments where zero cloud dependency is a strict requirement. The application ensures compliance with rigorous security baselines while maintaining a minimal operational footprint.

## Core Capabilities

### Security Hardening Engine
The core of SentinelField is an automated auditing engine designed to detect and remediate critical system vulnerabilities. It performs real-time verification of:
- **Protocol Security**: Identification and disabling of deprecated protocols, specifically SMBv1 and RDP indiscriminately exposed services.
- **Account Management**: Verification of Guest account status and automated logic to ensure disablement.
- **LSA Protection**: Enforcement of Local Security Authority (LSA) protection to mitigate credential dumping attacks.
- **Authentication Policies**: Audit of AutoLogon configurations to prevent unauthorized physical access.

### Network Sentry
SentinelField bypasses high-level abstractions to perform low-level network analysis. Utilizing native system calls (`GetExtendedTcpTable`), the Network Sentry module maps active TCP/UDP connections directly to their associated Process IDs (PIDs) and executable names. This capability allows analysts to immediately identify unauthorized listeners or outbound beacons without reliance on external firewalls.

### Field Compliance Module
Tailored for physical security requirements, this module audits local data-protection flags essential for field assets:
- **Data Exfiltration Control**: Verification of USB Write Protection policies to prevent unauthorized data transfer.
- **Session Security**: Auditing of Screen Lock Timeout thresholds to ensure unattended workstations are secured within compliant timeframes.

### Hardware Inventory
The application provides rapid, non-invasive retrieval of critical hardware identity and security states, including:
- **Asset Identity**: BIOS Serial Number extraction.
- **Platform Integrity**: Trusted Platform Module (TPM) 2.0 status verification.
- **Data-at-Rest Encryption**: BitLocker drive encryption status reporting.

### System Diagnostics
To support operational continuity in multi-monitor field setups, SentinelField includes a specialized utility for the **Windows Graphics Driver Configuration**. This feature clears corrupted configuration caches in the system registry to resolve display resolution anomalies without requiring full system re-imaging.

## Security Architecture

### Native Execution
SentinelField is compiled as a native .NET 8 binary. It requires **no external runtime dependencies**, libraries, or internet connectivity. This "Zero-Dependency" architecture guarantees execution reliability in strictly air-gapped environments.

### Privilege Management
To enable deep-system auditing and registry modification, SentinelField strictly enforces **Administrator-level access** via application manifest policies. Execution is blocked unless elevated privileges are confirmed, ensuring integrity of the audit results.

## Technical Specifications

- **Runtime Environment**: .NET 8.0 (Windows)
- **UI Framework**: Windows Presentation Foundation (WPF)
- **Deployment Format**: Self-contained, single-file `win-x64` binary
- **Cloud Dependency**: 0% (Fully offline capable)

## Build Instructions

To compile SentinelField from source, the **.NET 8 SDK** is required.

Execute the following commands in the solution root:

```powershell
# Restore project dependencies
dotnet restore

# Publish self-contained single-file executable
dotnet publish -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true
```

**Artifact Output**:
`bin\Release\net8.0-windows\win-x64\publish\SentinelField.exe`

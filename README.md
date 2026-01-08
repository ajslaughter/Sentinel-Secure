# SentinelField Security Auditor

**SentinelField** is a portable, single-file security auditing tool designed for Systems Analysts operating in air-gapped or low-connectivity environments (Data Centers, Construction Sites, Field Commissioning). 

It replaces completely the legacy "WinSysAuto" script collection with a high-performance, native .NET 8 executable that requires **zero cloud dependencies**.

## 🚀 Mission: The "Anti-Slop" Standard

Modern tools like Procore or CxAlloy are bloated and cloud-dependent. When you are standing in a server room with no cellular signal, you need a tool that works **instantly**. 

**SentinelField** provides:
- **Instant Auditing**: Launch and scan in < 2 seconds.
- **Single-File Zero-Install**: No MSI, no "npm install", no DLL hell. Just one `.exe`.
- **Admin-Aware**: Automatically enforces elevated privileges for deep system access.

## 🛡️ Key Capabilities

### 1. Dashboard Hub
- **Radial Hardening Score**: Immediate 0-100% security posture visualization.
- **Hardware ID**: Instant access to BIOS Serial, TPM Status, and BitLocker state for asset tagging.

### 2. Hardening Shield (One-Click Lockdown)
Automated checks and remediation for:
- **RDP & SMBv1**: Detect and kill legacy protocols.
- **Credential Guard**: Verify LSA Protection.
- **AutoLogon**: Detect dangerous convenience configurations.
- **PowerShell Policy**: Audit execution policies.

### 3. Network Sentry
- **Low-Level Port Audit**: Direct `iphlpapi.dll` calls to map listening ports to PIDs.
- **Connection Filter**: See exactly what process is talking to the outside world.

### 4. Resolution Emergency Tool
- **Display Driver Reset**: Clears the Windows Graphics Driver configuration cache in the Registry.
- **Use Case**: Fixing bugged dual-monitor setups on field workstations without a reinstall.

## 🔒 Security Specifications

- **Platform**: Windows 10/11 (x64)
- **Tech Stack**: C# .NET 8, WPF (ModernWpfUI), System.Management.Automation
- **Dependencies**: None (Self-Contained)
- **Privileges**: Administrator Required (Manifest-enforced)

## 📦 Build Instructions

Requirements: .NET 8 SDK

```powershell
# Restore Dependencies
dotnet restore

# Build Single-File Executable
dotnet publish -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true
```

*Output Location*: `bin\Release\net8.0-windows\win-x64\publish\SentinelField.exe`

---
*Built for the Field. Forged in C#.*

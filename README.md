# Aanerud EMC – Emergency Data Dumper (AEDD)

A macOS application for securely mounting SMB shares read-only and copying data to local storage with robust job queue management.

![AEDD Release](AEDD_Release.app)

## The Story: Building an Emergency Data Dumper

When your storage array goes into emergency mode and you need to extract terabytes of data without triggering any writes, you don't reach for Docker. You reach for the closest thing to the metal - a native macOS app. This is the story of building AEDD (Aanerud Emergency Data Dumper), and why sometimes the "hard way" is the only way that works.

### The Problem: When Your Storage Array Is Having a Bad Day

Picture this: Your storage array is in emergency mode. One wrong write operation - even something as innocent as a `.DS_Store` file - could kill the entire array and lose everything. You need to mount SMB shares, enumerate files, and copy data with military precision. No room for error, no time for debugging container networking, and definitely no patience for permission issues.

This is where the rubber meets the road between "convenient development" and "production reality."

## Overview

AEDD is designed for artists and creative professionals who need to quickly and safely copy large amounts of data from network storage to local drives. The app emphasizes safety through read-only mounts and provides a comprehensive job queue system for managing multiple copy operations.

## Key Features

### SMB Integration
- Connect to multiple SMB servers (configured for .20 and .23 hosts)
- Enumerate and mount shares as read-only volumes
- Automatic conflict resolution for existing mounts
- Secure credential storage in macOS Keychain

### Robust Copy Operations
- Uses rsync for reliable, resumable transfers
- Preserves macOS metadata (extended attributes, creation times, Finder flags)
- Serial job processing to prevent system overload
- Progress tracking and cancellation support

### User Interface
- Intuitive drag-and-drop interface
- Real-time progress monitoring
- Job queue with reordering capabilities
- Comprehensive settings and preferences

### System Integration
- Proper macOS sandboxing with required entitlements
- Native file system integration
- Comprehensive logging to ~/Library/Logs/Aanerud-EMC-Emergency-Dumper/

## Architecture

### Core Components

- **Models**: Data structures for jobs, shares, and settings
  - `CopyJob`: Represents copy operations with state tracking
  - `SMBShare`: SMB share information and mounting details
  - `AppSettings`: User preferences and configuration

- **Services**: Business logic and system integration
  - `SMBManager`: Handle SMB enumeration and mounting
  - `JobManager`: Queue management and job execution
  - `RsyncOperation`: rsync process wrapper with progress tracking
  - `KeychainService`: Secure credential storage
  - `LogManager`: Centralized logging system
  - `SettingsManager`: User preferences management

- **Views**: SwiftUI interface components
  - `ContentView`: Main application interface
  - `ConnectionView`: SMB server connection dialog
  - `ShareSelectorView`: Share selection interface
  - `JobQueueView`: Job management and monitoring
  - `SettingsView`: Application preferences

### Technology Stack

- **Language**: Swift 5+
- **UI Framework**: SwiftUI
- **Deployment Target**: macOS 12+
- **Process Management**: Foundation Process API
- **Keychain**: Security framework
- **Logging**: os.log unified logging

## Requirements

### System Requirements
- macOS 12.0 or later
- Network access to SMB servers
- Local storage for destination folders

### Permissions
- Network client access for SMB connections
- File system read/write access for selected folders
- Keychain access for credential storage
- Apple Events for Finder integration

## Installation

### Development Setup
1. Clone the repository
2. Open `AEDD.xcodeproj` in Xcode 15+
3. Build and run the project

### Distribution
- Code signed with Developer ID
- Hardened Runtime enabled
- Notarized for macOS Gatekeeper
- Distributed as signed DMG

## Usage

### Initial Setup
1. Launch AEDD
2. Click "Connect to .20" or "Connect to .23"
3. Enter SMB credentials (domain\username)
4. Choose to save credentials to Keychain
5. Select shares to mount read-only

### Creating Copy Jobs
1. Drag source folders from mounted SMB shares to the Sources pane
2. Drag or select a destination folder (must be local storage)
3. Click "Add to Queue" to create the copy job

### Managing Jobs
- Jobs execute serially in queue order
- Reorder pending jobs by dragging (cannot reorder active job)
- Cancel running jobs with graceful termination
- Retry failed jobs
- View detailed logs for troubleshooting

### Settings Configuration
- Customize default rsync options
- Manage server aliases and display names
- Configure log retention policies
- Manage stored keychain credentials
- Export/import settings for backup

## Rsync Configuration

### Default Flags
- `-aE`: Archive mode with extended attributes
- `--fileflags`: Preserve Finder flags (locked, hidden, etc.)
- `--crtimes`: Preserve creation times
- `--protect-args`: Handle special characters safely
- `--partial`: Keep partial transfers for resumption
- `--append-verify`: Resume large files with verification
- `--info=progress2`: Overall transfer progress
- `--exclude=.DS_Store`: Skip macOS metadata files

### Binary Selection
- Prefers Apple's built-in `/usr/bin/rsync` (version 2.6.9)
- Falls back to Homebrew rsync if available at `/opt/homebrew/bin/rsync`
- Optimized for macOS metadata preservation

## Security Considerations

### Sandboxing
- Full macOS App Sandbox enabled
- Minimal required entitlements
- No network server capabilities
- Read-only SMB mounts enforced

### Credential Handling
- Passwords never logged or stored in plain text
- Keychain integration for secure credential storage
- Automatic credential cleanup on uninstall

### File System Access
- User-selected file access only
- No background file system scanning
- Temporary file creation limited to user-selected locations

## Logging and Troubleshooting

### Log Locations
- Application logs: `~/Library/Logs/Aanerud-EMC-Emergency-Dumper/`
- Individual job logs with timestamp and job ID
- System logs via unified logging system

### Log Management
- Automatic cleanup after configurable retention period (default: 30 days)
- Log archiving and export functionality
- Per-job detailed rsync output capture

### Common Issues
- **Mount failures**: Check network connectivity and credentials
- **Permission denied**: Verify destination is on local storage
- **Partial transfers**: Rsync will resume on retry
- **Network timeouts**: Jobs can be retried safely

## Development

### The Technical Journey: From Simple to "Oh Right, This is macOS"

#### Container Apps vs Native Apps: The Great Divide

**What I Thought I Wanted: A Container App**

Initially, the plan was elegant: containerize everything, use standard tools, abstract away the platform complexity. After all, rsync works the same everywhere, right? SMB mounting is just CIFS under the hood, surely we can handle this with some Docker magic.

The reality check came fast:
- **Permission Hell**: Containers and macOS permissions are like oil and water
- **SMB Mounting**: Try explaining to Docker why it needs admin privileges to mount SMB shares
- **File System Access**: Sandboxed containers accessing mounted network drives? Good luck
- **User Experience**: "Please install Docker first" is not what someone wants to hear during a data emergency

**What I Actually Needed: A Native macOS App**

Building AEDD as a native Swift app revealed why Apple spent decades perfecting their platform APIs:

**The Good Parts:**
- Direct SMB mounting with `mount volume` - no sudo gymnastics
- Native file system access - no permission proxy dances
- System integration that actually works - real progress bars, proper error handling
- One-click deployment - no runtime dependencies

**The Learning Curve:**
- SwiftUI state management (or "how I learned to stop worrying and love @Published")
- Apple's permission system (TCC database, entitlements, and other mysteries)
- The subtle art of not accidentally sandboxing yourself into a corner

#### The Mount Volume Mystery: Read-Only That Isn't

Here's the amusing part: the app is supposed to mount shares read-only to prevent accidental writes. The `mount volume` command doesn't have an obvious read-only flag. Yet somehow, it works anyway.

Best guess? Apple's SMB implementation is smart enough to detect emergency scenarios, or perhaps the universe has a sense of humor about data recovery situations. Either way, "it works" trumps "I understand why" when terabytes are on the line.

### Building
```bash
xcodebuild -project AEDD.xcodeproj -scheme AEDD -configuration Release
```

### Testing
- Unit tests for core business logic
- Integration tests for SMB and rsync operations
- UI tests for critical user flows

### Code Signing
```bash
codesign --deep --force --verify --verbose --sign "Developer ID Application" AEDD.app
```

### Notarization
```bash
xcrun notarytool submit AEDD.dmg --keychain-profile "notarytool-password"
xcrun stapler staple AEDD.dmg
```

## Success Story

AEDD successfully rescued several terabytes of data during actual storage emergencies. The app successfully mounts SMB shares, enumerates files without triggering writes, shows real rsync progress, and copies data reliably. The logs show clean transfers, the progress bars update correctly, and most importantly - no storage array casualties.

## Lessons Learned: When to Go Native

**Choose containers when:**
- You control the deployment environment
- Cross-platform compatibility matters more than platform features
- Development speed trumps performance optimization
- You can afford the abstraction overhead

**Choose native when:**
- You need deep OS integration (mounting, permissions, system services)
- Performance matters (copying terabytes is not the time for overhead)
- The problem domain is platform-specific
- Reliability is non-negotiable

Sometimes the best architecture is the one that solves the actual problem, even if it means abandoning your preferred development patterns.

## License

© 2024 Aanerud EMC. All rights reserved.

## Support

For issues, feature requests, or support:
- Check the application logs first
- Review this documentation
- Contact the development team with log files for complex issues

---

**Bundle ID**: `no.uhoert.aedd`
**Version**: 1.0.0
**Minimum macOS**: 12.0
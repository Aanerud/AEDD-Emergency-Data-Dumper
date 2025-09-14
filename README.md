# AEDD - Emergency Data Dumper

A simple macOS application for mounting SMB shares and copying data to local storage using rsync.

## What It Does

AEDD mounts SMB servers, lets you browse shared folders, and copies selected folders to local drives. It's designed for when you need to quickly and reliably copy data from network storage without complications.

## The Problem It Solves

Sometimes you need to copy large amounts of data from SMB shares to local storage. The built-in Finder copy can be unreliable for large transfers, and manually running rsync commands gets tedious when you have multiple copy jobs. AEDD provides a simple interface for this common task.

## Key Features

- **SMB Server Mounting**: Connect to any SMB server using standard credentials
- **Simple Copy Jobs**: Select source folders and a destination, add to queue
- **Built-in rsync**: Uses macOS native rsync for reliable transfers
- **Job Queue**: Process multiple copy operations one at a time
- **Progress Tracking**: See real-time progress for active transfers
- **Credential Storage**: Save SMB passwords securely in macOS Keychain

## How It Works

1. **Connect to Server**: Enter SMB server address, username, and password
2. **Mount Shares**: Choose which shared folders to mount 
3. **Select Sources**: Browse mounted shares and select folders to copy
4. **Choose Destination**: Select a local folder where files should be copied
5. **Add to Queue**: Create copy jobs that will run one at a time
6. **Monitor Progress**: Watch transfers complete with real-time progress

## Installation

Download the latest release and move AEDD.app to your Applications folder. First launch may require right-click → Open due to macOS security settings.

## Usage

### Connecting to a Server
1. Launch AEDD
2. Click "Connect" 
3. Enter the SMB server IP address or hostname
4. Provide your username (e.g., DOMAIN\username) and password
5. Choose whether to save credentials to Keychain

### Setting Up Copy Jobs
1. Select which shares to mount from the available list
2. Browse the mounted shares and select source folders
3. Choose a destination folder on your local drive
4. Click "Add to Queue" to create the copy job

### Managing the Job Queue
- Jobs run one at a time to avoid overloading the system
- Cancel running jobs if needed
- Retry failed jobs
- View detailed logs for troubleshooting

### Settings
- Configure default rsync options in Settings
- Set default server addresses 
- Manage stored keychain credentials
- Configure log retention

## Technical Details

### rsync Configuration
AEDD uses the built-in macOS rsync (`/usr/bin/rsync`) with these default options:
- `-a`: Archive mode (preserves permissions, timestamps, etc.)
- `--partial`: Keep partial files for resuming interrupted transfers
- `--progress`: Show transfer progress
- `--exclude=.DS_Store`: Skip macOS metadata files

### SMB Mounting
- Uses Apple's `mount volume` command for mounting SMB shares
- Credentials are handled securely through the system
- Mounted shares appear in `/Volumes/` like any other mounted drive

### Job Processing
- Jobs are processed one at a time to prevent system overload
- Each job gets its own log file for troubleshooting
- Failed jobs can be retried without losing progress

## Troubleshooting

### Logs
Application logs are stored in `~/Library/Logs/Aanerud-EMC-Emergency-Dumper/` with separate files for each copy job.

### Common Issues
- **Can't connect to server**: Check network connectivity and credentials
- **Mount fails**: Verify the server address and that SMB is enabled
- **Copy fails**: Make sure destination has enough free space
- **Slow transfers**: Network speed and server load affect copy speed

## Requirements

- macOS 12.0 or later
- Network access to SMB servers  
- Local storage for destination folders

## Development

Built with Swift and SwiftUI. Uses standard macOS APIs for SMB mounting and file operations.

### Building from Source
1. Clone this repository
2. Open `AEDD.xcodeproj` in Xcode
3. Build and run

## License

© 2024 Aanerud EMC. All rights reserved.

---

*A simple tool for when you need to copy data from SMB shares without the complexity.*
# Building an Emergency Data Dumper: When Native Apps Remind You Why Containers Exist

When your storage array goes into emergency mode and you need to extract terabytes of data without triggering any writes, you don't reach for Docker. You reach for the closest thing to the metal - a native macOS app. This is the story of building AEDD (Aanerud Emergency Data Dumper), and why sometimes the "hard way" is the only way that works.

## The Problem: When Your Storage Array Is Having a Bad Day

Picture this: Your storage array is in emergency mode. One wrong write operation - even something as innocent as a `.DS_Store` file - could kill the entire array and lose everything. You need to mount SMB shares, enumerate files, and copy data with military precision. No room for error, no time for debugging container networking, and definitely no patience for permission issues.

This is where the rubber meets the road between "convenient development" and "production reality."

## Container Apps vs Native Apps: The Great Divide

### What I Thought I Wanted: A Container App

Initially, the plan was elegant: containerize everything, use standard tools, abstract away the platform complexity. After all, rsync works the same everywhere, right? SMB mounting is just CIFS under the hood, surely we can handle this with some Docker magic.

The reality check came fast:
- **Permission Hell**: Containers and macOS permissions are like oil and water
- **SMB Mounting**: Try explaining to Docker why it needs admin privileges to mount SMB shares
- **File System Access**: Sandboxed containers accessing mounted network drives? Good luck
- **User Experience**: "Please install Docker first" is not what someone wants to hear during a data emergency

### What I Actually Needed: A Native macOS App

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

## The Technical Journey: From Simple to "Oh Right, This is macOS"

### First Attempt: "How Hard Can SMB Be?"

```bash
# What I thought would work:
sudo mount_smbfs //user:pass@server/share /Volumes/share
```

Reality: Apple has opinions about mounting, permissions, and what constitutes "proper" authentication. Five different mounting strategies later, we discovered that `mount volume` with AppleScript is the path of least resistance.

### Second Attempt: "Let's Use Advanced Rsync Features"

The original rsync configuration was a thing of beauty:
```swift
args.append(contentsOf: ["-aE", "--fileflags", "--crtimes", "--protect-args", "--append-verify", "--info=progress2"])
```

This worked perfectly - on modern Linux systems with GNU rsync 3.2+. macOS ships with rsync from 2006. Back to basics:
```swift
args.append(contentsOf: ["-a", "--partial", "--progress", "--exclude=.DS_Store"])
```

Sometimes "worse is better" isn't just a Unix philosophy, it's a survival strategy.

### Third Attempt: "Surely SwiftUI State Management is Straightforward"

The credential flow seemed simple: get credentials, pass them around, mount shares. What could go wrong?

Everything. SwiftUI's state timing, sheet presentation order, and the general chaos of reactive programming meant credentials would mysteriously disappear between views. The solution? Store them in the manager class and stop playing hot potato with authentication data.

## The Mount Volume Mystery: Read-Only That Isn't

Here's the amusing part: the app is supposed to mount shares read-only to prevent accidental writes. The `mount volume` command doesn't have an obvious read-only flag. Yet somehow, it works anyway.

Best guess? Apple's SMB implementation is smart enough to detect emergency scenarios, or perhaps the universe has a sense of humor about data recovery situations. Either way, "it works" trumps "I understand why" when terabytes are on the line.

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

## The Real Victory: It Actually Works

AEDD successfully mounts SMB shares, enumerates files without triggering writes, shows real rsync progress (once we figured out stderr parsing), and copies data reliably. The logs show clean transfers, the progress bars update correctly, and most importantly - no storage array casualties.

Sometimes the best architecture is the one that solves the actual problem, even if it means abandoning your preferred development patterns.

## Final Thoughts: Native Development in 2024

Building a native macOS app in 2024 feels simultaneously retro and cutting-edge. Retro because you're dealing with platform-specific APIs, manual memory management concerns, and the peculiarities of a single operating system. Cutting-edge because the tools are genuinely excellent - Swift is a joy to write, SwiftUI handles the hard parts of UI development, and Xcode (despite its reputation) actually works quite well.

The real lesson isn't "containers bad, native good" - it's knowing when each approach fits the problem. When your storage array is having an existential crisis, you want the most direct path from your code to the hardware. Sometimes that means ditching the abstractions and embracing the platform.

And if anyone figures out why `mount volume` works in read-only mode without explicitly asking for it, please let me know. Some mysteries are worth solving, even after the crisis is over.

---

*AEDD (Aanerud Emergency Data Dumper) successfully rescued several terabytes of data during actual storage emergencies. No arrays were harmed in the making of this software, though several .DS_Store files were definitely excluded from the transfer.*
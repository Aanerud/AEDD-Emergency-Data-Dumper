#!/bin/bash

echo "🔧 Building AEDD Universal Binary..."

# Clean build first to ensure fresh build
echo "🧹 Cleaning previous builds..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project AEDD.xcodeproj \
    -scheme AEDD \
    clean \
    -quiet

# Build the universal app using Debug configuration (same as Xcode testing)
echo "🔨 Building universal binary..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
    -project AEDD.xcodeproj \
    -scheme AEDD \
    -configuration Debug \
    -arch arm64 -arch x86_64 \
    ONLY_ACTIVE_ARCH=NO \
    -quiet

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"

    # Remove old build
    rm -rf ./AEDD_Release.app

    # Copy to project directory (using Debug configuration)
    cp -R "/Users/aaanerud/Library/Developer/Xcode/DerivedData/AEDD-"*/Build/Products/Debug/AEDD.app ./AEDD_Release.app 2>/dev/null

    if [ -d "./AEDD_Release.app" ]; then
        echo "📱 Universal app copied to: ./AEDD_Release.app"
        echo "🔍 Architecture check:"
        lipo -archs ./AEDD_Release.app/Contents/MacOS/AEDD

        # Get file size
        echo "📦 App size: $(du -sh ./AEDD_Release.app | cut -f1)"
    else
        echo "⚠️  Could not copy app bundle"
    fi
else
    echo "❌ Build failed"
    exit 1
fi
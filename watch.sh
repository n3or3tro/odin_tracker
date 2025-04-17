#!/bin/bash

# Check if inotifywait is installed
if ! command -v inotifywait >/dev/null 2>&1; then
    echo "Error: inotifywait not found. Please install inotify-tools:"
    echo "sudo apt-get install inotify-tools  # For Debian/Ubuntu"
    echo "sudo dnf install inotify-tools      # For Fedora"
    exit 1
fi

# Default values
SOURCE_DIR="./src"
PROJECT_DIR="."  # Directory containing the Odin package
OUTPUT_NAME="main"
BUILD_FLAGS=""
MAIN_BINARY="main.bin"
MAIN_PID=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--directory)
            SOURCE_DIR="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT_DIR="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_NAME="$2"
            shift 2
            ;;
        -f|--flags)
            BUILD_FLAGS="$2"
            shift 2
            ;;
        -b|--binary)
            MAIN_BINARY="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Function to kill existing process
kill_existing_process() {
    if [ ! -z "$MAIN_PID" ]; then
        echo "Killing existing process (PID: $MAIN_PID)..."
        kill $MAIN_PID 2>/dev/null || true
        wait $MAIN_PID 2>/dev/null || true
    fi
    # Also try to kill any other instances that might be running
    pkill -f "$MAIN_BINARY" 2>/dev/null || true
}

# Function to launch the main binary
launch_binary() {
    kill_existing_process
    echo "Launching $MAIN_BINARY..."
    ./$MAIN_BINARY &
    MAIN_PID=$!
    echo "Started process with PID: $MAIN_PID"
}

# Function to build the shared library
build_library() {
    echo "Building $OUTPUT_NAME.so..."
    # Store current directory
    CURRENT_DIR=$(pwd)
    # Change to project directory
    cd "$PROJECT_DIR" || exit 1
    
    # Check if any .odin files exist in source directory
    if ! find "$SOURCE_DIR" -name "*.odin" -print -quit | grep -q .; then
        echo "Error: No .odin files found in $SOURCE_DIR"
        cd "$CURRENT_DIR"
        return 1
    fi
    
    # Run the build command
    if odin build "$SOURCE_DIR" -build-mode:shared -out:"$OUTPUT_NAME.so" $BUILD_FLAGS; then
        echo "Build successful: $(date)"
        # Return to original directory
        cd "$CURRENT_DIR"
        # Launch the binary after successful build
        launch_binary
        return 0
    else
        echo "Build failed: $(date)"
        # Return to original directory
        cd "$CURRENT_DIR"
        return 1
    fi
}

# Ensure directories exist
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist"
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "Error: Project directory '$PROJECT_DIR' does not exist"
    exit 1
fi

# Handle script termination
cleanup() {
    echo "Cleaning up..."
    kill_existing_process
    exit 0
}
trap cleanup SIGINT SIGTERM

echo "Watching directory '$SOURCE_DIR' for changes..."
echo "Initial build..."
build_library

# Watch for file changes
inotifywait -m -r -e modify,create,delete,move "$SOURCE_DIR" --format "%w%f" | while read FILE
do
    # Check if the changed file is an Odin source file
    if [[ "$FILE" =~ \.(odin|ods)$ ]]; then
        echo "Change detected in $FILE"
        build_library
    fi
done

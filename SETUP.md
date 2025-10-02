# Jarvis MLX Setup Guide

## Quick Start

Follow these steps to get Jarvis running with MLX:

### 1. Open in Xcode

```bash
cd /Users/zhen/Dev/Jarvis
open Jarvis.xcodeproj
```

### 2. Resolve Package Dependencies

When you first open the project, Xcode will automatically:
- Download MLX Swift packages from GitHub
- Resolve all dependencies
- Build the packages

This may take 2-5 minutes on first launch.

**If packages don't resolve automatically:**
1. Go to **File → Packages → Resolve Package Versions**
2. Wait for the download to complete
3. Clean build folder: **Product → Clean Build Folder** (Cmd+Shift+K)

### 3. Build the Project

1. Select your Mac as the target device
2. Click **Product → Build** (Cmd+B)
3. Wait for the build to complete

### 4. Run Jarvis

1. Click **Product → Run** (Cmd+R)
2. The app will launch and automatically download the Gemma3 model
3. Initial model download will take 2-5 minutes (one-time only)

## Expected Behavior

### First Launch

1. **App opens** - Shows "Loading Model" status in blue
2. **Model downloads** - Automatic download from Hugging Face (~2.5GB)
3. **Model loads** - MLX loads the model into memory (~30 seconds)
4. **Ready** - Status turns green, you can start chatting

### Subsequent Launches

- Model is cached locally
- Loads in ~10-15 seconds
- No internet required

## Troubleshooting

### Package Resolution Fails

**Error:** "Failed to resolve package dependencies"

**Solution:**
```bash
# Close Xcode
# Delete derived data
rm -rf ~/Library/Developer/Xcode/DerivedData

# Delete SPM cache
rm -rf ~/Library/Caches/org.swift.swiftpm

# Reopen project
open Jarvis.xcodeproj
```

### Build Errors

**Error:** "No such module 'MLX'"

**Solution:**
1. Wait for package resolution to complete (check status bar)
2. Clean build folder (Cmd+Shift+K)
3. Rebuild (Cmd+B)

**Error:** Compilation errors in MLXModelManager.swift

**Solution:**
The MLX Swift API may have changed. Check the latest examples:
```bash
git clone https://github.com/ml-explore/mlx-swift-examples.git
cd mlx-swift-examples/Applications/LLMEval
# Review the ModelContainer and generation code
```

### Runtime Errors

**Error:** "Model is not loaded"

**Cause:** Model download or loading failed

**Solution:**
1. Check internet connection
2. Ensure sufficient disk space (~5GB)
3. Check Console.app for detailed error messages
4. Try restarting the app

### Performance Issues

**Issue:** Slow inference

**Check:**
- Activity Monitor → Memory (ensure sufficient RAM)
- Activity Monitor → CPU (should show GPU activity)
- System Settings → Battery (disable Low Power Mode)

## Development Tips

### Testing Changes

After modifying code:
1. Stop the app (Cmd+.)
2. Clean build (Cmd+Shift+K)
3. Build (Cmd+B)
4. Run (Cmd+R)

### Debugging

Enable detailed logging by modifying `MLXModelManager.swift`:

```swift
// Add after model loading
print("Model loaded successfully")
print("Configuration: \(modelConfiguration)")
```

### Memory Profiling

Use Xcode Instruments:
1. Product → Profile (Cmd+I)
2. Select "Allocations" template
3. Run the app and monitor memory usage

## System Requirements Verification

### Check macOS Version

```bash
sw_vers
```

Should show: `ProductVersion: 14.0` or higher

### Check Apple Silicon

```bash
sysctl -n macros.cpu.brand_string
```

Should show: Apple M1/M2/M3

### Check Available RAM

```bash
sysctl hw.memsize | awk '{print $2/1024/1024/1024 " GB"}'
```

Should show: 8GB or more (16GB recommended)

### Check Disk Space

```bash
df -h ~
```

Ensure at least 10GB free for model cache

## Next Steps

Once everything is working:

1. **Test all features:**
   - General chat mode
   - Translation mode
   - Grammar fixing mode

2. **Try different models:**
   - Edit `JarvisViewModel.swift`
   - Change `availableModels` array
   - Select different model in UI

3. **Customize prompts:**
   - Edit `Prompts.swift`
   - Adjust system prompts for each role

4. **Performance tuning:**
   - Adjust temperature and topP in `sendMessage()`
   - Experiment with maxTokens

## Getting Help

If you encounter issues:

1. **Check Console.app** for error messages
2. **Review MLX_INTEGRATION.md** for detailed information
3. **Check GitHub issues** in ml-explore/mlx-swift-examples
4. **Compare with working examples** in mlx-swift-examples repo

## Success Indicators

You'll know it's working when:

✅ Xcode builds without errors  
✅ App launches and shows "Loading Model"  
✅ Status changes to "Ready" (green)  
✅ You can send a message and get a response  
✅ Response streams in real-time  
✅ Second launch is faster (model cached)  

Enjoy using Jarvis with on-device AI! 🚀


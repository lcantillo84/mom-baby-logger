# Mommy's Log - Xcode Setup Guide

## ✅ Step-by-Step Configuration

Follow these steps IN ORDER to configure your app for the App Store:

---

## 📱 STEP 1: Set App Name & Bundle Identifier (5 minutes)

1. **Open Xcode**
   ```bash
   open MomBabyLogger.xcodeproj
   ```

2. **Select the Project** (top of left sidebar)
   - Click "MomBabyLogger" (blue icon) in Project Navigator

3. **Select the Target**
   - Click "MomBabyLogger" under TARGETS (not PROJECT)

4. **General Tab** - Update these fields:

   **Display Name:**
   ```
   Mommy's Log
   ```
   *(This is what users see on their home screen)*

   **Bundle Identifier:**
   ```
   com.lilianne.mommyslog
   ```
   *(Must be unique - this identifies your app)*

   **Version:**
   ```
   1.0.0
   ```

   **Build:**
   ```
   1
   ```

   **Deployment Target:**
   ```
   iOS 16.0
   ```

---

## 🎨 STEP 2: Add App Icon (REQUIRED)

You MUST have a 1024x1024 PNG icon before submitting.

### In Xcode:

1. Click **Assets.xcassets** in Project Navigator
2. Click **AppIcon** in the list
3. Find the **"App Store iOS 1024pt"** slot (bottom right)
4. **Drag your 1024x1024 PNG** into that slot
5. Xcode will automatically generate all other sizes

### Don't Have an Icon Yet?

**Option A: Create in Canva (FREE, 10 minutes)**
1. Go to canva.com
2. Search "app icon template"
3. Design with baby theme:
   - Colors: Soft pink, baby blue, or pastel
   - Icons: Baby bottle, heart, pacifier, or "M" letter
   - Keep it simple and recognizable
4. Download as PNG 1024x1024

**Option B: Hire on Fiverr ($10-30, 24 hours)**
- Search "app icon design"
- Show them this description:
  ```
  App name: "Mommy's Log"
  Purpose: Baby feeding & diaper tracker
  Style: Cute, warm, trustworthy
  Colors: Soft pastels (pink/blue/neutral)
  Icon idea: Heart + baby bottle OR "M" letter with baby theme
  Size: 1024x1024 PNG
  ```

**Option C: Temporary Placeholder**
- Use a simple design tool to create basic icon
- You can update it later before final submission

---

## 🔐 STEP 3: Signing & Capabilities

1. Stay in **General** tab
2. Find **Signing & Capabilities** section
3. **Automatically manage signing:** ✅ CHECK THIS
4. **Team:** Select your Apple Developer account
   - If you don't see a team, you need to add your Apple ID:
     - Xcode → Settings → Accounts
     - Click "+" → Sign in with Apple ID
     - This requires Apple Developer Program membership ($99/year)

---

## 📋 STEP 4: Update Privacy Description (REQUIRED for App Store)

1. Click **Info** tab (next to General)
2. Look for or add these keys:

   **Privacy - Camera Usage Description:**
   ```
   This app does not use the camera
   ```
   *(Can leave blank or delete if not needed)*

   **Privacy - Photo Library Usage Description:**
   ```
   This app does not access your photos
   ```
   *(Can leave blank or delete if not needed)*

   These are just examples - our app doesn't need camera/photos, but App Store likes to see privacy descriptions.

---

## ✅ STEP 5: Verify Everything

Double-check these settings:

- [ ] Display Name = "Mommy's Log"
- [ ] Bundle Identifier = "com.lilianne.mommyslog"
- [ ] Version = 1.0.0
- [ ] Build = 1
- [ ] Deployment Target = iOS 16.0
- [ ] App Icon added (1024x1024)
- [ ] Signing = Automatic with your team selected

---

## 🧪 STEP 6: Test Build

1. **Select a simulator:**
   - Top toolbar: Click device dropdown
   - Choose "iPhone 15" or "iPhone 15 Pro"

2. **Build and Run:**
   - Press **Cmd+R** (or click Play button)
   - App should launch in simulator
   - Test all features:
     - Log feeding
     - Log diaper
     - View history
     - Export data
     - Delete data

3. **Fix any errors:**
   - If build fails, check the error messages
   - Most common: Missing files in target
   - Solution: Select file → Right sidebar → Target Membership → Check "MomBabyLogger"

---

## 📱 STEP 7: Test on Real iPhone (HIGHLY RECOMMENDED)

1. **Connect your iPhone** via USB cable
2. **Trust the computer** on your iPhone
3. **Select your iPhone** from device dropdown (top toolbar)
4. **Press Cmd+R** to build and run
5. **Test everything** on real device:
   - All features work?
   - Data persists after closing app?
   - Export works?
   - No crashes?

---

## 🚀 NEXT STEPS AFTER XCODE IS CONFIGURED:

Once you complete these steps, we'll move to:

1. ✅ Take App Store screenshots
2. ✅ Set up App Store Connect
3. ✅ Archive the app
4. ✅ Upload to App Store
5. ✅ Submit for review

---

## ❓ TROUBLESHOOTING

### "No such module" errors
- Product → Clean Build Folder (Shift+Cmd+K)
- Restart Xcode
- Build again

### "Signing requires a development team"
- You need Apple Developer Program membership ($99/year)
- Sign up at: developer.apple.com/programs
- Add your Apple ID in Xcode → Settings → Accounts

### App icon not showing
- Make sure it's exactly 1024x1024 pixels
- Make sure it's PNG format
- Make sure there's NO transparency (alpha channel)

### Build errors about missing files
- Select each Swift file in Project Navigator
- Check right sidebar → Target Membership
- Make sure "MomBabyLogger" is checked

---

## 📞 NEED HELP?

If you get stuck on ANY step, just tell me:
1. What step you're on
2. What error you see (if any)
3. Screenshot if possible

I'll help you fix it immediately!

---

## ✅ WHEN YOU'RE DONE:

Tell me: **"Xcode is configured!"**

And we'll move to the next phase: **Screenshots and App Store Connect setup!**

---

**Your App Details:**
- **Name:** Mommy's Log
- **Bundle ID:** com.lilianne.mommyslog
- **Version:** 1.0.0
- **Target:** iOS 16.0+

Let's make this happen! 🚀

# BlogApp - iOS Management App

## Quick Setup

### Create New Xcode Project

1. Open Xcode
2. **File → New → Project**
3. Select **iOS → App**
4. Configure:
   - Product Name: `BlogApp`
   - Interface: **SwiftUI**
   - Language: **Swift**
5. Choose a location and create

### Add Source Files

1. In Xcode's Project Navigator, **delete** the auto-generated `ContentView.swift`
2. **Right-click** on the `BlogApp` folder → **Add Files to "BlogApp"...**
3. Navigate to `/Users/farid/Developer/0xFarid/BlogApp/BlogApp/`
4. Select ALL files and folders:
   - `BlogAppApp.swift`
   - `ContentView.swift`
   - `Models/` folder
   - `Views/` folder  
   - `Services/` folder
   - `Generated/` folder
5. **Uncheck** "Copy items if needed"
6. **Check** "Create groups"
7. Click **Add**

### Configure Info.plist

Add this to your Info.plist (or update the existing one):

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

This allows HTTP connections for local development.

### Run

1. Select a simulator or device
2. Press **Cmd+R** to build and run
3. On first launch, configure:
   - **Server Host**: `localhost` (or your backend IP)
   - **Port**: `8081`
   - **API Key**: `your-secure-api-key-here`

## Features

- **Posts Tab**: View all posts, swipe to delete
- **New Post Tab**: Create new posts (280 char limit)
- **Moderate Tab**: View comments, approve or delete
- **Settings Tab**: Configure server connection

## API Key

The default API key is `your-secure-api-key-here`. 

To change it, set the `BLOG_API_KEY` environment variable in your docker-compose:

```yaml
environment:
  BLOG_API_KEY: your-custom-secret-key
```

# QuietExistence 👻

**The art of being there without being seen.**

QuietExistence is a macOS experiment that captures the contents of your screen and forwards them to a configured coding agent, displaying its response through an unobtrusive interface.

Note: No need to pay anything. No data leaves you machine everything run in you local mac.

## ✨ Features

- **macOS Native:** Built to run locally on macOS.
- **Screen Capture:** Reads the contents of your current screen.
- **AI Agent Integration:** Sends captured screen content to your configured coding agent.
- **Global Shortcut:** Instantly trigger the workflow using a keyboard shortcut.
- **Minimal Interface:** Designed to stay out of your way.

## 🚀 Getting Started

Follow these steps to build and run QuietExistence locally.

### 1. Fork & Clone

Fork this repository and clone your fork:

```bash
git clone <your-fork-url>
cd QuietExistence
```

### 2. Build the Application

Run the build script from the project directory:

```bash
chmod +x build.sh
./build.sh
```

This will build the macOS application.

### 3. Launch the Application

Open the generated application:

```bash
open QuietExistence.app/
```

### 4. Configure Your Environment

Once the settings window opens:

- Select your preferred coding agent.
- Configure the required command or provider settings.
- Adjust the application preferences.

### 5. Grant Permissions

Grant the macOS permissions required for the features you intend to use, such as:

- Screen Recording
- Accessibility (if required)

You may need to restart the application after granting permissions.

### 6. Save Your Configuration

Save your settings and close the configuration window.

## ⌨️ Keyboard Shortcut

Once configured, navigate to a screen you want to analyze and press:

`Control + Command + A`

This triggers the screen-capture workflow and sends the captured content to your configured coding agent.

The agent's response is then displayed through the application interface.

## 🛠️ Requirements

- macOS
- Xcode Command Line Tools
- A supported coding agent
- Required macOS permissions

## ⚠️ Disclaimer

QuietExistence is an experimental project intended for educational purposes and controlled demonstrations. [iykyk :lol]

Always obtain appropriate consent before capturing or processing someone else's screen or information. Do not use it to misrepresent your capabilities or gain an unfair advantage in interviews or assessments.

## ⭐ Support

If you find this project interesting, consider giving the repository a star!

**QuietExistence — Present, but barely noticed.** 👻

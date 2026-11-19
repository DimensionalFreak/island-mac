# Putting Island on your Mac (test build)

This build is **not signed by Apple** (that needs a paid Apple account), so your Mac will warn you the first time. The steps below are the normal way past that warning. It only has to be done once per downloaded build.

## 1. Download

1. On your Mac, open Safari or Chrome.
2. Go to `https://github.com/DimensionalFreak/island-mac/releases`.
3. Under the newest "Island for Mac, build N", click **Island-mac.zip** to download it.

## 2. Unzip and move it

1. Open **Finder > Downloads**. Safari unzips by itself; otherwise double-click `Island-mac.zip`.
2. You will see an app called **Island**. Drag it into the **Applications** folder (in the Finder sidebar).

## 3. Open it, and approve it in System Settings

1. Open **Applications** and double-click **Island**.
2. A box says Island "can't be opened" or "Apple could not verify it is free of malware". Click **Done** (do not click "Move to Bin").
3. Open **System Settings** (Apple menu > System Settings) > **Privacy & Security**.
4. Scroll down to the **Security** section. You will see: "Island was blocked to protect your Mac." Click **Open Anyway**.
5. Type your Mac password (or use Touch ID) and click **Open**.
6. If a last box asks "Are you sure you want to open it?", click **Open Anyway** / **Open**.

## 4. Activate it (needs a code from the owner)

The app starts **locked** and shows nothing until you activate it.

1. Click the **capsule icon** in the menu bar (top right) > **Copy my Device ID**, and send that ID to the owner.
2. The owner sends back a long code starting `ISL1-`. Copy the **whole** code (select it, Cmd+C).
3. Click the capsule icon > **Paste activation code from clipboard**. A box says "Island is activated". You only do this once.

## 5. What you should see

- **No Dock icon and no window.** That is correct.
- A small **capsule icon in the menu bar** (top right). Click it for the menu.
- On a Mac with a notch: the notch looks completely normal until a message arrives.
- On a Mac without a notch: a small black pill at the top centre.

Click the capsule icon > **Show a test message**. The island should grow out of the notch (or pill) with a spring motion, show the message for 6 seconds, then shrink back. Try the other three tests too (buttons, progress, urgent).

## 6. If something looks wrong

- Click the capsule icon > **Show the log in Finder** and send me the file `island.log`, or just tell me what you see.
- A screenshot of the top of the screen helps most.
- To stop it: capsule icon > **Quit Island**.

## For programs on the same Mac

Another app can send a message by connecting to the file `~/Library/Application Support/Island/island.sock` and writing one message per line, in the format in `shared/MESSAGES.md`. For a quick try from Terminal: `mac/send-test-message.sh "Hello" "From Terminal"`.

cask "remindian" do
  version "5.9.0"
  sha256 "72b5aa4bea15d51e9ec05c6036cc804a0e4dcc97a26f1e39f47e6b9a7cc85ef6"

  url "https://github.com/Santofer/Remindian/releases/download/v#{version}/Remindian-v#{version}.dmg"
  name "Remindian"
  desc "Sync Obsidian tasks with Apple Reminders, Todoist, Asana, Linear, and more"
  homepage "https://github.com/Santofer/Remindian"

  auto_updates true
  depends_on macos: ">= :ventura"

  app "Remindian.app"

  zap trash: [
    "~/Library/Application Support/Remindian",
    "~/Library/Containers/com.remindian.app",
    "~/Library/Preferences/com.remindian.app.plist",
  ]
end

cask "remindian" do
  version "5.7.0"
  sha256 "2fb7ce38856801bc914ff6d54b13514442d4966d671d14e79c10c5c4f73949ba"

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

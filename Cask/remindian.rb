cask "remindian" do
  version "4.2.0"
  sha256 "36ccda51397bce5ce23d1aab0e12bb7812ced248ec02b7dd9840f56d7f6ae2ca"

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

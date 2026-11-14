# Changelog

## 0.2.0

- **Lanes**: the day as a Gantt-style chart, one lane per tag or app, with sound, calls and each Mac underneath.
- **Sound and calls**: Trace notes which apps play sound or use the microphone, also in the background. While the app in front is making sound you are no longer counted as away.
- **Focus**: deep work time, app switches per hour and what interrupted you, on the overview. Each tag counts as focus, neutral or distraction.
- **Goals**: a daily target or limit per tag, shown as rings with streaks.
- **Sessions**: press Start and pick a tag; until you stop, everything counts as that tag. Open-ended or timed, from the new Focus page, the sidebar or the menu bar.
- **Being away**: a call, or sound from the app in front, keeps you counted as present; background sound can be made to count too. Away rows say what was playing.
- **Settings**: every installed app is listed with a switch to leave it out, most used first; the Sync pane shows clearly when the last sync finished and when the next is due.
- **Window and Dock**: closing the window leaves Trace recording in the menu bar without showing as running in the Dock; clicking the Dock icon or opening the app again always brings the window back. It quits only from the menu bar panel or with Command-Q.
- **Projects**: time per project, found from the folder each file is in.
- **Review**: a few sentences on each week and month compared with the one before.
- **Year calendar**: one square per day; click a day to open it.
- **Sync folder** (optional, off by default): keep several Macs in step, or keep a backup, through any folder that is synced for you, such as iCloud Drive. Each Mac writes its own records and reads the others'; tags and rules are shared. A menu in the sidebar shows all Macs together or one at a time. Macs can be named, reports show time per Mac, and simultaneous use on two Macs is drawn side by side.
- **Wider built-in tags**: about 180 more common apps and sites are recognised out of the box, including QQ, WeCom, DingTalk, Feishu, Tencent Meeting, NetEase Cloud Music, JetBrains IDEs, Zotero, Obsidian, Notion and Adobe apps. Existing installs receive the additions once.

## 0.1.0

First public release.

- **Automatic recording** of the frontmost app, window title, document path and page address, every two seconds, merged into one record per stay. Time away from the keyboard and mouse is left out.
- **Overview** of the day: total time, share by tag, time per hour, a two-lane timeline and the most used apps.
- **Timeline** that expands tag › app › file or site › page, with the day laid out top to bottom. Click a session or drag across a period to sum up only that part of the day.
- **Records** view that lists every stay, grouped into sessions, with an inspector for the selected record.
- **Tags**: eight built-in tags that work without setup, custom tags, rules on app, app category, file path, URL or window title, and tagging single records by hand.
- **Reports** by week, month and year, with active hours, top sites and top files, and CSV export.
- **Privacy controls**: turn off window titles, file paths or web addresses, exclude apps, pause recording, erase all records. All data stays in a local SQLite file.
- Light and dark appearance, English and Simplified Chinese, a menu bar panel, launch at login.
- Universal build for Apple silicon and Intel, signed with Developer ID and notarized by Apple. Requires macOS 14 or later.

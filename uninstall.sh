#!/bin/bash
launchctl bootout gui/$(id -u)/local.ccusage.widget 2>/dev/null
rm -f ~/Library/LaunchAgents/local.ccusage.widget.plist
pkill -x CCUsage 2>/dev/null
pluginkit -r /Applications/CCUsage.app/Contents/PlugIns/CCUsageWidget.appex 2>/dev/null
rm -rf /Applications/CCUsage.app
# 팀 ID 접두사가 붙은 컨테이너와 접두사 없는 옛 컨테이너를 모두 지운다.
rm -rf ~/Library/Group\ Containers/*group.local.ccusage
rm -rf ~/Library/Containers/local.ccusage.app.widget
defaults delete local.ccusage.app 2>/dev/null
rm -rf ~/Library/Caches/CCUsage
echo "제거 완료 (소스는 저장소에 남습니다)"

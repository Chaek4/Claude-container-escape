#!/bin/bash
set -e

echo "=== Emulator ready ==="
adb devices

# Запускаем перехват трафика
sudo tcpdump -i any -w /tmp/capture.pcap &
TCPDUMP_PID=$!
echo "tcpdump PID: $TCPDUMP_PID"

# Очищаем logcat
adb logcat -c

# Устанавливаем APK
echo "=== Installing APK ==="
adb install -r base.apk
echo "APK installed"

# Получаем package name — всё в одном процессе, переменные сохраняются
PACKAGE=$(adb shell pm list packages | grep lostbot | sed 's/package://' | tr -d '\r\n ')
echo "Package: [$PACKAGE]"

if [ -z "$PACKAGE" ]; then
  echo "ERROR: Package not found!"
  adb shell pm list packages | head -20
  exit 1
fi

# Запускаем приложение
echo "=== Launching app ==="
adb shell am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p "$PACKAGE"
sleep 5

# Скриншот 1
adb shell screencap -p /sdcard/screen1.png
adb pull /sdcard/screen1.png /tmp/screen1.png || true
echo "Screenshot 1 saved"

# Ждём пока приложение работает
echo "Waiting 40s..."
sleep 40

# Скриншот 2
adb shell screencap -p /sdcard/screen2.png
adb pull /sdcard/screen2.png /tmp/screen2.png || true
echo "Screenshot 2 saved"

echo "=== Granted permissions ==="
adb shell dumpsys package "$PACKAGE" | grep "granted=true"

echo "=== Network connections ==="
adb shell netstat 2>/dev/null | head -40 || true

echo "=== App files ==="
adb root && sleep 2 || true
adb shell ls -la /data/data/"$PACKAGE"/ 2>/dev/null || true

echo "=== Shared preferences ==="
PREFS=$(adb shell ls /data/data/"$PACKAGE"/shared_prefs/ 2>/dev/null || echo "")
for f in $PREFS; do
  f=$(echo "$f" | tr -d '\r')
  echo "--- $f ---"
  adb shell cat "/data/data/$PACKAGE/shared_prefs/$f" 2>/dev/null || true
done

echo "=== LOGCAT app-specific ==="
adb logcat -d | grep -iE "lostbot|urent|mqtt|spam|unlock|bluetooth|ble|telegram|token" | head -300

echo "=== LOGCAT network/errors ==="
adb logcat -d | grep -iE "connect|socket|http|mqtt|IOException|Exception" \
  | grep -vE "Zygote|art |dalvik|HealthConnect|wificond" | head -150

# Сохраняем полный logcat
adb logcat -d > /tmp/logcat_full.txt
grep -iE "lostbot|urent|mqtt|spam|unlock" /tmp/logcat_full.txt > /tmp/logcat_app.txt || true

# Останавливаем tcpdump
sudo kill $TCPDUMP_PID 2>/dev/null || true
sleep 3

echo "=== Unique destination IPs ==="
sudo tshark -r /tmp/capture.pcap -T fields -e ip.dst 2>/dev/null \
  | sort -u | grep -v '^$' | head -40

echo "=== DNS queries ==="
sudo tshark -r /tmp/capture.pcap -Y "dns.flags.response == 0" \
  -T fields -e dns.qry.name 2>/dev/null | sort -u | head -30

echo "=== MQTT port 1883 ==="
sudo tshark -r /tmp/capture.pcap -Y "tcp.port == 1883" 2>/dev/null | head -20

echo "=== HTTP requests ==="
sudo tshark -r /tmp/capture.pcap -Y "http.request" \
  -T fields -e ip.dst -e http.host -e http.request.uri 2>/dev/null | head -20

echo "=== DONE ==="

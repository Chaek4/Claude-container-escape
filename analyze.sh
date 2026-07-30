#!/bin/bash

echo "=== Emulator ready ==="
adb devices

# Перехват трафика
sudo tcpdump -i any -w /tmp/capture.pcap &
TCPDUMP_PID=$!

adb logcat -c

# Устанавливаем APK
echo "=== Installing APK ==="
adb install -r base.apk

PACKAGE=$(adb shell pm list packages | grep lostbot | sed 's/package://' | tr -d '\r\n ')
echo "Package: [$PACKAGE]"

# Запускаем
echo "=== Launching ==="
adb shell am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p "$PACKAGE"
sleep 5

adb shell screencap -p /sdcard/screen1.png
adb pull /sdcard/screen1.png /tmp/screen1.png || true

echo "Waiting 40s..."
sleep 40

adb shell screencap -p /sdcard/screen2.png
adb pull /sdcard/screen2.png /tmp/screen2.png || true

# Собираем результаты в текстовый файл
RESULT="/tmp/analysis.txt"

echo "=== PERMISSIONS ===" >> $RESULT
adb shell dumpsys package "$PACKAGE" | grep "granted=true" >> $RESULT

echo -e "\n=== NETWORK CONNECTIONS ===" >> $RESULT
adb shell netstat 2>/dev/null >> $RESULT || true

echo -e "\n=== APP FILES ===" >> $RESULT
adb root && sleep 2 || true
adb shell ls -la /data/data/"$PACKAGE"/ 2>/dev/null >> $RESULT || true

echo -e "\n=== SHARED PREFERENCES ===" >> $RESULT
PREFS=$(adb shell ls /data/data/"$PACKAGE"/shared_prefs/ 2>/dev/null | tr -d '\r' || echo "")
for f in $PREFS; do
    echo "--- $f ---" >> $RESULT
    adb shell cat "/data/data/$PACKAGE/shared_prefs/$f" 2>/dev/null >> $RESULT || true
done

echo -e "\n=== LOGCAT APP ===" >> $RESULT
adb logcat -d | grep -iE "lostbot|urent|mqtt|spam|unlock|bluetooth|ble|telegram|token" | head -300 >> $RESULT

echo -e "\n=== LOGCAT NETWORK ===" >> $RESULT
adb logcat -d | grep -iE "connect|socket|http|mqtt|IOException|Exception" \
  | grep -vE "Zygote|art |dalvik|HealthConnect|wificond" | head -150 >> $RESULT

# Полный logcat
adb logcat -d > /tmp/logcat_full.txt

# Останавливаем tcpdump
sudo kill $TCPDUMP_PID 2>/dev/null || true
sleep 3

echo -e "\n=== UNIQUE DEST IPs ===" >> $RESULT
sudo tshark -r /tmp/capture.pcap -T fields -e ip.dst 2>/dev/null | sort -u | grep -v '^$' >> $RESULT

echo -e "\n=== DNS QUERIES ===" >> $RESULT
sudo tshark -r /tmp/capture.pcap -Y "dns.flags.response == 0" \
  -T fields -e dns.qry.name 2>/dev/null | sort -u >> $RESULT

echo -e "\n=== MQTT port 1883 ===" >> $RESULT
sudo tshark -r /tmp/capture.pcap -Y "tcp.port == 1883" 2>/dev/null >> $RESULT

echo -e "\n=== HTTP REQUESTS ===" >> $RESULT
sudo tshark -r /tmp/capture.pcap -Y "http.request" \
  -T fields -e ip.dst -e http.host -e http.request.uri 2>/dev/null >> $RESULT

echo "=== DONE ==="
cat $RESULT

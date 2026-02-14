#!/bin/bash
set -euo pipefail

useradd -r -s /usr/sbin/nologin -G audio fluidsynth

cat > /etc/asound.conf << 'EOF'
defaults.pcm.card 0
defaults.ctl.card 0
EOF

cat > /etc/systemd/system/alsa-volume.service << 'EOF'
[Unit]
Description=Set ALSA volume
After=sound.target

[Service]
Type=oneshot
ExecStart=/usr/bin/amixer sset Master 80% unmute
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/fluidsynth.service << 'EOF'
[Unit]
Description=FluidSynth MIDI Synthesizer
After=sound.target alsa-volume.service

[Service]
Type=simple
User=fluidsynth
Group=audio
ExecStartPre=/bin/sh -c 'test -f /usr/share/soundfonts/FluidR3_GM.sf2 || exit 1'
ExecStart=/usr/bin/fluidsynth -a alsa -m alsa_seq -o audio.alsa.device=hw:0 -g 1.0 -r 48000 -o audio.periods=2 -o audio.period-size=128 /usr/share/soundfonts/FluidR3_GM.sf2
Restart=on-failure
RestartSec=3
LimitRTPRIO=95
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/midi-connect.service << 'EOF'
[Unit]
Description=Auto-connect MIDI inputs
After=fluidsynth.service
Requires=fluidsynth.service

[Service]
Type=simple
ExecStartPre=/bin/sleep 3
ExecStart=/usr/local/bin/midi-autoconnect.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/local/bin/midi-autoconnect.sh << 'EOF'
#!/bin/bash
while true; do
    FLUID_PORT=$(aconnect -o | grep -i fluid | head -1 | awk '{print $2}' | tr -d ':')
    [ -z "$FLUID_PORT" ] && sleep 2 && continue
    
    aconnect -i | grep client | grep -v "System\|Timer\|Announce" | while read line; do
        PORT=$(echo "$line" | awk '{print $2}' | tr -d ':')
        aconnect -l | grep -q "$PORT.*$FLUID_PORT" || aconnect "$PORT" "$FLUID_PORT" 2>/dev/null || true
    done
    sleep 2
done
EOF

chmod +x /usr/local/bin/midi-autoconnect.sh

systemctl enable alsa-volume.service
systemctl enable fluidsynth.service
systemctl enable midi-connect.service
systemctl disable NetworkManager sshd bluetooth 2>/dev/null || true

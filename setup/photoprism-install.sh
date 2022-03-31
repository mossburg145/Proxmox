#!/usr/bin/env bash
set -o errexit 
set -o errtrace 
set -o nounset 
set -o pipefail 
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
trap 'die "Script interrupted."' INT

function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occured.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR:LXC] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON"
  exit $EXIT
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}

CROSS='\033[1;31m\xE2\x9D\x8C\033[0m'
RD=`echo "\033[01;31m"`
BL=`echo "\033[36m"`
CM='\xE2\x9C\x94\033'
GN=`echo "\033[1;92m"`
CL=`echo "\033[m"`
RETRY_NUM=10
RETRY_EVERY=3
NUM=$RETRY_NUM

echo -en "${GN} Setting up Container OS... "
sed -i "/$LANG/ s/\(^# \)//" /etc/locale.gen
locale-gen >/dev/null
while [ "$(hostname -I)" = "" ]; do
  1>&2 echo -en "${CROSS}${RD}  No Network! "
  sleep $RETRY_EVERY
  ((NUM--))
  if [ $NUM -eq 0 ]
  then
    1>&2 echo -e "${CROSS}${RD}  No Network After $RETRY_NUM Tries${CL}"    
    exit 1
  fi
done
echo -e "${CM}${CL} \r"
echo -en "${GN} Network Connected: ${BL}$(hostname -I)${CL} "
echo -e "${CM}${CL} \r"

echo -en "${GN} Updating Container OS... "
apt update &>/dev/null
apt-get -qqy upgrade &>/dev/null
echo -e "${CM}${CL} \r"

echo -en "${GN} Installing Dependencies... "
apt-get install -y curl &>/dev/null
apt-get install -y sudo &>/dev/null
apt-get install -y gcc &>/dev/null
apt-get install -y g++ &>/dev/null
apt-get install -y git &>/dev/null
apt-get install -y gnupg &>/dev/null
apt-get install -y make &>/dev/null
apt-get install -y zip &>/dev/null
apt-get install -y unzip &>/dev/null
echo -e "${CM}${CL} \r"

echo -en "${GN} Setting up Node.js Repository... "
sudo curl -sL https://deb.nodesource.com/setup_16.x | sudo -E bash - &>/dev/null
echo -e "${CM}${CL} \r"

echo -en "${GN} Installing Node.js... "
apt-get install -y nodejs &>/dev/null
echo -e "${CM}${CL} \r"

echo -en "${GN} Installing Golang... "
wget https://golang.org/dl/go1.18.linux-amd64.tar.gz &>/dev/null
tar -C /usr/local -xzf go1.18.linux-amd64.tar.gz &>/dev/null
ln -s /usr/local/go/bin/go /usr/local/bin/go &>/dev/null
echo -e "${CM}${CL} \r"

echo -en "${GN} Installing Tensorflow... "
AVX=$(grep -o -m1 'avx[^ ]*' /proc/cpuinfo)
if [[ "$AVX" == "avx2" ]]; then
  wget https://dl.photoprism.org/tensorflow/linux/libtensorflow-linux-avx2-1.15.2.tar.gz &>/dev/null
  tar -C /usr/local -xzf libtensorflow-linux-avx2-1.15.2.tar.gz &>/dev/null
  ldconfig &>/dev/null
  elif [[ "$AVX" == "avx" ]]; then
  wget https://dl.photoprism.org/tensorflow/linux/libtensorflow-linux-avx-1.15.2.tar.gz &>/dev/null
  tar -C /usr/local -xzf libtensorflow-linux-avx-1.15.2.tar.gz &>/dev/null
  ldconfig &>/dev/null
  else
  wget https://dl.photoprism.org/tensorflow/linux/libtensorflow-linux-cpu-1.15.2.tar.gz &>/dev/null
  tar -C /usr/local -xzf libtensorflow-linux-cpu-1.15.2.tar.gz &>/dev/null
  ldconfig &>/dev/null
fi
echo -e "${CM}${CL} \r"

echo -en "${GN} Cloning PhotoPrism... "
mkdir -p /opt/photoprism/bin
mkdir /var/lib/photoprism
git clone https://github.com/photoprism/photoprism.git &>/dev/null
cd photoprism
git checkout release &>/dev/null
echo -e "${CM}${CL} \r"

echo -en "${GN} Building PhotoPrism... "
make all &>/dev/null
./scripts/build.sh prod /opt/photoprism/bin/photoprism &>/dev/null
cp -a assets/ /opt/photoprism/assets/ &>/dev/null
echo -e "${CM}${CL} \r"

env_path="/var/lib/photoprism/.env"
echo " 
PHOTOPRISM_ADMIN_PASSWORD='admin'
PHOTOPRISM_STORAGE_PATH='/var/lib/photoprism'
PHOTOPRISM_ORIGINALS_PATH='/var/lib/photoprism/photos/Originals'
PHOTOPRISM_IMPORT_PATH='/var/lib/photoprism/photos/Import'
" > $env_path

echo -en "${GN} Creating Service file photoprism.service... "
service_path="/etc/systemd/system/photoprism.service"

echo "[Unit]
Description=PhotoPrism service
After=network.target

[Service]
Type=forking
User=root
WorkingDirectory=/opt/photoprism
EnvironmentFile=/var/lib/photoprism/.env
ExecStart=/opt/photoprism/bin/photoprism up -d
ExecStop=/opt/photoprism/bin/photoprism down

[Install]
WantedBy=multi-user.target" > $service_path
systemctl enable --now photoprism &>/dev/null
echo -e "${CM}${CL} \r"

PASS=$(grep -w "root" /etc/shadow | cut -b6);
  if [[ $PASS != $ ]]; then
echo -en "${GN} Customizing Container... "
rm /etc/motd
rm /etc/update-motd.d/10-uname
touch ~/.hushlogin
GETTY_OVERRIDE="/etc/systemd/system/container-getty@1.service.d/override.conf"
mkdir -p $(dirname $GETTY_OVERRIDE)
cat << EOF > $GETTY_OVERRIDE
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud tty%I 115200,38400,9600 \$TERM
EOF
systemctl daemon-reload
systemctl restart $(basename $(dirname $GETTY_OVERRIDE) | sed 's/\.d//')
echo -e "${CM}${CL} \r"
  fi
  
echo -en "${GN} Cleanup... "
apt-get autoremove >/dev/null
apt-get autoclean >/dev/null
rm -rf /var/{cache,log}/* /var/lib/apt/lists/* /root/go
echo -e "${CM}${CL} \n"

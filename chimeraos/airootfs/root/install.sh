cp __frzr-deploy /usr/bin/__frzr-deploy
chmod 777 /usr/bin/__frzr-deploy

if [ $EUID -ne 0 ]; then
    echo "$(basename $0) must be run as root"
    exit 1
fi

export first_install="True"

#### Test conenction or ask the user for configuration ####
CHOICE=$(whiptail --menu "How would you like to install ChimeraOS?" 18 50 10 \
  "local" "Use local media for installation." \
  "stable" "Fetch the latest stable image." \
  "unstable" "Fetch the latest unstable image." \
  "testing" "Fetch the latest testing image." \
  "unofficial" "Custom ChimeraOS branches" \
   3>&1 1>&2 2>&3)
echo $CHOICE
if [ -z "${CHOICE}" ]; then
  echo "No option was chosen (user hit Cancel)"
elif [ "${CHOICE}" != "local" ]; then
   nmtui-connect
   if [ "${CHOICE}" == "unofficial" ]; then
	REPO=$(whiptail --menu "Custom image options:" 18 50 10 \
 	 "samsagax" "image provided by Samsagax" \
  	 "alkazar" "image provided by Alkazar" \
 	 "ruineka" "image provided by Ruineka" \
  	 3>&1 1>&2 2>&3)
   
   CHANNEL=$(whiptail --menu "What channel should we target for updates?" 18 50 10 \
 	 "stable" "(recommended)" \
  	 "unstable" "(experimental)" \
 	 "testing" "(not-recommended)" \
 	  3>&1 1>&2 2>&3)
   fi
else
   CHANNEL=$(whiptail --menu "What channel should we target for updates?" 18 50 10 \
 	 "stable" "(recommended)" \
  	 "unstable" "(experimental)" \
 	 "testing" "(not-recommended)" \
 	  3>&1 1>&2 2>&3)
   
   if (whiptail --title "Steam requires an internet connection on first boot" --yesno "Are you using a Wifi connection?" 8 78); then
    nmtui-connect
   else
    whiptail --msgbox --title "Network Connection" "You have chosen to not setup wifi, you will need an Ethernet connection on your first boot" 18 50
   fi
fi


#######################################

if ! frzr-bootstrap gamer; then
    whiptail --msgbox "System bootstrap step failed." 10 50
    exit 1
fi

#### Post install steps for system configuration
# Copy over all network configuration from the live session to the system
MOUNT_PATH=/tmp/frzr_root
SYS_CONN_DIR="/etc/NetworkManager/system-connections"
if [ -d ${SYS_CONN_DIR} ] && [ -n "$(ls -A ${SYS_CONN_DIR})" ]; then
    mkdir -p -m=700 ${MOUNT_PATH}${SYS_CONN_DIR}
    cp  ${SYS_CONN_DIR}/* \
        ${MOUNT_PATH}${SYS_CONN_DIR}/.
fi

# Detect hybrid intel-nvidia setups
NVIDIA_BUSID=$(lspci -nm -d 10de: | \
    awk '{print $1 " " $2 " " $3}' | \
    grep -e 300 -e 302 | \
    awk '{print $1}' | \
    sed 's/\./:/' )
INTEL_BUSID=$(lspci -nm -d 8086: | \
    awk '{print $1 " " $2 " " $3}' | \
    grep -e 300 -e 302 | \
    awk '{print $1}' | \
    sed 's/\./:/' )

if [[ $INTEL_BUSID == ??:??:? && $NVIDIA_BUSID == ??:??:? ]] ; then
    if (whiptail --yesno "Intel/Nvidia hybrid graphics detected. Would you like to force use of Nvidia graphics?"); then
        echo "
Section \"ServerLayout\"
    Identifier \"layout\"
    Screen 0 \"iGPU\"
    Option \"AllowNVIDIAGPUScreens\"
EndSection

Section \"Screen\"
    Identifier \"iGPU\"
    Device \"iGPU\"
EndSection

Section \"Device\"
    Identifier \"iGPU\"
    Driver \"modesetting\"
    BusID \"${INTEL_BUSID}\"
EndSection

Section \"Device\"
    Identifier \"dGPU\"
    Driver \"nvidia\"
    BusID \"${NVIDIA_BUSID}\"
EndSection" > ${MOUNT_PATH}/etc/X11/xorg.conf.d/10-nvidia-prime.conf
    fi
fi

export SHOW_UI=1

if [ "${CHOICE}" != "local" ] || [ "${CHOICE}" != "custom" ]; then
  export offline_installer="False"
  frzr-deploy chimeraos/chimeraos:${CHOICE}
  RESULT=$?
fi


if [ "${CHOICE}" == "unofficial" ]; then
   export offline_installer="False"
   if [ ${REPO} == "samsagax" ]; then
      frzr-deploy samsagax/chimeraos:$CHANNEL
      RESULT=$?
   fi
   
   if [ ${REPO} == "alkazar" ]; then
      frzr-deploy alkazar/chimeraos:$CHANNEL
      RESULT=$?
   fi
   
   if [ ${REPO} == "ruineka" ]; then
      frzr-deploy ruineka/chimeraos:$CHANNEL
      RESULT=$?
   fi
  RESULT=$?
fi

if [ "${CHOICE}" == "local" ]; then
  export offline_installer="True"
  frzr-deploy ruineka/chimeraos:$CHANNEL
  RESULT=$?
fi


MSG="Installation failed. ${input} and ${CHOICE}"
if [ "${RESULT}" == "0" ]; then
    MSG="Installation successfully completed."
elif [ "${RESULT}" == "29" ]; then
    MSG="GitHub API rate limit error encountered. Please retry installation later."
fi

if (whiptail --yesno "${MSG}\n\nWould you like to restart the computer?" 10 50); then

    reboot
fi

exit ${RESULT}

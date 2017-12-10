#!/bin/bash
#
# requires
# - compiled version of adb under /usr/bin
# - apt-get install etherwake cec-utils
#

#
log_sw="no"   # no stdout
log="/usr/share/openhab2/log/tv_control.log"
#log="/dev/stdout"
#

#
# IP address and port for devices
#
tv_ip="192.168.6.20"        # IP address of the TV (device id 1)
tv_mac="1C:5A:6B:A9:CC:4D"  # MAC address of the TV (required to wake-on-lan"
fire_tv_ip="192.168.6.174"  # IP address of the Fire TV (device id 2)
port="5555"                 # Port for ADB service
use_cec=1                   # 1=use cec-client to control TV power on/off and HDMI channel select
cec_port=RPI                # HDMI device to use, use "cec-client -l" to find, usually RPI for the Pi HDMI port (com port: RPI), /dev/ttyXXX for an HDMI USB controller
hdmi_address_avr="10:00"    # HDMI device address, use sudo echo "scan" | cec-client -s -d 1 to find address, e.g. address "1.4.0.0" will be converted to 14:00
dev_id="1"
dev_status="n/a"
dsp_status="n/a"
tv_key=""

function e {
	echo $1 >> $log
}  

function adb_start {
	e Starting ADB Daemon...
	adb start-server >> $log
}

function adb_kill {
	adb kill-server >> $log
	e "ADB Daemon killed."
}

function adb_connect {
	if sudo adb devices | grep -q $uri; then
		e "Already connected to $uri"
	else
		# Connect to device, if failed exit script
		e "Connecting to $uri"
		#adb_kill
		adb connect $uri >> $log
		device_status
		if [ "$dev_status" == "ON" ]
		then
			sleep 2 &> /dev/null		# for timing
			display_status
		fi
	fi
}


# device_status: returns the device/connection status into dev_status ("ON"/"OFF")
function device_status {
	e "Check device status for $uri..."
	dev_status="OFF"
#	if [ "$use_cec" == "1" ]; then
#e "device_status: use_cec"
#		if echo pow 0 | cec-client -s -d 1 | grep -q 'power status: on'; then
#			dev_status="ON"
#		fi
#	else
	  	if adb devices | grep -q $uri; then
  			dev_status="ON"
		fi
#	fi
	e "Device Status=$dev_status"
}

function display_status {
	e "Check display status for $uri..."
	if adb -s $uri shell dumpsys power | grep -q 'Display Power: state=ON'; then
		dsp_status="ON"
    else
    	dsp_status="OFF"
    fi
	e "Display Status=$dsp_status"
}

function sendkey {
	e "Send keycode=$1"
	adb -s $uri shell input keyevent $1 >> $log
}

function dev_on {
	display_status
	if [ "$dsp_status" == "OFF" ]; then
		if [ "$dev_id" == "1" ]; then
			#wakeup the device
			wakeonlan $tv_mac
			if [ "$use_cec" == "1" ]; then
e "dev_on: use cec"
				echo on 0 | cec-client $cec_port -s -d 1
				sleep 2 #Adjust this if needed!
				device_status
				if [ "$dev_status" == "ON" ]; then
					adb_connect
				fi
				tvservice -o   # disable HDMI
			fi
			until ping -c1 $tv_ip &> $log; do :; done
			e "sleep 5sec"
			sleep 5
		else
e "dev_on: use adb"
			adb_connect
			sendkey 26		# Power Button
			sleep 2 #Adjust this if needed!
			display_status
			if [ "$dsp_status" == "OFF" ]; then
				sendkey 26		# Power Button
				dev_status
				display_status
			fi
		fi
	else
		e "Display is already ON"
	fi
}

function dev_off {
	display_status
	if [ "$dsp_status" == "OFF" ]; then
		e "Display is already OFF"
	else
   	    sendkey 26		# Power button
    fi
}

function send_button {
local keycode

	case "$1" in
		0) keycode=7;;
		1) keycode=8;;
		2) keycode=9;;
		3) keycode=10;;
		4) keycode=11;;
		5) keycode=12;;
		6) keycode=13;;
		7) keycode=14;;
		8) keycode=15;;
		9) keycode=16;;
	esac
	sendkey $keycode
}

function presskey {

	e "Press key(s) '$1'"
	key1=${1:0:1}
	key2=${1:1:1}
	key3=${1:2:1}
	e "Key1='$key1', Key2='$key2', Key3='$key3'"
	send_button $key1
	send_button $key2
	send_button $key3
}

function usage {
	echo
	echo "Usage: tv_control.sh <command> [<device id>[log | trace | debug]]"
	echo
	echo "Valid commands:"
	echo "	status:  return device status - ON/OFF"
	echo "	on:      switch device ON"
	echo "	off:     switch device OFF"
	echo "  presskey:send key code to device (code according Android key codes"
	echo "	sleep:   switch device to sleep mode (you have to check if sleep or soft_sleep works with your device)"
	echo "	suspend: switch device to soft-sleep mode (you have to check if sleep or soft_sleep works with your device)"
	echo "	resume:  (try to) wakeup device (doesn't work if device is powered off)"
	echo "	avr:     speical: switch to HDMI1 on Philips TV to select AVR"
	echo
	echo "	netflix: Open the NetFlix App"
	echo "	tvguide: Open the TV Guide App"
	echo "	videotext: Open the Videotext App"
	echo
	echo "	see script code for key commands (simulate remote keys)"
	echo
	echo "Device IDs:"
	echo "	1: TV@$tv_ip:$port"
	echo "	2: Fire-TV@$fire_tv_ip:$port"
	echo "	Default IP=$tv_ip; Default Port=$port (see script)"
	echo
	echo "Debugging":
	echo "	log      Enable logging to stdout"
	echo "	trace    Enable ADB trace (output will be redirected to logfile)"
	echo "	debug    Enable ADB debugging (output will be redirected to logfile)"
	echo
	echo "Examples:"
	echo "	sudo ./tv_control.sh on (uses default IP $tv_ip - see script)"
	echo "	sudo ./tv_control.sh home (send HOME key to device)"
	echo "	sudo ./tv_control.sh sleep 192.168.1.1"
	echo
	echo "Note:"
	echo "	Logfile: $log"
	echo "	The scripts writes log messages to $log - change $$log in script if you don't have privileges there"
	echo
}


#export >> $log	# dump environment, e.g. user (privileges)

if [ "$1" == "" ]
then
	usage
	exit 1
fi
if [ "$1" == "--help" ]
then
	usage
	exit 1
fi


#
# tv_control
#
echo TV Control: $1 $2 $3> $log  # clear log

cmd="$1"
shift
if [ "$cmd" == "presskey" ]
then
	e "Press key '$1'"
	tv_key="$1"
	shift
fi

# build URI from device ip and port (5555)
dev_id="$1"
case $dev_id in
	"1") ip=$tv_ip;;          # TV
	"2") ip=$fire_tv_ip;;     # Fire-TV
	"")  ip=$tv_ip;;          # default = TV
esac
shift
uri="$ip:$port"
case $1 in
	"log")    log="/dev/stdout"; log_sw="yes";;
	"trace")  export ADB_TRACE=1;;
	"debug")  export ADB_TRACE=1;;
esac

# If not yet connected start ADB server and connect to device
# maybe it needs some more error handling
e "TV Control (IP=$uri): $1"
if [ "$cmd" == "check" ]
then
	device_status
	display_status
	echo "$dev_status"
	exit
fi
adb_connect
if [ "$device_status" == "OFF" ]
then
	e "Unable to connect to device."
	e "ADB Log:"
	if [ "$log_sw" == "yes" ]
	then
		cat "$log"
	fi
	exit 1
fi

#
# process command
#	
case "$cmd" in
	"status")	# Display status
    	display_status
		echo "$dsp_status";;

	"on")
		dev_on
		device_status
		echo "$dev_status";;

	"off")
		dev_off
		echo "$dsp_status";;

	"tv")
		dev_on
		sendkey 170		# TV Button
		display_status
		echo "$dsp_status";;

	"avr")
		dev_on
		if [ "$use_cec" == "1" ]; then
			e "Switch HDMI to address $hdmi_address_avr"
			e "tx 2F:82:$hdmi_address_avr"
			echo "tx 2F:82:$hdmi_address_avr" | cec-client $cec_port -s -d 1
			echo "tx 2F:82:$hdmi_address_avr" | cec-client $cec_port -s -d 1
		else
			adb -s $uri shell "input keyevent 178 && input keyevent 122 && input keyevent 122 && input keyevent 122 && input keyevent 20 && input keyevent 20 && input keyevent 20 && input keyevent 20 && input keyevent 20 && input keyevent 66"
		fi;;

	"ping")
		device_status
		if [ "$dev_status" == "ON" ]
		then
		 	sendkey 223  		# Sleep Button
			echo "ON"
		else
			echo "OFF"
		fi;;

	"netflix")
		dev_on
		adb -s $uri shell "am start -n com.netflix.ninja/com.netflix.ninja.MainActivity";;
	"tvguide")
		dev_on
		adb -s $uri shell "am start -n org.droidtv.epg/org.droidtv.epg.bcepg.epgui.NonZiggo";;
	"videotext")
		dev_on
		adb -s $uri shell "am start -n org.droidtv.teletext/org.droidtv.teletext.teletextfullscreen.TeletextFullscreen";;


	"power")      sendkey 26;;		# Power Button
	"sleep")      sendkey 223;;		# Sleep Button
	"suspend")    sendkey 276;;		# Soft Sleep Button
	"resume")     sendkey 224;;     # Wakeup Button	
	"pairing")    sendkey 225;;		# Pairing Button
	"settings")   sendkey 176;;		# Settings Button
	"presskey")   presskey $tv_key;;

    "input")      sendkey 178;;		# Source TV
    "sat")        sendkey 237;;		# Source SAT
    "hdmi1")      sendkey 243;;		# Source HDMI1
    "hdmi2")      sendkey 244;;		# Source HDMI2
    "hdmi3")      sendkey 245;;		# Source HDMI3
    "hdmi4")      sendkey 246;;		# Source HDMI4
    "composite1") sendkey 247;;		# Source Compsite1
    "composite2") sendkey 248;;		# Source Compsite2
    "component1") sendkey 249;;		# Source Component1
    "component2") sendkey 250;;		# Source Component2
    "vga")        sendkey 251;;		# Source VGA
    "text")       sendkey 233;;		# Source Video-Text

    "home")       sendkey 3;;		# Home Button
    "menu")       sendkey 82;;		# Menu Button
    "back")       sendkey 4;;		# Back Button
    "top")        sendkey 122;;		# Top Button
    "end")        sendkey 123;;		# End Button
    "enter")      sendkey 66;;		# Enter Button
    "up")         sendkey 19;;		# UP Button
    "down")       sendkey 20;;		# DOWN Button
    "left")       sendkey 21;;		# LEFT Button
    "right")      sendkey 22;;		# RIGHT Button
    "sysup")      sendkey 280;;		# SysUp Button
    "sysdown")    sendkey 281;;		# SysDown Button
    "sysleft")    sendkey 282;;		# SysLeft Button
    "sysright")   sendkey 283;;		# SysRight Button
  
    "blue")       sendkey 186;;		# Blue Button
    "green")      sendkey 184;;		# Green Button
    "red")        sendkey183;;		# Red Button
    "yellow")     sendkey 185;;		# Yellow Button
    "move_home")  sendkey 122;;		# MoveHome Button
    "search")     sendkey 84;;		# Search Button

	"volup")      sendkey 24;;		# VolUp Button
	"voldown")    sendkey 25;;		# VolDown Button
	"mute")       sendkey 164;;		# Mute Button

    "lastch")     sendkey 229;;		# LastChannel Button

	"kill")       adb_kill;;		# Kill ADB
	"start")      adb_start;;		# Start ADB

	*)            echo "Unknown command: $cmd"; exit;;
esac

exit 0


#!/bin/sh

### Matthias Strubel (c)2014 via GPL3
##    Autobuild and deploy script for PirateBox environment
##    with upload via lftp to a remove webside
##
##   Add it to /etc/rc.local or equivalent
##   To start manual and skip wait time and auto shutdown
##     run it like
##       # ./start_autobuild.sh go
##

## Server specific thread count
THREADS=$(grep processor  /proc/cpuinfo | wc -l)

## File that stops the automatic script, that you are able to do
##  work on the server, when the script autostarts.
exit_file=/tmp/no_build.semaphore
# Wait time before starting , this is needed for running in rc.local
auto_start_wait=1
# Shutdown after build is completed
shutdown="no"

# Build each arch on OpenWrt / LEDE
# --------------------------------- 
#  Currently the configuration file handling for the LEDE/openwrt build chain is not
#  optimal. For some reason, it happens that packages are missing between the archs.
#  As we do not have binary packages in the current build, we can just use one
#  build.
#  For LibraryBox this is not sufficient, because proftpd is currently needed.
build_each_arch="no"

deploy_folder=/tmp/deploy
log_folder=${deploy_folder}/log
build_log=${log_folder}/build.log
collect_log=${log_folder}/collect.log
package_destination=${deploy_folder}
package_destination_all=${deploy_folder}/all

## Adjust this path where your openwrt-dev-enfironment stuff is located
build_env=/home/admin/auto_build/openwrt-dev-environment

screen_cmd="screen -L -Dm -c ~/auto_screenrc"


target_list="ar71xx_generic ramips_mt7620"
set_target(){
   if [ "$1"  = "ar71xx_generic" ] ; then
	TARGET="ar71xx"
	TARGET_TYPE="generic"
	PARCH="mips_24kc"
   fi
   if [ "$1"  = "ramips_mt7620" ] ; then
	TARGET="ramips"
	TARGET_TYPE="mt7620"
	PARCH="mipsel_24kc"
   fi
}


if [ -z $1 ] ; then
	sleep $auto_start_wait
fi

if [ -e $exit_file ] ; then
	echo "Exit file ${exit_file} found. exiting"
	rm -v $exit_file
	exit 0
fi

#Empty deploy folder
[ -d $log_folder ] && rm  -rv  $log_folder
[ -d $deploy_folder ] && rm -rv  $deploy_folder
mkdir $deploy_folder
mkdir $log_folder


### Build
cd $build_env 
echo "##### Make clean" 
make clean 
rm -v openwrt-image-build/piratebox_ws_*_img.tar.gz
cd PirateBoxScripts_Webserver/  
make clean
echo "##### Make refresh_local_feeds ; Refresh repositories"
cd $build_env
$screen_cmd  make refresh_local_feeds
echo "##### Make auto_build_development"
cd $build_env

if [ "$build_each_arch" = "yes" ] ; then
    first="yes"
    for target in $target_list ; do
        set_target "${target}"
        if [ "$first" = "no" ] ; then
            build_target="auto_build_development_short"
        else
            build_target="auto_build_development"
            first="no"
        fi
        $screen_cmd make "$build_target" THREADS=$THREADS TARGET="$TARGET" TARGET_TYPE="$TARGET_TYPE" PARCH="$PARCH"
    done
else
    set_target "ar71xx_generic"
    build_target="auto_build_development"
    $screen_cmd make "$build_target" THREADS=$THREADS TARGET="$TARGET" TARGET_TYPE="$TARGET_TYPE" PARCH="$PARCH"
fi


RC=$?
cd $build_env/PirateBoxScripts_Webserver/
make package

## Collect
if [ $RC -eq 0 ] ; then
	mkdir "$package_destination" 2>&1 >> "$collect_log"

	#last ARCH is sufficient
	cp -rv  "$build_env/openwrt/bin/packages/$PARCH/piratebox" "$package_destination_all/" 2>&1 >> "$collect_log"

	for target in $target_list ; do
		set_target "${target}"
		# one arch can be used for multiple targets
		if test ! -d  "$package_destination/$PARCH" ; then
			mkdir -p "$package_destination/$PARCH"  2>&1 >> "$collect_log"
			cp -rv  "$build_env/openwrt/bin/packages/$PARCH/old_packages" "$package_destination/$PARCH/"  2>&1 >> "$collect_log"
		fi
	done
	cp -rv  $build_env/openwrt-image-build/target_* $deploy_folder 2>&1 >> $collect_log
	cp  $build_env/PirateBoxScripts_Webserver/piratebox*.tar.gz $deploy_folder  2>&1 >> $collect_log

    find "$deploy_folder" -name install -exec rm -r {} \;
	find "$deploy_folder" -type d -exec sh -c "echo 'IndexOptions NameWidth=*' > {}/.htaccess" \;

fi


### Deploy
. $build_env/ftp_config.sh
LCD="$deploy_folder"
lftp -c "set ftp:list-options -a;
set ftp:ssl-allow  false
open '$FTPURL';
lcd $LCD;
cd $RCD;
mirror --reverse \
       $DELETE \
       --verbose \
       --exclude-glob a-dir-to-exclude/ \
       --exclude-glob a-file-to-exclude \
       --exclude-glob a-file-group-to-exclude* \
       --exclude-glob other-files-to-exclude"


if [ "$shutdown" = "yes"  ] ; then
	sudo shutdown -h now
fi

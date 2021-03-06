#!/bin/bash

DATE_TIME=`date +"%Y%m%d-%H%M"`


IMAGES_DIR="/home/xiangfu/building/Milkymist/milkymist-firmware-${DATE_TIME}"
DEST_DIR="/home/xiangfu/build-milkymist"
mkdir -p ${IMAGES_DIR}
mkdir -p ${DEST_DIR}


BUILD_LOG="${IMAGES_DIR}/BUILD_LOG"
VERSIONS="${IMAGES_DIR}/VERSIONS"
touch ${BUILD_LOG} ${VERSIONS}


MILKYMIST_GIT_DIR=/home/xiangfu/milkymist-firmware/milkymist
SCRIPTS_GIT_DIR=/home/xiangfu/milkymist-firmware/scripts


MD5_BINARIES="bios.bin bios-rescue.bin boot.bin data.flash5.bin flickernoise flickernoise.bin flickernoise.fbi soc.fpg soc-rescue.fpg splash.raw splash-rescue.raw standby.fpg"


abort() {
	tail -n 100 ${IMAGES_DIR}/BUILD_LOG > ${IMAGES_DIR}/BUILD_LOG.`date +"%m%d%Y-%H%M"`.last100
	echo "$1"
	exit 1
}

get-feeds-revision() {
    if [ -d "$1" ]; then
        cd $1
        repo=$(git config -l | grep remote.origin.url | cut -d "=" -f 2)
        rev=$(git log | head -n 1 | cut -b8-)
        branch=$(git branch | grep "*" | cut -b3-)
        echo "${repo}  ${branch} ${rev}" >> ${VERSIONS}
    fi
}


RTEMS_MAKEFILE_PATH=/opt/rtems-4.11/lm32-rtems4.11/milkymist
export RTEMS_MAKEFILE_PATH

PATH=/opt/rtems-4.11/bin:${PATH}
export PATH


echo "update git ..."
(cd ${SCRIPTS_GIT_DIR} && git fetch -a && git reset --hard origin/master)
#make -C ${SCRIPTS_GIT_DIR}/compile-flickernoise/ milkymist-git-clone #no needs every build
MILKYMIST_GIT_DIR=${MILKYMIST_GIT_DIR}  make -C ${SCRIPTS_GIT_DIR}/compile-flickernoise/ milkymist-git-update
if [ "$?" != "0" ]; then
	abort "ERROR: milkymist-git-update"
fi


echo "handle werner's patches on rtems ..."
if [ ! -e ${MILKYMIST_GIT_DIR}/wernermisc ]; then
	git clone git://projects.qi-hardware.com/wernermisc.git ${MILKYMIST_GIT_DIR}/wernermisc
fi
(cd ${MILKYMIST_GIT_DIR}/wernermisc && git fetch -a && git reset --hard origin/master)
#(cd ${MILKYMIST_GIT_DIR}/rtems && git reset --hard 2cc4f3ca45e5cb20649c2733330977a2307e2e19)
(cd ${MILKYMIST_GIT_DIR}/rtems && rm -f patches && ln -s ${MILKYMIST_GIT_DIR}/wernermisc/m1/patches/rtems patches)
(cd ${MILKYMIST_GIT_DIR}/rtems && quilt pop -a -f && quilt push -a)
(cd ${MILKYMIST_GIT_DIR}/rtems && git diff > ${IMAGES_DIR}/rtems.on.f80b3a3.diff)


echo "update doc repo ..."
(cd ${MILKYMIST_GIT_DIR}/flickernoise-handbook && git fetch -a && git reset --hard origin/master)


echo "get git versions ..."
get-feeds-revision ${MILKYMIST_GIT_DIR}/autotest-m1
get-feeds-revision ${MILKYMIST_GIT_DIR}/flickernoise
get-feeds-revision ${MILKYMIST_GIT_DIR}/flickernoise-handbook
get-feeds-revision ${MILKYMIST_GIT_DIR}/liboscparse
get-feeds-revision ${MILKYMIST_GIT_DIR}/milkymist
get-feeds-revision ${MILKYMIST_GIT_DIR}/mtk
get-feeds-revision ${MILKYMIST_GIT_DIR}/rtems
get-feeds-revision ${MILKYMIST_GIT_DIR}/rtems-yaffs2
get-feeds-revision ${MILKYMIST_GIT_DIR}/wernermisc
get-feeds-revision ${SCRIPTS_GIT_DIR}/


VERSIONS_NEW=`cat ${VERSIONS}`
VERSIONS_OLD=`cat ${IMAGES_DIR}/../firmware-VERSIONS`
if [ "${VERSIONS_NEW}" == "${VERSIONS_OLD}" ]; then
	echo "No new commit, ignore build"
	rm -f ${IMAGES_DIR}/*
	rmdir ${IMAGES_DIR}
	exit 0
fi
cp ${VERSIONS} ${IMAGES_DIR}/../firmware-VERSIONS


echo "compile toolchain ..."
rm -rf /opt/rtems-4.11/
make -C ${SCRIPTS_GIT_DIR}/compile-lm32-rtems clean all >> ${BUILD_LOG} 2>&1
if [ "$?" != "0" ]; then
	abort "ERROR: compile-lm32-rtems toolchain "
fi


echo "compile tools ..."
make -C ${MILKYMIST_GIT_DIR}/milkymist clean tools >> ${BUILD_LOG} 2>&1
if [ "$?" != "0" ]; then
	abort "ERROR: milkymist/tools"
fi


echo "compile soc ..."
#the Xilinx libs(libstdc++.so.6) have some conflict
(source ~/.bashrc && \
 source /home/Xilinx/13.4/ISE_DS/settings64.sh && \
 make -C ${MILKYMIST_GIT_DIR}/milkymist/boards/milkymist-one/flash)  >> ${BUILD_LOG} 2>&1
if [ "$?" != "0" ]; then
	abort "ERROR: compile SOC"
fi
cp ${MILKYMIST_GIT_DIR}/milkymist/boards/milkymist-one/flash/standby.fpg ${IMAGES_DIR}
cp ${MILKYMIST_GIT_DIR}/milkymist/boards/milkymist-one/flash/soc.fpg ${IMAGES_DIR}
cp ${MILKYMIST_GIT_DIR}/milkymist/boards/milkymist-one/flash/bios.bin ${IMAGES_DIR}
cp ${MILKYMIST_GIT_DIR}/milkymist/boards/milkymist-one/flash/splash.raw ${IMAGES_DIR}
cp ${MILKYMIST_GIT_DIR}/milkymist/boards/milkymist-one/flash/soc-rescue.fpg ${IMAGES_DIR}
cp ${MILKYMIST_GIT_DIR}/milkymist/boards/milkymist-one/flash/bios-rescue.bin ${IMAGES_DIR}
cp ${MILKYMIST_GIT_DIR}/milkymist/boards/milkymist-one/flash/splash-rescue.raw ${IMAGES_DIR}
BIOS_LEN=`ls -l  ${IMAGES_DIR}/bios-rescue.bin  | awk '{printf "%d\n",$5-4}'`
dd if=${IMAGES_DIR}/bios-rescue.bin of=${IMAGES_DIR}/bios-rescue-without-CRC.bin bs=1 count=${BIOS_LEN}


echo "compile flickernoise ..."
export PATH=${MILKYMIST_GIT_DIR}/milkymist/tools:$PATH
export PATH=/home/xiangfu/openwrt-xburst.full_system/staging_dir/host/bin:$PATH  #for autoconf 2.68
MILKYMIST_GIT_DIR=${MILKYMIST_GIT_DIR} make -C ${SCRIPTS_GIT_DIR}/compile-flickernoise \
  clean flickernoise.fbi >> ${BUILD_LOG} 2>&1
if [ "$?" != "0" ]; then
	abort "ERROR: compile flickernoise"
fi
cp ${MILKYMIST_GIT_DIR}/flickernoise/src/bin/* ${IMAGES_DIR}/


echo "compile autotest ..."
MILKYMIST_GIT_DIR=${MILKYMIST_GIT_DIR} IMAGES_DIR=${IMAGES_DIR} make -C ${SCRIPTS_GIT_DIR}/compile-flickernoise \
  boot.bin boot.crc.bin >> ${BUILD_LOG} 2>&1
if [ "$?" != "0" ]; then
	(cd /opt/ && tar cjvf ${IMAGES_DIR}/Flickernoise-lm32-rtems-4.11-SDK-for-Linux-x86_64.tar.bz2 rtems-4.11/)
	abort "ERROR: compile autotest"
fi
cp ${MILKYMIST_GIT_DIR}/autotest-m1/src/boot*.bin ${IMAGES_DIR}/


echo "build data patitions ..."
mkdir -p ${IMAGES_DIR}/data.flash5/patchpool
make -C ${MILKYMIST_GIT_DIR}/flickernoise/patches/demo/pacman
(cd ${MILKYMIST_GIT_DIR}/flickernoise/patches/demo/wheel && ./gen)
find ${MILKYMIST_GIT_DIR}/flickernoise/patches/ \( -name *.fnp -o -name *.jpg -o -name *.png \) -exec cp {} ${IMAGES_DIR}/data.flash5/patchpool/ \;
rm ${IMAGES_DIR}/data.flash5/patchpool/raindance.fnp

make -C ${MILKYMIST_GIT_DIR}/rtems-yaffs2/utils nor-mkyaffs2image

${MILKYMIST_GIT_DIR}/rtems-yaffs2/utils/nor-mkyaffs2image \
  ${IMAGES_DIR}/data.flash5 ${IMAGES_DIR}/data.flash5.bin convert  >> ${BUILD_LOG} 2>&1
chmod 644 ${IMAGES_DIR}/data.flash5.bin


echo "generate md5sum ..."
(cd ${IMAGES_DIR} && md5sum --binary ${MD5_BINARIES} > ${IMAGES_DIR}/md5sums)


echo "copy rtems patches ..."
cp -a ${MILKYMIST_GIT_DIR}/wernermisc/m1/patches/rtems ${IMAGES_DIR}/rtems-patches


echo "create SDK ..."
(cd /opt/ && tar cjvf ${IMAGES_DIR}/Flickernoise-lm32-rtems-4.11-SDK-for-Linux-x86_64.tar.bz2 rtems-4.11/)


echo "compiling doc ..."
mkdir -p ${IMAGES_DIR}/doc
make -C ${MILKYMIST_GIT_DIR}/flickernoise-handbook clean all
mv ${MILKYMIST_GIT_DIR}/flickernoise-handbook/*.pdf ${IMAGES_DIR}/doc
yes "" | make -C ${MILKYMIST_GIT_DIR}/flickernoise/src/compiler/doc clean all
mv ${MILKYMIST_GIT_DIR}/flickernoise/src/compiler/doc/midi.pdf ${IMAGES_DIR}/doc


(cd ${IMAGES_DIR} && bzip2 -z BUILD_LOG;)
mv ${IMAGES_DIR} ${DEST_DIR}

echo "DONE!"

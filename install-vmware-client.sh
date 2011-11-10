#! /bin/bash
#
# Copyright (C) 2011  Olle Lundberg
#
# Author: Olle Lunderg (olle@redhat.com)
# Author: Olle Lunderg (geek@nerd.sh)
#
# This script reflects my personal standpoint and should not
# be confused with the views or standpoints of my employer.
#
# This script is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public
# License as published by the Free Software Foundation; either
# version 3.0 of the License, or (at your option) any later version.
#
# This script is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
# Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this script; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301 USA



ALIEN="alien_8.85.tar.gz"
ALIEN_URL="http://ftp.de.debian.org/debian/pool/main/a/alien/${ALIEN}"
ALIEND_DEPS="rpm-build"
HP_THIN_CLIENT="sp52674.exe"
HP_THIN_CLIENT_URL="ftp://ftp.hp.com/pub/softpaq/sp52501-53000/$HP_THIN_CLIENT"
HP_THIN_CLIENT_DEPS="p7zip p7zip-plugins"
DOT_DESKTOP="/usr/share/applications/vmware-view.desktop"
REMOVE="true"
WORKDIR=$(mktemp -d)
YES=""

array_push()
{
    name=$1
    value=$2
    eval index=\$\{\#$name\[\@\]\}
    eval $name\[\$index\]=\"$value\"
}

function print_synopsis() {
cat <<EOD
This script is a quick and fugly hack to install the vmware
view client on rhel6.  This is risky business. YMMV

EOD
}

function print_usage() {
cat <<EOD
$(basename ${0}) [OPTION]

$(print_synopsis)
Default behaviour is running the all of the actions switches
in the order specified below (except for -r)

Actions to take
-z          install p7zip
-d          download HP ThinClient
-e          extract the HP ThinClient
-a          download and install alien
-c          convert the view client package from a deb to rpm
-i          install the generated rpm using yum (*not done by default*)
-r          removes the rpm and every other hack done by this script
            if -r is specified all other actions get purged from the
            run queue and only the remove functionality is ran.
            (this might be dangerous since there are script symlinks
            being done by the script.)

Script configurations
-k          keep the tepmorary workspace after exiting.
-w  VALUE   use this folder as the workspace (also sets the -k flag)
-h          prints this help.
-y          assume yes on all questions

EOD
}

while getopts "kzdeaciryw:h" OPT; do
	case "${OPT}" in
        k)
            REMOVE="false"
        ;;
        z)
            array_push FUNCS install_7zip
        ;;
        d)
            array_push FUNCS download_client
        ;;
        e)
            array_push FUNCS extract_client
        ;;
        a)
            array_push FUNCS install_alien
        ;;
        c)
            array_push FUNCS convert_client	
        ;;
        i)
            array_push FUNCS install_rpm
        ;;
        r)
            FUNCS=(remove_rpm)
            break
        ;;
        w)
            WORKDIR=${OPTARG}
            REMOVE="false"
        ;;
        h)
            print_usage
            exit 0
        ;;
        y)
            YES="-y"
        ;;
        *)
            print_usage
            exit 2
        ;;
	esac
done

[[ "${#FUNCS[@]}" = 0 ]] && FUNCS=( ensure_root install_7zip download_client extract_client install_alien convert_client ) 


pushd $WORKDIR >>/dev/null

function cleanup() {
	if [[ "${REMOVE}" == "true" ]];then
		echo -e "\nCleaning up workdir: ${WORKDIR}"
		rm -rf "${WORKDIR}"
	else 
		echo -e "\nNot cleaning up workdir: ${WORKDIR}"
	fi
    exit $1
}

trap cleanup 1 2 3 15 ERR


function ensure_root() {
	MESSAGE=${1:-"run this script."}
	if [[ $EUID -ne 0 ]]; then
	   echo "I need root privileges to ${MESSAGE}" 1>&2
	   exit 1
	fi
}

function install_7zip() {
	ensure_root "install 7zip with dependencies."
	yum install "${YES}" ${HP_THIN_CLIENT_DEPS}
}

function download_client() {
	wget "${HP_THIN_CLIENT_URL}"
}

function extract_client() {
	7za e "${HP_THIN_CLIENT}"
}

function install_alien() {
	ensure_root "install alien with dependencies"
	yum install "${YES}" "${ALIEND_DEPS}"
	wget "${ALIEN_URL}"
	tar xf "${ALIEN}"
}

function convert_client() {
	PERL5LIB=./alien alien/alien.pl -r vmware-view-client*.deb
}

function install_rpm() {
	ensure_root "install the vmware client rpm"
	yum install ${YES} openssl098e.i686
	ln -s /usr/lib/libcrypto.so.0.9.8e /usr/lib/libcrypto.so.0.9.8
	rpm -ivh --nodeps vmware-view-client*.rpm
	mkdir -p /usr/bin/libdir/lib/libcrypto.so.0.9.8
	ln -s /usr/lib/libcrypto.so.0.9.8 /usr/bin/libdir/lib/libcrypto.so.0.9.8/libcrypto.so.0.9.8
	ln -s /usr/lib/vmware/vmware-view-usb /etc/vmware/usb.link
    mv /usr/share/pixmaps/view.{ico,png}
(cat <<EOD
[Desktop Entry]
Encoding=UTF-8
Type=Application
Icon=view
Exec=vmware-view
Categories=Application;Network;
Name=VMware View Client
EOD
) > "${DOT_DESKTOP}"
}

function remove_rpm() {
    ensure_root "to remove the vmware client rpm"
    rm -rf /usr/bin/libdir/lib/libcrypto.so.0.9.8
    rm -f /etc/vmware/usb.link
    mv /usr/share/pixmaps/view.{png,ico}
    rpm -e $(rpm -qa vmware-view-client)
    rm -f "${DOT_DESKTOP}"
}

print_synopsis

[[ -z "${YES}" ]] && read -n1 -p 'Ready to run script. Do you want to continue (y/N) ' -e CONFIRMATION

if [[ "${CONFIRMATION}"  == y || -n "${YES}" ]]; then
	for FUNC in ${FUNCS[@]}; do
        echo "-----------------------------------------------------"
		"$FUNC"
		EXIT_CODE=$?
		if [[ $EXIT_CODE -ne 0 ]]; then
			echo "Something went wrong, cowardly refusing to continue!"
			cleanup 3
		fi
	done
fi

popd >>/dev/null
cleanup 0

#!/usr/bin/env bash
# shellcheck disable=SC1090

is_command() {
    # Checks for existence of string passed in as only function argument.
    # Exit value of 0 when exists, 1 if not exists. Value is the result
    # of the `command` shell built-in call.
    local check_command="$1"

    command -v "${check_command}" >/dev/null 2>&1
}


distro_check() {
# If apt-get is installed, then we know it's part of the Debian family
if is_command apt-get ; then
    # Set some global variables here
    # We don't set them earlier since the family might be Red Hat, so these values would be different
    PKG_MANAGER="apt-get"
    # A variable to store the command used to update the package cache
    UPDATE_PKG_CACHE="${PKG_MANAGER} update"
    # An array for something...
    PKG_INSTALL=(${PKG_MANAGER} --yes --no-install-recommends install)
    # grep -c will return 1 retVal on 0 matches, block this throwing the set -e with an OR TRUE
    PKG_COUNT="${PKG_MANAGER} -s -o Debug::NoLocking=true upgrade | grep -c ^Inst || true"
    # Some distros vary slightly so these fixes for dependencies may apply
    # on Ubuntu 18.04.1 LTS we need to add the universe repository to gain access to dialog and dhcpcd5
    APT_SOURCES="/etc/apt/sources.list"
    if awk 'BEGIN{a=1;b=0}/bionic main/{a=0}/bionic.*universe/{b=1}END{exit a + b}' ${APT_SOURCES}; then
        if ! whiptail --defaultno --title "Dependencies Require Update to Allowed Repositories" --yesno "Would you like to enable 'universe' repository?\\n\\nThis repository is required by the following packages:\\n\\n- dhcpcd5\\n- dialog" ${r} ${c}; then
            printf "  %b Aborting installation: dependencies could not be installed.\\n" "${CROSS}"
            exit # exit the installer
        else
            printf "  %b Enabling universe package repository for Ubuntu Bionic\\n" "${INFO}"
            cp ${APT_SOURCES} ${APT_SOURCES}.backup # Backup current repo list
            printf "  %b Backed up current configuration to %s\\n" "${TICK}" "${APT_SOURCES}.backup"
            add-apt-repository universe
            printf "  %b Enabled %s\\n" "${TICK}" "'universe' repository"
        fi
    fi
    # Debian 7 doesn't have iproute2 so if the dry run install is successful,
    if ${PKG_MANAGER} install --dry-run iproute2 > /dev/null 2>&1; then
        # we can install it
        iproute_pkg="iproute2"
    # Otherwise,
    else
        # use iproute
        iproute_pkg="iproute"
    fi
    # Check for and determine version number (major and minor) of current php install
    if is_command php ; then
        printf "  %b Existing PHP installation detected : PHP version %s\\n" "${INFO}" "$(php <<< "<?php echo PHP_VERSION ?>")"
        printf -v phpInsMajor "%d" "$(php <<< "<?php echo PHP_MAJOR_VERSION ?>")"
        printf -v phpInsMinor "%d" "$(php <<< "<?php echo PHP_MINOR_VERSION ?>")"
        # Is installed php version 7.0 or greater
        if [ "${phpInsMajor}" -ge 7 ]; then
            phpInsNewer=true
        fi
    fi
    # Check if installed php is v 7.0, or newer to determine packages to install
    if [[ "$phpInsNewer" != true ]]; then
        # Prefer the php metapackage if it's there
        if ${PKG_MANAGER} install --dry-run php > /dev/null 2>&1; then
            phpVer="php"
        # fall back on the php5 packages
        else
            phpVer="php5"
        fi
    else
        # Newer php is installed, its common, cgi & sqlite counterparts are deps
        phpVer="php$phpInsMajor.$phpInsMinor"
    fi
    # We also need the correct version for `php-sqlite` (which differs across distros)
    if ${PKG_MANAGER} install --dry-run ${phpVer}-sqlite3 > /dev/null 2>&1; then
        phpSqlite="sqlite3"
    else
        phpSqlite="sqlite"
    fi
    # Since our install script is so large, we need several other programs to successfully get a machine provisioned
    # These programs are stored in an array so they can be looped through later
    INSTALLER_DEPS=(apt-utils dialog debconf dhcpcd5 git ${iproute_pkg} whiptail)
    # Pi-hole itself has several dependencies that also need to be installed
    PIHOLE_DEPS=(cron curl dnsutils iputils-ping lsof netcat psmisc sudo unzip wget idn2 sqlite3 libcap2-bin dns-root-data resolvconf libcap2)
    # The Web dashboard has some that also need to be installed
    # It's useful to separate the two since our repos are also setup as "Core" code and "Web" code
    PIHOLE_WEB_DEPS=(lighttpd ${phpVer}-common ${phpVer}-cgi ${phpVer}-${phpSqlite})
    # The Web server user,
    LIGHTTPD_USER="www-data"
    # group,
    LIGHTTPD_GROUP="www-data"
    # and config file
    LIGHTTPD_CFG="lighttpd.conf.debian"

    # A function to check...
    test_dpkg_lock() {
        # An iterator used for counting loop iterations
        i=0
        # fuser is a program to show which processes use the named files, sockets, or filesystems
        # So while the command is true
        while fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
            # Wait half a second
            sleep 0.5
            # and increase the iterator
            ((i=i+1))
        done
        # Always return success, since we only return if there is no
        # lock (anymore)
        return 0
    }

# If apt-get is not found, check for rpm to see if it's a Red Hat family OS
elif is_command apk ; then

  printf "  %b OS distribution supported\\n"

# If neither apt-get or yum/dnf package managers were found
else
    # it's not an OS we can support,
    printf "  %b OS distribution not supported\\n" "${CROSS}"
    # so exit the installer
    exit
fi
}
distro_check

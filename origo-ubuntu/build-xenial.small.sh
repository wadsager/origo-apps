#!/bin/bash

# The version of the app we are building
version="1.0"
#dname=`basename "$PWD"`
dname="origo-xenial.small"
me=`basename $0`

# Change working directory to script's directory
cd ${0%/*}

## If we are called from vmbuilder, i.e. with parameters, perform post-install operations
if [ $1 ]; then
	echo "Performing post-install operations in $1"
# Stop local webmin from blocking port 10000
    if [ -e "/etc/init.d/webmin" ]
    then
        /etc/init.d/webmin stop
    fi
# Add multiverse
#    chroot $1 perl -pi -e "s/universe/universe multiverse/;" /etc/apt/sources.list
# Install Webmin
#	chroot $1 bash -c 'echo "deb http://download.webmin.com/download/repository sarge contrib" >> /etc/apt/sources.list'
	chroot $1 bash -c 'echo "deb http://webmin.mirror.somersettechsolutions.co.uk/repository sarge contrib" >> /etc/apt/sources.list'
	chroot $1 wget http://www.webmin.com/jcameron-key.asc
	chroot $1 apt-key add jcameron-key.asc
	chroot $1 apt-get update

	chroot $1 apt-get -q -y --force-yes install webmin
# Install IOzone
	chroot $1 apt-get  -q -y --force-yes install iozone3
# Set up automatic scanning for other Webmin servers
	chroot $1 bash -c 'echo "auto_pass=origo
auto_self=1
auto_smtp=
auto_net=ens3
auto_type=ubuntu
auto_cluster-software=1
auto_remove=1
auto_user=origo
scan_time=10
resolve=0
auto_email=" > /etc/webmin/servers/config'
# Allow unauthenticated access to ubuntu module
	chroot $1 bash -c 'echo "anonymous=/origo=origo" >> /etc/webmin/miniserv.conf'
# Disable Webmin SSL
	chroot $1 perl -pi -e "s/ssl=1/ssl=0/g;" /etc/webmin/miniserv.conf
# Scan every 5 minutes for other Webmin servers
	chroot $1 perl -pi -e "s/(\{\'notfound\'\}\+\+ >=) 3/\$1 1/;" /usr/share/webmin/servers/auto.pl
	chroot $1 bash -c 'echo "#!/usr/bin/perl
open(CONF, qq[/etc/webmin/miniserv.conf]) || die qq[Failed to open /etc/webmin/miniserv.conf : \$!];
while(<CONF>) {
        \$root = \$1 if (/^root=(.*)/);
        }
close(CONF);
\$root || die qq[No root= line found in /etc/webmin/miniserv.conf];
\$ENV{PERLLIB} = \$root;
\$ENV{WEBMIN_CONFIG} = qq[/etc/webmin];
\$ENV{WEBMIN_VAR} = qq[/var/webmin];
chdir(qq[\$root/servers]);
exec(qq[\$root/servers/auto.pl], @ARGV) || die qq[Failed to run \$root/servers/auto.pl : \$!];" > /etc/webmin/servers/auto.pl'

    chroot $1 chmod 755 /etc/webmin/servers/auto.pl
# For now - disable automatic scanning
#	chroot $1 bash -c 'crontab -l | (cat;echo "0,5,10,15,20,25,30,35,40,45,50,55 * * * * /etc/webmin/servers/auto.pl") | crontab'
# Enable auto registering instead
	chroot $1 bash -c 'crontab -l | (cat;echo "0,5,10,15,20,25,30,35,40,45,50,55 * * * * /usr/local/bin/origo-ubuntu.pl") | crontab'
# Disable Webmin referer check
	chroot $1 perl -pi -e "s/referers_none=1/referers_none=0/;" /etc/webmin/config
	chroot $1 bash -c 'echo "webprefix=
referer=1
referers=" >> /etc/webmin/config'
# Change fstab since we are using virtio
	chroot $1 perl -pi -e "s/sda/vda/g;" /etc/fstab
# Install webmin module
# Include all the modules we want installed for this app
	tar cvf $dname.wbm.tar origo --exclude=origo/tabs/*
	tar rvf $dname.wbm.tar origo/tabs/commands origo/tabs/security origo/tabs/servers origo/tabs/software
	mv $dname.wbm.tar $dname.wbm
	gzip -f $dname.wbm
	cp -a $dname.wbm.gz $1/tmp/origo.wbm.gz
	chroot $1 bash -c '/usr/share/webmin/install-module.pl /tmp/origo.wbm.gz'
# Kill off webmin, which unfortunately get's started from the chroot, preventing it from being unmounted
	pkill -f webmin

# Simple script to register this server with admin webmin server when webmin starts
# This script is also responsible for mounting nfs-share, copy back data, etc. if upgrading/reinstalling
# started network-interface and started portmap and runlevel [2345]
    cp origo-ubuntu.pl $1/usr/local/bin
    chmod 755 $1/usr/local/bin/origo-ubuntu.pl
    chroot $1 ln -s /usr/local/bin/origo-ubuntu.pl /usr/local/bin/origo-helper
    chroot $1 bash -c 'echo "[Unit]
DefaultDependencies=no
Description=Utility script for Origo Compute
Wants=network-online.target
After=network.target network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/origo-ubuntu.pl
TimeoutSec=10
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/origo-ubuntu.service'
	chmod 664 $1/etc/systemd/system/origo-ubuntu.service

# Simple script to start shellinabox
    chroot $1 bash -c 'echo "[Unit]
DefaultDependencies=no
Description=Shellinabox for Origo Compute

[Service]
ExecStart=/usr/share/webmin/origo/tabs/servers/shellinaboxd -b -t -n --no-beep
TimeoutSec=10
RemainAfterExit=yes
Type=forking

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/origo-shellinabox.service'
	chmod 664 $1/etc/systemd/system/origo-shellinabox.service

# Simple script to configure IP address from address passed to VM through BIOS parameter SKU Number
    cp origo-xenial-networking.pl $1/usr/local/bin/origo-networking.pl
    chmod 755 $1/usr/local/bin/origo-networking.pl
    > $1/etc/network/interfaces
    chroot $1 bash -c 'echo "[Unit]
DefaultDependencies=no
Description=Setup network for Origo Compute
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/origo-networking.pl
TimeoutSec=0
RemainAfterExit=yes

[Install]
WantedBy=network.target" > /etc/systemd/system/origo-networking.service'
	chmod 664 $1/etc/systemd/system/origo-networking.service

	chroot $1 systemctl daemon-reload
	chroot $1 systemctl enable origo-networking.service
	chroot $1 systemctl enable origo-shellinabox.service
	chroot $1 systemctl enable origo-ubuntu.service

# Set up SSL access to Webmin on port 10001
    chroot $1 cp /etc/apache2/sites-available/default-ssl.conf /etc/apache2/sites-available/webmin-ssl.conf
    chroot $1 perl -pi -e 's/<VirtualHost _default_:443>/<VirtualHost _default_:10001>/;' /etc/apache2/sites-available/webmin-ssl.conf
    chroot $1 perl -pi -e 's/(<\/VirtualHost>)/    ProxyPass \/ http:\/\/127.0.0.1:10000\/\n            ProxyPassReverse \/ http:\/\/127.0.0.1:10000\/\n$1/;' /etc/apache2/sites-available/webmin-ssl.conf
    chroot $1 perl -pi -e 's/(DocumentRoot \/var\/www\/html)/$1\n        <Location \/>\n            deny from all\n            allow from 10.0.0.0\/8 #origo\n        <\/Location>/;' /etc/apache2/sites-available/webmin-ssl.conf
    chroot $1 perl -pi -e 's/Listen 443/Listen 443\n    Listen 10001/;' /etc/apache2/ports.conf

# Disable ondemand CPU-scaling service
    chroot $1 update-rc.d ondemand disable

# Disable gzip compression in Apache (enable it manually if desired)
    chroot $1 a2dismod deflate

# Enable SSL
    chroot $1 a2enmod ssl
    chroot $1 a2ensite default-ssl
    chroot $1 a2ensite webmin-ssl

# Enable mod_proxy
    chroot $1 a2enmod proxy
    chroot $1 a2enmod proxy_http

# Disable ssh login from outside - reenable from configuration UI
    chroot $1 bash -c 'echo "sshd: ALL" >> /etc/hosts.deny'
    chroot $1 bash -c 'echo "sshd: 10.0.0.0/8 #origo" >> /etc/hosts.allow'

# Disable Webmin login from outside - reenable from configuration UI
    chroot $1 bash -c 'echo "allow=10.0.0.0/8 127.0.0.0/16" >> /etc/webmin/miniserv.conf'

# Set nice color xterm as default
    chroot $1 bash -c 'echo "export TERM=xterm-color" >> /etc/bash.bashrc'
    chroot $1 perl -pi -e 's/PS1="/# PS1="/' /home/origo/.bashrc
    chroot $1 perl -pi -e 's/PS1="/# PS1="/' /root/.bashrc

# Start local webmin again
    if [ -e "/etc/init.d/webmin" ]
    then
        /etc/init.d/webmin start
    fi

# If called without parameters, build image
else
	vmbuilder kvm ubuntu \
		-o -v --debug \
		--suite xenial \
		--arch amd64 \
		--components main,universe,multiverse\
		--rootsize 9216 \
		--user origo --pass origo \
		--hostname $dname \
        --tmpfs 2048\
        --addpkg linux-image-generic\
        --addpkg apache2\
        --addpkg acpid\
        --addpkg curl\
        --addpkg dmidecode\
        --addpkg git\
        --addpkg iptables\
        --addpkg libapache2-mod-php\
        --addpkg libjson-perl\
        --addpkg libstring-shellquote-perl\
        --addpkg liburi-encode-perl\
        --addpkg man\
        --addpkg nfs-common\
        --addpkg openssh-server\
        --addpkg sysbench\
        --addpkg perl\
        --addpkg libnet-ssleay-perl\
        --addpkg openssl\
        --addpkg libauthen-pam-perl\
        --addpkg libpam-runtime\
        --addpkg libio-pty-perl\
        --addpkg apt-show-versions\
		--domain origo.io \
		--ip 10.1.1.2 \
		--execscript="./$me"

# Clean up
	mv ubuntu-kvm/*.qcow2 "./$dname-$version.master.qcow2"
	rm -r ubuntu-kvm
# convert to qcow2
    qemu-img amend -f qcow2 -o compat=0.10 ./$dname-$version.master.qcow2
fi


#!/bin/bash
# BSD 3-Clause License
# 
# Copyright (c) 2021, criten
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# 
# 3. Neither the name of the copyright holder nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# Version 1.1
# Available from https://github.com/criten/le4ispconfig

# Variables
ispccrt=/usr/local/ispconfig/interface/ssl/ispserver.crt
ispckey=/usr/local/ispconfig/interface/ssl/ispserver.key
ispcpem=/usr/local/ispconfig/interface/ssl/ispserver.pem
ispcacme=/usr/local/ispconfig/interface/acme/.well-known/acme-challenge
# Postfix
pfcrt=/etc/postfix/smtpd.cert
pfkey=/etc/postfix/smtpd.key
# MariaDB
mcrt=/etc/my.cnf.d/server-cert.pem
mkey=/etc/my.cnf.d/server-key.pem
# Pure-FTPD
ftpdpem=/etc/ssl/private/pure-ftpd.pem

while getopts ":hv" arg;
do
	case $arg in
		h) help=1;;
		v) verbose=1;;
	esac
done
if [[ $verbose -eq 1 ]]; then
	set -x
fi
if [[ $help -eq 1 ]]; then
	echo "Lets Encrypt 4 ISP Config"
	echo "-------------------------"
	echo
	echo "A simple tool to create/renew a Lets Encrypt certificate as"
	echo "the default certificate for ISP Config and associated services"
	echo
	echo "Be aware this script also installs an entry in /etc/crontab"
	echo
	echo " -h  Display help menu"
	echo " -v  Verbose on"
	echo
	exit 0
fi

# Cause script to exit when a call produces exit code 1
set -e

# Validate `hostname -f`
if [[ $(host `hostname -f`. | grep "not found" | wc -l) -eq "1" ]]; then
	echo "ERROR: $(hostname -f) does not have a DNS record. Lets Encrypt requires a DNS record or will fail"
	echo $(host `hostname -f`)
	exit 1
fi

# Populate SSL filename path and other vars
lelive=/etc/letsencrypt/live/$(hostname -f)
if [[ -e "$lelive" ]]; then
	mkdir -p "$lelive"
fi

# Function to setup certificates and permissions
# File permissions on the private key are particularly important - lets be as restrictive as possible!
resetpermissions() {
	# ISPConfig
	cp $lelive/fullchain.pem $ispccrt
	cp $lelive/privkey.pem $ispckey
	cat $ispckey $ispccrt > $ispcpem
	chown root:root $ispccrt $ipsckey $ispcpem
	chmod 600 $ispccrt $ipsckey $ispcpem

	# Postfix
	cp $ispccrt $pfcrt
	cp $ispckey $pfkey
	chown postfix:postfix $pfcrt $pfkey
	chmod 600 $pfcrt $pfkey

	# MariaDB
	cp $ispccrt $mcrt
	cp $ispckey $mkey
	chown mysql:mysql $mcrt $mkey
	chmod 600 $mcrt $mkey

	# Pure-FTPD
	cp $ispcpem $ftpdpem
	chown root:root $ftpdpem
	chmod 600 $ftpdpem
}

# Lets run if theres 30 days or less on the certifice validity
if [[ ! -e ${lelive}/cert.pem ]] || [[ $(date +%Y%m%d) -ge $(date --date="$(openssl x509 -noout -text -in ${lelive}/cert.pem | grep "Not After : " | tr -s ' ' | cut -c 14-) -30 day" +%Y%m%d) ]]; then
	if [[ $(systemctl status nginx 2>/dev/null | grep "   Active: active (running)" | wc -l) -eq "0" ]] && [[ $(systemctl status httpd 2>/dev/null | grep "   Active: active (running)" | wc -l) -eq "0" ]]; then
		websvr=0
		certbot certonly --standalone -d $(hostname -f)
	else
		if [[ $(systemctl status nginx 2>/dev/null | grep "   Active: active (running)" | wc -l) -eq "1" ]]; then
			websvr=nginx
		else
			websvr=httpd
		fi
		#certbot certonly --authenticator standalone -d $(hostname -f) --pre-hook "systemctl stop $websvr" --post-hook "systemctl start $websvr" # The following command is untested
		certbot certonly --webroot $ispcacme -d $(hostname -f)
	fi

	# Proceed if 'hostname -f' LE SSL certs path exists
	if [[ ! -d "$lelive" ]]; then
		echo "ERROR: ${lelive} does not exist. Did cerbot fail?"
		exit 1
	else
		resetpermissions

		# Reload webserver if enabled - but don't restart because that invokes an outage
		if [[ ${websvr} -ne "0" ]]; then
			systemctl reload $websvr
		fi
		
		# Postfix
		if [[ $(systemctl status postfix 2>/dev/null | grep "   Active: active (running)" | wc -l) -eq "1" ]]; then
			# Reload postfix and dovecot
			systemctl reload postfix
			if [[ $(systemctl status dovecot 2>/dev/null | grep "   Active: active (running)" | wc -l) -eq "1" ]]; then
				systemctl reload dovecot
			fi
		fi
		
		# MariaDB - no reload option so lets restart. Active connections interrupted
		if [[ $(systemctl status mariadb 2>/dev/null | grep "   Active: active (running)" | wc -l) -eq "1" ]]; then
			systemctl restart mariadb
		fi

		# Pure-FTPD - no reload option so lets restart. Active connections interrupted
		if [[ $(systemctl status pure-ftpd 2>/dev/null | grep "   Active: active (running)" | wc -l) -eq "1" ]]; then
			systemctl restart pure-ftpd
		fi
		
		# Monit - no reload option so lets restart. Active connections interrupted 
		if [[ $(systemctl status monit 2>/dev/null | grep "   Active: active (running)" | wc -l) -eq "1" ]]; then
			systemctl restart monit
		fi
	fi
else
	# Reset permissions on each daily run but don't restart services as this invokes an outage
	resetpermissions
fi

# Install a crontab
if [[ $(grep $0 /etc/crontab | wc -l) -eq "0" ]]; then
        echo "45 3 * * * root $0" >>/etc/crontab
fi
# EOF

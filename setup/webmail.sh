#!/bin/bash
# Webmail with Roundcube
# ----------------------

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# ### Installing Roundcube


# These dependencies are from `apt-cache showpkg roundcube-core`.
echo "Installing Roundcube (webmail)..."
apt_install \
	php php-sqlite php-intl \
	php-gd php-pspell imagemagick roundcubemail

# paths that are often reused.
RCM_DIR=/usr/share/webapps/roundcubemail/
RCM_PLUGIN_DIR=${RCM_DIR}/plugins
RCM_CONFIG=${RCM_DIR}/config/config.inc.php

# ### Configuring Roundcube

# Generate a safe 24-character secret key of safe characters.
SECRET_KEY=$(dd if=/dev/urandom bs=1 count=18 2>/dev/null | base64 | fold -w 24 | head -n 1)

# Create a configuration file.
#
# For security, temp and log files are not stored in the default locations
# which are inside the roundcube sources directory. We put them instead
# in normal places.
cat > $RCM_CONFIG <<EOF;
<?php
/*
 * Do not edit. Written by Mail-in-a-Box. Regenerated on updates.
 */
\$config = array();
\$config['log_dir'] = '/var/log/roundcubemail/';
\$config['temp_dir'] = '/var/tmp/roundcubemail/';
\$config['db_dsnw'] = 'mysql://$SQL_USER:$SQL_PASSWORD@$SQL_SERVER/$SQL_DATABASE';
\$config['default_host'] = 'ssl://localhost';
\$config['default_port'] = 993;
\$config['imap_conn_options'] = array(
  'ssl'         => array(
     'verify_peer'  => false,
     'verify_peer_name'  => false,
   ),
 );
\$config['imap_timeout'] = 15;
\$config['smtp_server'] = 'tls://127.0.0.1';
\$config['smtp_port'] = 587;
\$config['smtp_user'] = '%u';
\$config['smtp_pass'] = '%p';
\$config['smtp_conn_options'] = array(
  'ssl'         => array(
     'verify_peer'  => false,
     'verify_peer_name'  => false,
   ),
 );
\$config['support_url'] = 'https://mailinabox.email/';
\$config['product_name'] = '$PRIMARY_HOSTNAME Webmail';
\$config['des_key'] = '$SECRET_KEY';
\$config['plugins'] = array('archive', 'zipdownload', 'password', 'managesieve', 'jqueryui' );
\$config['skin'] = 'larry';
\$config['login_autocomplete'] = 2;
\$config['password_charset'] = 'UTF-8';
\$config['junk_mbox'] = 'Spam';
?>
EOF

# Configure CardDav
#cat > ${RCM_PLUGIN_DIR}/carddav/config.inc.php <<EOF;
#<?php
#/* Do not edit. Written by Mail-in-a-Box. Regenerated on updates. */
#\$prefs['_GLOBAL']['hide_preferences'] = true;
#\$prefs['_GLOBAL']['suppress_version_warning'] = true;
#\$prefs['ownCloud'] = array(
#	 'name'         =>  'ownCloud',
#	 'username'     =>  '%u', // login username
#	 'password'     =>  '%p', // login password
#	 'url'          =>  'https://${PRIMARY_HOSTNAME}/cloud/remote.php/carddav/addressbooks/%u/contacts',
#	 'active'       =>  true,
#	 'readonly'     =>  false,
#	 'refresh_time' => '02:00:00',
#	 'fixed'        =>  array('username','password'),
#	 'preemptive_auth' => '1',
#	 'hide'        =>  false,
#);
#EOF

# Create writable directories.
mkdir -p /var/log/roundcubemail /var/tmp/roundcubemail $STORAGE_ROOT/mail/roundcube
chown -R http.http /var/log/roundcubemail /var/tmp/roundcubemail $STORAGE_ROOT/mail/roundcube

# Ensure the log file monitored by fail2ban exists, or else fail2ban can't start.
sudo -u http touch /var/log/roundcubemail/errors

# Password changing plugin settings
# The config comes empty by default, so we need the settings
# we're not planning to change in config.inc.dist...
#cp ${RCM_PLUGIN_DIR}/password/config.inc.php.dist \
#	${RCM_PLUGIN_DIR}/password/config.inc.php

#tools/editconf.py ${RCM_PLUGIN_DIR}/password/config.inc.php \
#	"\$config['password_minimum_length']=8;" \
#	"\$config['password_db_dsn']='sqlite:///$STORAGE_ROOT/mail/users.sqlite';" \
#	"\$config['password_query']='UPDATE users SET password=%D WHERE email=%u';" \
#	"\$config['password_dovecotpw']='/usr/bin/doveadm pw';" \
#	"\$config['password_dovecotpw_method']='SHA512-CRYPT';" \
#	"\$config['password_dovecotpw_with_method']=true;"

# so PHP can use doveadm, for the password changing plugin
usermod -a -G dovecot http

# set permissions so that PHP can use users.sqlite
# could use dovecot instead of www-data, but not sure it matters
chown root.http $STORAGE_ROOT/mail
chmod 775 $STORAGE_ROOT/mail
chown root.http $STORAGE_ROOT/mail/users.sqlite
chmod 664 $STORAGE_ROOT/mail/users.sqlite

# Fix Carddav permissions:
#chown -f -R root.http ${RCM_PLUGIN_DIR}/carddav
# root.www-data need all permissions, others only read
#chmod -R 774 ${RCM_PLUGIN_DIR}/carddav

# Run Roundcube database migration script (database is created if it does not exist)
${RCM_DIR}/bin/initdb.sh --dir ${RCM_DIR}/SQL --package roundcube
${RCM_DIR}/bin/updatedb.sh --dir ${RCM_DIR}/SQL --package roundcube
#chown http:http $STORAGE_ROOT/mail/roundcube/roundcube.sqlite
#chmod 664 $STORAGE_ROOT/mail/roundcube/roundcube.sqlite

# Enable PHP modules.
#phpenmod -v php7.0 mcrypt imap
restart_service php-fpm
